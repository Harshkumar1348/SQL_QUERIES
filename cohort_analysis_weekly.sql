with cohort as (
with age as(
select PROVIDER_ID,
       APPROVAL_DATE,
       LAST_DELIVERY_DATE,
       CASE 
       WHEN DATEDIFF('day', APPROVAL_DATE, LAST_DELIVERY_DATE) > 30
       THEN 'LLC'
       ELSE 'ELC'
       END AS PRO_AGE
       FROM provider__daily__facts
       ),
Q28 as (
SELECT DISTINCT 
    provider_id,
    CREATED_BY,
    CASE 
        WHEN module_key = 'Objective criteria - Bangalore' THEN
            CASE answer
                WHEN 'QQ1' THEN 'Foundational Cohort'
                WHEN 'QQ2' THEN 'language Cohort'
                WHEN 'QQ3' THEN 'No Cohort'
            END
        WHEN module_key = 'Objective criteria delhi' THEN
            CASE answer
                WHEN 'QQ1' THEN 'Foundational Cohort'
                WHEN 'QQ2' THEN 'No Cohort'
                WHEN 'QQ3' THEN 'No Cohort'
            END
        ELSE
            CASE answer
                WHEN 'QQ1' THEN 'Foundational Cohort'
                WHEN 'QQ2' THEN 'language Cohort'
                WHEN 'QQ3' THEN 'No Cohort'
            END
    END AS response,
    ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY created_at_ist DESC) AS rn
FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
WHERE customer_category_key = 'insta_maids'
  AND module_type = 'screening'
  AND statement ILIKE '%Cohort%'
QUALIFY rn = 1

    ),
 current_hub as(
Select PROVIDER_ID,PRIMARY_HUB_ID , HUB_NAME, s.city,
row_number () over(partition by e.provider_id order by e.updated_at desc) as rn
from PUBLIC.PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS e
left join SMART_HUBS_VIEW s on e.PRIMARY_HUB_ID = s.hub_id
qualify rn = 1
),

cte as (
select q.provider_id, ch.city, q.response as cohort, a.PRO_AGE
from q28 q 
left join current_hub ch on q.provider_id = ch.provider_id
left join age a on q.provider_id = a.provider_id
),

ranked AS (
  SELECT 
    provider_id, 
    tier, 
    tier_start_date,
    ROW_NUMBER() OVER (
      PARTITION BY provider_id 
      ORDER BY DATE(tier_start_date) ASC
    ) AS rk_all,
    ROW_NUMBER() OVER (
      PARTITION BY provider_id 
      ORDER BY CASE WHEN tier = 'new' THEN NULL ELSE DATE(tier_start_date) END ASC
    ) AS rk_non_new
  FROM PROVIDER_PROMISE_PLAN__DAILY__METRICS
  WHERE CATEGORY = 'instant_maids_l3'
),

ranked_final AS (
  SELECT 
    provider_id,
    MAX(CASE WHEN rk_non_new = 1 THEN tier END) AS C1_tier,
    MAX(CASE WHEN rk_non_new = 2 THEN tier END) AS C2_tier
  FROM ranked
 -- WHERE tier <> 'new'
  GROUP BY provider_id
),

ratings as (

with rating_b as (
    select 
        customer_request_id,
        provider_id,
        bdate,
        bdate_final,
        DATE_TRUNC('week', DATE(bdate)) as week,
        start_at,
        end_at,
        rating,
        late_show,
        ROW_NUMBER() over (partition by provider_id order by bdate) as del_no
    from PUBLIC.MASTER_DATA_EXPLORE_TABLE
    where provider_id in (select distinct provider_id from cte)
      and service_delivered = 1 
      and net_status = 'net_request'
      and rating is not null
      
),

rating_raw as (
    select 
        provider_id,
        week,
        count(distinct case when rating is not null then customer_request_id end) as total_rated_jobs,
        AVG(rating) as avg_rating,
        AVG(case when del_no <= 20 then rating end) as f20_avg_rating,

    from rating_b
    group by provider_id, week
)

select 
    distinct provider_id,
    week,
    total_rated_jobs,
    avg_rating,
  f20_avg_rating
from rating_raw

),

p_tier as (

WITH pip_base AS (
  SELECT 
    provider_id,
    tier,
    tier_start_date,
    tier_end_date,
    PAF_CANCELLATION_AT_TIER AS paf_error,
    RATING_ERROR_AT_TIER AS rating_error,
    GRADED_LEAVE_DAYS_AT_TIER as total_graded_leaves ,
    ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY DATE(tier_start_date) ASC) AS cycle_no
  FROM PROVIDER_PROMISE_PLAN__DAILY__METRICS
  WHERE CATEGORY = 'instant_maids_l3'
    AND tier IS NOT NULL
    --and provider_id = '6879f900b739390026298762'
),

cm1 AS (
  SELECT 
    pb.provider_id,
    pb.cycle_no,
    DATE(a.date) AS date,
    dayofweek(DATE(a.date)) AS week_day,
    pb.tier_start_date,
    pb.tier_end_date,
    SUM(CASE WHEN a.status = 'marked working' THEN 1 ELSE 0 END) AS marked_working,
    SUM(CASE WHEN a.status = 'marked leave' THEN 1 ELSE 0 END) AS marked_leave
  FROM PUBLIC.providerXdateXhour__calendar_marking__hourly__facts a
  JOIN pip_base pb
    ON pb.provider_id = a.provider_id
   AND DATE(a.date) BETWEEN DATE(pb.tier_start_date) AND DATE(pb.tier_end_date)
  WHERE a.start_hour_local BETWEEN 8 AND 19
    AND CUSTOMER_CATEGORY_KEY = 'Insta_maids'
  GROUP BY 1,2,3,4,5,6
),

avg_cm1 AS (
  SELECT provider_id, cycle_no, AVG(marked_working) AS avg_working_hours
  FROM cm1
  GROUP BY provider_id, cycle_no
),

cm_f1 AS (
  SELECT c.*, COALESCE(a.avg_working_hours, 0) AS avg_wrkn_hrs
  FROM cm1 c
  LEFT JOIN avg_cm1 a
    ON c.provider_id = a.provider_id
   AND c.cycle_no = a.cycle_no
),

final_cm1 AS (
  SELECT
    provider_id,
    cycle_no,
    tier_start_date,
    tier_end_date,
    COUNT(DISTINCT CASE 
      WHEN (avg_wrkn_hrs > 7 AND marked_leave > 5) OR (avg_wrkn_hrs <= 7 AND marked_leave > 6)
      THEN date ELSE NULL END) AS total_leaves,
    COUNT(DISTINCT CASE 
      WHEN ((avg_wrkn_hrs > 7 AND marked_leave > 5) OR (avg_wrkn_hrs <= 7 AND marked_leave > 6))
           AND week_day IN (5,6,0) THEN date ELSE NULL END) AS total_weekend_leaves,
    COUNT(DISTINCT CASE 
      WHEN ((avg_wrkn_hrs > 7 AND marked_leave > 5) OR (avg_wrkn_hrs <= 7 AND marked_leave > 6))
           AND week_day NOT IN (5,6,0) THEN date ELSE NULL END) AS total_weekday_leaves
  FROM cm_f1
  GROUP BY 1,2,3,4
),

cmmetrics AS (
  SELECT 
    provider_id,
    cycle_no,
    tier_start_date,
    tier_end_date,
    COALESCE(total_weekday_leaves,0) + COALESCE(total_weekend_leaves,0) * 2 AS total_graded_leaves
  FROM final_cm1
),

cycles AS (
  SELECT
    pb.provider_id,
    pb.cycle_no,
    pb.tier,
    pb.tier_start_date,
    pb.tier_end_date,
    pb.rating_error,
    pb.paf_error,
    pb.total_graded_leaves,
  --  COALESCE(cm.total_graded_leaves, 0) AS total_graded_leaves
  FROM pip_base pb
),

cycles_with_potential AS (
  SELECT
    provider_id,
    cycle_no,
    tier_end_date,
    CASE
      WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 0 THEN 'diamond'
      WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 1 THEN 'gold'
      WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 2 THEN 'silver'
      WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves BETWEEN 3 AND 4 THEN 'bronze'
      ELSE 'pip'
    END AS potential_tier
  FROM cycles
),

selected_cycles AS (
  SELECT 
    provider_id,
    MAX(CASE WHEN cycle_no = 1 THEN potential_tier END) AS c1_cycle1,
    MAX(CASE WHEN cycle_no = 2 THEN potential_tier END) AS c2_cycle2,
    MAX(CASE WHEN cycle_no = 3 THEN potential_tier END) AS c1_cycle3,
    MAX(CASE WHEN cycle_no = 4 THEN potential_tier END) AS c2_cycle4
  FROM cycles_with_potential
  GROUP BY provider_id
)

SELECT
  provider_id,
  -- Get last two non-null values for C1 and C2
  CASE 
    WHEN c2_cycle4 IS NOT NULL THEN c1_cycle3
    WHEN c1_cycle3 IS NOT NULL THEN c2_cycle2
    WHEN c2_cycle2 IS NOT NULL THEN c1_cycle1
    ELSE c1_cycle1
  END AS C1_potential_tier,
  CASE 
    WHEN c2_cycle4 IS NOT NULL THEN c2_cycle4
    WHEN c1_cycle3 IS NOT NULL THEN c1_cycle3
    WHEN c2_cycle2 IS NOT NULL THEN c2_cycle2
    ELSE c2_cycle2
  END AS C2_potential_tier
FROM selected_cycles
)



select c.provider_id,c.city,c.cohort, c.PRO_AGE, f.week, case 
    when r.C1_tier is null or r.C1_tier = 'new' then C1_potential_tier 
    else r.C1_tier
end as c1_tier
, case 
    when r.C2_tier is null or r.C2_tier = 'new' then C2_potential_tier 
    else r.C2_tier
end as c2_tier

,total_rated_jobs,avg_rating, f20_avg_rating from cte c left join ranked_final r on c.provider_id = r.provider_id
left join ratings f on c.provider_id = f.provider_id
left join p_tier p on c.provider_id = p.provider_id
where c.city is not null
and f.week is not null

)

SELECT
    DATE(week) as "week::multi-filter",
    cohort,city as "city::filter",

    CASE 
        WHEN SUM(COALESCE(total_rated_jobs, 0)) = 0 THEN NULL
        ELSE SUM( COALESCE(avg_rating, 0) * COALESCE(total_rated_jobs, 0) )
             / NULLIF(SUM(COALESCE(total_rated_jobs, 0)), 0)
    END AS avg_rating,

    CASE 
        WHEN SUM( LEAST(COALESCE(total_rated_jobs, 0), 20) ) = 0 THEN NULL
        ELSE SUM(
                COALESCE(f20_avg_rating, 0)
                * LEAST(COALESCE(total_rated_jobs, 0), 20)
             )
             / NULLIF(
                 SUM( LEAST(COALESCE(total_rated_jobs, 0), 20) ),
                 0
             )
    END AS f20_avg_rating

FROM cohort
GROUP BY 1,2,3
union
SELECT
    DATE(week) as "week::multi-filter",
    cohort,'overall' as "city::filter",

    CASE 
        WHEN SUM(COALESCE(total_rated_jobs, 0)) = 0 THEN NULL
        ELSE SUM( COALESCE(avg_rating, 0) * COALESCE(total_rated_jobs, 0) )
             / NULLIF(SUM(COALESCE(total_rated_jobs, 0)), 0)
    END AS avg_rating,

    CASE 
        WHEN SUM( LEAST(COALESCE(total_rated_jobs, 0), 20) ) = 0 THEN NULL
        ELSE SUM(
                COALESCE(f20_avg_rating, 0)
                * LEAST(COALESCE(total_rated_jobs, 0), 20)
             )
             / NULLIF(
                 SUM( LEAST(COALESCE(total_rated_jobs, 0), 20) ),
                 0
             )
    END AS f20_avg_rating

FROM cohort
GROUP BY 1,2,3
