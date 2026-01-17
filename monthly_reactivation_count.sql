WITH l7d AS (
    SELECT 
        pdf.provider_id,
        CASE 
            WHEN SUM(CASE WHEN status = 'marked working' THEN 1 ELSE 0 END) > 8 THEN 'Working'
            ELSE 'Not Working'
        END AS L7D_status
    FROM provider__daily__facts pdf
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON pdf.provider_id = acm.provider_id
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY 1
),

provider_weeks AS (
    SELECT DISTINCT 
        provider_id, 
        DATE_TRUNC('week', DATE(bdate_final)) AS week, 
        reporting_city
    FROM request__daily__facts
    WHERE customer_category_key = 'insta_maids'
      AND country = 'India'
      AND reporting_city <> 'Singapore'
      AND service_delivered = 1
      AND DATE(bdate_final) >= '2024-04-01'
),

provider_current_status AS (
    SELECT
        pdf.provider_id,
        pdf.city AS reporting_city,
        CASE 
            WHEN last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('week', DATE(approval_date)), 'YYYY-MM-DD') 
            ELSE TO_CHAR(DATE_TRUNC('week', DATE(last_delivery_date)), 'YYYY-MM-DD') 
        END AS ldd_week,
        CASE 
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN 'Churned'
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN 'Active'
            WHEN last_delivery_date IS NULL 
                 AND DATE(approval_date) >= CURRENT_DATE - 7 THEN 'Active'
        END AS pro_current_status
    FROM provider__daily__facts pdf
    LEFT JOIN l7d ON pdf.provider_id = l7d.provider_id
    WHERE pdf.reporting_supercategory_new = 'Insta Help'
      AND pdf.city NOT IN ('Singapore','Mysore')
      AND approval_date IS NOT NULL
),

provider_weeks_combined AS (
    SELECT DISTINCT
        p.provider_id,
        p.city AS reporting_city,
        DATE(p.approval_date) AS approval_date,
        DATE_TRUNC('week', g.week) AS week_start
    FROM provider__daily__facts p
    JOIN (
        SELECT DISTINCT DATE_TRUNC('week', DATE(bdate_final)) AS week
        FROM request__daily__facts
        WHERE customer_category_key = 'insta_maids'
          AND country = 'India'
          AND reporting_city <> 'Singapore'
          AND DATE(bdate_final) >= '2024-04-01'
    ) g ON TRUE
    WHERE p.customer_category_key = 'insta_maids'
      AND p.provider_id NOT IN (
            '649809118e2b920027381c8b','6540b306f93f8f0024edae02',
            '652e3bd7be83ab00347c41b9','65d743bb2894c80027f18563',
            '6593d80bd91e7c00253bc68b'
      )
      AND p.country = 'India'
      AND p.city NOT IN ('Singapore','Mysore')
),

min_bdate AS (
    SELECT 
        provider_id,
        first_delivery_date AS min_bdate_final,
        last_delivery_date AS ldd
    FROM provider__daily__facts
),

provider_weekly_markings AS (
    SELECT
        pwc.provider_id,
        pwc.week_start,
        COALESCE(SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END), 0) AS marked_count_week,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END), 0) > 8 
                THEN 'Working'
            ELSE 'Not Working'
        END AS week_mark_status
    FROM provider_weeks_combined pwc
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
      ON pwc.provider_id = acm.provider_id
      AND DATE_TRUNC('week', DATE(acm.date)) = pwc.week_start
      AND acm.start_hour_local BETWEEN 8 AND 19
    GROUP BY 1,2
),

provider_weekly_markings_with_lag AS (
    SELECT
        provider_id,
        week_start,
        marked_count_week,
        week_mark_status,
        LAG(week_mark_status) OVER (PARTITION BY provider_id ORDER BY week_start) AS lag_week_mark_status
    FROM provider_weekly_markings
),

-- calendar-based churn
churn_events AS (
    SELECT
        provider_id,
        week_start AS churn_week
    FROM provider_weekly_markings_with_lag
    WHERE lag_week_mark_status = 'Working'
      AND week_mark_status = 'Not Working'
),

base_final AS (
    SELECT
        pwc.reporting_city,
        pwc.provider_id,
        pwc.week_start,
        m.min_bdate_final,
        pwc.approval_date,
        CASE
            WHEN pw.week IS NOT NULL THEN 1
            WHEN pwc.week_start <= DATE_TRUNC('week', approval_date) 
                 AND m.ldd >= approval_date THEN 1
            ELSE 0
        END AS working_status,
        pcs.pro_current_status,
        LAG(
            CASE
                WHEN pw.week IS NOT NULL THEN 1
                WHEN pwc.week_start <= DATE_TRUNC('week', approval_date) 
                     AND m.ldd >= approval_date THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY pwc.provider_id ORDER BY pwc.week_start) AS lag_status,
        pwm.week_mark_status,
        pwm.lag_week_mark_status
    FROM provider_weeks_combined pwc
    LEFT JOIN provider_weeks pw 
        ON pw.provider_id = pwc.provider_id 
       AND pw.week = pwc.week_start
    LEFT JOIN min_bdate m 
        ON m.provider_id = pwc.provider_id
    LEFT JOIN provider_current_status pcs 
        ON pcs.provider_id = pwc.provider_id
    LEFT JOIN provider_weekly_markings_with_lag pwm
        ON pwm.provider_id = pwc.provider_id 
       AND pwm.week_start = pwc.week_start
    WHERE pwc.approval_date IS NOT NULL
),

churned AS (
      SELECT
        reporting_city as city,
        ldd_week AS week,
        COUNT(DISTINCT provider_id) AS churned
    FROM provider_current_status
    WHERE pro_current_status = 'Churned'
    GROUP BY 1, 2
),

-- STRICT & TIGHT reactivation:
-- only count if (1) this week = Working, (2) last week = Not Working, 
-- (3) provider churned EXACTLY last week.
reactivation AS (
    SELECT
        bf.reporting_city,
        bf.week_start AS week,
        COUNT(DISTINCT bf.provider_id) AS reactivations
    FROM base_final bf
    WHERE bf.week_mark_status = 'Working'
      AND bf.lag_week_mark_status = 'Not Working'
      AND bf.working_status = 1
      AND bf.pro_current_status = 'Active'
      AND EXISTS (
          SELECT 1 FROM churn_events ce
          WHERE ce.provider_id = bf.provider_id
            AND ce.churn_week = (bf.week_start - INTERVAL '1 week')
      )
    GROUP BY 1,2
)

SELECT
    rf.reporting_city AS "city::filter",
    DATE_TRUNC('month', rf.week_start) AS "month::filter",
    SUM(COALESCE(ch.churned, 0)) AS churned,
    SUM(COALESCE(r.reactivations, 0)) AS reactivations
FROM (
    SELECT reporting_city, week_start 
    FROM base_final 
    GROUP BY 1,2
) rf
LEFT JOIN churned ch 
    ON ch.city = rf.reporting_city 
   AND ch.week = rf.week_start
LEFT JOIN reactivation r 
    ON r.reporting_city = rf.reporting_city 
   AND r.week = rf.week_start
GROUP BY 1, 2
ORDER BY 1, 2;
