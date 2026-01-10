-- ============================================================
-- HUB-WISE REACTIVATION QUERY
-- ============================================================
-- This query calculates reactivation at HUB level instead of CITY level
-- Reactivation is based on ldd_week (week of last delivery date)
-- A provider is considered "reactivated" when they:
--   1. Were "Not Working" in the previous week (lag_week_mark_status)
--   2. Are "Working" in the current week (week_mark_status)
--   3. Delivered a job that week (working_status = 1)
--   4. Are currently Active
--   5. Had a churn event in the previous week
-- ============================================================

WITH delivery_log AS (
    -- Step 1: Get every single day a provider successfully delivered a job
    SELECT DISTINCT
        provider_id,
        reporting_city,
        DATE(bdate_final) AS delivery_date
    FROM PUBLIC.request__daily__facts
    WHERE reporting_supercategory_new = 'Insta Help'
      AND service_delivered = 1
      AND country = 'India'
      AND city NOT IN ('Singapore', 'Mysore')
),

delivery_gaps AS (
    -- Step 2: Use LEAD to find the gap between current delivery and the next one
    SELECT 
        provider_id,
        reporting_city,
        delivery_date AS ldd_date,
        DATE_TRUNC('week', delivery_date) AS ldd_week,
        COALESCE(
            LEAD(delivery_date) OVER (PARTITION BY provider_id ORDER BY delivery_date), 
            CURRENT_DATE
        ) AS next_activity_date
    FROM delivery_log
),

churn_instances AS (
    -- Step 3: Filter for gaps of 6 days or more and check marking hours
    SELECT
        dg.provider_id,
        dg.reporting_city,
        dg.ldd_week,
        dg.ldd_date,
        COUNT(CASE WHEN acm.status = 'marked working' THEN 1 END) AS post_ldd_working_hours
    FROM delivery_gaps dg
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON dg.provider_id = acm.provider_id
        AND DATE(acm.date) > dg.ldd_date
        AND DATE(acm.date) <= dg.ldd_date + INTERVAL '7 day'
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE DATEDIFF('day', dg.ldd_date, dg.next_activity_date) > 6
    GROUP BY 1, 2, 3, 4
),

l7d AS (
    -- Original churn definition logic (for gross_churn)
    SELECT
        reporting_city,
        ldd_week,
        provider_id,
        'Not Working' AS l7d_status
    FROM churn_instances
    WHERE post_ldd_working_hours < 8
),

l7d_current AS (
    -- L7D status based on last 7 days calendar marking (for net_churn)
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

provider_current_status_for_reactivation AS (
    -- For reactivation calculation using l7d_current
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

-- ============================================================
-- HUB TAGGED LOGIC - Get provider's hub for each date/week
-- ============================================================
hub_tagged_base AS (
    SELECT 
        aa.provider_id,
        DATE(aa.updated_at) AS updated,
        DATE_TRUNC('week', DATE(aa.updated_at)) AS week_start,
        LEFT(hub_name, CHARINDEX('_city', hub_name) - 1) AS tagged_hub
    FROM PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS aa
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW ON SMART_HUBS_VIEW.hub_id = aa.primary_hub_id
    LEFT JOIN PROVIDER__DAILY__FACTS pdf ON pdf.provider_id = aa.provider_id
    WHERE pdf.CUSTOMER_CATEGORY_KEY = 'insta_maids'
      AND updated >= '2024-04-01'
),

-- Get the latest hub for each provider per week
provider_hub_weekly AS (
    SELECT 
        provider_id,
        week_start,
        tagged_hub,
        ROW_NUMBER() OVER (PARTITION BY provider_id, week_start ORDER BY updated DESC) AS rn
    FROM hub_tagged_base
    WHERE tagged_hub IS NOT NULL
),

provider_hub_latest AS (
    SELECT 
        provider_id,
        week_start,
        tagged_hub
    FROM provider_hub_weekly
    WHERE rn = 1
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

-- ============================================================
-- HUB-WISE REACTIVATION CALCULATION
-- ============================================================
reactivation_hub_wise AS (
    SELECT
        bf.reporting_city,
        COALESCE(phl.tagged_hub, 'Unknown Hub') AS hub,
        bf.week_start AS week,
        COUNT(DISTINCT bf.provider_id) AS reactivations
    FROM base_final bf
    -- Join with provider's hub for that week
    LEFT JOIN provider_hub_latest phl
        ON phl.provider_id = bf.provider_id
        AND phl.week_start = bf.week_start
    WHERE bf.week_mark_status = 'Working'
      AND bf.lag_week_mark_status = 'Not Working'
      AND bf.working_status = 1
      AND bf.pro_current_status_for_reactivation = 'Active'
      AND EXISTS (
          SELECT 1 FROM churn_events ce
          WHERE ce.provider_id = bf.provider_id
            AND ce.churn_week = (bf.week_start - INTERVAL '1 week')
      )
    GROUP BY 1, 2, 3
)

-- ============================================================
-- FINAL OUTPUT: Hub-wise Reactivations
-- ============================================================
SELECT 
    reporting_city,
    hub,
    week,
    reactivations
FROM reactivation_hub_wise
WHERE week >= '2024-04-01'
ORDER BY reporting_city, hub, week DESC;


-- ============================================================
-- ALTERNATIVE: If you want SUM of reactivations by hub across all cities
-- ============================================================
/*
SELECT 
    hub,
    week,
    SUM(reactivations) AS total_reactivations
FROM reactivation_hub_wise
WHERE week >= '2024-04-01'
GROUP BY hub, week
ORDER BY hub, week DESC;
*/


-- ============================================================
-- ALTERNATIVE: Hub-wise with city breakdown and totals
-- ============================================================
/*
SELECT 
    hub,
    week,
    SUM(reactivations) AS total_reactivations,
    LISTAGG(DISTINCT reporting_city, ', ') WITHIN GROUP (ORDER BY reporting_city) AS cities
FROM reactivation_hub_wise
WHERE week >= '2024-04-01'
GROUP BY hub, week
ORDER BY hub, week DESC;
*/
