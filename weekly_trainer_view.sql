WITH view1 AS (
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
            DATE_TRUNC('week', DATE(b.updated_at_ist)) AS tweek,
            COUNT(DISTINCT s.provider_id) AS total_partner,
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
            s.raw_trainer,
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
        GROUP BY ts.app_week, s.raw_trainer
    )

    SELECT
        COALESCE(pt.created_by, post.raw_trainer) AS trainer,
        COALESCE(pt.sdate, post.tweek) AS week,
        post.total_partner,
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
        ) AS score
    FROM pre_training pt
    FULL OUTER JOIN post_training post
        ON pt.created_by = post.raw_trainer
       AND pt.sdate = post.tweek
    LEFT JOIN final_pip_metrics pip
        ON pt.created_by = pip.raw_trainer
       AND pt.sdate = pip.app_week
    WHERE pt.created_by IS NOT NULL
),

view2 AS (
    WITH base AS (
        SELECT DISTINCT
            pdf.provider_id,
            provider_name,
            city,
            avg_rating,
            DATE(approval_date) AS app_date,
            DATE_TRUNC('week', DATE(approval_date)) AS approval_week,
            CASE
                WHEN last_delivery_date > CURRENT_DATE - 7 THEN 'Active'
                WHEN last_delivery_date IS NULL AND DATE(approval_date) > CURRENT_DATE - 7 THEN 'Active'
                ELSE 'Churned'
            END AS active_status,
            SUM(CASE WHEN acm.date BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + 7 THEN marked_working END) AS working_hrs,
            CASE
                WHEN SUM(CASE WHEN acm.date BETWEEN CURRENT_DATE + 1 AND CURRENT_DATE + 7 THEN marked_working END) > 5
                    THEN 'Working'
                ELSE 'Not Working'
            END AS n7d_status
        FROM provider__daily__facts pdf
        LEFT JOIN (
            SELECT DISTINCT
                provider_id,
                date,
                COUNT(CASE WHEN status IN ('unmarked', 'marked leave', 'marked working') THEN provider_id ELSE NULL END) AS total_hours,
                COUNT(CASE WHEN status IN ('marked working') THEN provider_id ELSE NULL END) AS marked_working
            FROM public.providerXdateXhour__calendar_marking__hourly__facts
            WHERE DATE(date) BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
              AND start_hour_local BETWEEN 8 AND 19
            GROUP BY 1, 2
        ) acm ON acm.provider_id = pdf.provider_id
        WHERE customer_category_key = 'insta_maids'
          AND approval_date >= '2025-01-01'
          AND country = 'India'
        GROUP BY ALL
    ),

    cm AS (
        SELECT DISTINCT
            a.provider_id,
            DATE_TRUNC('week', DATE(a.date)) AS cm_week,
            date,
            DAYOFWEEK(date) AS week_day,
            COUNT(CASE WHEN status IN ('marked working') THEN a.provider_id ELSE NULL END) AS marked_working,
            COUNT(CASE WHEN status IN ('marked leave') THEN a.provider_id ELSE NULL END) AS marked_leave
        FROM public.providerXdateXhour__calendar_marking__hourly__facts a
        JOIN base b ON b.provider_id = a.provider_id
        WHERE a.provider_id IN (SELECT DISTINCT provider_id FROM base)
          AND start_hour_local BETWEEN 8 AND 19
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

    rating_raw AS (
        SELECT DISTINCT
            responded_pro_booking AS provider_id,
            rating,
            DATE(rating_date) + 3 AS ratings_date,
            DATE_TRUNC('week', DATE(rating_date) + 3) AS rating_week,
            customer_request_id,
            RANK() OVER (PARTITION BY responded_pro_booking ORDER BY DATE(rating_date) + 3) AS rnk
        FROM public.request__hourly__facts
        WHERE customer_category_key = 'insta_maids'
          AND responded_pro_booking IN (SELECT DISTINCT provider_id FROM base)
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
            LISTAGG(DISTINCT customer_request_id, ', ') WITHIN GROUP (ORDER BY customer_request_id ASC) AS request_ids
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
            DATE_TRUNC('week', DATE(paf.cancelled_at)) AS paf_week,
            LISTAGG(DISTINCT paf.customer_request_id, ', ') WITHIN GROUP (ORDER BY paf.customer_request_id ASC) AS paf_request_ids
        FROM request__bce__hourly__facts paf
        JOIN request__hourly__facts rhf ON rhf.customer_request_id = paf.customer_request_id
        WHERE paf.customer_category_key = 'insta_maids'
          AND fault = 'PRO'
          AND paf.ns_provider_at_fault_flag = 1
          AND responded_pro_booking IN (SELECT DISTINCT provider_id FROM base)
        GROUP BY 1, 2
    ),

    paf_raw AS (
        SELECT
            responded_pro_booking AS provider_id,
            DATE_TRUNC('week', DATE(paf.cancelled_at)) AS paf_week,
            COUNT(DISTINCT CASE WHEN paf.ns_provider_at_fault_flag = 1 THEN paf.customer_request_id END) AS paf_count
        FROM request__bce__hourly__facts paf
        JOIN request__hourly__facts rhf ON rhf.customer_request_id = paf.customer_request_id
        WHERE paf.customer_category_key = 'insta_maids'
          AND responded_pro_booking IN (SELECT DISTINCT provider_id FROM base)
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
            CASE WHEN active_status = 'Churned' AND n7d_status = 'Not Working' THEN 'churn' ELSE 'active' END AS churn_status,
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
            RANK() OVER (PARTITION BY provider_id ORDER BY cm_week) AS week_num,
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
                DATE_TRUNC('week', DATE(bdate_final)) AS week,
                COUNT(DISTINCT CASE WHEN gross_status = 'gross_request' THEN customer_request_id END) AS gr,
                COUNT(DISTINCT CASE WHEN net_status = 'net_request' AND service_delivered = 'true' THEN customer_request_id END) AS sd
            FROM master_data
            WHERE customer_category_key = 'insta_maids'
              AND responded_pro_booking IN (SELECT DISTINCT provider_id FROM base)
            GROUP BY 1, 2
        ) u ON u.responded_pro_booking = a.provider_id AND u.week = a.cm_week
        ORDER BY provider_id, cm_week
    ),

    trainer_mapping AS (
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
            CASE WHEN total_graded_leaves IS NULL THEN 0 ELSE total_graded_leaves END AS total_graded_leaves
        FROM final f
        LEFT JOIN (SELECT * FROM trainer_mapping WHERE trainer_name IS NOT NULL) tm
            ON f.provider_id = tm.provider_id
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
                WHEN COALESCE(bad_rated_jobs, 0) = 0
                  AND COALESCE(total_graded_leaves, 0) = 0
                  AND COALESCE(paf_count, 0) = 0 THEN 'No Error'
            END AS week_perf,
            request_ids AS bad_rated_request_ids,
            paf_request_ids
        FROM lst
    )

    SELECT
        trainer_name,
        perf_week,
        SUM(total_deliveries) AS util,
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END) AS hh_eligible,
        COUNT(DISTINCT CASE
            WHEN life_cycle = 'ELC' AND churn_status = 'churn' THEN provider_id
        END) AS churn_pros,
        SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rating END)
        / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN f10_sum_weekly_rated_jobs END), 0)
        AS f10_rating,
        COUNT(DISTINCT CASE WHEN life_cycle = 'LLC' THEN provider_id END) AS total_old,
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'No Error' THEN provider_id END) AS no_error,
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Good' THEN provider_id END) AS good,
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Average' THEN provider_id END) AS average,
        COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END) AS bad,
        (
            COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END)
          + COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Average' THEN provider_id END)
        ) * 100.0
        / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
        AS bad_average_perc,
        100
        - (
            COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' AND week_perf = 'Bad' THEN provider_id END)
            * 100.0
            / NULLIF(COUNT(DISTINCT CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
        )
        AS ideal_partner_perc,
        SUM(CASE WHEN life_cycle = 'ELC' THEN paf_count END) * 100.0
        / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_requests END), 0)
        AS paf_perc,
        SUM(CASE WHEN life_cycle = 'ELC' THEN total_graded_leaves END)
        / NULLIF(COUNT(CASE WHEN life_cycle = 'ELC' THEN provider_id END), 0)
        AS leaves_per_pro,
        SUM(CASE WHEN life_cycle = 'ELC' THEN total_rating_sum END)
        / NULLIF(SUM(CASE WHEN life_cycle = 'ELC' THEN total_rated_jobs END), 0)
        AS hh_pros_avg_rating
    FROM cumulative
    GROUP BY trainer_name, perf_week
    ORDER BY trainer_name, perf_week
),

final AS (
    SELECT DISTINCT
        COALESCE(v.trainer, v1.trainer_name) AS trainer,
        COALESCE(v.week, v1.perf_week) AS week,
        v1.hh_eligible,
        v.sp_pct,
        v.sp_tp_pct,
        v.tp_pct,
        v.elc_pip_pct,
        v1.hh_pros_avg_rating,
        ROUND(
            (0.1  * COALESCE(v.sp_pct, 0)) +
            (0.15 * COALESCE(v.sp_tp_pct, 0)) +
            (0.15 * COALESCE(v.tp_pct, 0)) +
            COALESCE((0.6  * (100 - v.elc_pip_pct)), 0),
            2
        ) AS score
    FROM view1 v
    FULL OUTER JOIN view2 v1
        ON v.trainer = v1.trainer_name
       AND v.week = v1.perf_week
),

POCO AS (
    SELECT
        provider_id,
        created_by,
        created_at_ist,
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

tm_age AS (
    SELECT
        created_by,
        MIN(DATE(created_at_ist)) AS first_screening,
        DATEDIFF('day', first_screening, CURRENT_DATE()) AS tmm,
        CASE WHEN tmm > 60 THEN 'LLC Trainer' ELSE 'ELC Trainer' END AS age_tm
    FROM POCO
    GROUP BY 1
),

trainer_week AS (
    SELECT
        a.trainer,
        DATE(a.week) AS week,
        a.hh_eligible,
        a.sp_pct,
        a.sp_tp_pct,
        a.tp_pct,
        a.elc_pip_pct,
        a.hh_pros_avg_rating,
        a.score,
        t.age_tm
    FROM final a
    LEFT JOIN tm_age t ON a.trainer = t.created_by
    WHERE a.hh_eligible > 20
),

weekly_summary AS (
    SELECT
        week,
        COUNT(DISTINCT trainer) AS total_trainers_elc_week,
        COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END) AS trainers_score_gt_75,
        COUNT(DISTINCT CASE WHEN elc_pip_pct < 20 THEN trainer END) AS trainers_elc_pip_pct_lt_20,
        COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END) AS trainers_lt_60d
    FROM trainer_week
    GROUP BY week
)

SELECT
    week,
    total_trainers_elc_week,
    trainers_score_gt_75,
    trainers_elc_pip_pct_lt_20,
    trainers_lt_60d
FROM weekly_summary
ORDER BY week DESC;
