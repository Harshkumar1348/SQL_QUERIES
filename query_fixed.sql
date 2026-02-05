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

-- FIX 1: Expanded tm_age to include trainers from both POC and src
tm_age AS (
    SELECT 
        created_by,
        MIN(DATE(sdate)) AS first_screening,
        DATEDIFF('day', first_screening, CURRENT_DATE()) AS tmm,
        CASE WHEN tmm > 60 THEN 'LLC Trainer' ELSE 'ELC Trainer' END AS age_tm
    FROM (
        -- From POC (screening trainers)
        SELECT created_by, sdate FROM poc WHERE created_by IS NOT NULL
        UNION ALL
        -- From src (post-training trainers) - captures trainers who only did training
        SELECT DISTINCT raw_trainer AS created_by, DATE_TRUNC('week', updated_at_ist) AS sdate 
        FROM src 
        WHERE raw_trainer IS NOT NULL
    )
    WHERE created_by IS NOT NULL
    GROUP BY 1
),

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
    COALESCE(pt.created_by, post.raw_trainer) AS trainer,
    COALESCE(pt.sdate, post.tweek) AS week,
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
        COALESCE((0.6  * (100 - pip.elc_pip_pct)), 0),
        2
    ) AS score,
    DENSE_RANK() OVER(PARTITION BY COALESCE(pt.sdate, post.tweek) ORDER BY score DESC) AS FINAL_RANK

FROM pre_training pt
FULL OUTER JOIN post_training post
    ON pt.created_by = post.raw_trainer
   AND pt.sdate = post.tweek
LEFT JOIN final_pip_metrics pip
    ON COALESCE(pt.created_by, post.raw_trainer) = pip.RAW_TRAINER  -- FIX 2: Use COALESCE
   AND COALESCE(pt.sdate, post.tweek) = pip.app_week               -- FIX 2: Use COALESCE
LEFT JOIN tm_age ta 
    ON COALESCE(pt.created_by, post.raw_trainer) = ta.created_by   -- FIX 3: Use COALESCE for tm_age join
WHERE COALESCE(pt.created_by, post.raw_trainer) IS NOT NULL        -- FIX 4: Update WHERE clause
ORDER BY COALESCE(pt.sdate, post.tweek) DESC, FINAL_RANK ASC
)
,

view2 as(
with base as (select distinct pdf.provider_id,
provider_name,
city,
avg_rating,
date(approval_date)as app_date,
date_trunc(week,app_date) as approval_week,
    case when last_delivery_date>current_date-7 then 'Active'
     when last_delivery_date is null and app_date>current_date-7 then 'Active' else 'Churned' end as active_status,
    sum(case when acm.date between current_date+1 and current_date+7 then marked_working end) as working_hrs,
    case when working_hrs>5 then 'Working' else 'Not Working' end as N7D_status

from provider__daily__facts pdf
left join (select distinct 
PROVIDER_ID, date,
COUNT(CASE WHEN status IN ('unmarked', 'marked leave', 'marked working') THEN provider_id ELSE NULL END) AS total_hours ,
COUNT(CASE WHEN status IN ('marked working') THEN provider_id ELSE NULL END) AS marked_working 

from PUBLIC.providerXdateXhour__calendar_marking__hourly__facts 
where date(date) between current_date and current_date+7
AND START_HOUR_LOCAL BETWEEN 8 AND 19
group by 1,2)
acm on acm.provider_id=pdf.provider_id
where customer_category_key='insta_maids'
and approval_date>='2025-01-01'
and country='India'
group by all)

,

cm as (select distinct 
a.PROVIDER_ID, date_trunc(week,date(a.date)) as cm_week,
date,
dayofweek(date) week_day,
COUNT(CASE WHEN status IN ('marked working') THEN a.provider_id ELSE NULL END) AS marked_working,
COUNT(CASE WHEN status IN ('marked leave') THEN a.provider_id ELSE NULL END) AS marked_leave
from PUBLIC.providerXdateXhour__calendar_marking__hourly__facts a
join base b on b.provider_id=a.provider_id
where a.provider_id in (select distinct provider_id from base)
AND START_HOUR_LOCAL BETWEEN 8 AND 19
and date<=current_date
and app_date<=date
group by 1,2,3,4)
,
f_cm as (select distinct provider_id,
avg(marked_working) as avg_working_hours
from cm
group by 1)
,
cm_final as (select distinct cm.*,
case when avg_working_hours is null then 0 else avg_working_hours end as avg_wrkn_hrs
from cm left join f_cm on cm.provider_id=f_cm.provider_id
)
,
Rating_raw AS (
    SELECT 
        distinct responded_pro_booking as provider_id,
        rating,date(rating_date)+3 as ratings_date,
        date_trunc('week',ratings_date) AS rating_week,
        customer_request_id,
    rank() over(partition by responded_pro_booking order by ratings_date ) as rnk
    FROM PUBLIC.REQUEST__HOURLY__FACTS 
    WHERE customer_category_key = 'insta_maids'
    and provider_id in (select distinct provider_id from base)
      AND rating IS NOT NULL
      --and rating <=4.5
) 
,
l10rating as (select distinct provider_id,rating_week,
sum(rating) as f10_sum_weekly_rating,count(distinct customer_request_id) as f10_sum_weekly_rated_jobs
from rating_raw 
where rnk<=10
group by 1,2
)
,

rr as (select distinct provider_id,rating_week,
listagg(distinct customer_request_id, ', ') within group(order by customer_request_id asc) as request_ids
from rating_raw where rating<4.5
group by 1,2
)
,

rating as (select distinct r.provider_id,
r.rating_week,rr.request_ids,
avg(rating) as avg_weekly_rating,
sum(rating) as total_rating_sum,
     count(distinct customer_request_id) as total_rated_jobs,
     count(distinct case when rating<4.5 then customer_request_id end) as bad_rated_jobs  --------==<4
from rating_raw r 
left join rr on r.provider_id=rr.provider_id and r.rating_week=rr.rating_week
group by 1,2,3)
,
pp as (SELECT 
        responded_pro_booking AS provider_id, 
        DATE_TRUNC('WEEK', date(paf.cancelled_at)) AS paf_week,
listagg(distinct paf.customer_request_id, ', ') within group(order by paf.customer_request_id asc) as paf_request_ids
         FROM REQUEST__BCE__HOURLY__FACTS paf
    JOIN request__hourly__facts rhf on rhf.customer_request_id=paf.customer_request_id
    WHERE paf.customer_category_key = 'insta_maids'
     and fault='PRO' and  paf.ns_provider_at_fault_flag=1
    and provider_id in (select distinct provider_id from base)
    GROUP BY 1,2)
 --   select * from rating
,
PAF_raw AS (
    SELECT 
        responded_pro_booking AS provider_id, 
        DATE_TRUNC('WEEK', date(paf.cancelled_at)) AS paf_week,
   --     paf_request_ids,
        COUNT(distinct case when --fault='PRO' and  
        paf.ns_provider_at_fault_flag=1  then paf.customer_request_id end) AS paf_count
         FROM REQUEST__BCE__HOURLY__FACTS paf
    JOIN request__hourly__facts rhf on rhf.customer_request_id=paf.customer_request_id
   -- left join pp on rhf.responded_pro_booking=pp.provider_id and pp.paf_week=DATE_TRUNC('WEEK', date(paf.cancelled_at))
    WHERE paf.customer_category_key = 'insta_maids'
    and provider_id in (select distinct provider_id from base)
    GROUP BY 1,2
)
,
paf as (select pr.*,paf_request_ids
from paf_raw pr left join 
   pp on pr.provider_id=pp.provider_id and pp.paf_week=pr.paf_week
)
,
final_raw as 
(select b.*,
case when active_status='Churned' and n7d_status='Not Working' then 'churn' else 'active' end as churn_status,
cm_week,cm_week-app_date as age,
total_rated_jobs,
bad_rated_jobs,
request_ids,
avg_weekly_rating,
f10_sum_weekly_rating,f10_sum_weekly_rated_jobs,
total_rating_sum,
paf_count,
paf_request_ids,
count(distinct case when avg_wrkn_hrs>7 and marked_leave>5 then date 
                when avg_wrkn_hrs <7 and marked_leave>6 then date end) as total_leaves,
count(distinct case when avg_wrkn_hrs>7 and marked_leave>5 and week_day in (5,6,0) then date 
               when avg_wrkn_hrs<7 and marked_leave>6 and week_day in (5,6,0) then date end) as total_weekend_leaves,
count(distinct case when avg_wrkn_hrs>7 and marked_leave>5 and week_day not in (5,6,0) then date 
               when avg_wrkn_hrs<7 and marked_leave>6 and week_day not in (5,6,0) then date end) as total_weekday_leaves
from base b left join cm_final cm on b.provider_id=cm.provider_id
left join rating r on r.provider_id=cm.provider_id and r.rating_week=cm.cm_week
left join l10rating r10 on r10.provider_id=cm.provider_id and r10.rating_week=cm.cm_week
left join paf p on p.provider_id=cm.provider_id and p.paf_week=cm.cm_week
where cm_week is not null
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
)
,
final as (select distinct provider_id,
provider_name,
churn_status,
city,app_date,
approval_week,
cm_week,
rank() over(partition by provider_id order by cm_week) as week_num,
age,
gr,
sd,
total_rated_jobs,
bad_rated_jobs,
request_ids,
avg_rating as overall_avg_rating,
f10_sum_weekly_rating,f10_sum_weekly_rated_jobs,
avg_weekly_rating,total_rating_sum,
paf_count,
paf_request_ids,
total_weekday_leaves+(total_weekend_leaves*2) as total_graded_leaves
from final_raw a
left join (select distinct responded_pro_booking,
date_trunc(week,date(bdate_final)) as week,
count(distinct case when gross_status='gross_request' then customer_request_id end) as gr,
count(distinct case when net_status='net_request' and service_delivered='true' then customer_request_id end) as sd,
from master_data
where customer_category_key= 'insta_maids'
and responded_pro_booking in (select distinct provider_id from base)
group by 1,2
) u on  u.responded_pro_booking=a.provider_id and u.week=a.cm_week
--where provider_id='62c9b1b2c4c415002866407b'
order by provider_id,cm_week),

trainer_mapping as 
(

 SELECT DISTINCT
        a.provider_id,
        f.value:"questionnaire_created_by"::string AS trainer_name,
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

)
,
lst as (
select distinct f.provider_id,
provider_name,trainer_name,
city,
app_date,
approval_week,
cm_week as perf_week,
week_num,
age,
churn_status,
case when age<=30 then 'ELC' else 'LLC' end as life_cycle,
overall_avg_rating,f10_sum_weekly_rating,f10_sum_weekly_rated_jobs,
avg_weekly_rating,total_rating_sum,total_rated_jobs,
gr as total_requests,
sd as total_deliveries,
case when bad_rated_jobs is null then 0 else bad_rated_jobs end as bad_rated_jobs,
request_ids,
case when paf_count is null then 0 else paf_count end as paf_count,
paf_request_ids,
case when total_graded_leaves is null then 0 else total_graded_leaves end as total_graded_leaves
from
final f left join 
(select * from trainer_mapping where trainer_name is not null) tm on f.provider_id=tm.provider_id),

cumulative as (select distinct provider_id,
provider_name,trainer_name,
city,
churn_status,
app_date,
--approval_week,
 perf_week,
week_num,
age,
life_cycle,
total_requests,
total_deliveries,
total_rated_jobs,total_rating_sum,
overall_avg_rating,
f10_sum_weekly_rating,f10_sum_weekly_rated_jobs,
avg_weekly_rating,
bad_rated_jobs,
paf_count,
total_graded_leaves,
CASE 
      --  WHEN GREATEST(bad_rated_jobs, total_graded_leaves, paf_count) >= 3 THEN 'Bad'
        WHEN bad_rated_jobs > 2 OR total_graded_leaves > 2 OR paf_count > 2 THEN 'Bad'
        WHEN bad_rated_jobs = 2 OR total_graded_leaves = 2 OR paf_count = 2 THEN 'Average'
        WHEN bad_rated_jobs = 1 OR total_graded_leaves = 1 OR paf_count = 1 THEN 'Good'
        WHEN COALESCE(bad_rated_jobs, 0) = 0 AND COALESCE(total_graded_leaves, 0) = 0 AND COALESCE(paf_count, 0) = 0 THEN 'No Error'
        end as week_perf,
request_ids as bad_rated_request_ids,
paf_request_ids
from
lst)

SELECT
    trainer_name,
    perf_week,

    SUM(total_deliveries) AS Util,

    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END) AS hh_eligible,

    COUNT(DISTINCT CASE 
        WHEN life_cycle = 'ELC' AND churn_status = 'churn' 
        THEN provider_id END) AS churn_pros,

    SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rating END)
    / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rated_jobs END), 0)
    AS F10_rating,

    COUNT(DISTINCT CASE WHEN life_cycle = 'LLC' THEN provider_id END) AS total_old,

    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'No Error' THEN provider_id END) AS no_error,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Good' THEN provider_id END) AS good,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Average' THEN provider_id END) AS average,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END) AS bad,

    /* bad + average % */
    (
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END)
      + COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Average' THEN provider_id END)
    ) * 100.0
    / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
    AS bad_average_perc,

    /* ideal partner % */
    100
    - (
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END)
        * 100.0
        / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
      )
    AS ideal_partner_perc,

    /* PAF % */
    SUM(CASE WHEN life_cycle = 'ELC' THEN paf_count END) * 100.0
    / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_requests END), 0)
    AS paf_perc,

    /* leaves per pro */
    SUM(CASE WHEN life_cycle = 'ELC' THEN total_graded_leaves END)
    / NULLIF(COUNT(CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
    AS leaves_per_pro,

    /* avg rating */
    SUM(CASE WHEN life_cycle = 'ELC' THEN total_rating_sum END)
    / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rated_jobs END), 0)
    AS hh_pros_avg_rating

FROM cumulative
GROUP BY trainer_name, perf_week 
ORDER BY trainer_name, perf_week  

)
,

final as(SELECT DISTINCT COALESCE(v.trainer, v1.trainer_name) AS trainer,
      COALESCE(v.week, v1.perf_week) AS week,
      v.age_tm,
       v1.hh_eligible,
       v.sp_pct,
       v.sp_tp_pct,
       v.tp_pct,
       v.elc_pip_pct,
       --v1.bad_average_perc,
       v1.hh_pros_avg_rating,
        ROUND(
    (0.1  * COALESCE(v.sp_pct, 0)) +
    (0.15 * COALESCE(v.sp_tp_pct, 0)) +
    (0.15 * COALESCE(v.tp_pct, 0)) +
    COALESCE((0.6  * (100 - v.elc_pip_pct)),0),
    2
) AS score
      FROM view1 v
FULL OUTER JOIN view2 v1
  ON v.trainer = v1.trainer_name
 AND v.week    = v1.perf_week
)
       
       select trainer,
       date(week) as "week::multi-filter",
       hh_eligible,
       age_tm,
       sp_pct,
       sp_tp_pct,
       tp_pct,
       elc_pip_pct,
       hh_pros_avg_rating,
       score ,
       case when score>75 then 'Greater than 75'
       else 'Less than 75'
       end as score_range,
       DENSE_RANK() OVER(PARTITION BY week ORDER BY SCORE DESC) AS FINAL_RANK
       from final
       where hh_eligible>0
