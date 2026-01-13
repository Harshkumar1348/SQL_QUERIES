-- Corrected churn_pros and churn_status logic
-- Changes made:
-- 1. Changed l7d (last 7 days) to n7d (next 7 days) for working hours calculation
-- 2. Added active_status based on last_delivery_date logic
-- 3. churn_status now correctly combines active_status AND n7d_status
-- 4. Changed working hours threshold from >8 to >5

WITH main AS (
    -- Assuming main CTE exists with provider_id, ldd (last_delivery_date), app_date, age, etc.
    SELECT * FROM your_main_table
),

trainer_mapping AS (
    -- Assuming trainer_mapping CTE exists
    SELECT * FROM your_trainer_mapping
),

current_hub AS (
    -- Assuming current_hub CTE exists
    SELECT * FROM your_current_hub
),

-- CORRECTED: Changed from l7d (last 7 days) to n7d (next 7 days)
-- This calculates working hours for the NEXT 7 days (current_date+1 to current_date+7)
n7d AS (
    SELECT 
        pdf.provider_id,
        SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END) AS working_hrs,
        CASE 
            WHEN SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END) > 5 THEN 'Working'
            ELSE 'Not Working'
        END AS N7D_status
    FROM provider__daily__facts pdf
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON pdf.provider_id = acm.provider_id
        AND DATE(acm.date) BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + 7
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),

delivery_count AS (
    SELECT 
        provider_id,
        COUNT(DISTINCT customer_request_id) AS delivery_count
    FROM request__daily__facts
    WHERE service_delivered = 1
      AND reporting_supercategory_new = 'Insta Help'
    GROUP BY provider_id
),

utilization AS (
    SELECT 
        provider_id,
        COUNT_IF(DATE(bdate) >= DATEADD('day', -14, CURRENT_DATE)) AS last_14_days_util,
        COUNT_IF(DATE(bdate) >= DATEADD('day', -7, CURRENT_DATE)) AS last_7_days_util
    FROM request__daily__facts
    WHERE service_delivered = 1
      AND reporting_supercategory_new = 'Insta Help'
    GROUP BY provider_id
),

psp_data_raw AS (
    SELECT
        ppp.referenceid AS _id,
        ppp.provider_id AS providerid,
        pm.provider_name,
        pm.city,
        pm.approval_date AS app_date,
        TO_CHAR(DATE_TRUNC('month', app_date), 'YYYY-MM') AS app_month,
        ppp.tier_start_date AS start_date,
        ppp.tier_end_date AS end_date
    FROM PUBLIC.PROVIDER_PROMISE_PLAN__DAILY__METRICS AS ppp
    LEFT JOIN public.provider_master pm 
        ON ppp.provider_id = pm.provider_id
        AND pm.CUSTOMER_CATEGORY_KEY = 'insta_maids'
        AND pm.provider_name NOT ILIKE '%test%'
),

ta AS (
    SELECT 
        ppp.tier_start_date AS start_date,
        ppp.tier_end_date AS tier_end_date,
        ppp.provider_id AS providerid,
        ppp.plan_status AS status,
        ppp.referenceid AS _id,
        ppp.tier
    FROM PUBLIC.PROVIDER_PROMISE_PLAN__DAILY__METRICS ppp
    WHERE ppp.provider_id IN (SELECT DISTINCT psp_data_raw.providerid FROM psp_data_raw)
      AND ppp.plan_status IN ('active', 'inReview', 'completed')
      AND ppp.tier IS NOT NULL
),

tier_ranked AS (
    SELECT
        providerid,
        tier,
        start_date,
        tier_end_date,
        ROW_NUMBER() OVER (PARTITION BY providerid ORDER BY start_date DESC) AS tier_rank
    FROM ta
),

tier_final AS (
    SELECT *
    FROM tier_ranked
    WHERE tier_rank <= 2
),

tier_pivot AS (
    SELECT 
        providerid,
        MAX(CASE WHEN tier_rank = 1 THEN tier END) AS last_tier,
        MAX(CASE WHEN tier_rank = 2 THEN tier END) AS prev_tier
    FROM tier_final
    GROUP BY providerid
),

tier_as_of_ldd AS (
    SELECT
        ta.providerid,
        ta.tier,
        ta.start_date,
        ta.tier_end_date
    FROM ta
    WHERE ta.tier IS NOT NULL
),

tier_cycle_summary AS (
    SELECT
        providerid,
        COUNT(*) AS total_tier_cycles,
        COUNT_IF(LOWER(tier) = 'pip') AS pip_tier_cycles,
        ROUND(
            COUNT_IF(LOWER(tier) = 'pip')::FLOAT / NULLIF(COUNT(*), 0), 2
        ) AS pip_percent
    FROM ta
    GROUP BY providerid
)

SELECT 
    final.*,
    COALESCE(tm.trainer_name, 'Unknown') AS trainer_name,
    COALESCE(tp.last_tier, 'Unknown') AS last_tier,
    COALESCE(tp.prev_tier, 'Unknown') AS prev_tier,
    COALESCE(ldd_tier.tier, 'Unknown') AS tier_as_of_ldd,
    COALESCE(tcs.total_tier_cycles, 0) AS total_tier_cycles,
    COALESCE(tcs.pip_tier_cycles, 0) AS pip_tier_cycles,
    COALESCE(tcs.pip_percent, 0) AS pip_percent,
    ch.hub_name AS hub_name
FROM (
    SELECT 
        m.*,
        m.ldd_week AS "ldd_week::filter",
        COALESCE(n7d.N7D_status, 'Unknown') AS N7D_status,
        COALESCE(dc.delivery_count, 0) AS delivery_count,
        COALESCE(u.last_14_days_util, 0) AS last_14_days_util,
        COALESCE(u.last_7_days_util, 0) AS last_7_days_util,
        
        -- CORRECTED: active_status based on last_delivery_date (ldd)
        CASE 
            WHEN m.ldd > CURRENT_DATE - 7 THEN 'Active'
            WHEN m.ldd IS NULL AND DATE(m.app_date) > CURRENT_DATE - 7 THEN 'Active'
            ELSE 'Churned'
        END AS active_status,
        
        -- CORRECTED: churn_status combines active_status AND n7d_status
        -- A provider is 'churn' ONLY if they are 'Churned' AND 'Not Working' in next 7 days
        CASE 
            WHEN (
                CASE 
                    WHEN m.ldd > CURRENT_DATE - 7 THEN 'Active'
                    WHEN m.ldd IS NULL AND DATE(m.app_date) > CURRENT_DATE - 7 THEN 'Active'
                    ELSE 'Churned'
                END
            ) = 'Churned' AND COALESCE(n7d.N7D_status, 'Not Working') = 'Not Working' 
            THEN 'churn'
            ELSE 'active'
        END AS churn_status,

        -- Updated churn_bucket logic (keeping original structure but using corrected churn logic)
        CASE    
            WHEN COALESCE(n7d.N7D_status, 'Unknown') = 'Working' THEN '1. Active'
            WHEN m.ldd IS NULL AND m.app_date >= CURRENT_DATE - 7 THEN '1. Active'
            WHEN m.ldd > CURRENT_DATE - 7 THEN '1. Active'
            WHEN m.age = 0 THEN '3. D0 churn'
            WHEN m.age <= 7 THEN '4. D7 churn'
            WHEN m.age <= 17 THEN '5. D15 churn'
            WHEN m.age <= 30 THEN '6. D30 churn'
            WHEN m.age <= 60 THEN '7. D60 churn'
            WHEN m.age <= 90 THEN '8. D90 churn'
            WHEN m.age <= 120 THEN '9. D120 churn'
            ELSE '10. >D120 churn'
        END AS churn_bucket,

        -- Recompute ELC_LLC to match above logic
        CASE 
            WHEN COALESCE(n7d.N7D_status, 'Unknown') = 'Working' THEN '1. Active'
            WHEN m.ldd IS NULL AND m.app_date >= CURRENT_DATE - 7 THEN '1. Active'
            WHEN m.ldd > CURRENT_DATE - 7 THEN '1. Active'
            WHEN m.age <= 30 THEN '3. ELC churn'
            ELSE '4. LLC churn' 
        END AS ELC_LCC

    FROM main m
    LEFT JOIN n7d ON m.provider_id = n7d.provider_id
    LEFT JOIN delivery_count dc ON m.provider_id = dc.provider_id
    LEFT JOIN utilization u ON m.provider_id = u.provider_id
) final
LEFT JOIN trainer_mapping tm ON final.provider_id = tm.provider_id
LEFT JOIN tier_pivot tp ON final.provider_id = tp.providerid
LEFT JOIN tier_as_of_ldd ldd_tier
    ON final.provider_id = ldd_tier.providerid
   AND final.ldd BETWEEN ldd_tier.start_date AND ldd_tier.tier_end_date
LEFT JOIN tier_cycle_summary tcs ON final.provider_id = tcs.providerid
LEFT JOIN current_hub ch ON final.provider_id = ch.provider_id;
