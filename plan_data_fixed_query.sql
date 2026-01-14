/*
================================================================================
FIXED QUERY - Get only the LAST COMPLETED plan (not ongoing)
================================================================================
Issues Fixed:
1. Syntax error: "between(1,2)" changed to "= 1" or "BETWEEN 1 AND 2"
2. Logic: Added filter to exclude ongoing plans (plan_end_date >= CURRENT_DATE)
3. ROW_NUMBER now only considers COMPLETED plans
================================================================================
*/

WITH plan_data AS (
    SELECT 
        DISTINCT 
        provider_id,
        REPORTING_CITY,
        plan_start_date,
        plan_end_date,
        TARGET_EARNINGS__SUM,
        ACTUAL_EARNINGS__SUM,
        MING_INCENTIVE_PAYOUT__SUM,
        PAF_CANCELLATION_AT_TIER,
        RATING_ERROR_AT_TIER,
        -- ROW_NUMBER applied ONLY to completed plans (plan_end_date < CURRENT_DATE)
        ROW_NUMBER() OVER(PARTITION BY PROVIDER_ID ORDER BY plan_end_date DESC) AS rn
    FROM PUBLIC.PROVIDER_PROMISE_PLAN__DAILY__METRICS
    WHERE REPORTING_CATEGORY_NEW = 'Insta Help'
      AND plan_start_date IS NOT NULL
      AND provider_id IS NOT NULL
      -- IMPORTANT: Only consider COMPLETED plans (plan_end_date < current_date)
      -- This excludes ongoing plans
      AND CAST(plan_end_date AS DATE) < CURRENT_DATE
      AND CAST(plan_end_date AS DATE) >= CURRENT_DATE - 60
),

provider_map AS (
    SELECT DISTINCT
        provider_id,
        sql_provider_id
    FROM provider__daily__facts
    WHERE customer_category_key = 'insta_maids'
),

hub_tagged_base AS (
    SELECT * FROM (
        SELECT 
            aa.provider_id,
            DATE(aa.updated_at) AS updated,
            sh.hub_name,
            ROW_NUMBER() OVER (PARTITION BY aa.provider_id ORDER BY updated DESC) AS rnk
        FROM PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS aa
        LEFT JOIN SMART_HUBS_VIEW sh 
            ON sh.hub_id = aa.primary_hub_id
        LEFT JOIN PROVIDER__DAILY__FACTS pdf 
            ON pdf.provider_id = aa.provider_id
        WHERE pdf.reporting_category_new = 'Insta Help'
          AND updated >= '2025-01-01'
    ) t
    WHERE rnk = 1
),

working_days AS (
    SELECT 
        p.provider_id,
        p.plan_start_date,
        p.plan_end_date,
        COUNT(DISTINCT DATE(cs.date)) AS working_days
    FROM PUBLIC.PROVIDER_PROMISE_PLAN__DAILY__METRICS p
    JOIN PROVIDERXDATEXHOUR__CALENDAR_MARKING__HOURLY__FACTS cs
        ON cs.provider_id = p.provider_id
       AND cs.status = 'marked working'
       AND cs.START_HOUR_LOCAL BETWEEN 8 AND 18
       AND DATE(cs.date) BETWEEN p.plan_start_date AND p.plan_end_date
    JOIN PUBLIC.REQUEST__DAILY__FACTS md
        ON md.provider_id = p.provider_id
       AND DATE(md.BDATE_FINAL) = DATE(cs.date)
       AND md.service_delivered IN ('1', 1, 'true', TRUE)
    WHERE p.REPORTING_CATEGORY_NEW = 'Insta Help'
      AND CAST(p.plan_end_date AS DATE) < CURRENT_DATE
      AND CAST(p.plan_end_date AS DATE) >= CURRENT_DATE - 60
    GROUP BY p.provider_id, p.plan_start_date, p.plan_end_date
)

SELECT DISTINCT  
    p.REPORTING_CITY AS "City::multi-filter",
    h.hub_name AS "Hub::multi-filter",
    p.provider_id,
    h.hub_name,
    p.TARGET_EARNINGS__SUM AS Target_earning,
    p.ACTUAL_EARNINGS__SUM AS Actual_earning,
    p.MING_INCENTIVE_PAYOUT__SUM AS Burn_MG,
    p.plan_start_date,
    p.plan_end_date,
    w.working_days,
    p.PAF_CANCELLATION_AT_TIER,
    p.RATING_ERROR_AT_TIER
FROM plan_data p
LEFT JOIN hub_tagged_base h
    ON p.provider_id = h.provider_id
LEFT JOIN working_days w
    ON p.provider_id = w.provider_id
   AND p.plan_start_date = w.plan_start_date
   AND p.plan_end_date = w.plan_end_date 
-- FIXED: Correct syntax for filtering row number
WHERE p.rn = 1  -- Get only the LAST completed plan per provider
ORDER BY p.provider_id, p.plan_start_date;


/*
================================================================================
ALTERNATIVE: If you want LAST 2 completed plans, use this WHERE clause instead:
================================================================================
WHERE p.rn BETWEEN 1 AND 2
-- OR
WHERE p.rn IN (1, 2)
================================================================================
*/
