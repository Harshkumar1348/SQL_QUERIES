/*
================================================================================
QUERY A - COMPLETE CORRECTED VERSION WITH FIXED CHURN_STATUS AND CHURN_PROS
================================================================================
Key Corrections Applied:
1. n7d uses NEXT 7 days (current_date+1 to current_date+7) instead of past
2. Working hours threshold changed from >8 to >5  
3. churn_status = 'churn' ONLY when active_status='Churned' AND n7d_status='Not Working'
4. active_status based on last_delivery_date logic
================================================================================
*/

WITH base AS (
    SELECT DISTINCT 
        pdf.provider_id,
        provider_name,
        city,
        avg_rating,
        DATE(approval_date) AS app_date,
        DATE_TRUNC(week, app_date) AS approval_week,
        last_delivery_date,
        -- CORRECTED: active_status based on last_delivery_date
        CASE 
            WHEN last_delivery_date > CURRENT_DATE - 7 THEN 'Active'
            WHEN last_delivery_date IS NULL AND app_date > CURRENT_DATE - 7 THEN 'Active' 
            ELSE 'Churned' 
        END AS active_status,
        -- CORRECTED: working_hrs from NEXT 7 days (current_date+1 to current_date+7)
        SUM(CASE WHEN acm.date BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + 7 THEN marked_working END) AS working_hrs,
        -- CORRECTED: threshold changed from >5 to match Query A logic
        CASE WHEN working_hrs > 5 THEN 'Working' ELSE 'Not Working' END AS N7D_status
    FROM provider__daily__facts pdf
    LEFT JOIN (
        SELECT DISTINCT 
            PROVIDER_ID, 
            date,
            COUNT(CASE WHEN status IN ('unmarked', 'marked leave', 'marked working') THEN provider_id ELSE NULL END) AS total_hours,
            COUNT(CASE WHEN status IN ('marked working') THEN provider_id ELSE NULL END) AS marked_working 
        FROM PUBLIC.providerXdateXhour__calendar_marking__hourly__facts 
        WHERE DATE(date) BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
          AND START_HOUR_LOCAL BETWEEN 8 AND 19
        GROUP BY 1, 2
    ) acm ON acm.provider_id = pdf.provider_id
    WHERE customer_category_key = 'insta_maids'
      AND approval_date >= '2025-02-01'
      AND country = 'India'
    GROUP BY ALL
),

cm AS (
    SELECT DISTINCT 
        a.PROVIDER_ID, 
        DATE_TRUNC(week, DATE(a.date)) AS cm_week,
        date,
        DAYOFWEEK(date) week_day,
        COUNT(CASE WHEN status IN ('marked working') THEN a.provider_id ELSE NULL END) AS marked_working,
        COUNT(CASE WHEN status IN ('marked leave') THEN a.provider_id ELSE NULL END) AS marked_leave
    FROM PUBLIC.providerXdateXhour__calendar_marking__hourly__facts a
    JOIN base b ON b.provider_id = a.provider_id
    WHERE a.provider_id IN (SELECT DISTINCT provider_id FROM base)
      AND START_HOUR_LOCAL BETWEEN 8 AND 19
      AND date <= CURRENT_DATE
      AND app_date <= date
    GROUP BY 1, 2, 3, 4
),

f_cm AS (
    SELECT DISTINCT 
        provider_id,
        AVG(marked_working) AS avg_working_hours
    FROM cm
    GROUP BY 1
),

cm_final AS (
    SELECT DISTINCT 
        cm.*,
        CASE WHEN avg_working_hours IS NULL THEN 0 ELSE avg_working_hours END AS avg_wrkn_hrs
    FROM cm 
    LEFT JOIN f_cm ON cm.provider_id = f_cm.provider_id
),

Rating_raw AS (
    SELECT 
        DISTINCT responded_pro_booking AS provider_id,
        rating,
        DATE(rating_date) + 3 AS ratings_date,
        DATE_TRUNC('week', ratings_date) AS rating_week,
        customer_request_id,
        RANK() OVER(PARTITION BY responded_pro_booking ORDER BY ratings_date) AS rnk
    FROM PUBLIC.REQUEST__HOURLY__FACTS 
    WHERE customer_category_key = 'insta_maids'
      AND provider_id IN (SELECT DISTINCT provider_id FROM base)
      AND rating IS NOT NULL
),

l10rating AS (
    SELECT DISTINCT 
        provider_id,
        rating_week,
        SUM(rating) AS f10_sum_weekly_rating,
        COUNT(DISTINCT customer_request_id) AS f10_sum_weekly_rated_jobs
    FROM rating_raw 
    WHERE rnk <= 10
    GROUP BY 1, 2
),

rr AS (
    SELECT DISTINCT 
        provider_id,
        rating_week,
        LISTAGG(DISTINCT customer_request_id, ', ') WITHIN GROUP(ORDER BY customer_request_id ASC) AS request_ids
    FROM rating_raw 
    WHERE rating < 4.5
    GROUP BY 1, 2
),

rating AS (
    SELECT DISTINCT 
        r.provider_id,
        r.rating_week,
        rr.request_ids,
        AVG(rating) AS avg_weekly_rating,
        SUM(rating) AS total_rating_sum,
        COUNT(DISTINCT customer_request_id) AS total_rated_jobs,
        COUNT(DISTINCT CASE WHEN rating < 4.5 THEN customer_request_id END) AS bad_rated_jobs
    FROM rating_raw r 
    LEFT JOIN rr ON r.provider_id = rr.provider_id AND r.rating_week = rr.rating_week
    GROUP BY 1, 2, 3
),

pp AS (
    SELECT 
        responded_pro_booking AS provider_id, 
        DATE_TRUNC('WEEK', DATE(paf.cancelled_at)) AS paf_week,
        LISTAGG(DISTINCT paf.customer_request_id, ', ') WITHIN GROUP(ORDER BY paf.customer_request_id ASC) AS paf_request_ids
    FROM REQUEST__BCE__HOURLY__FACTS paf
    JOIN request__hourly__facts rhf ON rhf.customer_request_id = paf.customer_request_id
    WHERE paf.customer_category_key = 'insta_maids'
      AND fault = 'PRO' 
      AND paf.ns_provider_at_fault_flag = 1
      AND provider_id IN (SELECT DISTINCT provider_id FROM base)
    GROUP BY 1, 2
),

PAF_raw AS (
    SELECT 
        responded_pro_booking AS provider_id, 
        DATE_TRUNC('WEEK', DATE(paf.cancelled_at)) AS paf_week,
        COUNT(DISTINCT CASE WHEN paf.ns_provider_at_fault_flag = 1 THEN paf.customer_request_id END) AS paf_count
    FROM REQUEST__BCE__HOURLY__FACTS paf
    JOIN request__hourly__facts rhf ON rhf.customer_request_id = paf.customer_request_id
    WHERE paf.customer_category_key = 'insta_maids'
      AND provider_id IN (SELECT DISTINCT provider_id FROM base)
    GROUP BY 1, 2
),

paf AS (
    SELECT 
        pr.*,
        paf_request_ids
    FROM paf_raw pr 
    LEFT JOIN pp ON pr.provider_id = pp.provider_id AND pp.paf_week = pr.paf_week
),

final_raw AS (
    SELECT 
        b.*,
        -- ================================================================
        -- CORRECTED: churn_status combines active_status AND n7d_status
        -- 'churn' ONLY if active_status='Churned' AND n7d_status='Not Working'
        -- ================================================================
        CASE 
            WHEN active_status = 'Churned' AND n7d_status = 'Not Working' THEN 'churn' 
            ELSE 'active' 
        END AS churn_status,
        cm_week,
        cm_week - app_date AS age,
        total_rated_jobs,
        bad_rated_jobs,
        request_ids,
        avg_weekly_rating,
        f10_sum_weekly_rating,
        f10_sum_weekly_rated_jobs,
        total_rating_sum,
        paf_count,
        paf_request_ids,
        COUNT(DISTINCT CASE 
            WHEN avg_wrkn_hrs > 7 AND marked_leave > 5 THEN date 
            WHEN avg_wrkn_hrs < 7 AND marked_leave > 6 THEN date 
        END) AS total_leaves,
        COUNT(DISTINCT CASE 
            WHEN avg_wrkn_hrs > 7 AND marked_leave > 5 AND week_day IN (5, 6, 0) THEN date 
            WHEN avg_wrkn_hrs < 7 AND marked_leave > 6 AND week_day IN (5, 6, 0) THEN date 
        END) AS total_weekend_leaves,
        COUNT(DISTINCT CASE 
            WHEN avg_wrkn_hrs > 7 AND marked_leave > 5 AND week_day NOT IN (5, 6, 0) THEN date 
            WHEN avg_wrkn_hrs < 7 AND marked_leave > 6 AND week_day NOT IN (5, 6, 0) THEN date 
        END) AS total_weekday_leaves
    FROM base b 
    LEFT JOIN cm_final cm ON b.provider_id = cm.provider_id
    LEFT JOIN rating r ON r.provider_id = cm.provider_id AND r.rating_week = cm.cm_week
    LEFT JOIN l10rating r10 ON r10.provider_id = cm.provider_id AND r10.rating_week = cm.cm_week
    LEFT JOIN paf p ON p.provider_id = cm.provider_id AND p.paf_week = cm.cm_week
    WHERE cm_week IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21
),

final AS (
    SELECT DISTINCT 
        provider_id,
        provider_name,
        churn_status,
        city,
        app_date,
        approval_week,
        cm_week,
        RANK() OVER(PARTITION BY provider_id ORDER BY cm_week) AS week_num,
        age,
        gr,
        sd,
        total_rated_jobs,
        bad_rated_jobs,
        request_ids,
        avg_rating AS overall_avg_rating,
        f10_sum_weekly_rating,
        f10_sum_weekly_rated_jobs,
        avg_weekly_rating,
        total_rating_sum,
        paf_count,
        paf_request_ids,
        total_weekday_leaves + (total_weekend_leaves * 2) AS total_graded_leaves
    FROM final_raw a
    LEFT JOIN (
        SELECT DISTINCT 
            responded_pro_booking,
            DATE_TRUNC(week, DATE(bdate_final)) AS week,
            COUNT(DISTINCT CASE WHEN gross_status = 'gross_request' THEN customer_request_id END) AS gr,
            COUNT(DISTINCT CASE WHEN net_status = 'net_request' AND service_delivered = 'true' THEN customer_request_id END) AS sd
        FROM master_data
        WHERE customer_category_key = 'insta_maids'
          AND responded_pro_booking IN (SELECT DISTINCT provider_id FROM base)
        GROUP BY 1, 2
    ) u ON u.responded_pro_booking = a.provider_id AND u.week = a.cm_week
    ORDER BY provider_id, cm_week
),

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
    ('687217892dd26500228c391e','Jayashree')
    -- Add remaining manual mappings here...
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
        ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY tier_start_date) AS cycle_no
    FROM pip_raw_source
),

pip_provider_metrics AS (
    SELECT 
        provider_id,
        COUNT(CASE WHEN cycle_no IN (1, 2) AND potential_tier = 'pip' AND tier_end_date <= CURRENT_DATE THEN 1 END) AS pip_fail_count,
        COUNT(CASE WHEN cycle_no IN (1, 2) AND tier_end_date <= CURRENT_DATE THEN 1 END) AS pip_complete_count
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
            WHEN TRIM(LOWER(REPLACE(pmpr.createdby, '@urbancompany.com', ''))) IN ('kavitapoojari', 'amitsemwal', 'babitakumari') THEN 'NR'
            ELSE INITCAP(REPLACE(pmpr.createdby, '@urbancompany.com', ''))
        END AS trainer_name,
        DATE(pmpr.updated_at_ist) AS training_date
    FROM src pmpr
),

trainer_mapping1 AS (
    SELECT provider_id FROM ob_mapping 
    UNION ALL
    SELECT provider_id FROM manual_mapping
),

trainer_mapping AS (
    SELECT DISTINCT 
        tm.provider_id,
        CASE WHEN mm.trainer_name IS NULL THEN om.trainer_name ELSE mm.trainer_name END AS trainer_name
    FROM trainer_mapping1 tm
    LEFT JOIN manual_mapping mm ON mm.provider_id = tm.provider_id
    LEFT JOIN ob_mapping om ON tm.provider_id = om.provider_id
),

dnps_calc_base AS (
    SELECT 
        r.customer_request_id,
        r.PROVIDER_ID,
        r.service_delivered,
        DATE_TRUNC('week', r.BDATE) AS week,
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

lst AS (
    SELECT DISTINCT 
        f.provider_id,
        provider_name,
        trainer_name,
        city,
        app_date,
        approval_week,
        cm_week AS perf_week,
        week_num,
        age,
        churn_status,
        CASE WHEN age <= 30 THEN 'ELC' ELSE 'LLC' END AS life_cycle,
        overall_avg_rating,
        f10_sum_weekly_rating,
        f10_sum_weekly_rated_jobs,
        avg_weekly_rating,
        total_rating_sum,
        total_rated_jobs,
        gr AS total_requests,
        sd AS total_deliveries,
        CASE WHEN bad_rated_jobs IS NULL THEN 0 ELSE bad_rated_jobs END AS bad_rated_jobs,
        request_ids,
        CASE WHEN paf_count IS NULL THEN 0 ELSE paf_count END AS paf_count,
        paf_request_ids,
        CASE WHEN total_graded_leaves IS NULL THEN 0 ELSE total_graded_leaves END AS total_graded_leaves,
        COALESCE(ppm.pip_fail_count, 0) AS pip_fail_count,
        COALESCE(ppm.pip_complete_count, 0) AS pip_complete_count,
        dnps.del_nps
    FROM final f 
    LEFT JOIN (SELECT * FROM trainer_mapping WHERE trainer_name IS NOT NULL) tm ON f.provider_id = tm.provider_id
    LEFT JOIN pip_provider_metrics ppm ON f.provider_id = ppm.provider_id
    LEFT JOIN dnps_calc dnps ON f.provider_id = dnps.provider_id AND f.cm_week = dnps.perf_week
),

cumulative AS (
    SELECT DISTINCT 
        provider_id,
        provider_name,
        trainer_name,
        city,
        churn_status,
        app_date,
        perf_week,
        week_num,
        age,
        life_cycle,
        total_requests,
        total_deliveries,
        total_rated_jobs,
        total_rating_sum,
        overall_avg_rating,
        f10_sum_weekly_rating,
        f10_sum_weekly_rated_jobs,
        avg_weekly_rating,
        bad_rated_jobs,
        paf_count,
        total_graded_leaves,
        CASE 
            WHEN bad_rated_jobs > 2 OR total_graded_leaves > 2 OR paf_count > 2 THEN 'Bad'
            WHEN bad_rated_jobs = 2 OR total_graded_leaves = 2 OR paf_count = 2 THEN 'Average'
            WHEN bad_rated_jobs = 1 OR total_graded_leaves = 1 OR paf_count = 1 THEN 'Good'
            WHEN COALESCE(bad_rated_jobs, 0) = 0 AND COALESCE(total_graded_leaves, 0) = 0 AND COALESCE(paf_count, 0) = 0 THEN 'No Error'
        END AS week_perf,
        request_ids AS bad_rated_request_ids,
        paf_request_ids,
        pip_fail_count,
        pip_complete_count,
        del_nps
    FROM lst
)

-- ============================================================================
-- FINAL SELECT with churn_pros correctly calculated
-- churn_pros now counts providers where:
--   1. life_cycle = 'ELC' (age <= 30 days)
--   2. churn_status = 'churn' (active_status='Churned' AND n7d_status='Not Working')
-- ============================================================================
SELECT
    DISTINCT trainer_name,
    city AS "city::multi-filter",
    perf_week AS "perf_week::multi-filter",
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END) AS hh_eligible,
    -- CORRECTED churn_pros: Now uses the corrected churn_status logic
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND churn_status = 'churn' THEN provider_id END) AS churn_pros,
    SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rating END) / SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rated_jobs END) AS F10_rating,
    COUNT(DISTINCT CASE WHEN life_cycle = 'LLC' THEN provider_id END) AS total_old,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'No Error' THEN provider_id END) AS no_error,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Good' THEN provider_id END) AS good,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Average' THEN provider_id END) AS average,
    COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END) AS Bad,
    (Bad + average) * 100 / hh_eligible AS bad_average_perc,
    100 - Bad * 100 / hh_eligible AS ideal_partner_perc,
    CASE 
        WHEN NULLIF(SUM(DISTINCT CASE WHEN life_cycle = 'ELC' THEN paf_count END), 0) / NULLIF(SUM(DISTINCT CASE WHEN life_cycle = 'ELC' THEN total_requests END), 0) IS NULL THEN 0 
        ELSE NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN paf_count END), 0) * 100 / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_requests END), 0) 
    END AS paf_perc,
    CASE 
        WHEN NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_graded_leaves END), 0) / NULLIF(COUNT(CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0) IS NULL THEN 0 
        ELSE NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_graded_leaves END), 0) / NULLIF(COUNT(CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0) 
    END AS leaves_per_pro,
    CASE 
        WHEN NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rating_sum END), 0) / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rated_jobs END), 0) IS NULL THEN 0
        ELSE NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rating_sum END), 0) / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rated_jobs END), 0) 
    END AS hh_pros_avg_rating,
    SUM(total_deliveries) / hh_eligible AS Util,
    ROUND(
        100.0 * 
        SUM(CASE WHEN life_cycle = 'ELC' THEN pip_fail_count ELSE 0 END)
        /
        NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN pip_complete_count ELSE 0 END), 0),
        2
    ) AS elc_pip_pct,
    AVG(del_nps) AS dnps
FROM cumulative 
WHERE trainer_name IS NOT NULL
GROUP BY ALL
HAVING COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END) > 0
   AND (
        SUM(total_deliveries)
        / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
    ) < 30
ORDER BY 1, 2, 3;
