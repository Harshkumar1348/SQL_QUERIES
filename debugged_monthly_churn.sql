WITH provider_months AS (
    SELECT distinct p.provider_id, date_trunc('month', date(BDATE_FINAL)) as month, reporting_city
    FROM (SELECT DISTINCT provider_id, bdate_final, reporting_city
    FROM request__daily__facts
    where customer_category_key in ('insta_maids')
    and country='India'
    AND reporting_city <> 'Singapore'
    and service_delivered=1
    and date(bdate_final) < current_date
    ) p
),

months as (
    SELECT DATE_TRUNC('month', CURRENT_DATE) AS month_start, 0 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month', 1 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '2 month', 2 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '3 month', 3 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '4 month', 4 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5 month', 5 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 month', 6 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '7 month', 7 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '8 month', 8 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '9 month', 9 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '10 month', 10 AS month_num
    UNION ALL
    SELECT DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 month', 11 AS month_num
),

-- ============== NEW: L7D FOR GROSS CHURN (ORIGINAL DELIVERY GAP LOGIC) ==============
delivery_log AS (
    SELECT DISTINCT
        provider_id,
        reporting_city,
        DATE(bdate_final) AS delivery_date
    FROM PUBLIC.request__daily__facts
    WHERE reporting_supercategory_new = 'Insta Help'
      AND service_delivered = 1
      AND country = 'India'
      AND city NOT IN ('Singapore', 'Mysore')
),

delivery_gaps AS (
    SELECT 
        provider_id,
        reporting_city,
        delivery_date AS ldd_date,
        DATE_TRUNC('month', delivery_date) AS ldd_month,
        COALESCE(
            LEAD(delivery_date) OVER (PARTITION BY provider_id ORDER BY delivery_date), 
            CURRENT_DATE
        ) AS next_activity_date
    FROM delivery_log
),

churn_instances AS (
    SELECT
        dg.provider_id,
        dg.reporting_city,
        dg.ldd_month,
        dg.ldd_date,
        COUNT(CASE WHEN acm.status = 'marked working' THEN 1 END) AS post_ldd_working_hours
    FROM delivery_gaps dg
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON dg.provider_id = acm.provider_id
        AND DATE(acm.date) > dg.ldd_date
        AND DATE(acm.date) <= dg.ldd_date + INTERVAL '7 day'
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE DATEDIFF('day', dg.ldd_date, dg.next_activity_date) > 6
    GROUP BY 1, 2, 3, 4
),

l7d_gross AS (
    SELECT
        reporting_city,
        ldd_month,
        provider_id,
        'Not Working' AS l7d_status
    FROM churn_instances
    WHERE post_ldd_working_hours < 8
),

-- ============== NEW: L7D FOR NET CHURN ==============
l7d_for_net_churn AS (
    SELECT 
        pdf.provider_id,
        CASE 
            WHEN SUM(CASE WHEN status = 'marked working' THEN 1 ELSE 0 END) > 8 THEN 'Working'
            ELSE 'Not Working'
        END AS L7D_status
    FROM provider__daily__facts pdf
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON pdf.provider_id = acm.provider_id
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
        AND acm.start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY 1
),

-- ============== NEW: PROVIDER CURRENT STATUS FOR GROSS CHURN ==============
provider_current_status_gross as (
    SELECT
        pdf.provider_id,
        pdf.city AS reporting_city,
        CASE 
            WHEN pdf.last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('month', DATE(pdf.approval_date)), 'YYYY-MM-DD') 
            ELSE TO_CHAR(DATE_TRUNC('month', DATE(pdf.last_delivery_date)), 'YYYY-MM-DD') 
        END AS ldd_month,
        CASE 
            WHEN COALESCE(l7d_gross.l7d_status, 'Unknown') = 'Not Working' THEN 'Churned'
            WHEN pdf.last_delivery_date IS NULL 
                 AND DATE(pdf.approval_date) >= CURRENT_DATE - 7 THEN 'Active'
            ELSE 'Active'
        END AS pro_current_status
    FROM provider__daily__facts pdf
    LEFT JOIN (SELECT DISTINCT provider_id, l7d_status FROM l7d_gross) l7d_gross 
        ON pdf.provider_id = l7d_gross.provider_id
    WHERE pdf.reporting_supercategory_new = 'Insta Help'
      AND pdf.city NOT IN ('Singapore','Mysore')
      AND pdf.approval_date IS NOT NULL
),

-- ============== NEW: PROVIDER CURRENT STATUS FOR NET CHURN ==============
provider_current_status_net AS (
    SELECT
        pdf.provider_id,
        pdf.city AS reporting_city,
        CASE 
            WHEN last_delivery_date IS NULL THEN TO_CHAR(DATE_TRUNC('month', DATE(approval_date)), 'YYYY-MM-DD') 
            ELSE TO_CHAR(DATE_TRUNC('month', DATE(last_delivery_date)), 'YYYY-MM-DD') 
        END AS ldd_month,
        CASE 
            WHEN COALESCE(l7d_for_net_churn.L7D_status, 'Unknown') = 'Not Working' THEN 'Churned'
            WHEN COALESCE(l7d_for_net_churn.L7D_status, 'Unknown') = 'Working' THEN 'Active'
            WHEN last_delivery_date IS NULL 
                 AND DATE(approval_date) >= CURRENT_DATE - 7 THEN 'Active'
        END AS pro_current_status
    FROM provider__daily__facts pdf
    LEFT JOIN l7d_for_net_churn ON pdf.provider_id = l7d_for_net_churn.provider_id
    WHERE pdf.reporting_supercategory_new = 'Insta Help'
      AND pdf.city NOT IN ('Singapore','Mysore')
      AND approval_date IS NOT NULL
),

provider_months_combined AS (
    SELECT 
        p.provider_id,
        p.city as reporting_city,
        date(p.approval_date) as approval_date,
        w.month_start,
        w.month_num
    FROM provider__daily__facts p
    CROSS JOIN months w
    WHERE customer_category_key in ('insta_maids')
      AND p.provider_id not in('649809118e2b920027381c8b','6540b306f93f8f0024edae02','652e3bd7be83ab00347c41b9','65d743bb2894c80027f18563','6593d80bd91e7c00253bc68b')
      AND country='India'
      AND city not in ('Singapore', 'Mysore')
),

min_bdate as (
    SELECT provider_id,
           FIRST_DELIVERY_DATE as min_bdate_final,
           LAST_DELIVERY_DATE as ldd
    FROM provider__Daily__Facts
),

-- ============== NEW: MONTHLY CALENDAR MARKINGS ==============
provider_monthly_markings AS (
    SELECT
        pmc.provider_id,
        pmc.month_start,
        COALESCE(SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END), 0) AS marked_count_month,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END), 0) > 8 
                THEN 'Working'
            ELSE 'Not Working'
        END AS month_mark_status
    FROM provider_months_combined pmc
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
      ON pmc.provider_id = acm.provider_id
      AND DATE_TRUNC('month', DATE(acm.date)) = pmc.month_start
      AND acm.start_hour_local BETWEEN 8 AND 19
    GROUP BY pmc.provider_id, pmc.month_start
),

provider_monthly_markings_with_lag AS (
    SELECT
        provider_id,
        month_start,
        marked_count_month,
        month_mark_status,
        LAG(month_mark_status) OVER (PARTITION BY provider_id ORDER BY month_start) AS lag_month_mark_status
    FROM provider_monthly_markings
),

-- churn_events logic kept for reference but not strictly needed for simplified reactivation
churn_events AS (
    SELECT
        provider_id,
        month_start AS churn_month
    FROM provider_monthly_markings_with_lag
    WHERE lag_month_mark_status = 'Working'
      AND month_mark_status = 'Not Working'
),

base_final as (
    SELECT
        pwc.reporting_city,
        pwc.provider_id,
        pwc.month_start,
        m.min_bdate_final,
        pwc.approval_Date,
        CASE
            WHEN pw.month IS NOT NULL THEN 1
            WHEN pwc.month_start <= date_trunc('month', pwc.approval_Date) and m.ldd >= pwc.approval_Date THEN 1
            ELSE 0
        END AS working_status,
        pcs_gross.pro_current_status,
        LAG(
            CASE
                WHEN pw.month IS NOT NULL THEN 1
                WHEN pwc.month_start <= date_trunc('month', pwc.approval_Date) and m.ldd >= pwc.approval_Date THEN 1
                ELSE 0
            END
        ) OVER (PARTITION BY pwc.provider_id ORDER BY pwc.month_Start) as lag_Status,
        pmm.month_mark_status,
        pmm.lag_month_mark_status,
        pcs_net.pro_current_status AS pro_current_status_for_reactivation
    FROM provider_months_combined pwc
    LEFT JOIN provider_months pw 
        ON pwc.provider_id = pw.provider_id 
        AND pwc.month_start = pw.month
    LEFT JOIN min_bdate m 
        ON m.provider_id = pwc.provider_id
    LEFT JOIN provider_current_status_gross pcs_gross 
        ON pcs_gross.provider_id = pwc.provider_id
    LEFT JOIN provider_monthly_markings_with_lag pmm
        ON pmm.provider_id = pwc.provider_id 
        AND pmm.month_start = pwc.month_start
    LEFT JOIN provider_current_status_net pcs_net
        ON pcs_net.provider_id = pwc.provider_id
    WHERE pwc.approval_Date is not null
),

-- ============== NEW: GROSS CHURN (ORIGINAL L7D LOGIC) ==============
churned_gross as (
    SELECT
        reporting_city,
        ldd_month as month,
        COUNT(DISTINCT provider_id) AS churned
    FROM l7d_gross
    GROUP BY 1, 2
),

-- ============== NEW: NET CHURN ==============
churned_net as (
    SELECT
        reporting_city,
        ldd_month as month,
        COUNT(DISTINCT provider_id) AS churned
    FROM provider_current_status_net
    WHERE pro_current_status = 'Churned'
    GROUP BY 1, 2
),

-- ============== NEW: REACTIVATION ==============
reactivation as (
    SELECT
        bf.reporting_city,
        bf.month_start AS month,
        COUNT(DISTINCT bf.provider_id) AS reactivations
    FROM base_final bf
    WHERE bf.month_mark_status = 'Working'
      AND bf.lag_month_mark_status = 'Not Working'
      -- Ensure not the first month of activation (filter out new joiners)
      AND bf.month_start > DATE_TRUNC('month', bf.min_bdate_final)
      AND bf.working_status = 1
      AND bf.pro_current_status_for_reactivation = 'Active'
      AND EXISTS (
          SELECT 1 FROM churn_events ce
          WHERE ce.provider_id = bf.provider_id
            AND ce.churn_month < bf.month_start
      )
    GROUP BY 1, 2
),

approvals as (
    SELECT city as reporting_city,
           date_trunc('month', date(approval_date)) as month,
           count(distinct provider_id) as approvals,
           COUNT(DISTINCT CASE WHEN DATE_TRUNC('month', approval_Date) != DATE_TRUNC('month', FIRST_DELIVERY_DATE) THEN provider_id END) AS approved_pro_not_delivering_same_month
    FROM provider__daily__facts
    WHERE customer_category_key in ('insta_maids')
      AND reporting_city <> 'Singapore'
      AND provider_id not in('649809118e2b920027381c8b','6540b306f93f8f0024edae02','652e3bd7be83ab00347c41b9','65d743bb2894c80027f18563','6593d80bd91e7c00253bc68b')
    GROUP BY 1,2
),

-- ============== HUB TAGGED LOGIC FOR APC ==============
hub_tagged_base AS (
    SELECT 
        aa.provider_id,
        DATE(aa.updated_at) AS updated,
        LEFT(hub_name, CHARINDEX('_city', hub_name) - 1) AS tagged_hub
    FROM PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS aa
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW ON SMART_HUBS_VIEW.hub_id = aa.primary_hub_id
    LEFT JOIN PROVIDER__DAILY__FACTS pdf ON pdf.provider_id = aa.provider_id
    WHERE pdf.CUSTOMER_CATEGORY_KEY = 'insta_maids'
      AND updated >= '2024-01-01'
),

apc_CM AS (
    SELECT 
        p.city,
        p.provider_id,
        DATE(date) AS start_time_ist,
        COUNT(DISTINCT CASE WHEN status IN ('marked working') THEN START_HOUR_LOCAL END) AS DayCM
    FROM PROVIDER__DAILY__FACTS p
    LEFT JOIN PROVIDERXDATEXHOUR__CALENDAR_MARKING__HOURLY__FACTS cs 
        ON cs.provider_id = p.provider_id 
        AND status IN ('marked working') 
        AND date BETWEEN CURRENT_DATE() - 180 AND CURRENT_DATE() + 14 
        AND START_HOUR_LOCAL BETWEEN 8 AND 18
    WHERE p.CUSTOMER_CATEGORY_KEY = 'insta_maids'
    GROUP BY 1, 2, 3
),

pro_final AS (
    SELECT
        city,
        hub_tagged_base.provider_id,
        updated,
        DayCM,
        tagged_hub
    FROM apc_CM
    LEFT JOIN hub_tagged_base 
        ON apc_CM.provider_id = hub_tagged_base.provider_id 
        AND updated = apc_CM.start_time_ist
),

pp AS (
    SELECT
        pro_final.city,
        pro_final.provider_id,
        DATE_TRUNC('month', updated) AS month,
        COUNT(DISTINCT CASE WHEN tagged_hub IS NOT NULL AND DayCM >= 6 THEN updated END) AS hub_tagged_and_cm_days
    FROM pro_final
    LEFT JOIN PROVIDER__DAILY__FACTS pdf ON pdf.provider_id = pro_final.provider_id
    WHERE pro_final.provider_id IS NOT NULL
      AND approval_date IS NOT NULL
    GROUP BY 1, 2, 3
),

APC AS (
    SELECT
        city AS reporting_city,
        month,
        COUNT(DISTINCT CASE WHEN hub_tagged_and_cm_days >= 1 THEN provider_id END) AS apc
    FROM pp
    GROUP BY 1, 2
),

cm as (
    SELECT distinct 
        a.PROVIDER_ID,
        date,
        CITY,
        COUNT(CASE WHEN a.status IN ('marked working') THEN a.provider_id ELSE NULL END) AS marked_working,
        COUNT(CASE WHEN a.status IN ('marked leave') THEN a.provider_id ELSE NULL END) AS marked_leave
    FROM PUBLIC.providerXdateXhour__calendar_marking__hourly__facts a
    JOIN (
        SELECT DISTINCT PROVIDER_ID AS PRO_ID,CITY 
        FROM PROVIDER_MASTER
        WHERE customer_category_key in ('insta_maids')
          AND city not in ('Singapore', 'Mysore')
    ) B ON A.PROVIDER_ID=B.PRO_ID
    WHERE START_HOUR_LOCAL BETWEEN 8 AND 19
      AND date<=current_date
    GROUP BY 1,2,3
    HAVING marked_working>8
),

CM_F AS (
    SELECT DISTINCT PROVIDER_ID, DATE_TRUNC(MONTH,DATE) AS MONTH, CITY
    FROM CM
),

CAL_MARK_PROS AS (
    SELECT DISTINCT MONTH, CITY,
           COUNT(DISTINCT PROVIDER_ID) AS CAL_MARK_PROS
    FROM CM_F
    GROUP BY 1,2
),

final as (
    SELECT 
        apc.reporting_city,
        apc.month,
        COALESCE(apc.APC, 0) AS APC,
        LAG(COALESCE(apc.APC, 0), 1) OVER (PARTITION BY apc.reporting_city ORDER BY apc.month) AS apc_lag,
        COALESCE(approvals.approvals, 0) AS approvals,
        COALESCE(CMP.CAL_MARK_PROS, 0) AS CAL_MARK_PROS,
        COALESCE(approvals.approved_pro_not_delivering_same_month, 0) AS approved_pro_not_delivering_same_month,
        COALESCE(ch_gross.churned, 0) as churned,
        COALESCE(r.reactivations, 0) as reactivations,
        COALESCE(ch_net.churned, 0) as net_churn
    FROM APC apc
    LEFT JOIN approvals ON approvals.reporting_city = apc.reporting_city AND approvals.month = apc.month
    LEFT JOIN reactivation r ON r.reporting_city = apc.reporting_city AND r.month = apc.month
    LEFT JOIN churned_gross ch_gross ON ch_gross.reporting_city = apc.reporting_city AND ch_gross.month = apc.month
    LEFT JOIN churned_net ch_net ON ch_net.reporting_city = apc.reporting_city AND ch_net.month = apc.month
    LEFT JOIN CAL_MARK_PROS CMP ON cMP.city = apc.reporting_city AND cMP.month = apc.month
),

final_overall as (
    SELECT 
        'zOverall' as reporting_city,
        month,
        sum(APC) as APC,
        sum(apc_lag) as apc_lag,
        sum(approvals) as approvals,
        SUM(CAL_MARK_PROS) AS CAL_MARK_PROS,
        sum(approved_pro_not_delivering_same_month) as approved_pro_not_delivering_same_month,
        sum(churned) as churned,
        sum(reactivations) as reactivations,
        sum(net_churn) as net_churn
    FROM final
    GROUP BY 1,2
)

SELECT 
    reporting_city as "reporting_city::filter",
    month,
    APC,
    approvals,
    CAL_MARK_PROS,
    approved_pro_not_delivering_same_month,
    (reactivations+net_churn) as gross_churn,
    reactivations,
    net_churn,
    net_churn*100/nullif(apc,0) as net_churn_perc,
    churned*100/nullif(apc,0) as gross_churn_perc
FROM final
WHERE month>='2024-01-01'

UNION

SELECT
    reporting_city as "reporting_city::filter",
    month,
    APC,
    approvals,
    CAL_MARK_PROS,
    approved_pro_not_delivering_same_month,
    (reactivations+net_churn) as gross_churn,
    reactivations,
    net_churn,
    net_churn*100/nullif(apc,0) as net_churn_perc,
    churned*100/nullif(apc,0) as gross_churn_perc
FROM final_overall
WHERE month>='2024-01-01'

ORDER BY 1, 2 DESC
