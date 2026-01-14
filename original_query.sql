with 
base as (select distinct pdf.provider_id,
provider_name,
city,
avg_rating,
date(approval_date)as app_date,
date_trunc(week,app_date) as approval_week,
      CASE   WHEN COALESCE(acm.L7D_status, 'Unknown') = 'Not Working' THEN 'Churn'
      WHEN COALESCE(acm.L7D_status, 'Unknown') = 'Working' THEN 'Active'
      WHEN last_delivery_date IS NULL AND DATE(app_date) >= CURRENT_DATE - 7 THEN 'Active' end as active_status
    --sum(case when acm.date between current_date+1 and current_date+7 then marked_working end) as working_hrs,
from provider__daily__facts pdf
left join (
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
    GROUP BY pdf.provider_id)
acm on acm.provider_id=pdf.provider_id
where customer_category_key='insta_maids'
and approval_date>='2025-02-01'
and country='India'
group by all)
,
date_spine AS (
    SELECT DATEADD(WEEK, SEQ4(), DATE_TRUNC('WEEK', '2025-01-01'::DATE)) AS week_start
    FROM TABLE(GENERATOR(ROWCOUNT => 104)) 
    WHERE week_start <= CURRENT_DATE
),
provider_spine AS (
    SELECT 
        b.provider_id,
        ds.week_start AS cm_week
    FROM base b
    CROSS JOIN date_spine ds
    WHERE ds.week_start >= b.approval_week
)
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
case when active_status='Churn'  then 'churn' else 'active' end as churn_status,
ps.cm_week,
ps.cm_week-app_date as age,
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
from provider_spine ps
join base b on ps.provider_id = b.provider_id
left join cm_final cm on ps.provider_id=cm.provider_id and ps.cm_week=cm.cm_week
left join rating r on r.provider_id=ps.provider_id and r.rating_week=ps.cm_week
left join l10rating r10 on r10.provider_id=ps.provider_id and r10.rating_week=ps.cm_week
left join paf p on p.provider_id=ps.provider_id and p.paf_week=ps.cm_week
-- where cm_week is not null -- REMOVED to include all weeks
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
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
order by provider_id,cm_week)
,
manual_mapping AS (
    SELECT * FROM VALUES 
('6850dc05de1a83002892570f','Jayashree'),
('684932e1f5b98500228f60bf','Jayashree'),
('684917f1774b5800238b64d0','Kristi Vishwakarma'),
('683015d500008e0022f2786d','Aditi Deshbhartar'),
('685f830f78acc8002b740d2f','Ravi Sharma'),
('68305fc3ea8667002699eb87','Swati Weldode'),
('682affc3ed0fca00253cee05','Swati Weldode'),
('685a4121bb16e50027752d6d','Aditi Deshbhartar'),
('68382fa5b0a0b200211209b6','Preeti Grewal'),
('685e3a62e8af7900280f086c','Bhavesh Chauhan'),
('6852710e466ee00024243f5a','Anuja Rakshe'),
('6850ffbbb141420023e929f4','Preeti Grewal'),
('68341db9c329ce0024742b39','Preeti Grewal'),
('68355ad9c9e5c90025109af7','Preeti Grewal'),
('685f7a5bc0fb520027b92e49','Swati Weldode'),
('683ecd32289e64002970b606','Kristi Vishwakarma'),
('6844219bca391a0023173084','Jayashree'),
('68400f98dfaf0f0027d872da','Aditi Deshbhartar'),
('685d1bd6a86018002618d751','Jayashree'),
('67e70cd14e1da8002449a475','Bhavesh Chauhan'),
('6834062ec8c7c60026ff2858','Preeti Grewal'),
('665828468357d60022ef54e4','Shriya Bhardwaj'),
('685bb8e8d3d4a2002171c47e','Shriya Bhardwaj'),
('68415f4283961d0028ab70ed','Kristi Vishwakarma'),
('685fcc345034060025d39ab5','Ravi Sharma'),
('684fb5904926d600263f209d','Ravi Sharma'),
('683967b17c0f000024b53127','Shriya Bhardwaj'),
('68284be46d7203002511a2d0','Preeti Grewal'),
('67f7a13775a2cc0026ebee88','Anuja Rakshe'),
('68500f38230dd30024841e8d','Kristi Vishwakarma'),
('685bc3248b03b800239924e8','Shriya Bhardwaj'),
('684aa761e3d14500226f3ffc','Shriya Bhardwaj'),
('67e6bdbbaf664e0021ffe77a','Swati Weldode'),
('685901d37fc79f0024110045','Anuja Rakshe'),
('684d5ff366c63e0024114998','Kristi Vishwakarma'),
('684fdb0ddf3963002465bfcd','Shriya Bhardwaj'),
('684034db7cbb24002393b494','Jayashree'),
('68500334ff4c0a0025b38114','Kristi Vishwakarma'),
('684a98789a66890025a9d316','Kristi Vishwakarma'),
('685924c48392030024797ac2','Anuja Rakshe'),
('6870fb373df681002419fbb1','Jayashree'),	
('686502635764ed0022da316f','Jayashree'),	
('686e65a1ccbbe60028c65f83','Jayashree'),	
('685ce5fa7b60d20026e7d81b','Jayashree'),	
('680a31b51ea4e60026253747','Jayashree'),	
('686e47f8327389002517cafc','Jayashree'),	
('6864cf6ab7e77100287477ab','Jayashree'),	
('686f89b49225f100230ad25f','Jayashree'),	
('686e280260ffa70027125790','Jayashree'),	
('6868bcb1acde770026436eef','Jayashree'),	
('6863a8140c497b002c975607','Jayashree'),	
('687217892dd26500228c391e','Jayashree'),
('685ba719aeaed700230769ea','Aditi Deshbhartar'),
('684a8efca4907f00255fccf8','Bhavesh Chauhan'),
('684fbf7b6c24d10026dd7e48','Preeti Grewal'),
('683e849d74504b002525aa01','Preeti Grewal'),
('63aed2c4e438a60025d7639d','Shriya Bhardwaj'),
('68495c05557d42002106f254','Swati Weldode'),
('684fae63164c7300255dd64d','Kristi Vishwakarma'),
('685bbc34d534b50023e56605','Shriya Bhardwaj'),
('684d3759719b6b0024587cf5','Swati Weldode'),
('682f0180550a2500267c69ee','Preeti Grewal'),
('6842a718199165002464dc7b','Swati Weldode'),
('685a5d519c09cd003222c9f4','Anuja Rakshe'),
('685cb5dc8fba1c00286b77db','Bhavesh Chauhan'),
('68512a26294428002825f13e','Preeti Grewal'),
('6853c922a253c20022769ce8','Anuja Rakshe'),
('6836b9459142eb0024e35a3b','Kristi Vishwakarma'),
('68313787ce03170024f5445b','Preeti Grewal'),
('68256d4261da6b0025205e5c','Preeti Grewal'),
('68188697a6c19b0027a47c43','Ratchitha'),
('685e23fe458278002367fadf','Sujatha'),
('66b72f5df87fe400222bc35d','Ratchitha'),
('6858e62663ce7b0027987956','Praveen Mahato'),
('6842878b3f8b2f0026d971f9','Ratchitha'),
('685f871b465dc000249de942','Pavithra'),
('685e29b3669c2f0029448b4f','Sujatha'),
('68309a8a0f39bc00265d70cc','Ratchitha'),
('68616ec86ba64900249bb83f','Pavithra'),
('6858ff918692cb00230779c8','Pavithra'),
('683d549837d86a0027a6684f','Amit Semwal'),
('6832e2a87f3d7f0028154031','Shirisha Marathi'),
('68393b4ca6cd010024591ca3','Jyoti Bisht'),
('68516128f43c2f0027dc3ae5','Praveen Mahato'),
('685f84169dc08400242d6442','Pavithra'),
('685a7d1761f5f4002495396b','Praveen Mahato'),
('6859177c62e32d002505f270','Praveen Mahato'),
('6843fc3607fa9f002271e720','Shirisha Marathi'),
('68414cd6e9ff4000258be76f','Ratchitha'),
('682eefff117faf0023082bc9','Ratchitha'),
('685e241c669c2f002943f8d8','Sujatha'),
('685e244a66bf610027fec272','Sujatha'),
('6858e67e4822970025b66cda','Praveen Mahato'),
('6842ac1730fc40002239599d','Anushka Singh'),
('683d55dbb6888a00260fefae','Amit Semwal'),
('684285c52a8dee0025ae3b84','Ratchitha'),
('685f85a7cabbf900249f5001','Pavithra'),
('6853b42e5f94e80023cde8ed','Praveen Mahato'),
('684016ed22f8530027481c89','Ratchitha'),
('685f842785294a0026402791','Pavithra'),
('683b0255992c530023146961','Amit Semwal'),
('684270425915810027015d35','Ratchitha'),
('6832dcd17496350029774c12','Joybroto Choudhury'),
('684a5adb215db100259a6538','Sujatha'),
('685e240fcfae400022603d62','Sujatha'),
('6831c66f1739380023b4ab20','Ratchitha'),
('685a31cd8b82fc0024c96c46','Pavithra'),
('68621e68188b3100234b97ce','Pavithra'),
('6862175458fe350028401cca','Pavithra'),
('68516100ca1c24002369e04e','Praveen Mahato'),
('6858f491f847e4002da82bc9','Praveen Mahato'),
('6858ff28b2af9e00233aa8dc','Praveen Mahato'),
('685e1c6edad4010025836ad4','Sujatha'),
('685a4f71d42dea0029aed240','Pavithra'),
('6842aa8c45f56a0024f80d1c','Anushka Singh'),
('68412a9442aa8300235f3750','Ratchitha'),
('68414b53b1c5bd00247e94e1','Ratchitha'),
('68622cec7cfbcf0024c35fe4','Pavithra'),
('685f8547aa227800265088b6','Pavithra'),
('686217411513ef0024d33dcd','Pavithra'),
('6853b60fd0b20a0027c55253','Sangeeta Rai'),
('685501a067f9880027481e0d','Sangeeta Rai'),
('683ac6dce0affc0025dc6192','Krishnamurari'),
('6838741a0893790024524a3c','Sangeeta Rai'),
('682ada189d751d00265aaba0','Neha Negi'),
('685111e82064d10024aea8ed','Sangeeta Rai'),
('682c1e6deb0a370024369eb6','Anshu Mandal'),
('6836a24c6f28af002a0bee87','Sangeeta Rai'),
('682adb7a69823c00246ca775','Neha Negi'),
('684a5c00b6c6330022161fc9','Anshu Mandal'),
('685663a6a525b5002222f1ed','Sangeeta Rai'),
('6836acf40aa5840022a252d6','Sangeeta Rai'),
('6858f2c8aae2a00024b6702c','Sangeeta Rai'),
('68565f3f46b7a0002779fd14','Sangeeta Rai'),
('685926fcefba69002441106f','Sangeeta Rai'),
('6856660d2451e700268495eb','Sangeeta Rai'),
('6853a5d93c9ce100270936cd','Sangeeta Rai'),
('68565d009e84cc002254a129','Sangeeta Rai'),
('683e95427a16f20022d71a55','Sangeeta Rai'),
('6853d7e128a66b00272e801e','Sangeeta Rai'),
('681efdecf23bc600252cc365','Preeti Grewal'),
('683d5e7930f8780024f1b49f','Preeti Grewal'),
('683418a526548100222e3c2b','Babita Kumari'),
('682b0b8c8f63ae00269ba6e5','Ravi Shekhar'),
('68356a45a1ed4a00239ee76b','Babita Kumari'),
('6833ecccbd58480027dd80d8','Babita Kumari'),
('683058b030a6ba0025d060d8','Babita Kumari'),
('6804a6f3cc42bd0024080e16','Kristi Vishwakarma'),
('683084e0e6313c0022d914bd','Amit Semwal'),
('683186eb2ad5ad0025329469','Amit Semwal'),
('6837fdd2fc543d002964a93b','Babita Kumari'),
('683aefd7f11265002648afb6','Amit Semwal'),
('682ec3cc2805980025c6a9ed','Babita Kumari'),
('6828697a69388d0022f2eb4a','Shirisha Marathi'),
('6412bcc424f8b9002873cbfa','Babita Kumari'),
('682d5aed6977f20022bf5e7d','Babita Kumari'),
('6835b47639747100268aeacf','Preeti Grewal'),
('683d3280ee2c4c0024e99055','Amit Semwal'),
('6825857647edaf0024d1a0aa','Vaitla Soundharya'),
('67ef9c404f740a002487be49','Jyoti Bisht'),
('683d4244e516df0026400086','Babita Kumari'),
('68354df5857338002a07121a','Babita Kumari'),
('68397445511bad0028e78db6','Babita Kumari'),
('67f0d09566c80e0021657644','Preeti Grewal'),
('683e6c7e4e82b800281b7aab','Babita Kumari'),
('6825a02d6e90aa0022414819','Preeti Grewal'),
('68383c39ce6f0c0024e045d2','Preeti Grewal'),
('6837fd7e210376002541c6e9','Babita Kumari'),
('6830863552aec2002357cf39','Amit Semwal'),
('683d518508410a0026357283','Amit Semwal'),
('68257f69b422b70028370fee','Preeti Grewal'),
('683ebda96ac19a00229cc9e2','Babita Kumari'),
('683d50f959e4d7002297c21d','Amit Semwal'),
('68358f99b85a8d0026a148ed','Babita Kumari'),
('682c3394480bcf00286e456d','Vaitla Soundharya'),
('683eece925c68600244e48b7','Babita Kumari'),
('6831843c2ad5ad0025324267','Babita Kumari'),
('68188361f866b300223d7dcf','Anuja Rakshe'),
('64abb0d5d07ebb002b5e0a85','Babita Kumari'),
('682a103287b0ca0025478f90','Babita Kumari'),
('63313b227dc449002595d2b1','Babita Kumari'),
('68381b9275de4c00239a07ae','Babita Kumari'),
('683803afe803e30025d1d00b','Babita Kumari'),
('683170445ee2930024d5554c','Babita Kumari'),
('683417c0e05ea8002b3c2d10','Babita Kumari'),
('5d872417567763240061f6e9','Babita Kumari'),
('682ef2259b930e002927026b','Babita Kumari'),
('67fe1ac4f626a50026810d75','Vaitla Soundharya'),
('6833fa327994550027b9c32e','Amit Semwal'),
('682acc675f5b7e00258ad27e','Babita Kumari'),
('68257dd047edaf0024d0b17f','Amit Semwal'),
('683d3aed4c83de0026b44fd2','Amit Semwal'),
('6810ad7870be490022f9bf92','Shirisha Marathi'),
('6805fe6a8d70fa0026ccba58','Anuja Rakshe'),
('682afa214792f700231110cf','Anshu Mandal'),
('6807307ec772dd0021940353','Shirisha Marathi'),
('6826455ac9106d0024fa67e7','Babita Kumari'),
('682568f10922bc0024c0f72a','Preeti Grewal'),
('682acce5c683790025a6d26c','Neha Negi'),
('682c5a9aac124a00224a7e23','Neha Negi'),
('6822e166c49b9c002a837a6d','Kristi Vishwakarma'),
('6278a2c5d307e0002724a530','Amit Semwal'),
('6825870d4e8dfd002418e53e','Amit Semwal'),
('682307b2a57e900026fd1c32','Amit Semwal'),
('682ae45d2bf66f002928c9d1','Amit Semwal'),
('6825854cc9eb4b0023d79510','Babita Kumari'),
('68218501309e850024aae323','Amit Semwal'),
('67e3a24d31ed7f0028e750aa','Jyoti Bisht'),
('6826ece599a7730024d212fc','Jyoti Bisht'),
('6819c11d755b1d00243b539c','Jyoti Bisht'),
('67fe1aa3d6fd600025e77700','Jyoti Bisht'),
('6811c708470d6f0025e88f4e','Preeti Grewal'),
('64a7de7feb36a60024748c23','Babita Kumari'),
('682abd5dcda80b0023553294','Anshu Mandal'),
('6807605ec48498002369a02e','Kristi Vishwakarma'),
('680f2734675bea002845285b','Preeti Grewal'),
('681343d6f4b36100283f42ea','Anuja Rakshe'),
('67f0be27063c6b002636fac6','Shirisha Marathi'),
('68188b5e2a16c800251933a2','Jyoti Bisht'),
('67d50c3fca750b0023d5ff27','Babita Kumari'),
('6822e6abcd31a80023b5e281','Swati Weldode'),
('6826e71595d1b6002c2b54de','Jyoti Bisht'),
('6804a4ce0ef44d00252d2348','Preeti Grewal'),
('6821970cd4c1ef00254bfda7','Jyoti Bisht'),
('682ac774e612720025f1780f','Amit Semwal'),
('67f9044ab4b5720024da6287','Preeti Grewal'),
('68315a2632ecdf0024aa5e73','Amit Semwal'),
('681f2539b9743b00249b3a24','Anuja Rakshe'),
('681c9fa1f676f1002465f8f4','Kristi Vishwakarma'),
('6825a16f783a4f0027880ef7','Preeti Grewal'),
('682721642ed1de0025b0868a','Preeti Grewal'),
('67ea7be795a85400272fb1fd','Preeti Grewal'),
('682ac83a087e620024086120','Kristi Vishwakarma'),
('682abae861fadb00295867df','Babita Kumari'),
('67f8f217ab65880027e36f20','Shirisha Marathi'),
('6826d3291e5cae002552c270','Babita Kumari'),
('6825bc1107af820024be3370','Kristi Vishwakarma'),
('6819d3abf075fd0022d5fe10','Anuja Rakshe'),
('6821c54e63e72d00241ed1bd','Jyoti Bisht'),
('6825985e94bbff002440307b','Amit Semwal'),
('6827103acfe4940022bb9563','Preeti Grewal'),
('68233195ddc08c00232ed8b7','Babita Kumari'),
('682c4353b582a10023721099','Amit Semwal'),
('68219bcec583300023dc82c8','Jyoti Bisht'),
('682851c79c235600248ffa1a','Anuja Rakshe'),
('682442aae917e50022b0f726','Shirisha Marathi'),
('62d7e06f95db0b003510f57d','Babita Kumari'),
('682c1834bc5ac70022c95818','Amit Semwal'),
('681f28ffab16810022089ae9','Swati Weldode'),
('680f1cfa79d6ba0025430b6e','Shirisha Marathi'),
('683022529a70220023863f13','Amit Semwal'),
('681da54b731e0f002419e9c3','Anuja Rakshe'),
('6822ebd03dcfee0023868272','Shirisha Marathi'),
('682ec70ecafee600260c7d82','Amit Semwal'),
('6821a40d23d6db0024bef94b','Preeti Grewal'),
('682ac92aca7f3e002553dd83','Neha Negi'),
('6822ed324cc6e000276987a8','Shirisha Marathi'),
('6825821e33087b002310d07d','Jyoti Bisht'),
('681f46aab4dc430024ecad36','Kristi Vishwakarma'),
('6821d277535628002292a824','Kristi Vishwakarma'),
('67e4eb03f46eff0026494f5f','Anuja Rakshe'),
('6822e50d70cfd50028506fc8','Shirisha Marathi'),
('681c7fa11d7deb002207c358','Preeti Grewal'),
('67e52bd605502e00265eb843','Shirisha Marathi'),
('6826e9bcd8dfe60025704651','Anuja Rakshe'),
('682edc4559f1f10022b4d696','Amit Semwal'),
('682ac977e5b6610022ce7952','Amit Semwal'),
('682c1af06a1e2c00296ce20b','Anshu Mandal'),
('67ef7ca99bb7de002488ec56','Jayashree'),
('6815e3ef88619900286fbc27','Anuja Rakshe'),
('680787e8567f210025e3559d','Jyoti Bisht'),
('6821b831c224bf0026fdb6c1','Amit Semwal'),
('681f2786f399f00024a2d61f','Anuja Rakshe'),
('68275c27bb3010002443ce05','Amit Semwal'),
('68259e1d70a4fa002200d4fd','Shirisha Marathi'),
('68131e82d504a90026ccd914','Preeti Grewal'),
('680b606c423d1000234d4359','Jyoti Bisht'),
('67ee1761f4ae230026990a26','Jyoti Bisht'),
('681097c5bb4aba002257e4fc','Kristi Vishwakarma'),
('68020fd8c825b40029224d6a','Kristi Vishwakarma'),
('6826e50239df190024332694','Preeti Grewal'),
('6821970fa1db9d0022424021','Jyoti Bisht'),
('680b60d0156ebc0028a242dd','Jyoti Bisht'),
('641077f3c72214002891eb08','Jyoti Bisht'),
('68107367c0b6d50023f48c04','Shirisha Marathi'),
('6829988dc212dd0024134a43','Shirisha Marathi'),
('6822fad72e01dc002567e8a8','Shirisha Marathi'),
('6822c333dd560b0024701322','Shirisha Marathi'),
('683186c7929d8e0022eec84c','Amit Semwal'),
('6776568b07ac7e0025e19af1','Neha Negi'),
('6825a0e7c8ee6d002513b669','Preeti Grewal'),
('6803a6046214390026582a8b','Kristi Vishwakarma'),
('681eea3d96721400238c2260','Jayashree'),
('681478d88c69e70025836579','Preeti Grewal'),
('6824590c9548cf002323be3a','Shirisha Marathi'),
('67ecc0ccfe6e8b00271a851d','Jyoti Bisht'),
('6800ad30ab9fbf002356032d','Jyoti Bisht'),
('682c37193bcfbf00231e07e3','Amit Semwal'),
('68219116521aee0024131ac8','Swati Weldode'),
('6822ce795856cf00248e1aa3','Shirisha Marathi'),
('681f939a44d7eb0025994b93','Kristi Vishwakarma'),
('6814b1d4528b8f0025d874ed','Kristi Vishwakarma'),
('681ba81f68ace10025477554','Amit Semwal'),
('67ee623d12d0420023ca5a7a','Shirisha Marathi'),
('6822ec574a8f6700257dfb80','Shirisha Marathi'),
('681c67cb5925d500289fd58d','Kristi Vishwakarma'),
('68299c16f3826700237b0069','Amit Semwal'),
('682893281fa40c002514ec89','Babita Kumari'),
('682ae5ba181e7a00243e6847','Anshu Mandal'),
('68302c40ba43ee00259ebb79','Amit Semwal'),
('680f36eb1d4d98002399a9d9','Anuja Rakshe'),
('682c5d5808fc060023cdc916','Babita Kumari'),
('681ef8792ba71700286877d9','Jayashree'),
('68298a533b6e240023b5b094','Anuja Rakshe'),
('68234b4bf14a1300277d7b83','Anuja Rakshe'),
('67e26064113d9f0024dcd0fc','Anuja Rakshe'),
('680208fad01a2d002ca0a422','Preeti Grewal'),
('6819bfc445d09e00246da0a8','Preeti Grewal'),
('6825847c7e52300025c3a4a1','Jyoti Bisht'),
('680373b8be72940025d02513','Jyoti Bisht'),
('67ef678886b6950025e2a9cd','Kristi Vishwakarma'),
('681f1fd79e9c0c00232c63a7','Jayashree'),
('682c1cdf9f1c5900239798aa','Anshu Mandal'),
('67ef799d098fb70024f1f912','Preeti Grewal'),
('68257d3a600c8d002546898f','Anuja Rakshe'),
('682aeea67b940200253aa45e','Shirisha Marathi'),
('6814c45fc0e6370023a12b5f','Kavita Suvarna'),
('681321da0417a500231573f6','Preeti Grewal'),
('681da6bce5f9b40024090469','Kristi Vishwakarma'),
('681f1d5624bffa00238f39e0','Jyoti Bisht'),
('64f9772e4787d00028575f2f','Swati Weldode'),
('6821a3086263810024accc9f','Anuja Rakshe'),
('681d989908638f0025901246','Amit Semwal'),
('680b38624933f900236f9350','Kristi Vishwakarma'),
('67fa31f03161bb0029d32270','Anuja Rakshe'),
('66a75d66ba51180021c6840e','Anuja Rakshe'),
('682897e9f49656002781b45c','Babita Kumari'),
('6829b5a4c212dd0024163143','Babita Kumari'),
('6805fe4d8d70fa0026ccb721','Anuja Rakshe'),
('6821d1477d6b2800248a37a2','Kristi Vishwakarma'),
('682acc0b0b7311002634432d','Neha Negi'),
('67ecf0d4535060002376e801','Swati Weldode'),
('681f09e79ce5c500294ba408','Preeti Grewal'),
('68185a8517da3b00238f5be7','Jyoti Bisht'),
('68078896cf8e770023cdc68b','Jyoti Bisht'),
('6824424b85f2b80028a506e6','Amit Semwal'),
('681f067d29bae60023fd8c6b','Shirisha Marathi'),
('680733ca4dd44500258496d7','Kristi Vishwakarma'),
('68131e6ad4edf90022cfe35a','Preeti Grewal'),
('682adbac5b33a800250793df','Babita Kumari'),
('6821bbc1e8c64900245e858e','Swati Weldode'),
('681f94c1dc52fd002268a31a','Babita Kumari'),
('68258aff101f720025eea444','Swati Weldode'),
('682199946e74b2002bd1968f','Shirisha Marathi'),
('6815e4503e7cf4002280d662','Anuja Rakshe'),
('6819da971e21ff0026280ea6','Anuja Rakshe'),
('682ac8057ba1a40025271911','Kristi Vishwakarma'),
('682ade3e751fb90026403712','Anshu Mandal'),
('680728454fb5a40026076554','Shirisha Marathi'),
('64c483e525d6f3002a28d2ba','Babita Kumari'),
('67e508a37841250022e7e691','Anuja Rakshe'),
('6831a995b2545700292543d2','Amit Semwal'),
('68219b048a819e00263de092','Shirisha Marathi'),
('683564b3df1e240024362f7f','Amit Semwal'),
('68245803b8ca220023a97f96','Kristi Vishwakarma'),
('6809db1f5ce970002552ae9d','Jyoti Bisht'),
('68230297db13e6002561456a','Swati Weldode'),
('6828068ff34e410023cae9d1','Babita Kumari'),
('68299763f49656002794c062','Shirisha Marathi'),
('682ad8557ba1a40025290be8','Anshu Mandal'),
('67cec1c2f8564d0024577ae9','Kavita Suvarna'),
('68107cb8e89b24002842949a','Shirisha Marathi'),
('683fe99d2198f400243b2979','Hari'),
('6836f760b094f200234c2b4f','Hari'),
('68341b3141f1fe0028960660','Hari'),
('68341c5549affe0024c7095b','Hari'),
('683fec2a0e71a10026bc5a95','Hari'),
('68412b37b00cd900241974b1','Hari'),
('682d941773f363002245cefc','Hari'),
('6842b1c08fbb3200275a6dd2','Hari'),
('6841756885676a002a9c1ad8','Hari'),
('6843c04e59d91900280b4670','Hari'),
('685522148d66ce00266c0846','Neeraj'),
('6854ecf3d706cb00254ef5f0','Neeraj'),
('6854ec0158c9c800246a29f9','Neeraj'),
('6853b5429694160023d8d528','Neeraj'),
('685249c442391f0026e9b95b','Neeraj'),
('68526778fb08ce00236ddd3e','Neeraj'),
('685252fecfd7e40025a02b03','Neeraj'),
('685130c26c0fce00244818d7','Neeraj'),
('684944f33a910100274c6054','Neeraj'),
('683846f32e81740025814be7','Neeraj'),
('6854f0d56eb35200273d09fb','Neeraj'),
('685501ec8815080022975bae','Neeraj'),
('6855032c1b667800275c3e60','Neeraj'),
('6852b153fb08ce0023758711','Neeraj'),
('685a5466c30d690024641ed6','Hari'),
('685a2f93956c950023a6ca23','Hari'),
('685a2cd3aeaed70023eb1aa0','Hari'),
('685ce70d24509500263424ed','Hari'),
('685ce596c9a20f00232d3de5','Hari'),
('685a2d164451860022df6442','Hari'),
('685ce67762cb780022bd8273','Hari'),
('685d30a0c4e169002812e1c4','Hari'),
('68566e0796a3e9002b8b6f15','Hari'),
('685a392a62b6fa00245b7467','Hari'),
('685b905e2bd2c000250d7b77','Hari'),
('685cdc312450950026330a83','Hari'),
('6116960e6db8de26005fbb6f','Hari'),
('685e536a581e9d0025bcd21a','Hari'),
('685e57235c65910023a021c8','Hari'),
('685e564da262020026d8b3ad','Hari'),
('68565776da8f2900280fca2f','Hari'),
('685a5466c30d690024641ed6','Neeraj'),
('685a2f93956c950023a6ca23','Neeraj'),
('685a2cd3aeaed70023eb1aa0','Neeraj'),
('685ce70d24509500263424ed','Neeraj'),
('685ce596c9a20f00232d3de5','Neeraj'),
('685a2d164451860022df6442','Neeraj'),
('685ce67762cb780022bd8273','Neeraj'),
('685d30a0c4e169002812e1c4','Neeraj'),
('68566e0796a3e9002b8b6f15','Neeraj'),
('685a392a62b6fa00245b7467','Neeraj'),
('685b905e2bd2c000250d7b77','Neeraj'),
('685cdc312450950026330a83','Neeraj'),
('6116960e6db8de26005fbb6f','Neeraj'),
('685e536a581e9d0025bcd21a','Neeraj'),
('685e57235c65910023a021c8','Neeraj'),('687492789f5dce0024f17857','Manisharathod'),
('6870fb373df681002419fbb1','Jayashree'),
('68677fb076f6d70024b2121c','Manisharathod'),
('687b0af397446f0025bf129c','Manisharathod'),
('686e280260ffa70027125790','Jayashree'),
('686e65a1ccbbe60028c65f83','Jayashree'),
('687b28cc6eb18f0024379580','Manisharathod'),
('687763d982b57d0027923bce','Manisharathod'),
('6825bafad6feb8002376ac04','Manisharathod'),
('686e47f8327389002517cafc','Jayashree'),
('687df9fd3ce05c0023bd619e','Manisharathod'),
('686f89b49225f100230ad25f','Jayashree'),
('6874fcc74b784600241707d3','Manisharathod'),
('6880c4176451a9002442f5e4','Manisharathod'),
('687f36e712f61d0026e25daf','Manisharathod'),
('687b2214adc53b002a8d689a','Manisharathod'),
('6868bcb1acde770026436eef','Jayashree'),
('685e564da262020026d8b3ad','Neeraj')
AS t(provider_id, trainer_name)
),
 
pip_raw_source AS (
  SELECT DISTINCT
      provider_id,
      tier_start_date,
      tier_end_date,
      paf_cancellation_at_tier AS paf_error,
      rating_error_at_tier AS rating_error,
      graded_leave_days_at_tier AS total_graded_leaves
  FROM PUBLIC.provider_promise_plan__daily__metrics
  WHERE category = 'instant_maids_l3'
    AND tier IS NOT NULL
),
 
pip_status_calc AS (
  SELECT 
      provider_id,
      tier_end_date,
      CASE
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 0 THEN 'diamond'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 1 THEN 'gold'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 2 THEN 'silver'
          WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves BETWEEN 3 AND 4 THEN 'bronze'
          ELSE 'pip'
      END AS potential_tier,
      ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY tier_start_date) as cycle_no
  FROM pip_raw_source
),
 
pip_provider_metrics AS (
    SELECT 
        provider_id,
        COUNT(CASE WHEN cycle_no IN (1, 2) AND potential_tier = 'pip' AND tier_end_date <= CURRENT_DATE THEN 1 END) as pip_fail_count,
        COUNT(CASE WHEN cycle_no IN (1, 2) AND tier_end_date <= CURRENT_DATE THEN 1 END) as pip_complete_count
    FROM pip_status_calc
    WHERE cycle_no IN (1, 2)
    GROUP BY provider_id
),
 
src AS (
    SELECT DISTINCT
        a.provider_id,
        f.value:"questionnaire_created_by"::string AS createdby,
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
ob_mapping AS (
    SELECT DISTINCT
        pmpr.provider_id,
    CASE
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('jyotibisht.ext', 'jyoti bisht') THEN 'Jyoti Bisht'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('kristivishwakarma', 'kristi harak vishwakarma') THEN 'Kristi Vishwakarma'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'jamadarsubhash.ext' THEN 'Jayashree'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'camelia kar' THEN 'Camelia Kar'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'babitakumari' THEN 'Babita Kumari'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'amitsemwal' THEN 'Amit Semwal'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('shirishamarathi', 'shirisha rajayya marathi') THEN 'Shirisha Marathi'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('preetigrewal.ext', 'preeti grewal') THEN 'Preeti Grewal'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('anjumandal', 'anju mandal') THEN 'Anshu Mandal'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('swatiweldode', 'swati dasharath weldode') THEN 'Swati Weldode'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'nehanegi' THEN 'Neha Negi'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('anujarakshe', 'anuja shyam rakshe') THEN 'Anuja Rakshe'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'manaswinichaturvedi' THEN 'Manaswini Chaturvedi'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'aditideshbhartar' THEN 'Aditi Deshbhartar'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('anushkasingh.ext', 'Anushkasingh.ext') THEN 'Anushka Singh'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('bhaveshchauhan', 'Bhaveshchauhan') THEN 'Bhavesh Chauhan'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('lakshmidevi', 'Lakshmidevi', 'Lakshmi devi') THEN 'Lakshmi Devi'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('ravishekhar', 'ravishekhar') THEN 'Ravi Shekhar'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('sangeetarai.ext', 'sangeeta') THEN 'Sangeeta Rai'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'swathi.ext' THEN 'Swathi'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'ravikumarsharma' THEN 'Ravi Sharma'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'poortigupta.ext' THEN 'Poorti Gupta'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'shivashankara.ext' THEN 'Shiva Shankara'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'abhaygupta' THEN 'Abhay Gupta'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('ambatiharibabu', 'haribabu') THEN 'Hari'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'prashantkumar2' THEN 'Prashant Kumar'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'gaddamidikarthik' THEN 'Karthik'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'neerajsamyal.ext' THEN 'Neeraj'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'parveenmahato.ext' THEN 'Praveen Mahato'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'shriyabhardwaj' THEN 'Shriya Bhardwaj'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'chandanverma' THEN 'Chandan Verma'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'joybrotochoudhury' THEN 'Joybroto Choudhury'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('pavithrajl', 'pavithra') THEN 'Pavithra'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('krishnamurari', 'Krishnamurari') THEN 'Krishan'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'thaneshwaripatel' THEN 'Thaneshwari Patel'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'vaitlasoundharya' THEN 'Soundharya'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'sujathakc' THEN 'Sujatha'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'ajithp.ext' THEN 'Ajith'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'anandidas.ext' THEN 'Anandidas'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'debashreesethi.ext' THEN 'Debashree'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'hepsibaramanujam.ext' THEN 'Hepsiba'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'priyankasingh1' THEN 'Priyanka Singh'
WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) = 'shravyakondvilkar' THEN 'Shravya Kondvilkar'
      WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) in ('kavitapoojari','amitsemwal','babitakumari') THEN 'NR'
      ELSE INITCAP(REPLACE(pmpr.createdby, '@urbancompany.com', ''))
    END AS trainer_name,
    DATE(pmpr.updated_at_ist) AS training_date
    FROM src pmpr
    
    )
,
 
trainer_mapping1 AS (
 SELECT provider_id
    FROM ob_mapping 
 
    UNION all
 
    SELECT provider_id
    FROM manual_mapping
)
,
trainer_mapping as 
(select distinct tm.provider_id ,
case when mm.trainer_name is null then om.trainer_name else mm.trainer_name end as trainer_name
from trainer_mapping1 tm
left join manual_mapping mm on mm.provider_id=tm.provider_id
left join ob_mapping om on tm.provider_id=om.provider_id)
,
 
-- [NEW] DNPS Calculation Logic from Query A
dnps_calc_base AS (
    SELECT 
        r.customer_request_id,
        r.PROVIDER_ID,
        r.service_delivered,
        DATE_TRUNC('week', r.BDATE) as week,
        CASE 
            WHEN r.service_rating >= 9 THEN 1
            WHEN r.service_rating <= 6 THEN -1
            WHEN r.service_rating IN (7, 8) THEN 0
            ELSE NULL
        END AS nps
    FROM PUBLIC.REQUEST__DAILY__FACTS r
    WHERE r.reporting_supercategory_new = 'Insta Help'
      AND r.bdate_final > '2025-02-05'
      AND r.reporting_city <> 'Singapore'
),
 
dnps_calc AS (
    SELECT 
        provider_id,
        week AS perf_week,
        ROUND(
            (
                (SUM(CASE WHEN nps = 1 AND service_delivered = 1 THEN 1 ELSE 0 END)
               - SUM(CASE WHEN nps = -1 AND service_delivered = 1 THEN 1 ELSE 0 END)) 
               * 100.0
            ) 
            / NULLIF(COUNT(CASE WHEN nps IS NOT NULL AND service_delivered = 1 THEN 1 END), 0)
        , 2) AS del_nps
    FROM dnps_calc_base
    GROUP BY provider_id, week
),
 
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
case when total_graded_leaves is null then 0 else total_graded_leaves end as total_graded_leaves,
COALESCE(ppm.pip_fail_count, 0) as pip_fail_count,
COALESCE(ppm.pip_complete_count, 0) as pip_complete_count,
dnps.del_nps
 
from
final f 
left join (select * from trainer_mapping where trainer_name is not null) tm on f.provider_id=tm.provider_id
left join pip_provider_metrics ppm on f.provider_id = ppm.provider_id
left join dnps_calc dnps on f.provider_id = dnps.provider_id AND f.cm_week = dnps.perf_week
),
 
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
paf_request_ids,
pip_fail_count,
pip_complete_count,
del_nps
from
lst)
 
SELECT
DISTINCT trainer_name,
city as "city::multi-filter",
perf_week as "perf_week::multi-filter", -----changes
count(distinct case when life_cycle='ELC' then provider_id end) as hh_eligible,
count(distinct case when life_cycle='ELC' and churn_status='churn' then provider_id end) as churn_pros,
sum(case when life_cycle='ELC' then f10_sum_weekly_rating end)/sum(case when life_cycle='ELC' then f10_sum_weekly_rated_jobs end) as F10_rating,
count(distinct case when life_cycle='LLC' then provider_id end) as total_old,
count(distinct case when life_cycle='ELC' and week_perf='No Error' then provider_id end) as no_error,
count(distinct case when life_cycle='ELC' and week_perf='Good' then provider_id end) as good,
count(distinct case when life_cycle='ELC' and week_perf='Average' then provider_id end) as average,
count(distinct case when life_cycle='ELC' and week_perf='Bad' then provider_id end) as Bad,
(Bad+average)*100/hh_eligible as bad_average_perc,
100-Bad*100/hh_eligible as ideal_partner_perc,
case when nullif(sum(distinct case when life_cycle='ELC' then paf_count end),0)/nullif(sum(distinct case when life_cycle='ELC' then total_requests end),0)
is null then 0 else 
nullif(sum(case when life_cycle='ELC' then paf_count end),0)*100/nullif(sum(case when life_cycle='ELC' then total_requests end),0) end as paf_perc,
case when nullif(sum(case when life_cycle='ELC' then total_graded_leaves end),0)/nullif(count(case when life_cycle='ELC' then provider_id end),0) is null then
0 else 
nullif(sum(case when life_cycle='ELC' then total_graded_leaves end),0)/nullif(count( case when life_cycle='ELC' then provider_id end),0) end as leaves_per_pro,
case when nullif(sum(case when life_cycle='ELC' then total_rating_sum end),0)/nullif(sum(case when life_cycle='ELC' then total_rated_jobs end),0)
is null then 0 else
nullif(sum(case when life_cycle='ELC' then total_rating_sum end),0)/nullif(sum(case when life_cycle='ELC' then total_rated_jobs end),0) end as hh_pros_avg_rating,
sum(total_deliveries)/hh_eligible AS Util,
 
ROUND(
    100.0 * 
    SUM(CASE WHEN life_cycle='ELC' THEN pip_fail_count ELSE 0 END)
    /
    NULLIF(SUM(CASE WHEN life_cycle='ELC' THEN pip_complete_count ELSE 0 END), 0),
    2
) AS elc_pip_pct,
 
AVG(del_nps) AS dnps
 
from cumulative 
where trainer_name is not null
 
group by all
HAVING COUNT(DISTINCT CASE WHEN life_cycle='ELC' THEN provider_id END) > 0
and (
        SUM(total_deliveries)
        / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle='ELC' THEN provider_id END),0)
    ) < 30
order by 1,2,3