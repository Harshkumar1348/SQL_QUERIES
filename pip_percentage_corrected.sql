-- CORRECTED PIP Percentage Query
-- Issue: Original query counted churned providers in pip_px but not in active_px
-- Fix: Both metrics now only count active (non-churned) providers

WITH pip_base AS (
  SELECT
    lt.provider_id,
    COALESCE(lt.leave_days, 0) AS leave_days,
    COALESCE(pp.paf_cancels, 0) AS cancels,
    COALESCE(ls.late_show_count, 0) AS late_shows,
    COALESCE(ar.avg_rating_50, 0) AS l50_rating,
    CASE
      WHEN COALESCE(lt.leave_days, 0) >= 5
      OR COALESCE(pp.paf_cancels, 0) >= 4
      OR COALESCE(ar.avg_rating_50, 0) < 4.7
      OR COALESCE(ls.late_show_count, 0) >= 5 THEN 1
      ELSE 0
    END AS is_pip
  FROM
    latest_tier lt
    LEFT JOIN avg_rating_last_50 ar ON lt.provider_id = ar.provider_id
    LEFT JOIN late_shows ls ON lt.provider_id = ls.provider_id
    LEFT JOIN paf_provider pp ON lt.provider_id = pp.provider_id
),
pip_tm AS (
  SELECT
    tm.trainer_name AS tm,
    -- Count ACTIVE providers on PIP
    COUNT(
      DISTINCT CASE
        WHEN pb.is_pip = 1 
        AND COALESCE(c.churn_status, 'active') <> 'churn' 
        THEN pb.provider_id
      END
    ) AS pip_px,
    -- Count total ACTIVE providers
    COUNT(
      DISTINCT CASE
        WHEN COALESCE(c.churn_status, 'active') <> 'churn' 
        THEN pb.provider_id
      END
    ) AS active_px,
    -- Calculate PIP percentage
    ROUND(
      CASE 
        WHEN COUNT(
          DISTINCT CASE
            WHEN COALESCE(c.churn_status, 'active') <> 'churn' 
            THEN pb.provider_id
          END
        ) > 0 
        THEN (
          COUNT(
            DISTINCT CASE
              WHEN pb.is_pip = 1 
              AND COALESCE(c.churn_status, 'active') <> 'churn' 
              THEN pb.provider_id
            END
          ) * 100.0 / 
          COUNT(
            DISTINCT CASE
              WHEN COALESCE(c.churn_status, 'active') <> 'churn' 
              THEN pb.provider_id
            END
          )
        )
        ELSE 0 
      END, 
      2
    ) AS pip_percentage
  FROM
    pip_base pb
    JOIN trainer_mapping tm ON pb.provider_id = tm.provider_id
    LEFT JOIN churn_cte c ON pb.provider_id = c.provider_id
  GROUP BY
    tm.trainer_name
)
SELECT 
  tm,
  pip_px,
  active_px,
  pip_percentage
FROM pip_tm
ORDER BY pip_percentage DESC;

-- EXPLANATION OF CHANGES:
-- 
-- BEFORE (INCORRECT):
-- pip_px: COUNT(DISTINCT CASE WHEN pb.is_pip = 1 THEN pb.provider_id END)
--   - This counted ALL pip providers including churned ones
--
-- active_px: COUNT(DISTINCT CASE WHEN churn_status <> 'churn' THEN pb.provider_id END)  
--   - This counted ALL active providers (pip + non-pip)
--
-- AFTER (CORRECT):
-- pip_px: COUNT(DISTINCT CASE WHEN pb.is_pip = 1 AND churn_status <> 'churn' THEN pb.provider_id END)
--   - Now counts ONLY ACTIVE providers on PIP
--
-- active_px: Same as before - counts all active providers
--   - This remains the correct denominator
--
-- pip_percentage: Direct calculation added to avoid external computation errors
