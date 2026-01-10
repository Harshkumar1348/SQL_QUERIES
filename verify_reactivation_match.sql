-- Verification Query: Ensure hub-wise reactivation sums match city-level reactivation
-- Run this to validate that SUM(hub reactivation) = city reactivation from Query A

-- ============== COMMON CTEs (Same as both queries) ==============

WITH provider_weeks AS (
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
    GROUP BY pwc.provider_id, pwc.week_start
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

churn_events AS (
    SELECT
        provider_id,
        week_start AS churn_week
    FROM provider_weekly_markings_with_lag
    WHERE lag_week_mark_status = 'Working'
      AND week_mark_status = 'Not Working'
),

l7d_current AS (
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
    WHERE pdf.approval_date >= '2024-04-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY 1
),

provider_current_status_for_reactivation AS (
    SELECT
        pdf.provider_id,
        pdf.city AS reporting_city,
        CASE 
            WHEN COALESCE(l7d_current.L7D_status, 'Unknown') = 'Not Working' THEN 'Churned'
            WHEN COALESCE(l7d_current.L7D_status, 'Unknown') = 'Working' THEN 'Active'
            WHEN last_delivery_date IS NULL 
                 AND DATE(approval_date) >= CURRENT_DATE - 7 THEN 'Active'
        END AS pro_current_status
    FROM provider__daily__facts pdf
    LEFT JOIN l7d_current ON pdf.provider_id = l7d_current.provider_id
    WHERE pdf.reporting_supercategory_new = 'Insta Help'
      AND pdf.city NOT IN ('Singapore','Mysore')
      AND approval_date IS NOT NULL
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
            WHEN pwc.week_start <= DATE_TRUNC('week', pwc.approval_date) 
                 AND m.ldd >= pwc.approval_date THEN 1
            ELSE 0
        END AS working_status,
        pwm.week_mark_status,
        pwm.lag_week_mark_status,
        pcs_react.pro_current_status AS pro_current_status_for_reactivation
    FROM provider_weeks_combined pwc
    LEFT JOIN provider_weeks pw 
        ON pw.provider_id = pwc.provider_id 
        AND pw.week = pwc.week_start
    LEFT JOIN min_bdate m 
        ON m.provider_id = pwc.provider_id
    LEFT JOIN provider_weekly_markings_with_lag pwm
        ON pwm.provider_id = pwc.provider_id 
        AND pwm.week_start = pwc.week_start
    LEFT JOIN provider_current_status_for_reactivation pcs_react
        ON pcs_react.provider_id = pwc.provider_id
    WHERE pwc.approval_date IS NOT NULL
),

-- Reactivation at provider level
reactivation_providers AS (
    SELECT
        bf.reporting_city,
        bf.provider_id,
        bf.week_start AS reactivation_week
    FROM base_final bf
    WHERE bf.week_mark_status = 'Working'
      AND bf.lag_week_mark_status = 'Not Working'
      AND bf.working_status = 1
      AND bf.pro_current_status_for_reactivation = 'Active'
      AND EXISTS (
          SELECT 1 FROM churn_events ce
          WHERE ce.provider_id = bf.provider_id
            AND ce.churn_week = (bf.week_start - INTERVAL '1 week')
      )
),

-- Current hub for each provider
current_hub AS (
    SELECT
        e.provider_id,
        e.primary_hub_id,
        s.hub_name,
        ROW_NUMBER() OVER (PARTITION BY e.provider_id ORDER BY e.updated_at DESC) AS rn
    FROM PUBLIC.PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS e
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW s ON e.primary_hub_id = s.hub_id
    QUALIFY rn = 1
),

-- City-level reactivation (Query A style)
city_reactivation AS (
    SELECT
        reporting_city,
        reactivation_week,
        COUNT(DISTINCT provider_id) AS city_reactivation_count
    FROM reactivation_providers
    GROUP BY reporting_city, reactivation_week
),

-- Hub-level reactivation (Query B style)
hub_reactivation AS (
    SELECT 
        ch.hub_name,
        rp.reporting_city,
        rp.reactivation_week,
        COUNT(DISTINCT rp.provider_id) AS hub_reactivation_count
    FROM reactivation_providers rp
    LEFT JOIN current_hub ch ON rp.provider_id = ch.provider_id
    GROUP BY ch.hub_name, rp.reporting_city, rp.reactivation_week
),

-- Sum of hub reactivations by city
hub_sum_by_city AS (
    SELECT 
        reporting_city,
        reactivation_week,
        SUM(hub_reactivation_count) AS sum_hub_reactivations
    FROM hub_reactivation
    GROUP BY reporting_city, reactivation_week
)

-- VERIFICATION: Compare city-level vs sum of hub-level
SELECT 
    cr.reporting_city,
    cr.reactivation_week,
    cr.city_reactivation_count AS "City Level Reactivation (Query A)",
    hs.sum_hub_reactivations AS "Sum of Hub Reactivations (Query B)",
    CASE 
        WHEN cr.city_reactivation_count = hs.sum_hub_reactivations THEN '✓ MATCH'
        ELSE '✗ MISMATCH'
    END AS match_status,
    (cr.city_reactivation_count - COALESCE(hs.sum_hub_reactivations, 0)) AS difference
FROM city_reactivation cr
LEFT JOIN hub_sum_by_city hs 
    ON cr.reporting_city = hs.reporting_city 
    AND cr.reactivation_week = hs.reactivation_week
WHERE cr.reactivation_week >= '2024-12-01'
ORDER BY cr.reporting_city, cr.reactivation_week DESC;
