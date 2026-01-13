/*
================================================================================
CHURN_STATUS AND CHURN_PROS LOGIC FIX
================================================================================

PROBLEM:
The original query uses L7D (Last 7 Days) logic which looks at PAST working hours,
but the correct logic from Query A uses N7D (Next 7 Days) which looks at FUTURE
working hours to determine if a provider will be working.

ORIGINAL INCORRECT LOGIC:
========================
1. L7D checked PAST 7 days: DATE(acm.date) BETWEEN CURRENT_DATE - 6 and CURRENT_DATE
2. Threshold was >8 hours
3. churn_status was determined solely by L7D_status

CORRECT LOGIC FROM QUERY A:
===========================
1. active_status based on last_delivery_date:
   - 'Active' if last_delivery_date > current_date - 7
   - 'Active' if last_delivery_date IS NULL AND app_date > current_date - 7
   - 'Churned' otherwise

2. N7D_status based on FUTURE working hours (next 7 days):
   - working_hrs = SUM of marked_working for dates BETWEEN current_date+1 AND current_date+7
   - 'Working' if working_hrs > 5
   - 'Not Working' otherwise

3. churn_status combines BOTH conditions:
   - 'churn' ONLY if active_status = 'Churned' AND n7d_status = 'Not Working'
   - 'active' otherwise

================================================================================
*/

-- =============================================================================
-- SECTION 1: CHANGE N7D CTE (replaces l7d CTE)
-- =============================================================================

-- OLD (INCORRECT):
/*
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
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 and CURRENT_DATE  -- WRONG: Looking at PAST
        AND start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),
*/

-- NEW (CORRECT):
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
        AND DATE(acm.date) BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + 7  -- CORRECT: Looking at NEXT 7 days
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),


-- =============================================================================
-- SECTION 2: CHANGE churn_status LOGIC IN THE SELECT STATEMENT
-- =============================================================================

-- OLD (INCORRECT):
/*
CASE   
    WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN '3. Churn'
    WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
    WHEN m.ldd IS NULL AND DATE(m.app_date) >= CURRENT_DATE - 7 THEN '1. Active'
END AS churn_status,
*/

-- NEW (CORRECT):
-- First, we need to calculate active_status inline or as a separate column
-- active_status logic:
CASE 
    WHEN m.ldd > CURRENT_DATE - 7 THEN 'Active'
    WHEN m.ldd IS NULL AND DATE(m.app_date) > CURRENT_DATE - 7 THEN 'Active'
    ELSE 'Churned'
END AS active_status,

-- churn_status logic (combines active_status AND n7d_status):
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


-- =============================================================================
-- SECTION 3: UPDATE THE JOIN
-- =============================================================================

-- OLD:
-- LEFT JOIN l7d on m.provider_id = l7d.provider_id

-- NEW:
-- LEFT JOIN n7d ON m.provider_id = n7d.provider_id


-- =============================================================================
-- SECTION 4: churn_pros COUNT REMAINS THE SAME
-- =============================================================================

-- The churn_pros calculation itself doesn't change:
-- count(distinct case when life_cycle='ELC' and churn_status='churn' then provider_id end) as churn_pros

-- But now churn_status will be correctly calculated using the new logic above,
-- so churn_pros will reflect the correct count of providers who:
-- 1. Are in ELC (Early Life Cycle, age <= 30 days)
-- 2. Have active_status = 'Churned' (no delivery in last 7 days, not newly approved)
-- 3. AND have N7D_status = 'Not Working' (no working hours marked for next 7 days)


-- =============================================================================
-- SECTION 5: ALSO UPDATE churn_bucket AND ELC_LCC IF NEEDED
-- =============================================================================

-- If you want these to be consistent with the new logic:

-- Updated churn_bucket:
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

-- Updated ELC_LCC:
CASE 
    WHEN COALESCE(n7d.N7D_status, 'Unknown') = 'Working' THEN '1. Active'
    WHEN m.ldd IS NULL AND m.app_date >= CURRENT_DATE - 7 THEN '1. Active'
    WHEN m.ldd > CURRENT_DATE - 7 THEN '1. Active'
    WHEN m.age <= 30 THEN '3. ELC churn'
    ELSE '4. LLC churn' 
END AS ELC_LCC
