WITH tier_status AS (
    SELECT
        provider_id,
        city,
        app_month,
        cycle_no,
        potential_tier,
        tier_start_date,
        tier_end_date,
        CASE
            WHEN tier_end_date <= CURRENT_DATE THEN 1
            ELSE 0
        END AS completion_flag
    FROM tier_calc
),

pros AS (
    SELECT
        pm.provider_id,
        pm.provider_name,
        pm.approval_date AS app_date,
        pm.last_delivery_date
    FROM PUBLIC.PROVIDER_MASTER pm
    WHERE pm.customer_category_key = 'insta_maids'
      AND pm.country = 'India'
      AND pm.approval_date >= '2025-01-01'
),

latest_working_hub AS (
    SELECT
        provider_id,
        tagged_hub,
        city,
        updated_day,
        ROW_NUMBER() OVER (
            PARTITION BY provider_id
            ORDER BY updated_day DESC
        ) AS rn
    FROM (
        SELECT DISTINCT
            DATE(aa.updated_at) AS updated_day,
            aa.provider_id,
            sh.hub_name AS tagged_hub,
            pdf.city
        FROM PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS aa
        INNER JOIN PROVIDERXDATEXHOUR__CALENDAR_MARKING__HOURLY__FACTS mw
            ON aa.provider_id = mw.provider_id
           AND DATE(aa.updated_at) = DATE(mw.date)
           AND mw.status = 'marked working'
           AND mw.start_hour_local BETWEEN 8 AND 18
        LEFT JOIN PUBLIC.PROVIDER__DAILY__FACTS pdf
            ON pdf.provider_id = aa.provider_id
        LEFT JOIN PUBLIC.SMART_HUBS_VIEW sh
            ON sh.hub_id = aa.primary_hub_id
        WHERE pdf.customer_category_key = 'insta_maids'
          AND pdf.provider_name NOT ILIKE '%test%'
          AND sh.hub_name NOT ILIKE '%routines%'
          AND sh.hub_name IS NOT NULL
    ) x
),

psp_data_raw AS (
    SELECT
        ppp.referenceid AS _id,
        ppp.provider_id AS providerid,
        pm.provider_name,
        pm.city,
        pm.last_delivery_date,
        pm.approval_date AS app_date,
        TO_CHAR(DATE_TRUNC('month', pm.approval_date), 'YYYY-MM') AS app_month,
        ppp.tier_start_date AS start_date,
        ppp.tier_end_date AS end_date
    FROM provider_promise_plan__daily__metrics ppp
    LEFT JOIN public.provider_master pm
        ON ppp.provider_id = pm.provider_id
    WHERE pm.customer_category_key = 'insta_maids'
      AND pm.provider_name NOT ILIKE '%test%'
      AND ppp.provider_id IN (SELECT DISTINCT provider_id FROM pros)
),

ta AS (
    SELECT *
    FROM (
        SELECT
            ppp.tier_start_date AS start_date,
            ppp.tier_end_date,
            DATE_TRUNC('week', ppp.tier_end_date) AS tier_end_week,
            ppp.provider_id AS providerid,
            ppp.plan_status AS status,
            ppp.referenceid AS _id,
            ppp.tier,
            ppp.rating_error_at_tier,
            ppp.graded_leave_days_at_tier,
            ppp.paf_cancellation_at_tier,
            ppp.CM_ERROR_AT_TIER,
            CASE
                WHEN ppp.city IN ('city_gurgaon_v2', 'city_noida_v2')
                    THEN 'city_delhi_v2'
                ELSE ppp.city
            END AS city,
            ROW_NUMBER() OVER (
                PARTITION BY ppp.provider_id,
                             ppp.tier_start_date,
                             ppp.tier_end_date
                ORDER BY
                    CASE WHEN ppp.plan_status = 'completed' THEN 1 ELSE 2 END,
                    ppp.row_updated_at DESC
            ) AS rn
        FROM provider_promise_plan__daily__metrics ppp
        WHERE ppp.provider_id IN (
            SELECT DISTINCT providerid FROM psp_data_raw
        )
    ) x
    WHERE rn = 1
),

tm AS (
    SELECT
        ta.start_date,
        ta.tier_end_date,
        ta.tier_end_week,
        ta.providerid,
        ta.status,
        ta._id,
        ta.tier,
        ta.rating_error_at_tier         AS tm_rating_error,
        ta.graded_leave_days_at_tier    AS tm_leave_days,
        ta.paf_cancellation_at_tier     AS tm_paf_cancellation,
        ta.CM_ERROR_AT_TIER             AS tm_cm_error,
        ta.city,
        RANK() OVER (PARTITION BY ta.providerid ORDER BY ta.start_date ASC)  AS cycle_rank,
        RANK() OVER (PARTITION BY ta.providerid ORDER BY ta.start_date DESC) AS recent_cycle_rank
    FROM ta
    WHERE ta.tier IS NOT NULL
),

late_shows_by_tier AS (
    SELECT
        ppp.provider_id AS providerid,
        ppp.tier_start_date AS start_date,
        ppp.tier_end_date,
        MAX(
            CASE
                WHEN m.value:METRICNAME::STRING = 'currentTierLateShowErrors'
                THEN TRY_TO_NUMBER(m.value:metricvalue::STRING)
            END
        ) AS late_show_count,
        MAX(
            CASE
                WHEN ppp.actions ILIKE '%currentTierLateShowErrors%'
                     OR pm.approval_date >= '2026-01-26'
                THEN 1
                ELSE 0
            END
        ) AS late_show_metric_exists
    FROM provider_promise_plan__daily__metrics ppp
         LEFT JOIN provider_master pm
             ON pm.provider_id = ppp.provider_id,
         LATERAL FLATTEN(
             INPUT => ppp.PROVIDER_REFERENCE_METRICS_ARRAY__METADATA,
             OUTER => TRUE
         ) m
    WHERE ppp.provider_id IN (
        SELECT DISTINCT providerid FROM psp_data_raw
    )
    GROUP BY
        ppp.provider_id,
        ppp.tier_start_date,
        ppp.tier_end_date
),

l50_by_tier AS (
    SELECT
        providerid,
        start_date,
        tier_end_date,
        ROUND(AVG(rating), 2) AS l50_rating_before_tier_end
    FROM (
        SELECT
            tm.providerid,
            tm.start_date,
            tm.tier_end_date,
            rdf.rating,
            ROW_NUMBER() OVER (
                PARTITION BY tm.providerid, tm.start_date, tm.tier_end_date
                ORDER BY rdf.bdate DESC
            ) AS rn
        FROM tm
        LEFT JOIN request__daily__facts rdf
            ON rdf.provider_id = tm.providerid
           AND rdf.rating IS NOT NULL
           AND rdf.reporting_supercategory_new = 'Insta Help'
           AND rdf.bdate < tm.tier_end_date
    ) x
    WHERE rn <= 50
    GROUP BY providerid, start_date, tier_end_date
),

l30_by_tier AS (
    SELECT
        providerid,
        start_date,
        tier_end_date,
        ROUND(AVG(rating), 2) AS l30_rating_before_tier_end
    FROM (
        SELECT
            tm.providerid,
            tm.start_date,
            tm.tier_end_date,
            rdf.rating,
            ROW_NUMBER() OVER (
                PARTITION BY tm.providerid, tm.start_date, tm.tier_end_date
                ORDER BY rdf.bdate DESC
            ) AS rn
        FROM tm
        LEFT JOIN request__daily__facts rdf
            ON rdf.provider_id = tm.providerid
           AND rdf.rating IS NOT NULL
           AND rdf.reporting_supercategory_new = 'Insta Help'
           AND rdf.bdate < tm.tier_end_date
    ) x
    WHERE rn <= 30
    GROUP BY providerid, start_date, tier_end_date
),

cycle_paf_request AS (
    SELECT
        providerid,
        start_date,
        tier_end_date,
        COUNT(DISTINCT CASE
            WHEN ns_provider_at_fault_flag = 1
                 AND paf_reversed_by IS NULL
            THEN customer_request_id
        END) AS paf_request,
        COUNT(DISTINCT CASE
            WHEN NS_PAF_REVERSAL_FLAG = 1
            THEN customer_request_id
        END) AS paf_reversed,
        COUNT(DISTINCT CASE
            WHEN ns_provider_at_fault_flag = 1
                 OR NS_PAF_REVERSAL_FLAG = 1
            THEN customer_request_id
        END) AS paf_total
    FROM (
        SELECT
            tm.providerid,
            tm.start_date,
            tm.tier_end_date,
            r.customer_request_id,
            r.ns_provider_at_fault_flag,
            r.paf_reversed_by,
            r.NS_PAF_REVERSAL_FLAG
        FROM tm
        LEFT JOIN request__bce__hourly__facts r
            ON r.provider_id = tm.providerid
           AND DATE(r.bdate) >= tm.start_date
           AND DATE(r.bdate) <= tm.tier_end_date
           AND r.customer_category_key = 'insta_maids'
    ) x
    GROUP BY providerid, start_date, tier_end_date
),

paf_agg AS (
    SELECT
        tm.providerid,
        tm.start_date,
        tm.tier_end_date,
        COUNT(DISTINCT paf.customer_request_id) AS cancellations_in_tier
    FROM tm
    LEFT JOIN REQUEST__BCE__HOURLY__FACTS paf
        ON paf.provider_id = tm.providerid
       AND paf.CUSTOMER_CATEGORY_KEY = 'insta_maids'
       AND paf.NS_PROVIDER_AT_FAULT_FLAG = 1
       AND DATE(paf.cancelled_at) BETWEEN tm.start_date AND tm.tier_end_date
    GROUP BY tm.providerid, tm.start_date, tm.tier_end_date
),

flip_tier AS (
    SELECT
        tm.providerid,
        tm.start_date,
        tm.tier_end_date,
        COALESCE(ls.late_show_count, 0)        AS late_show_count,
        COALESCE(pa.cancellations_in_tier, 0)  AS cancellations_in_tier,
        tm.tm_leave_days,
        COALESCE(ls.late_show_metric_exists, 0) AS late_show_metric_exists,
        COALESCE(l50.l50_rating_before_tier_end, 0) AS l50_rating,
        CASE
            WHEN tm.tm_leave_days <= 1
             AND COALESCE(pa.cancellations_in_tier, 0) <= 1
             AND COALESCE(ls.late_show_count, 0) < 4
             AND COALESCE(l50.l50_rating_before_tier_end, 0) >= 4.7 THEN '1. Diamond'
            WHEN tm.tm_leave_days <= 2
             AND COALESCE(pa.cancellations_in_tier, 0) <= 1
             AND COALESCE(ls.late_show_count, 0) < 5
             AND COALESCE(l50.l50_rating_before_tier_end, 0) >= 4.6 THEN '2. Gold'
            WHEN tm.tm_leave_days <= 3
             AND COALESCE(pa.cancellations_in_tier, 0) <= 2
             AND COALESCE(ls.late_show_count, 0) < 6
             AND COALESCE(l50.l50_rating_before_tier_end, 0) >= 4.5 THEN '3. Silver'
            WHEN tm.tm_leave_days <= 4
             AND COALESCE(pa.cancellations_in_tier, 0) <= 3
             AND COALESCE(ls.late_show_count, 0) < 7
             AND COALESCE(l50.l50_rating_before_tier_end, 0) >= 4.4 THEN '4. Bronze'
            ELSE '5. PIP'
        END AS flipped_tier
    FROM tm
    LEFT JOIN late_shows_by_tier ls
        ON tm.providerid = ls.providerid
       AND tm.start_date = ls.start_date
       AND tm.tier_end_date = ls.tier_end_date
    LEFT JOIN paf_agg pa
        ON tm.providerid = pa.providerid
       AND tm.start_date = pa.start_date
       AND tm.tier_end_date = pa.tier_end_date
    LEFT JOIN l50_by_tier l50
        ON tm.providerid = l50.providerid
       AND tm.start_date = l50.start_date
       AND tm.tier_end_date = l50.tier_end_date
),

final_pip_metrics AS (
    SELECT
        ts.provider_id,
        ts.city,
        ts.app_month,
        l.L7D_status,

        /* Cycle 1 */
        MAX(CASE WHEN ts.cycle_no = 1 THEN ts.tier_start_date END) AS c1_tier_start_date,
        MAX(CASE WHEN ts.cycle_no = 1 THEN ts.tier_end_date   END) AS c1_tier_end_date,
        MAX(CASE WHEN ts.cycle_no = 1 THEN ts.completion_flag END) AS c1_completion_flag,
        MAX(CASE WHEN ts.cycle_no = 1 THEN ft.flipped_tier    END) AS c1_potential_tier,

        /* Cycle 2 */
        MAX(CASE WHEN ts.cycle_no = 2 THEN ts.tier_start_date END) AS c2_tier_start_date,
        MAX(CASE WHEN ts.cycle_no = 2 THEN ts.tier_end_date   END) AS c2_tier_end_date,
        MAX(CASE WHEN ts.cycle_no = 2 THEN ts.completion_flag END) AS c2_completion_flag,
        MAX(CASE WHEN ts.cycle_no = 2 THEN ft.flipped_tier    END) AS c2_potential_tier

    FROM tier_status ts
    LEFT JOIN l7d l
        ON ts.provider_id = l.provider_id
    LEFT JOIN flip_tier ft
        ON ts.provider_id = ft.providerid
       AND ts.tier_start_date = ft.start_date
       AND ts.tier_end_date   = ft.tier_end_date
    WHERE ts.cycle_no IN (1, 2)
    GROUP BY ts.provider_id, ts.city, ts.app_month, l.L7D_status
)

SELECT
    provider_id,
    city,
    c1_potential_tier,
    c1_tier_start_date,
    c1_tier_end_date,
    c1_completion_flag,
    c2_potential_tier,
    c2_tier_start_date,
    c2_tier_end_date,
    c2_completion_flag
FROM final_pip_metrics;
