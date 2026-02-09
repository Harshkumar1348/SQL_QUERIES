WITH base AS (
    SELECT DISTINCT
        lead_id,
        a.PROVIDER_ID,
        b.provider_name,
        DATE_TRUNC(week, DATE(b.approval_date)) AS approval_week,
        city,
        DATE_TRUNC(week, DATE(WALKED_IN)) AS wi_week,
        WALKED_IN AS walked_in,
        DATE_TRUNC(week, DATE(SCREENING_DATE)) AS sa_week,
        DATE_TRUNC(week, DATE(SCREENING_QUALIFIED)) AS sp_week,
        DATE_TRUNC(week, DATE(SCREENING_REJECTED)) AS sf_week,
        DATE_TRUNC(week, DATE(PARTIALLY_RECHARGED)) AS pr_week,
        DATE_TRUNC(week, DATE(SCHEDULED_FOR_TRAINING)) AS ts_week,
        DATE_TRUNC(week, DATE(SCHEDULING_TRIGGERED_FOR_TRAINING)) AS stt_week,
        DATE_TRUNC(week, DATE(IN_TRAINING)) AS it_week,
        DATE_TRUNC(week, DATE(TRAINING_PASSED)) AS tp_week
    FROM PUBLIC.LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
    LEFT JOIN provider__daily__facts b ON a.provider_id = b.provider_id
    WHERE a.customer_category_key = 'insta_maids'
      AND wi_week > '2025-07-01'
      AND walked_in IS NOT NULL
      AND city IS NOT NULL
),

screening AS (
    WITH S_provider_details AS (
        SELECT DISTINCT
            pmpr.provider_id AS pro_id,
            pm.provider_name AS pro_name,
            pmpr.created_at_ist AS sdate,
            pmpr.created_by,
            pmpr.evaluation AS "Result::multi-filter",
            pm.city AS "City::multi-filter",
            DATE_TRUNC('WEEK', pmpr.created_at_ist) AS "week::multi-filter"
        FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
        LEFT JOIN provider__daily__facts pm ON pmpr.provider_id = pm.provider_id
        WHERE pmpr.customer_category_key = 'insta_maids'
          AND pmpr.module_type = 'screening'
          AND pmpr.module_key IN (
              'instahelp_screening',
              'Objective criteria delhi',
              'Objective Criteria - Mumbai',
              'Objective criteria - Bangalore',
              'Objective Criteria Hyd',
              'Objective Criteria- Pune',
              'Objective Criteria-Chennai',
              'Objective Criteria KOL',
              'Objective Criteria - AMD'
          )
    ),

    s_fail_reason AS (
        SELECT
            provider_id,
            LISTAGG(statement, '; ') WITHIN GROUP (ORDER BY statement) AS fail_reason
        FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
        WHERE customer_category_key = 'insta_maids'
          AND module_type = 'screening'
          AND module_key IN (
              'instahelp_screening',
              'Objective criteria delhi',
              'Objective Criteria - Mumbai',
              'Objective criteria - Bangalore',
              'Objective Criteria Hyd',
              'Objective Criteria- Pune',
              'Objective Criteria-Chennai',
              'Objective Criteria KOL',
              'Objective Criteria - AMD'
          )
          AND (score < 0 OR answer = 'fail')
        GROUP BY provider_id
    ),

    prioritized AS (
        SELECT
            spd.pro_id AS partner_id,
            spd.pro_name,
            spd.sdate AS scr_date,
            spd."Result::multi-filter" AS s_result,
            spd."City::multi-filter",
            spd."week::multi-filter",
            sfr.fail_reason AS fail,
            ROW_NUMBER() OVER (PARTITION BY spd.pro_id ORDER BY spd.sdate DESC) AS bundle_num,
            CASE
                WHEN POSITION('What is partner''s age? (Check Aadhar for confirmation)' IN sfr.fail_reason) > 0 THEN 'Age'
                WHEN POSITION('Does the partner have her own smartphone? (Trainer to cross-question & confirm)' IN sfr.fail_reason) > 0 THEN 'Smartphone'
                WHEN POSITION('Is the partner's family aware and supportive of her decision to work? (Call partner''s family members to verify)' IN sfr.fail_reason) > 0 THEN 'family unawar/unsupportive of her decision to work'
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
        LEFT JOIN s_fail_reason sfr ON spd.pro_id = sfr.provider_id
    )

    SELECT * FROM prioritized
    QUALIFY bundle_num = 1
),

pre_screening AS (
    WITH ps_provider_details AS (
        SELECT DISTINCT
            pmpr.provider_id AS pro_id,
            pm.provider_name,
            pmpr.created_at_ist AS psdate,
            pmpr.created_by,
            pmpr.evaluation AS pre_screening_result,
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
            ppd.pro_id AS pro__id,
            ppd.psdate AS pdate,
            ppd.pre_screening_result AS ps_result,
            pfr.fail_reason AS fail,
            ROW_NUMBER() OVER (PARTITION BY ppd.pro_id ORDER BY ppd.psdate DESC) AS ps_bundle_num,
            pfr.fail_reason AS psfail,
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
    QUALIFY ps_bundle_num = 1
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
        DATEADD(day, 7, ldd_week) AS churn_week,
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
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
        AND start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id
),

-- =====================================================================
-- FIX 1: Cleaned do_d7 CTE
--   - Removed references to undefined aliases: n7d, dc, u
--   - These were causing SQL errors (n7d.N7D_status, dc.delivery_count,
--     u.last_14_days_util, u.last_7_days_util are not joined)
--   - If you need those columns, add the corresponding CTEs/tables
--     and LEFT JOINs back here
-- =====================================================================
do_d7 AS (
    SELECT
        m.*,
        m.ldd_week AS "ldd_week::filter",
        COALESCE(l7d.L7D_status, 'Unknown') AS L7D_status_resolved,

        -- churn_status: based on L7D working status and recency
        CASE
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working' THEN '3. Churn'
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working'     THEN '1. Active'
            WHEN m.ldd IS NULL AND DATE(m.app_date) >= CURRENT_DATE - 7 THEN '1. Active'
        END AS churn_status,

        -- churn_bucket: classifies churn by age (days since approval)
        CASE
            WHEN churn_status = '1. Active'                          THEN '1. Active'
            WHEN m.age = 0  AND churn_status = '3. Churn'            THEN '3. D0 churn'
            WHEN m.age <= 7  AND churn_status = '3. Churn'           THEN '4. D7 churn'
            WHEN m.age <= 17 AND churn_status = '3. Churn'           THEN '5. D15 churn'
            WHEN m.age <= 30 AND churn_status = '3. Churn'           THEN '6. D30 churn'
            WHEN m.age <= 60 AND churn_status = '3. Churn'           THEN '7. D60 churn'
            WHEN m.age <= 90 AND churn_status = '3. Churn'           THEN '8. D90 churn'
            WHEN m.age <= 120 AND churn_status = '3. Churn'          THEN '9. D120 churn'
            ELSE '10. >D120 churn'
        END AS churn_bucket,

        -- ELC / LLC classification
        CASE
            WHEN churn_status = '1. Active'                          THEN '1. Active'
            WHEN m.age <= 30 AND churn_status = '3. Churn'           THEN '3. ELC churn'
            ELSE '4. LLC churn'
        END AS ELC_LCC

    FROM main m
    LEFT JOIN l7d ON m.provider_id = l7d.provider_id
),

-- =====================================================================
-- FIX 2: NEW CTE — churn counts grouped by ldd_week and city
--   Aggregates d0_churn_count and d7_churn_count from do_d7
-- =====================================================================
churn_summary AS (
    SELECT
        ldd_week,
        LOWER(city) AS city,
        COUNT(DISTINCT CASE WHEN churn_bucket = '3. D0 churn' THEN provider_id END) AS d0_churn_count,
        COUNT(DISTINCT CASE WHEN churn_bucket = '4. D7 churn' THEN provider_id END) AS d7_churn_count
    FROM do_d7
    GROUP BY ldd_week, LOWER(city)
),

-- =====================================================================
-- FIX 3: NEW CTE — overall churn counts grouped by ldd_week only
--   Used by the "zOverall" UNION block
-- =====================================================================
churn_overall AS (
    SELECT
        ldd_week,
        COUNT(DISTINCT CASE WHEN churn_bucket = '3. D0 churn' THEN provider_id END) AS d0_churn_count,
        COUNT(DISTINCT CASE WHEN churn_bucket = '4. D7 churn' THEN provider_id END) AS d7_churn_count
    FROM do_d7
    GROUP BY ldd_week
),

final AS (
    SELECT
        b.city,
        provider_id,
        provider_name,
        wi_week,
        sa_week,
        sf_week,
        sp_week,
        ts_week,
        stt_week,
        it_week,
        tp_week,
        approval_week,
        pr_week,
        CASE
            WHEN sp_week IS NOT NULL THEN sp_week
            WHEN sf_week IS NOT NULL THEN sf_week
            ELSE sa_week
        END AS aligned_sa_week
    FROM base b
    LEFT JOIN pre_screening p ON b.provider_id = p.pro__id
    LEFT JOIN screening s ON b.provider_id = s.partner_id
),

weeks AS (
    SELECT DISTINCT week_val
    FROM (
        SELECT wi_week AS week_val FROM final
        UNION SELECT sa_week FROM final
        UNION SELECT sp_week FROM final
        UNION SELECT pr_week FROM final
        UNION SELECT stt_week FROM final
        UNION SELECT ts_week FROM final
        UNION SELECT it_week FROM final
        UNION SELECT tp_week FROM final
        UNION SELECT approval_week FROM final
        UNION SELECT aligned_sa_week FROM final
    )
    WHERE week_val IS NOT NULL
)

-- =====================================================================
-- FINAL SELECT — city-level with d0_churn_count & d7_churn_count
-- =====================================================================
SELECT
    LOWER(f.city) AS "city::filter",
    w.week_val AS week,

    COUNT(DISTINCT CASE WHEN f.wi_week IS NOT NULL AND f.wi_week = w.week_val THEN provider_id END) AS wi,
    COUNT(DISTINCT CASE
        WHEN f.sp_week = w.week_val
          OR f.sf_week = w.week_val
        THEN provider_id
    END) AS sa,
    COUNT(DISTINCT CASE WHEN f.sp_week = w.week_val THEN provider_id END) AS sp,
    COUNT(DISTINCT CASE WHEN f.pr_week = w.week_val THEN provider_id END) AS pr,
    COUNT(DISTINCT CASE WHEN f.it_week = w.week_val THEN provider_id END) AS it,
    COUNT(DISTINCT CASE WHEN f.it_week = w.week_val AND tp_week IS NOT NULL THEN provider_id END) AS tp,
    COUNT(DISTINCT CASE WHEN f.approval_week = w.week_val THEN provider_id END) AS app,

    -- FIX: d0_churn_count and d7_churn_count joined from churn_summary
    COALESCE(MAX(cs.d0_churn_count), 0) AS d0_churn_count,
    COALESCE(MAX(cs.d7_churn_count), 0) AS d7_churn_count,

    (app / NULLIF(wi, 0)) * 100 AS wi_app,
    (sp / NULLIF(sa, 0)) * 100 AS sa_sp,
    (tp / NULLIF(sp, 0)) * 100 AS sp_tp,
    (it / NULLIF(pr, 0)) * 100 AS pr_it,
    (tp / NULLIF(it, 0)) * 100 AS it_tp,
    (app / NULLIF(tp, 0)) * 100 AS tp_app

FROM weeks w
LEFT JOIN final f ON 1 = 1
-- FIX: Join churn_summary on matching week and city
LEFT JOIN churn_summary cs
    ON w.week_val = cs.ldd_week
    AND LOWER(f.city) = cs.city
GROUP BY 1, 2


UNION


-- =====================================================================
-- OVERALL SELECT — with d0_churn_count & d7_churn_count
-- =====================================================================
SELECT DISTINCT
    'zOverall' AS "city::filter",
    w.week_val,

    COUNT(DISTINCT CASE WHEN f.wi_week IS NOT NULL AND f.wi_week = w.week_val THEN provider_id END) AS wi,
    COUNT(DISTINCT CASE
        WHEN f.sp_week = w.week_val
          OR f.sf_week = w.week_val
        THEN provider_id
    END) AS sa,
    COUNT(DISTINCT CASE WHEN sp_week = w.week_val THEN provider_id END) AS sp,
    COUNT(DISTINCT CASE WHEN pr_week = w.week_val THEN provider_id END) AS pr,
    COUNT(DISTINCT CASE WHEN it_week = w.week_val THEN provider_id END) AS it,
    COUNT(DISTINCT CASE WHEN it_week = w.week_val AND tp_week IS NOT NULL THEN provider_id END) AS tp,
    COUNT(DISTINCT CASE WHEN approval_week = w.week_val THEN provider_id END) AS app,

    -- FIX: d0_churn_count and d7_churn_count joined from churn_overall
    COALESCE(MAX(co.d0_churn_count), 0) AS d0_churn_count,
    COALESCE(MAX(co.d7_churn_count), 0) AS d7_churn_count,

    (app / NULLIF(wi, 0)) * 100 AS wi_app,
    (sp / NULLIF(sa, 0)) * 100 AS sa_sp,
    (tp / NULLIF(sp, 0)) * 100 AS sp_tp,
    (it / NULLIF(pr, 0)) * 100 AS pr_it,
    (tp / NULLIF(it, 0)) * 100 AS it_tp,
    (app / NULLIF(tp, 0)) * 100 AS tp_app

FROM weeks w
LEFT JOIN final f ON 1 = 1
-- FIX: Join churn_overall on matching week (no city filter for overall)
LEFT JOIN churn_overall co
    ON w.week_val = co.ldd_week
GROUP BY 1, 2

ORDER BY week DESC, "city::filter"
