-- =============================================================================
-- CHURN LOGIC BUG ANALYSIS
-- Issue: Providers with approval_date = CURRENT_DATE incorrectly marked as Churn
-- =============================================================================

-- =============================================================================
-- BUG #1: SQL Operator Precedence (AND binds tighter than OR)
-- =============================================================================
--
-- ORIGINAL (line in the final SELECT):
--
--   CASE
--     WHEN COALESCE(l7d.L7D_status,'Unknown') = 'Not Working'
--          or ran.status_pro='churn' AND m.app_date is not null
--     THEN '3. Churn'
--     ...
--
-- Because AND has higher precedence than OR, SQL parses this as:
--
--   WHEN (L7D = 'Not Working')
--     OR (status_pro = 'churn' AND app_date IS NOT NULL)
--
-- The "AND m.app_date IS NOT NULL" guard only applies to the
-- ran.status_pro = 'churn' branch.  It does NOT protect the
-- L7D = 'Not Working' branch.  So any provider whose L7D_status
-- is 'Not Working' is immediately classified as Churn, regardless
-- of approval_date or any other condition.
--
-- If the intent was to require app_date IS NOT NULL for BOTH
-- OR-branches, you need explicit parentheses:
--
--   WHEN (L7D = 'Not Working' OR status_pro = 'churn')
--     AND m.app_date IS NOT NULL


-- =============================================================================
-- BUG #2: CASE Evaluation Order — Newly-Approved Exemption Is Unreachable
-- =============================================================================
--
-- ORIGINAL order:
--
--   CASE
--     WHEN <churn condition>  THEN '3. Churn'   -- evaluated 1st
--     WHEN <active condition> THEN '1. Active'  -- evaluated 2nd
--     WHEN m.ldd IS NULL
--       AND DATE(m.app_date) >= CURRENT_DATE - 7
--     THEN '1. Active'                          -- evaluated 3rd  <-- TOO LATE
--   END
--
-- CASE returns the FIRST matching branch.  A provider approved
-- today will match the churn condition first (because of Bug #1
-- + Bug #3 below), so the third branch never runs for them.
--
-- FIX: Move the newly-approved exemption to the FIRST position
-- so it is evaluated before the churn check.


-- =============================================================================
-- BUG #3: New Providers Always Have L7D_status = 'Not Working'
-- =============================================================================
--
-- The l7d CTE counts "marked working" slots in the last 7 days
-- and requires the count > 8 to label a provider as 'Working'.
--
-- A provider approved today:
--   - Has at most 1 day of calendar slots (today)
--   - Even with 12 hours of slots (8 AM–7 PM), many won't have
--     marked all of them
--   - The LEFT JOIN to calendar data can return 0 working slots
--
-- So for any newly-approved provider, L7D_status = 'Not Working'
-- is almost guaranteed.  Combined with Bug #1 + Bug #2, the
-- churn CASE branch catches them immediately.


-- =============================================================================
-- BUG #4 (Minor): Mixed Data Types in ldd_week Column
-- =============================================================================
--
-- In the main CTE:
--
--   CASE
--     WHEN last_delivery_date IS NULL
--       THEN TO_CHAR(DATE_TRUNC('W', DATE(approval_date)), 'YYYY-MM-DD')
--     ELSE DATE_TRUNC('W', DATE(last_delivery_date))
--   END AS ldd_week
--
-- The first branch returns VARCHAR, the second returns DATE.
-- Snowflake may implicitly cast, but this is fragile and can
-- cause unexpected comparison behavior in:
--   WHERE m.ldd_week >= '2025-01-01'
--
-- FIX: Use a consistent return type (both DATE or both VARCHAR).


-- =============================================================================
-- BUG #5 (Minor): Second WHEN Also Has Unparenthesized OR
-- =============================================================================
--
-- ORIGINAL:
--   WHEN COALESCE(l7d.L7D_status,'Unknown') = 'Working'
--        or ran.status_pro = 'active'
--   THEN '1. Active'
--
-- This means a provider is Active if EITHER L7D is Working OR
-- status_pro is active — but this branch is only reached if the
-- first churn branch did NOT match.  Due to Bug #1, any provider
-- with L7D = 'Not Working' already matched the churn branch,
-- so even if status_pro = 'active', they're already Churn.
--
-- In effect, the OR in the second WHEN is dead logic for the
-- conflicting case (L7D = 'Not Working' AND status_pro = 'active').


-- =============================================================================
-- CORRECTED churn_status LOGIC
-- =============================================================================
--
-- Replace the original CASE block:
--
--   CASE
--     WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working'
--       or ran.status_pro='churn' AND m.app_date is not null
--     THEN '3. Churn'
--     WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working'
--       or ran.status_pro= 'active'
--     THEN '1. Active'
--     WHEN m.ldd IS NULL
--       AND DATE(m.app_date) >= CURRENT_DATE - 7
--     THEN '1. Active'
--   END AS churn_status
--
-- With:
--
--   CASE
--     -- 1) Newly approved (within 7 days) with no deliveries → Active
--     WHEN m.ldd IS NULL
--       AND DATE(m.app_date) >= CURRENT_DATE - 7
--     THEN '1. Active'
--
--     -- 2) Working in L7D or not temp-blocked → Active
--     WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working'
--       OR COALESCE(ran.status_pro, 'active') = 'active'
--     THEN '1. Active'
--
--     -- 3) Not working in L7D OR temp-blocked > 7 days → Churn
--     WHEN (COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working'
--       OR ran.status_pro = 'churn')
--       AND m.app_date IS NOT NULL
--     THEN '3. Churn'
--   END AS churn_status
--
-- Key changes:
--   a) Newly-approved exemption is now FIRST (evaluated before churn)
--   b) Active check comes SECOND (providers working OR not temp-blocked)
--   c) Churn check is LAST, with proper parentheses around the OR
--   d) The AND m.app_date IS NOT NULL now guards the entire condition


-- =============================================================================
-- FULL CORRECTED QUERY (only the final SELECT subquery is changed)
-- =============================================================================
-- The fix is in the inner SELECT of the "final" subquery.
-- All CTEs above remain unchanged.

/*
  ... (all CTEs remain the same up to and including utilization) ...

  Replace the inner SELECT that produces `final` with:
*/

-- CORRECTED inner SELECT:
-- (showing only the changed CASE expression and its context)

/*
SELECT
    m.*,
    m.ldd_week as "ldd_week::filter",
    COALESCE(n7d.N7D_status, 'Unknown') AS N7D_status,
    COALESCE(dc.delivery_count, 0) AS delivery_count,
    COALESCE(u.last_14_days_util, 0) AS last_14_days_util,
    COALESCE(u.last_7_days_util, 0) AS last_7_days_util,

    -- ===== CORRECTED churn_status =====
    CASE
      -- 1) Newly approved providers (within last 7 days, no deliveries yet)
      WHEN m.ldd IS NULL AND DATE(m.app_date) >= CURRENT_DATE - 7
        THEN '1. Active'

      -- 2) Active: L7D working OR not temp-blocked
      WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working'
        OR COALESCE(ran.status_pro, 'active') = 'active'
        THEN '1. Active'

      -- 3) Churn: not working AND/OR temp-blocked, with valid app_date
      WHEN (COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working'
            OR ran.status_pro = 'churn')
        AND m.app_date IS NOT NULL
        THEN '3. Churn'
    END AS churn_status,
    -- ===== END CORRECTED churn_status =====

    CASE
      WHEN churn_status = '1. Active' THEN '1. Active'
      WHEN m.age = 0   AND churn_status = '3. Churn' THEN '3. D0 churn'
      WHEN m.age <= 7  AND churn_status = '3. Churn' THEN '4. D7 churn'
      WHEN m.age <= 17 AND churn_status = '3. Churn' THEN '5. D15 churn'
      WHEN m.age <= 30 AND churn_status = '3. Churn' THEN '6. D30 churn'
      WHEN m.age <= 60 AND churn_status = '3. Churn' THEN '7. D60 churn'
      WHEN m.age <= 90 AND churn_status = '3. Churn' THEN '8. D90 churn'
      WHEN m.age <= 120 AND churn_status = '3. Churn' THEN '9. D120 churn'
      ELSE '10. >D120 churn'
    END AS churn_bucket,

    CASE
      WHEN churn_status = '1. Active' THEN '1. Active'
      WHEN m.age <= 30 AND churn_status = '3. Churn' THEN '3. ELC churn'
      ELSE '4. LLC churn'
    END AS ELC_LCC

FROM main m
LEFT JOIN n7d ON m.provider_id = n7d.provider_id
LEFT JOIN l7d ON m.provider_id = l7d.provider_id
LEFT JOIN ranked ran ON m.provider_id = ran.provider_id AND ran.rn = 1
LEFT JOIN delivery_count dc ON m.provider_id = dc.provider_id
LEFT JOIN utilization u ON m.provider_id = u.provider_id
WHERE m.ldd_week >= '2025-01-01'
*/


-- =============================================================================
-- ALSO RECOMMENDED: Fix ldd_week mixed types in the main CTE
-- =============================================================================
--
-- Change:
--   CASE
--     WHEN last_delivery_date IS NULL
--       THEN TO_CHAR(DATE_TRUNC('W', DATE(approval_date)), 'YYYY-MM-DD')
--     ELSE DATE_TRUNC('W', DATE(last_delivery_date))
--   END AS ldd_week
--
-- To (consistent DATE type):
--   CASE
--     WHEN last_delivery_date IS NULL
--       THEN DATE_TRUNC('W', DATE(approval_date))::DATE
--     ELSE DATE_TRUNC('W', DATE(last_delivery_date))::DATE
--   END AS ldd_week


-- =============================================================================
-- SUMMARY OF ALL ISSUES
-- =============================================================================
--
-- | #  | Severity | Description                                           |
-- |----|----------|-------------------------------------------------------|
-- | 1  | CRITICAL | AND/OR precedence: AND m.app_date IS NOT NULL only    |
-- |    |          | guards the second OR branch, not the first            |
-- | 2  | CRITICAL | CASE order: newly-approved check is 3rd, but churn    |
-- |    |          | branch catches new providers first                    |
-- | 3  | CRITICAL | L7D_status for new providers is always 'Not Working'  |
-- |    |          | (they have no calendar history yet)                   |
-- | 4  | MINOR    | ldd_week mixes VARCHAR and DATE return types           |
-- | 5  | MINOR    | Second WHEN branch has dead logic for conflict cases   |
-- =============================================================================
