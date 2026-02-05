with view1 as(
WITH base AS (
    SELECT DISTINCT
        lead_id,
        a.provider_id,
        b.provider_name,
        DATE(b.approval_date) AS approval_date,
        city,
        DATE_TRUNC('week', DATE(walked_in)) AS wi_week,
        walked_in AS wi_date,
        screening_date,
        screening_qualified,
        partially_recharged,
        scheduled_for_training,
        scheduling_triggered_for_training,
        in_training,
        training_passed,
        training_failed,
        updated_at_ist
    FROM public.lead__onboarding_funnel__daily__facts a
    LEFT JOIN provider__daily__facts b 
        ON a.provider_id = b.provider_id
    WHERE a.customer_category_key = 'insta_maids'
      AND walked_in IS NOT NULL
      AND DATE_TRUNC('week', DATE(walked_in)) > '2025-01-01'
),

src AS (
    SELECT DISTINCT
        a.provider_id,
        f.value:"questionnaire_created_by"::string AS raw_trainer,
        f.value:"questionnaire_key"::string AS questionnaire_key,
        f.value:"questionnaire_status"::string AS questionnaire_status,
        a.updated_at_ist
    FROM providerxcoursexchapterxassessment__provider_training__daily__facts a,
         LATERAL FLATTEN(input => questionnaire_info) f
    WHERE customer_category_key = 'insta_maids'
      AND questionnaire_key = 'IH_FA_Module'
      AND questionnaire_status = 'completed'
    QUALIFY RANK() OVER (
        PARTITION BY a.provider_id 
        ORDER BY a.updated_at_ist DESC
    ) = 1
),

POC AS (
    SELECT 
        provider_id,
        created_by,
        DATE_TRUNC('week', created_at_ist) AS sdate
    FROM (
        SELECT 
            provider_id,
            created_by,
            created_at_ist,
            ROW_NUMBER() OVER (
                PARTITION BY provider_id
                ORDER BY created_at_ist DESC
            ) AS rn
        FROM public.provider_module_provider_response__view
        WHERE module_type = 'screening'
    )
    WHERE rn = 1
      AND created_by IS NOT NULL
),
tm_age as(
select created_by,
min(date(sdate)) as first_screening,
datediff('day',first_screening,current_date()) as tmm,
case when tmm>60 then 'LLC Trainer'
else 'ELC Trainer'
end as age_tm
from poc
group by 1
)
,
pre_training AS (
    SELECT
        p.created_by,
        p.sdate,
        COUNT(CASE WHEN p.sdate IS NOT NULL THEN 1 END) AS total_screening,
        ROUND(
            100.0 * COUNT(CASE WHEN b.screening_qualified IS NOT NULL THEN 1 END)
            / NULLIF(COUNT(CASE WHEN p.sdate IS NOT NULL THEN 1 END), 0),
            2
        ) AS sp_pct,
        ROUND(
            100.0 * COUNT(CASE WHEN b.training_passed IS NOT NULL THEN 1 END)
            / NULLIF(COUNT(CASE WHEN b.screening_qualified IS NOT NULL THEN 1 END), 0),
            2
        ) AS sp_tp_pct
    FROM base b
    LEFT JOIN POC p ON b.provider_id = p.provider_id
    GROUP BY p.created_by, p.sdate
),

post_training AS (
    SELECT
        s.raw_trainer,
        DATE_TRUNC('week', date(b.updated_at_ist)) AS tweek,
        COUNT(DISTINCT s.provider_id) as Total_partner,
        ROUND(
            COUNT(CASE WHEN b.training_passed IS NOT NULL THEN 1 END)::FLOAT
            / NULLIF(COUNT(CASE WHEN b.in_training IS NOT NULL THEN 1 END), 0),
            2
        ) * 100 AS tp_pct
    FROM src s
    LEFT JOIN base b ON s.provider_id = b.provider_id
    GROUP BY s.raw_trainer, tweek
),

pip_base AS (
  SELECT 
      provider_id,
      DATE_TRUNC('week', approval_date) AS app_week,
      tier,
      tier_start_date,
      tier_end_date,
      paf_cancellation_at_tier AS paf_error,
      rating_error_at_tier AS rating_error,
      graded_leave_days_at_tier AS total_graded_leaves,
      ROW_NUMBER() OVER (
          PARTITION BY provider_id 
          ORDER BY DATE(tier_start_date)
      ) AS cycle_no
  FROM provider_promise_plan__daily__metrics
  WHERE category = 'instant_maids_l3'
    AND tier IS NOT NULL
),

tier_status AS (
  SELECT
      provider_id,
      app_week,
      cycle_no,
      CASE
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 0 THEN 'diamond'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 1 THEN 'gold'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 2 THEN 'silver'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves BETWEEN 3 AND 4 THEN 'bronze'
          ELSE 'pip'
      END AS potential_tier,
      CASE WHEN tier_end_date <= CURRENT_DATE THEN 1 ELSE 0 END AS completion_flag
  FROM pip_base
),

final_pip_metrics AS (
  SELECT
      ts.app_week,
      S.RAW_TRAINER,
      ROUND(
          100.0 * (
              COUNT(CASE WHEN cycle_no = 1 AND potential_tier = 'pip' AND completion_flag = 1 THEN 1 END)
            + COUNT(CASE WHEN cycle_no = 2 AND potential_tier = 'pip' AND completion_flag = 1 THEN 1 END)
          )
          /
          NULLIF(
              COUNT(CASE WHEN cycle_no = 1 AND completion_flag = 1 THEN 1 END)
            + COUNT(CASE WHEN cycle_no = 2 AND completion_flag = 1 THEN 1 END),
              0
          ),
          2
      ) AS elc_pip_pct
  FROM tier_status ts
  LEFT JOIN src s ON ts.provider_id = s.provider_id
  GROUP BY ts.app_week, S.RAW_TRAINER
)

SELECT
    coalesce(pt.created_by,post.raw_trainer) AS trainer,
    coalesce (pt.sdate,post.tweek) AS week,
    post.Total_partner,
    ta.age_tm,
    pt.sp_pct,
    pt.sp_tp_pct,
    post.tp_pct,
    pip.elc_pip_pct,
   ROUND(
    (0.1  * COALESCE(pt.sp_pct, 0)) +
    (0.15 * COALESCE(pt.sp_tp_pct, 0)) +
    (0.15 * COALESCE(post.tp_pct, 0)) +
    COALESCE((0.6  * (100 - pip.elc_pip_pct)),0),
    2
) AS score,
DENSE_RANK() OVER(PARTITION BY pt.sdate ORDER BY SCORE DESC) AS FINAL_RANK

FROM pre_training pt
full outer join post_training post
    ON pt.created_by = post.raw_trainer
   AND pt.sdate = post.tweek
LEFT JOIN final_pip_metrics pip
    ON pt.created_by = pip.RAW_TRAINER
   AND pt.sdate = pip.app_week
left join tm_age ta on pt.created_by=ta.created_by
WHERE pt.created_by IS NOT NULL
--AND post.Total_partner>10
ORDER BY pt.sdate desc, FINAL_RANK asc)
