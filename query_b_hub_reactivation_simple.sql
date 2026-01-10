-- ================================================================================
-- QUERY B MODIFIED: Hub-wise Net Churn + Reactivation
-- ================================================================================
-- Key Change: Added reactivation column at hub level
-- Validation: SUM(reactivation) for all hubs in Bangalore = City reactivation for Bangalore
-- 
-- REACTIVATION LOGIC (from Query A):
-- A provider is "reactivated" when:
--   1. week_mark_status = 'Working' (>8 hours marked working in current week)
--   2. lag_week_mark_status = 'Not Working' (previous week was not working)
--   3. working_status = 1 (had delivery in that week)
--   4. pro_current_status_for_reactivation = 'Active' (currently active per L7D)
--   5. Churn event existed in the previous week
-- ================================================================================

WITH main AS (
    SELECT
        provider_id,
        provider_name,
        DATE(approval_date) AS app_date, 
        DATE(last_delivery_date) AS ldd, 
        CASE 
            WHEN last_delivery_date IS NULL THEN DATE_TRUNC('W', DATE(approval_date))
            ELSE DATE_TRUNC('W', DATE(last_delivery_date)) 
        END AS ldd_week,
        city,
        CASE 
            WHEN last_delivery_date IS NULL THEN 0 
            ELSE DATEDIFF('day', DATE(approval_date), DATE(last_delivery_date))
        END AS age
    FROM provider__daily__facts
    WHERE reporting_supercategory_new = 'Insta Help'
      AND approval_date IS NOT NULL
),

current_hub AS (
    SELECT
        e.provider_id,
        s.hub_name,
        ROW_NUMBER() OVER (PARTITION BY e.provider_id ORDER BY e.updated_at DESC) AS rn
    FROM PUBLIC.PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS e
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW s ON e.primary_hub_id = s.hub_id
    QUALIFY rn = 1
),

-- L7D status for churn classification
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

-- ===================== REACTIVATION CTEs =====================

-- All weeks with deliveries
all_weeks AS (
    SELECT DISTINCT DATE_TRUNC('week', DATE(bdate_final)) AS week
    FROM request__daily__facts
    WHERE customer_category_key = 'insta_maids'
      AND country = 'India'
      AND reporting_city NOT IN ('Singapore', 'Mysore')
      AND DATE(bdate_final) >= '2024-04-01'
),

-- Provider delivery weeks
provider_delivery_weeks AS (
    SELECT DISTINCT 
        provider_id, 
        DATE_TRUNC('week', DATE(bdate_final)) AS week
    FROM request__daily__facts
    WHERE customer_category_key = 'insta_maids'
      AND country = 'India'
      AND reporting_city NOT IN ('Singapore', 'Mysore')
      AND service_delivered = 1
      AND DATE(bdate_final) >= '2024-04-01'
),

-- Provider info
provider_info AS (
    SELECT 
        provider_id,
        city,
        DATE(approval_date) AS approval_date,
        last_delivery_date AS ldd
    FROM provider__daily__facts
    WHERE customer_category_key = 'insta_maids'
      AND country = 'India'
      AND city NOT IN ('Singapore', 'Mysore')
      AND provider_id NOT IN (
            '649809118e2b920027381c8b','6540b306f93f8f0024edae02',
            '652e3bd7be83ab00347c41b9','65d743bb2894c80027f18563',
            '6593d80bd91e7c00253bc68b'
      )
),

-- Provider-week combinations
provider_weeks_all AS (
    SELECT 
        pi.provider_id,
        pi.city,
        pi.approval_date,
        pi.ldd,
        w.week AS week_start
    FROM provider_info pi
    CROSS JOIN all_weeks w
),

-- Weekly marking status
weekly_markings AS (
    SELECT
        pwa.provider_id,
        pwa.city,
        pwa.week_start,
        pwa.approval_date,
        pwa.ldd,
        CASE WHEN pdw.provider_id IS NOT NULL THEN 1 ELSE 0 END AS had_delivery,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END), 0) > 8 
            THEN 'Working' ELSE 'Not Working'
        END AS week_mark_status
    FROM provider_weeks_all pwa
    LEFT JOIN provider_delivery_weeks pdw 
        ON pwa.provider_id = pdw.provider_id 
        AND pwa.week_start = pdw.week
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON pwa.provider_id = acm.provider_id
        AND DATE_TRUNC('week', DATE(acm.date)) = pwa.week_start
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE pwa.approval_date IS NOT NULL
    GROUP BY pwa.provider_id, pwa.city, pwa.week_start, pwa.approval_date, pwa.ldd, pdw.provider_id
),

-- Add lag for previous week status
weekly_with_lag AS (
    SELECT
        *,
        LAG(week_mark_status) OVER (PARTITION BY provider_id ORDER BY week_start) AS prev_week_status
    FROM weekly_markings
),

-- Churn events
churn_events AS (
    SELECT provider_id, week_start AS churn_week
    FROM weekly_with_lag
    WHERE prev_week_status = 'Working' AND week_mark_status = 'Not Working'
),

-- Current L7D status for reactivation
l7d_current AS (
    SELECT 
        pdf.provider_id,
        CASE 
            WHEN SUM(CASE WHEN status = 'marked working' THEN 1 ELSE 0 END) > 8 THEN 'Active'
            ELSE 'Churned'
        END AS current_status
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

-- Identify reactivated providers per week
reactivated_providers AS (
    SELECT 
        wwl.provider_id,
        wwl.city,
        wwl.week_start AS reactivation_week
    FROM weekly_with_lag wwl
    JOIN l7d_current lc ON wwl.provider_id = lc.provider_id
    WHERE wwl.week_mark_status = 'Working'           -- Currently working
      AND wwl.prev_week_status = 'Not Working'       -- Was not working last week
      AND wwl.had_delivery = 1                       -- Had delivery this week
      AND lc.current_status = 'Active'               -- Currently active (L7D)
      AND EXISTS (
          SELECT 1 FROM churn_events ce
          WHERE ce.provider_id = wwl.provider_id
            AND ce.churn_week = wwl.week_start - INTERVAL '1 week'
      )
),

-- Hub-wise reactivation aggregation
hub_reactivation AS (
    SELECT 
        ch.hub_name,
        rp.city,
        rp.reactivation_week,
        COUNT(DISTINCT rp.provider_id) AS reactivation_count
    FROM reactivated_providers rp
    LEFT JOIN current_hub ch ON rp.provider_id = ch.provider_id
    GROUP BY ch.hub_name, rp.city, rp.reactivation_week
),

-- ===================== MAIN QUERY (Original Query B logic) =====================

final_raw AS (
    SELECT 
        m.provider_id,
        m.ldd_week,
        m.city,
        ch.hub_name,
        CASE 
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN '3. Churn'
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
            WHEN m.ldd IS NULL AND m.app_date >= CURRENT_DATE - 7 THEN '1. Active'
        END AS churn_status
    FROM main m
    LEFT JOIN l7d ON m.provider_id = l7d.provider_id
    LEFT JOIN current_hub ch ON m.provider_id = ch.provider_id
)

-- ===================== FINAL OUTPUT =====================
SELECT 
    fr.hub_name,
    fr.ldd_week AS "ldd_week::multi-filter",
    fr.city AS "city::multi-filter",
    COUNT(DISTINCT CASE WHEN fr.churn_status = '3. Churn' THEN fr.provider_id END) AS net_churn_count,
    COALESCE(hr.reactivation_count, 0) AS reactivation_count
FROM final_raw fr
LEFT JOIN hub_reactivation hr 
    ON COALESCE(fr.hub_name, 'Unknown') = COALESCE(hr.hub_name, 'Unknown')
    AND fr.city = hr.city
    AND fr.ldd_week = hr.reactivation_week
GROUP BY fr.hub_name, fr.ldd_week, fr.city, hr.reactivation_count
ORDER BY fr.city, fr.hub_name, fr.ldd_week DESC;
