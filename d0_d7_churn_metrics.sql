with base as 
(
select distinct lead_id,a.PROVIDER_ID,b.provider_name,date_trunc(week,date(b.approval_date)) as approval_week,city,
date_trunc(week,date(WALKED_IN)) as wi_week,
WALKED_IN as walked_in,
date_trunc(week,date(SCREENING_DATE)) as sa_week,
date_trunc(week,date(SCREENING_QUALIFIED)) as sp_week,
date_trunc(week, date(SCREENING_REJECTED)) as sf_week,
date_trunc(week,date(PARTIALLY_RECHARGED)) as pr_week,
date_trunc(week,date(SCHEDULED_FOR_TRAINING)) as ts_week,
date_trunc(week,date(SCHEDULING_TRIGGERED_FOR_TRAINING)) as stt_week,
date_trunc(week,date(IN_TRAINING)) as it_week,
date_trunc(week,date(TRAINING_PASSED)) as tp_week
from PUBLIC.LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
left join provider__daily__facts b on a.provider_id=b.provider_id
where a.customer_category_key ='insta_maids'
and wi_week>'2025-07-01'
and walked_in is not null
and city is not null
),

screening AS (
WITH S_provider_details AS (
  SELECT DISTINCT 
    pmpr.provider_id as pro_id,pm.provider_name as pro_name,pmpr.created_at_ist as sdate,pmpr.created_by,pmpr.evaluation as "Result::multi-filter",
    pm.city as "City::multi-filter",
    DATE_TRUNC('WEEK', pmpr.created_at_ist) as "week::multi-filter"
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
  LEFT JOIN provider__daily__facts pm ON pmpr.provider_id = pm.provider_id
  WHERE pmpr.customer_category_key = 'insta_maids'
    AND pmpr.module_type = 'screening'
    AND pmpr.module_key in 
    ('instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai','Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune','Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD')
),

s_fail_reason AS (
  SELECT 
    provider_id,
    LISTAGG(statement, '; ') WITHIN GROUP (ORDER BY statement) AS fail_reason
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
  WHERE customer_category_key = 'insta_maids'
    AND module_type = 'screening'
    AND module_key in 
   ('instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai','Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune','Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD')
    AND (score < 0 OR answer = 'fail')
  GROUP BY provider_id
  ),
  
  prioritized AS (
  SELECT 
    spd.pro_id as partner_id,spd.pro_name,spd.sdate as scr_date,spd."Result::multi-filter" as s_result,spd."City::multi-filter",spd."week::multi-filter",
    sfr.fail_reason as fail,row_number() over( partition by spd.pro_id order by spd.sdate desc) as bundle_num,
    CASE
      WHEN POSITION('What is partner''s age? (Check Aadhar for confirmation)' IN sfr.fail_reason) > 0 THEN 'Age'
      WHEN POSITION('Does the partner have her own smartphone? (Trainer to cross-question & confirm)' IN sfr.fail_reason) > 0 THEN 'Smartphone'
      WHEN POSITION('Is the partner’s family aware and supportive of her decision to work? (Call partner''s family members to verify)' IN sfr.fail_reason) > 0 THEN 'family unawar/unsupportive of her decision to work'
      WHEN POSITION('Which language will the partner use in UC app?' IN sfr.fail_reason) > 0 THEN 'can not understand language used in app'
      WHEN POSITION('What languages does the partner understand?' IN sfr.fail_reason) > 0 THEN 'can not understand any language'
      WHEN POSITION('Can the Partner use basic app from her own phone?' IN sfr.fail_reason) > 0 THEN 'can not use basic app from her own phone'
     WHEN sfr.fail_reason ILIKE 'Based on the below list, is the partner fit to work? (Back pain, Stomach pain, Knee pain, Arthritis, Movement-limiting injuries, Recent major surgeries, Chronic surgery effects, Asthma, Breathing issues, Vision problems,Skin allergies, pregnancy%' 
     THEN 'partner not fit to work'
      WHEN POSITION('Is the partner in the habit of using any tobacco products, such as chewing tobacco or gutkha?' IN sfr.fail_reason) > 0 THEN 'uses tobacco products'
      WHEN POSITION('What is the Candidate''s education status?' IN sfr.fail_reason) > 0 THEN 'Graduate or Pursuing Graduation'
      WHEN POSITION('How much does the partner earn in her current / last job?' IN sfr.fail_reason) > 0 THEN 'earning mismatch'
      WHEN POSITION('What is the candidate''s current / last job?' IN sfr.fail_reason) > 0 THEN 'Fresher'
      WHEN POSITION('How much experience does the partner have in housekeeping?' IN sfr.fail_reason) > 0 THEN 'no experience in housekeeping'
      WHEN POSITION('How is the Partner''s Communication Skill?' IN sfr.fail_reason) > 0 THEN 'Poor communication skill'
      WHEN POSITION('Is the partner aligned to travel to and work in the assigned hub/society?' IN sfr.fail_reason) > 0 THEN 'not aligned to travel/work in the assigned hub/society'
      WHEN POSITION('R2 Practical Result for Partner' IN sfr.fail_reason) > 0 THEN 'Practical fail'
      ELSE NULL
    END AS final_fail_reason
  FROM s_provider_details spd
  LEFT JOIN s_fail_reason sfr ON spd.pro_id = sfr.provider_id)
  
  SELECT * FROM prioritized
qualify bundle_num = 1
),

pre_screening as(
WITH ps_provider_details AS (
  SELECT DISTINCT 
    pmpr.provider_id as pro_id,pm.provider_name,pmpr.created_at_ist as psdate,pmpr.created_by,pmpr.evaluation as pre_screening_result,
    DATE_TRUNC('WEEK', pmpr.created_at_ist) AS created_week
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
  LEFT JOIN provider__daily__facts pm ON pmpr.provider_id = pm.provider_id
  WHERE pmpr.customer_category_key = 'insta_maids'
    AND pmpr.module_type = 'uc_qualification'
    AND pmpr.module_key = 'insta_maids_hardreject_pre_screening'
),

ps_fail_reason AS (
  SELECT 
    provider_id,
    LISTAGG(statement, '; ') WITHIN GROUP (ORDER BY statement) AS fail_reason
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
  WHERE customer_category_key = 'insta_maids'
    AND module_type = 'uc_qualification'
    AND module_key = 'insta_maids_hardreject_pre_screening'
    AND (score = 0 OR answer = 'No')
  GROUP BY provider_id
),

prioritized AS (
  SELECT 
    ppd.pro_id as pro__id,ppd.psdate as pdate,ppd.pre_screening_result as ps_result,
    pfr.fail_reason as fail,row_number() over( partition by ppd.pro_id order by ppd.psdate desc) as ps_bundle_num,
    pfr.fail_reason as psfail,
    CASE
      WHEN POSITION('What is partner''s age? (Check Aadhar / any other valid ID)' IN pfr.fail_reason) > 0 THEN 'Age'
      WHEN POSITION('Can Partner read and understand any of the Training Languages?' IN pfr.fail_reason) > 0 THEN 'Training Language'
      WHEN POSITION('Does the Partner have her own Smartphone?' IN pfr.fail_reason) > 0 THEN 'Smartphone'
      WHEN POSITION('Is she comfortable working 6 to 10 hours a day with 2 to 4 houses, including weekends, with one weekday off every 15 days?' IN pfr.fail_reason) > 0 THEN 'Not Okay with work Policy'
      WHEN POSITION('Is the partner eligible to move forward for final screening?' IN pfr.fail_reason) > 0 THEN 'Not eligible'
      WHEN POSITION('Partner Home Location (Latitude); Partner Home Location (Longitude); Which hub is allotted to the Partner ?; Which of the following criterias does the Partner not meet for Screening?' IN pfr.fail_reason) > 0 THEN 'Business Expectations'
      WHEN POSITION('Which hub is allotted to the Partner ?' IN pfr.fail_reason) > 0 THEN ' '
      ELSE NULL
    END AS final_fail_reason
  FROM ps_provider_details ppd
  LEFT JOIN ps_fail_reason pfr ON ppd.pro_id = pfr.provider_id
  )
  
SELECT * FROM prioritized
qualify ps_bundle_num = 1
), 

main AS (
    SELECT
        provider_id,
        provider_name,
        TO_CHAR(DATE(approval_date), 'YYYY-MM') AS app_month, 
        DATE(approval_date) AS app_date, 
        DATE(last_delivery_date) AS ldd, 
        CASE 
            WHEN last_delivery_date IS NULL THEN DATE_TRUNC('W', DATE(approval_date)) 
            ELSE DATE_TRUNC('W', DATE(last_delivery_date)) 
        END AS ldd_week,
        DATEADD(day, 7, ldd_week) as churn_week,
        CASE 
            WHEN last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('W', DATE(approval_date)), 'YYYY-MM') 
            ELSE TO_CHAR(DATE_TRUNC('W', DATE(last_delivery_date)), 'YYYY-MM') 
        END AS ldd_month,    
        CASE 
            WHEN last_delivery_date IS NULL AND DATE(approval_date) >= CURRENT_DATE - 7 THEN 'Active' 
            WHEN last_delivery_date > CURRENT_DATE - 7 THEN 'Active' 
            ELSE 'Inactive' 
        END AS active_status,
        customer_category_key,
        city,
        CASE 
            WHEN last_delivery_date IS NULL THEN 0 
            ELSE (DATE(last_delivery_date) - DATE(approval_date)) 
        END AS age
    FROM provider__daily__facts
    WHERE reporting_supercategory_new = 'Insta Help'
      AND approval_date IS NOT NULL
),
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
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 and CURRENT_DATE
        AND start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),
churn_base as (
    SELECT 
        m.*,
        m.ldd_week as "ldd_week::filter",
        CASE   
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN '3. Churn'
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
            WHEN m.ldd IS NULL AND DATE(m.app_date) >= CURRENT_DATE - 7 THEN '1. Active'
        END AS churn_status
    FROM main m
    LEFT JOIN l7d on m.provider_id = l7d.provider_id
),
do_d7 as (
    SELECT
        cb.*,
        CASE    
            WHEN cb.churn_status = '1. Active' then '1. Active'
            WHEN cb.age = 0 and cb.churn_status = '3. Churn' THEN '3. D0 churn'
            WHEN cb.age <= 7 and cb.churn_status = '3. Churn' THEN '4. D7 churn'
            WHEN cb.age <= 17 and cb.churn_status = '3. Churn' THEN '5. D15 churn'
            WHEN cb.age <= 30 and cb.churn_status = '3. Churn' THEN '6. D30 churn'
            WHEN cb.age <= 60 and cb.churn_status = '3. Churn' THEN '7. D60 churn'
            WHEN cb.age <= 90 and cb.churn_status = '3. Churn' THEN '8. D90 churn'
            WHEN cb.age <= 120 and cb.churn_status = '3. Churn' THEN '9. D120 churn'
            ELSE '10. >D120 churn'
        END AS churn_bucket,
        CASE 
            WHEN cb.churn_status = '1. Active' then '1. Active'
            WHEN cb.age <= 30 and cb.churn_status = '3. Churn' THEN '3. ELC churn'
            ELSE '4. LLC churn' 
        END AS ELC_LCC
    FROM churn_base cb
),

final as 
(
select b.city, provider_id, provider_name, wi_week, sa_week,sf_week, sp_week, ts_week, stt_week, it_week, tp_week, approval_week, pr_week,
CASE 
    WHEN sp_week IS NOT NULL THEN sp_week
    WHEN sf_week IS NOT NULL THEN sf_week
    ELSE sa_week
END AS aligned_sa_week
from base b
left join  pre_screening p on b.provider_id=p.pro__id
left join screening s on b.provider_id = s.partner_id
)
,
weeks as (
select distinct week_val from (
    select wi_week as week_val from final
    union select sa_week from final
    union select sp_week from final
    union select pr_week from final
    union select stt_week from final
    union select ts_week from final
    union select it_week from final
    union select tp_week from final
    union select approval_week from final
    union select aligned_sa_week from final
    union select ldd_week from do_d7
)
where week_val is not null
),
churn_counts as (
    SELECT
        lower(city) as city,
        ldd_week,
        count(distinct case when churn_bucket = '3. D0 churn' then provider_id end) as d0_churn_count,
        count(distinct case when churn_bucket = '4. D7 churn' then provider_id end) as d7_churn_count
    FROM do_d7
    GROUP BY 1,2
),
overall_churn_counts as (
    SELECT
        ldd_week,
        count(distinct case when churn_bucket = '3. D0 churn' then provider_id end) as d0_churn_count,
        count(distinct case when churn_bucket = '4. D7 churn' then provider_id end) as d7_churn_count
    FROM do_d7
    GROUP BY 1
)

select
lower(f.city) as "city::filter",
w.week_val as week,

count(distinct case when f.wi_week is not null and f.wi_week = w.week_val then provider_id end ) as wi,
count(distinct case 
        when f.sp_week = w.week_val 
          OR f.sf_week = w.week_val
        then provider_id 
end ) as sa,
--count(distinct case when f.sp_week is not null and f.sa_week = f.sp_week then provider_id end ) as sa,
count(distinct case when f.sp_week = w.week_val then provider_id end ) as sp,
count(distinct case when f.pr_week = w.week_val then provider_id end ) as pr,
--count(distinct case when f.stt_week = w.week_val then provider_id end ) as stt,
--count(distinct case when f.ts_week = w.week_val then provider_id end ) as ts,
count(distinct case when f.it_week = w.week_val then provider_id end ) as it,
count(distinct case when f.it_week = w.week_val and tp_week is not null then provider_id end )as tp,
count(distinct case when f.approval_week = w.week_val then provider_id end ) as app,
--(sa / NULLIF(wi, 0)) * 100 AS wi_sa,
--(sp / NULLIF(wi, 0)) * 100 AS wi_sp,
--(pr / NULLIF(wi, 0)) * 100 AS wi_pr,
--(stt / NULLIF(wi, 0)) * 100 AS wi_stt,
--(ts / NULLIF(wi, 0)) * 100 AS wi_ts,
--(it / NULLIF(wi, 0)) * 100 AS wi_it,
--(tp / NULLIF(wi, 0)) * 100 AS wi_tp,
(app / NULLIF(wi, 0)) * 100 AS wi_app,
(sp / NULLIF(sa, 0)) * 100 AS sa_sp,
--(pr / NULLIF(sp, 0)) * 100 AS sp_pr,
(tp / NULLIF(sp, 0)) * 100 AS sp_tp,
(it / NULLIF(pr, 0)) * 100 AS pr_it,
--(ts / NULLIF(stt, 0)) * 100 AS stt_ts,
--(it / NULLIF(ts, 0)) * 100 AS ts_it,
(tp / NULLIF(it, 0)) * 100 AS it_tp,
(app / NULLIF(tp, 0)) * 100 AS tp_app,
COALESCE(MAX(churn_counts.d0_churn_count), 0) as d0_churn_count,
COALESCE(MAX(churn_counts.d7_churn_count), 0) as d7_churn_count
--(it / NULLIF(pr, 0)) * 100 AS pr_it,
--(tp / NULLIF(pr, 0)) * 100 AS pr_tp,
--(app /nullif(pr,0)) * 100 AS pr_app

from weeks w
left join final f on 1=1
left join churn_counts
  on lower(f.city) = churn_counts.city
  and w.week_val = churn_counts.ldd_week
group by 1,2


union

select
distinct 'zOverall'as "city::filter",
w.week_val,

count(distinct case when f.wi_week is not null and f.wi_week = w.week_val then provider_id end ) as wi,
--count(distinct case when f.sa_week is not null and f.sp_week = w.week_val then provider_id end ) as sa,
count(distinct case 
        when f.sp_week = w.week_val 
          OR f.sf_week = w.week_val
        then provider_id 
end ) as sa,
count(distinct case when sp_week = w.week_val then provider_id end )as sp,
count(distinct case when pr_week = w.week_val then provider_id end )as pr,
--count(distinct case when stt_week = w.week_val then provider_id end )as stt,
--count(distinct case when ts_week = w.week_val then provider_id end ) as ts,
count(distinct case when it_week = w.week_val then provider_id end )as it,
count(distinct case when it_week = w.week_val and tp_week is not null then provider_id end )as tp,
count(distinct case when approval_week = w.week_val then provider_id end ) as app,
--(sa / NULLIF(wi, 0)) * 100 AS wi_sa,
--(sp / NULLIF(wi, 0)) * 100 AS wi_sp,
--(pr / NULLIF(wi, 0)) * 100 AS wi_pr,
--(stt / NULLIF(wi, 0)) * 100 AS wi_stt,
--(ts / NULLIF(wi, 0)) * 100 AS wi_ts,
--(it / NULLIF(wi, 0)) * 100 AS wi_it,
--(tp / NULLIF(wi, 0)) * 100 AS wi_tp,
(app / NULLIF(wi, 0)) * 100 AS wi_app,
(sp / NULLIF(sa, 0)) * 100 AS sa_sp,
--(pr / NULLIF(sp, 0)) * 100 AS sp_pr,
(tp / NULLIF(sp, 0)) * 100 AS sp_tp,
(it / NULLIF(pr, 0)) * 100 AS pr_it,
--(stt / NULLIF(pr, 0)) * 100 AS pr_stt,
--(ts / NULLIF(stt, 0)) * 100 AS stt_ts,
--(it / NULLIF(ts, 0)) * 100 AS ts_it,
(tp / NULLIF(it, 0)) * 100 AS it_tp,
(app / NULLIF(tp, 0)) * 100 AS tp_app,
COALESCE(MAX(overall_churn_counts.d0_churn_count), 0) as d0_churn_count,
COALESCE(MAX(overall_churn_counts.d7_churn_count), 0) as d7_churn_count
--(it / NULLIF(pr, 0)) * 100 AS pr_it,
--(tp / NULLIF(pr, 0)) * 100 AS pr_tp,
--(app /nullif(pr,0)) * 100 AS pr_app
from weeks w
left join final f on 1=1
left join overall_churn_counts
  on w.week_val = overall_churn_counts.ldd_week
group by 1,2
order by week desc, "city::filter"
