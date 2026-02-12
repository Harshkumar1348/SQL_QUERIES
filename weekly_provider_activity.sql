with app_pros as 
(
SELECT pdf.provider_id,provider_name,city,
approval_date as app_date,
to_char(date_trunc('week',app_date),'IYYY-IW') as app_week,
date(last_delivery_date) as last_delivery_date,
case when last_delivery_date<app_date then NULL else last_delivery_date end as ldd,
 sum(case when acm.date between current_date+1 and current_date+7 then acm.marked_working end) as working_hrs,
 sum(case when l7d.date between current_date-7 and current_date then l7d.marked_working end) as l7d_working_hrs,
    case when working_hrs>5 then 'Working' else 'Not Working' end as N7D_status,
    case when l7d_working_hrs>8 then 'active' else 'churned' end as l7D_status,
case when (l7D_status='churned' and app_date<CURRENT_DATE-7) then 'Churn'
when ldd is null AND DATE(app_date) >= CURRENT_DATE - 7 THEN '1. Active'
when l7D_status='active' then '1. Active' end as act_bucket,
case when ldd is null then 0 else DATEDIFF('days',app_date,ldd) end as age,
case when ldd is null then 'W0' else CONCAT('W',FLOOR((age/7)+1)) end as week,
case when act_bucket='Churn' then week else act_bucket end as age_level,
case when act_bucket='Churn' and FLOOR((age/7)+1)>2 then 'W3+'
when act_bucket='Churn' then week 
else act_bucket end as Age_
FROM PUBLIC.PROVIDER__DAILY__FACTS pdf
left join (select distinct 
PROVIDER_ID, date, 
COUNT(CASE WHEN status IN ('unmarked', 'marked leave', 'marked working') THEN provider_id ELSE NULL END) AS total_hours ,
COUNT(CASE WHEN status IN ('marked working') THEN provider_id ELSE NULL END) AS marked_working 

from PUBLIC.providerXdateXhour__calendar_marking__hourly__facts 
where date(date) between current_date and current_date+7
AND START_HOUR_LOCAL BETWEEN 8 AND 19
group by 1,2)
acm on acm.provider_id=pdf.provider_id

left join (select distinct 
PROVIDER_ID, date,
COUNT(CASE WHEN status IN ('unmarked', 'marked leave', 'marked working') THEN provider_id ELSE NULL END) AS total_hours ,
COUNT(CASE WHEN status IN ('marked working') THEN provider_id ELSE NULL END) AS marked_working 

from PUBLIC.providerXdateXhour__calendar_marking__hourly__facts 
where date(date) between current_date-7 and current_date
AND START_HOUR_LOCAL BETWEEN 8 AND 19
group by 1,2)
l7d on l7d.provider_id=pdf.provider_id
where app_date>='2025-02-01'
-- and city in ('Mumbai')
and customer_category_key='insta_maids'
group by all
)
SELECT provider_id,provider_name,app_date,app_week,
ldd,date_trunc('week',date(ldd)) as ldw,
case when act_bucket is null then '1. Active' else act_bucket end as act_bucket,
age,
case when age_level is null then '1. Active' else age_level end as age_level,
week,
case when Age_ is null then '1. Active' else Age_ end as Age_,last_delivery_date,
city as "city::filter"
from app_pros


UNION  

SELECT provider_id,provider_name,app_date,app_week,
ldd,date_trunc('week',date(ldd)) as ldw,
case when act_bucket is null then '1. Active' else act_bucket end as act_bucket,
age,
case when age_level is null then '1. Active' else age_level end as age_level,
week,
case when Age_ is null then '1. Active' else Age_ end as Age_,last_delivery_date, 
'Overall' as "city::filter"
from app_pros
