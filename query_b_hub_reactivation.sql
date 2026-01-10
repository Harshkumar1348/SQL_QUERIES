-- Query B Modified: Hub-wise Reactivation
-- The sum of reactivation across all hubs in a city should match city-level reactivation from Query A

WITH main AS (
    SELECT
        provider_id,
        provider_name,
        TO_CHAR(DATE(approval_date), 'YYYY-MM') AS app_month, 
        DATE(approval_date) AS app_date, 
        DATE(last_delivery_date) AS ldd, 
        CASE 
            WHEN last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('W', DATE(approval_date)), 'YYYY-MM-DD') 
            ELSE DATE_TRUNC('W', DATE(last_delivery_date)) 
        END AS ldd_week,
        DATEADD(day, 7, ldd_week) AS churn_week,
        CASE 
            WHEN last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('W', DATE(approval_date)), 'YYYY-MM') 
            ELSE TO_CHAR(DATE_TRUNC('W', DATE(last_delivery_date)), 'YYYY-MM') 
        END AS ldd_month,    
        CASE 
            WHEN last_delivery_date IS NULL AND DATE(approval_date) >= CURRENT_DATE - 7 THEN 'Active' 
            WHEN last_delivery_date > CURRENT_DATE - 7 THEN 'Active' 
            ELSE 'Inactive' 
        END AS active_status,
        customer_category_key,
        city,
        CASE 
            WHEN last_delivery_date IS NULL THEN 0 
            ELSE (DATE(last_delivery_date) - DATE(approval_date)) 
        END AS age
    FROM provider__daily__facts
    WHERE reporting_supercategory_new = 'Insta Help'
      AND approval_date IS NOT NULL
),

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

l7d AS (
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
        AND start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),

-- ============== REACTIVATION CALCULATION CTEs (from Query A) ==============

-- Get all weeks with provider activity
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

-- All provider-week combinations
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

-- Weekly marking status per provider
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

-- Add lag status for previous week comparison
provider_weekly_markings_with_lag AS (
    SELECT
        provider_id,
        week_start,
        marked_count_week,
        week_mark_status,
        LAG(week_mark_status) OVER (PARTITION BY provider_id ORDER BY week_start) AS lag_week_mark_status
    FROM provider_weekly_markings
),

-- Churn events (transition from Working to Not Working)
churn_events AS (
    SELECT
        provider_id,
        week_start AS churn_week
    FROM provider_weekly_markings_with_lag
    WHERE lag_week_mark_status = 'Working'
      AND week_mark_status = 'Not Working'
),

-- L7D current status for reactivation
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

-- Provider current status for reactivation calculation
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

-- Base final with all statuses
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

-- Reactivation at provider level with week (same logic as Query A)
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

-- ============== END OF REACTIVATION CTEs ==============

final_raw AS (
    SELECT 
        final.*,
        ch.hub_name AS hub_name
    FROM (
        SELECT 
            m.*,
            m.ldd_week AS "ldd_week::filter",
            CASE 
                WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN '3. Churn'
                WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
                WHEN m.ldd IS NULL AND DATE(m.app_date) >= CURRENT_DATE - 7 THEN '1. Active'
            END AS churn_status,
            CASE 
                WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
                WHEN m.ldd IS NULL AND m.app_date >= CURRENT_DATE - 7 THEN '1. Active'
                WHEN m.age = 0 THEN '3. D0 churn'
                WHEN m.age <= 7 THEN '4. D7 churn'
                WHEN m.age <= 17 THEN '5. D15 churn'
                WHEN m.age <= 30 THEN '6. D30 churn'
                WHEN m.age <= 60 THEN '7. D60 churn'
                WHEN m.age <= 90 THEN '8. D90 churn'
                WHEN m.age <= 120 THEN '9. D120 churn'
                ELSE '10. >D120 churn'
            END AS churn_bucket
        FROM main m
        LEFT JOIN l7d ON m.provider_id = l7d.provider_id
    ) final
    LEFT JOIN current_hub ch ON final.provider_id = ch.provider_id
),

-- Hub-wise reactivation count
hub_reactivation AS (
    SELECT 
        ch.hub_name,
        rp.reporting_city AS city,
        rp.reactivation_week,
        COUNT(DISTINCT rp.provider_id) AS reactivation_count
    FROM reactivation_providers rp
    LEFT JOIN current_hub ch ON rp.provider_id = ch.provider_id
    GROUP BY ch.hub_name, rp.reporting_city, rp.reactivation_week
)

-- Final output: Hub-wise metrics with reactivation
SELECT 
    fr.hub_name,
    fr.ldd_week AS "ldd_week::multi-filter",
    fr.city AS "city::multi-filter",
    COUNT(DISTINCT CASE WHEN fr.churn_status = '3. Churn' THEN fr.provider_id END) AS net_churn_count,
    COALESCE(hr.reactivation_count, 0) AS reactivation_count
FROM final_raw fr
LEFT JOIN hub_reactivation hr 
    ON fr.hub_name = hr.hub_name 
    AND fr.city = hr.city
    AND fr.ldd_week = hr.reactivation_week
GROUP BY fr.hub_name, fr.ldd_week, fr.city, hr.reactivation_count
ORDER BY fr.city, fr.hub_name, fr.ldd_week DESC;
