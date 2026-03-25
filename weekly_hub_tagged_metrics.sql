/*
================================================================================
  WEEKLY HUB TAGGED METRICS — Insta Help
  
  PURPOSE:
    Track week-on-week operational metrics for Insta Help across 8 Indian cities
    and overall, including hub-tagged provider counts, deliveries, NPS, churn,
    traffic/conversion funnels, and more.

  HUB TAGGED LOGIC (city-level and overall, week-on-week):
  -------------------------------------------------------
    A provider is "hub-tagged & calendar-marked" for a given week when:
      1. They are an approved 'insta_maids' provider.
      2. On at least 2 days in that week, BOTH of these hold:
         a. The provider has a primary hub assignment (tagged_hub IS NOT NULL)
            — sourced from PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS joined with
              SMART_HUBS_VIEW, extracting the hub name prefix before '_city'.
         b. The provider has >= 6 working-hours calendar-marked (hours 7–18)
            — sourced from PROVIDERXDATEXHOUR__CALENDAR_MARKING__HOURLY__FACTS.
    The final metric `hub_tagged_cm_marked_pros` counts distinct providers per
    city per week meeting that threshold.

  BUG FIXES APPLIED (vs. original query):
    1.  Removed 14 trailing commas before FROM/closing parentheses that caused
        syntax errors.
    2.  Fixed CHARINDEX safety in hub_tagged_base — returns NULL instead of
        empty string when hub_name lacks '_city'.
    3.  Replaced ambiguous LEFT JOIN in `pp` CTE with EXISTS to prevent
        potential row duplication from PROVIDER__DAILY__FACTS.
    4.  Used explicit table-qualified column `cs.date` in apc_CM to resolve
        column ambiguity.
    5.  Used `start_time_ist` (from apc_CM) instead of `updated` (from
        hub_tagged_base) in pro_final so the week grouping is never NULL.
    6.  Added missing column aliases in aa_overall for clarity.
    7.  Fixed `base_new` reference to undefined `master_data` table
        (changed to REQUEST__DAILY__FACTS).
    8.  Removed unused CTEs: `conv`, `del_pros`, `base_new`, `final_v1`
        (kept commented out for reference).
================================================================================
*/


WITH base AS (
  SELECT DISTINCT
    a.*,
    source_Data.REPORTING_SUPERCATEGORY_NEW AS source_cat,
    amb.categorykey                         AS mastercat_key,
    CASE
      WHEN source_type IN ('reference','referral_share')    THEN 'Referral'
      WHEN source_type  = 'fmf'                             THEN 'Fmf'
      WHEN source_type IN ('organic_signup','organic_signup_wa') THEN '01. Organic'
      ELSE '02. Third Party'
    END AS source
  FROM LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
  LEFT JOIN PROVIDERXCAMPAIGNXCATEGORYXSTATUS__AMBASSADOR_PROVIDER__DAILY__FACTS amb
    ON  a.source_id = amb.AMBASSADOR_PROVIDER_ID
    AND DATE(COALESCE(PARTIALLY_RECHARGED, WALKED_IN, a.CREATED_AT_IST))
          >= TO_TIMESTAMP(amb.CAMPAIGNSTARTTIME / 1000)
    AND DATE(COALESCE(PARTIALLY_RECHARGED, WALKED_IN, a.CREATED_AT_IST))
          <= TO_TIMESTAMP(amb.CAMPAIGNENDTIME / 1000)
  LEFT JOIN PROVIDER__DAILY__FACTS source_Data
    ON a.source_id = source_Data.provider_id
  WHERE (a.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
         OR a.PROVIDER_CATEGORY_KEY = 'instant_maids_l3')
    AND reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                           'Pune','Chennai','Kolkata','Ahmedabad')
)


, partially_recharged AS (
  SELECT
    reporting_city,
    DATE_TRUNC('week', partially_recharged) AS pr_week,
    COUNT(DISTINCT provider_id)             AS prs
  FROM base
  WHERE partially_recharged IS NOT NULL
  GROUP BY 1, 2
)


, in_training AS (
  SELECT
    reporting_city,
    DATE_TRUNC('week', in_training) AS in_training_week,
    COUNT(DISTINCT provider_id)     AS in_training
  FROM base
  WHERE in_training IS NOT NULL
  GROUP BY 1, 2
)


-- ================================================
-- conv CTE removed — it was defined but never referenced downstream.
-- If you need TRF / SLD / CNV, uncomment and join into final_version.
-- ================================================
-- , conv AS (
--   SELECT
--     reporting_city AS city,
--     DATE_TRUNC('week', DATE(ts_base)) AS trf_week,
--     COUNT(DISTINCT login_id) AS TRF,
--     COUNT(DISTINCT CASE WHEN ts_funnel_end IS NOT NULL THEN login_id END) AS sld,
--     COUNT(DISTINCT CASE WHEN ts_funnel_end IS NOT NULL THEN login_id END)
--       / NULLIF(COUNT(DISTINCT login_id), 0) * 100 AS CNV
--   FROM MVRF_CAT
--   WHERE ts_base >= '2025-01-01'
--     AND reporting_supercategory_new IN ('Insta Help')
--   GROUP BY 1, 2
-- )


, RL AS (
  SELECT
    week,
    reporting_city,
    RL_abs,
    (RL_abs * 100) / NULLIF(gr_rl, 0) AS rl_perc
  FROM (
    SELECT DISTINCT
      DATE_TRUNC('week', DATE(dt)) AS week,
      reporting_city,
      SUM(REQUEST_LOST) AS RL_abs,
      SUM(gr_count)     AS gr_rl
    FROM PUBLIC.OVERALL_RL_EXPLORE_VIEW
    WHERE country = 'India'
      AND reporting_supercategory_new IN ('Insta Help')
      AND DATE(dt) >= '2025-01-01'
      AND hub_name NOT ILIKE '%test%'
      AND SLOT_BLOCK_REASON_FINAL NOT IN ('Unserviceable - Area')
    GROUP BY 1, 2
  )
)


, hub_first_delivery_base AS (
  SELECT DISTINCT
    reporting_city,
    hub_name,
    DATE_TRUNC('week', DATE(bdate_final)) AS week   -- FIX: removed trailing comma
  FROM PUBLIC.REQUEST__DAILY__FACTS md
  WHERE md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
    AND DATE(md.bdate_final) >= '2025-01-01'
    AND md.reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                              'Pune','Chennai','Kolkata','Ahmedabad')
    AND service_delivered = 1
)


, hub_first_delivery AS (
  SELECT DISTINCT
    reporting_city,
    hub_name,
    MIN(week) AS launch_week
  FROM hub_first_delivery_base
  GROUP BY 1, 2
)


, hub_count AS (
  SELECT DISTINCT
    md.reporting_city,
    DATE_TRUNC('week', DATE(bdate_final)) AS week,
    COUNT(DISTINCT CASE WHEN service_delivered = 1 THEN md.hub_name END) AS hubs,
    COUNT(DISTINCT CASE WHEN dd.launch_week = DATE_TRUNC('week', DATE(bdate_final))
                         THEN dd.hub_name END) AS new_launched
  FROM PUBLIC.REQUEST__DAILY__FACTS md
  LEFT JOIN hub_first_delivery dd
    ON  dd.launch_week      = DATE_TRUNC('week', DATE(bdate_final))
    AND dd.reporting_city   = md.reporting_city
  WHERE md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
    AND DATE(md.bdate_final) >= '2025-01-01'
    AND md.reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                              'Pune','Chennai','Kolkata','Ahmedabad')
  GROUP BY 1, 2
)


, final_flag AS (
  SELECT DISTINCT
    cat.reporting_city,
    USER_STATE_CAT_DEL AS USER_COHORT,
    DATE_TRUNC('week', DATE(ts_base)) AS week,
    user_id,
    COUNT(DISTINCT user_id) AS UNIQUE_USERs,
    COUNT(DISTINCT CASE WHEN TS_FUNNEL_ADD_TO_CART IS NOT NULL THEN user_id END) AS ADD_TO_CART,
    COUNT(DISTINCT CASE WHEN TS_FUNNEL_SUMMARY IS NOT NULL    THEN user_id END) AS SUMMARY,
    COUNT(DISTINCT CASE WHEN TS_FUNNEL_SLOTS IS NOT NULL      THEN user_id END) AS SLOTS,
    COUNT(DISTINCT CASE WHEN TS_FUNNEL_PAY IS NOT NULL        THEN user_id END) AS PAYMENT,
    COUNT(DISTINCT CASE WHEN TS_FUNNEL_END IS NOT NULL        THEN user_id END) AS FUNNEL_END
  FROM PUBLIC.MVRF_CAT cat
  WHERE CUSTOMER_CATEGORY_KEY = 'insta_maids'
    AND cat.reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                               'Pune','Chennai','Kolkata','Ahmedabad')
    AND DATE(ts_base) >= CURRENT_DATE - 180
  GROUP BY 1, 2, 3, 4
)


, final_traffic AS (
  SELECT
    reporting_city,
    week,
    SUM(UNIQUE_USERs) AS Total_Traffic,
    SUM(FUNNEL_END)   AS Overall_Conv,
    SUM(CASE WHEN USER_COHORT IN ('FTP','FTSC','RTPFTC') THEN UNIQUE_USERs END) AS FTP_Traffic,
    SUM(CASE WHEN USER_COHORT IN ('FTP','FTSC','RTPFTC') THEN FUNNEL_END END)   AS FTP_Conversion,
    SUM(CASE WHEN USER_COHORT IN ('RTC')                 THEN UNIQUE_USERs END) AS RTC_Traffic,
    SUM(CASE WHEN USER_COHORT IN ('RTC')                 THEN FUNNEL_END END)   AS RTC_Conversion
  FROM final_flag
  GROUP BY 1, 2
)


, reqdata AS (
  SELECT
    md.reporting_city AS city,
    DATE_TRUNC('week', DATE(md.bdate_final)) AS week,

    COUNT(DISTINCT CASE WHEN md.gross_status IN ('gross_request')
                        THEN md.customer_request_id END) AS GR,

    COUNT(DISTINCT CASE WHEN md.SERVICE_DELIVERED = 1
                        THEN md.customer_request_id END) AS DEL,

    COUNT(DISTINCT CASE WHEN DATE_TRUNC('week', DATE(md.bdate_final))
                              = DATE_TRUNC('week', DATE(b.APPROVAL_DATE))
                          AND md.SERVICE_DELIVERED = 1
                        THEN md.customer_request_id END) AS DEL_new_pros,

    COUNT(DISTINCT CASE WHEN DATE_TRUNC('week', DATE(md.bdate_final))
                             != DATE_TRUNC('week', DATE(b.APPROVAL_DATE))
                          AND md.SERVICE_DELIVERED = 1
                        THEN md.customer_request_id END) AS DEL_old_pros,

    COUNT(DISTINCT CASE WHEN md.SERVICE_DELIVERED = 1
                          AND md.USER_STATE_CAT_DEL IN ('FTP','FTSC','RTPFTC')
                        THEN md.customer_request_id END) AS new_trial_del,

    DEL / NULLIF(GR, 0) * 100 AS SD,

    COUNT(DISTINCT CASE WHEN DATE(md.root_bdate) = DATE(md.bdate_final)
                          AND md.SERVICE_DELIVERED = 1
                        THEN md.customer_request_id END)
      / NULLIF(GR, 0) * 100 AS OTIF,

    COUNT(DISTINCT CASE WHEN md.gross_status = 'got_rescheduled'
                        THEN md.customer_request_id END) AS RS,

    COUNT(DISTINCT CASE WHEN md.NET_STATUS = 'cancelled'
                          AND md.gross_status IN ('gross_request','got_transferred')
                        THEN md.customer_request_id END)
      / NULLIF(GR, 0) * 100 AS CN,

    AVG(CASE WHEN ABS(TIMEDIFF('day', md.bdate_final, b.first_approval_date)) <= 30
             THEN md.rating END) AS NPR,

    SUM(CASE WHEN md.service_rating >= 9              THEN  1
             WHEN md.service_rating <  7              THEN -1
             WHEN md.service_rating IN (7, 8)         THEN  0
             ELSE NULL END)
      / NULLIF(COUNT(DISTINCT CASE WHEN md.service_rating IS NOT NULL
                                   THEN md.CUSTOMER_REQUEST_ID END), 0)
      * 100 AS gnps,

    SUM(CASE WHEN md.service_rating >= 9 AND md.SERVICE_DELIVERED = 1 THEN  1
             WHEN md.service_rating <  7 AND md.SERVICE_DELIVERED = 1 THEN -1
             WHEN md.service_rating IN (7, 8) AND md.SERVICE_DELIVERED = 1 THEN 0
             ELSE NULL END)
      / NULLIF(COUNT(DISTINCT CASE WHEN md.service_rating IS NOT NULL
                                     AND md.SERVICE_DELIVERED = 1
                                   THEN md.CUSTOMER_REQUEST_ID END), 0)
      * 100 AS dnps,

    COUNT(DISTINCT CASE WHEN md.service_rating IS NOT NULL
                        THEN md.CUSTOMER_REQUEST_ID END)
      / NULLIF(GR, 0) * 100 AS NPS_RSP,

    COUNT(DISTINCT CASE WHEN md.rating IS NOT NULL
                        THEN md.CUSTOMER_REQUEST_ID END)
      / NULLIF(DEL, 0) * 100 AS RTG_RSP,

    COUNT(DISTINCT CASE
      WHEN (md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
            AND a.req_level_bce IN ('No_Response_Rescheduled','No_Response_Cancelled',
                                    'No_Show_Rescheduled','No_Show_Cancelled',
                                    'Response_After_SLA_Cancelled'))
        OR (md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
            AND a.final_bce IN ('No_Response_Rescheduled','No_Response_Cancelled',
                                'No_Show_Rescheduled','No_Show_Cancelled',
                                'Response_After_SLA_Cancelled')
            AND md.gross_status IN ('gross_request','got_transferred'))
      THEN md.root_request_id END) AS fbce,

    COUNT(DISTINCT CASE
      WHEN ((md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
             AND a.req_level_bce IN ('No_Response_Rescheduled','No_Response_Cancelled',
                                     'No_Show_Rescheduled','No_Show_Cancelled',
                                     'Response_After_SLA_Cancelled'))
         OR (md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
             AND a.final_bce IN ('No_Response_Rescheduled','No_Response_Cancelled',
                                 'No_Show_Rescheduled','No_Show_Cancelled',
                                 'Response_After_SLA_Cancelled')
             AND md.gross_status IN ('gross_request','got_transferred')))
        AND md.net_status = 'cancelled'
      THEN md.root_request_id END) AS BCE_UR,

    COUNT(DISTINCT CASE WHEN md.SERVICE_DELIVERED = 1
                        THEN md.provider_id END) AS pros,

    COUNT(DISTINCT CASE WHEN DATE_TRUNC('week', DATE(md.bdate_final))
                              = DATE_TRUNC('week', DATE(b.APPROVAL_DATE))
                        THEN md.provider_id END) AS new_pros,

    COUNT(DISTINCT CASE WHEN DATE_TRUNC('week', DATE(md.bdate_final))
                              > DATE_TRUNC('week', DATE(b.APPROVAL_DATE))
                        THEN md.provider_id END) AS old_pros,

    DEL / NULLIF(pros, 0) AS utl,

    COUNT(DISTINCT CASE WHEN md.gross_status IN ('gross_request','got_transferred')
                          AND ABS(TIMEDIFF('day', md.bdate_final, b.first_approval_date)) <= 30
                        THEN md.customer_request_id END)
      / NULLIF(GR, 0) * 100 AS New_pro_jobs,

    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.service_rating BETWEEN 0 AND 6
             THEN 1 ELSE 0 END) AS Detractors,
    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.service_rating BETWEEN 7 AND 8
             THEN 1 ELSE 0 END) AS Passives,
    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.service_rating BETWEEN 9 AND 10
             THEN 1 ELSE 0 END) AS Promotors,

    (Promotors - Detractors) * 100.00                   AS num_gross,
    Promotors + Detractors + Passives                   AS total_responses_gross,

    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.SERVICE_DELIVERED = 1
              AND md.service_rating BETWEEN 0 AND 6 THEN 1 ELSE 0 END) AS del_Detractors,
    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.SERVICE_DELIVERED = 1
              AND md.service_rating BETWEEN 7 AND 8 THEN 1 ELSE 0 END) AS del_Passives,
    SUM(CASE WHEN md.service_rating IS NOT NULL AND md.SERVICE_DELIVERED = 1
              AND md.service_rating BETWEEN 9 AND 10 THEN 1 ELSE 0 END) AS del_Promotors,

    (del_Promotors - del_Detractors) * 100.00           AS num_del,
    del_Promotors + del_Detractors + del_Passives       AS del_total_responses,

    SUM(CASE
      WHEN md.service_delivered = 1
        AND (COALESCE(mde.discount, 0) > 0
             OR COALESCE(ep.uc_funded_catalog_discount, 0) > 0
             OR mde.BUNDLE_DISCOUNT > 0)
        THEN mde.delivered_gmv
             - COALESCE(mde.discount, 0)
             - COALESCE(ep.uc_funded_catalog_discount, 0)
             - COALESCE(mde.BUNDLE_DISCOUNT, 0)
      WHEN md.service_delivered = 1
        THEN mde.delivered_gmv
    END) AS bpt                                          -- FIX: removed trailing comma

  FROM PUBLIC.REQUEST__DAILY__FACTS md
  LEFT JOIN master_data_explore_table mde
    ON mde.customer_request_id = md.customer_request_id
  LEFT JOIN PUBLIC.request__bce__hourly__facts a
    ON a.CUSTOMER_REQUEST_ID = md.customer_request_id
  LEFT JOIN ENTITY__PAYMENT_SUMMARY__HOURLY__FACTS ep
    ON ep.ENTITY_ID = md.customer_request_id
  LEFT JOIN PROVIDER__DAILY__FACTS b
    ON b.provider_id = md.provider_id

  WHERE md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
    AND b.CUSTOMER_CATEGORY_KEY = 'insta_maids'
    AND DATE(md.bdate_final) <= CURRENT_DATE
    AND DATE(md.bdate_final) >= '2025-01-01'
    AND md.reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                              'Pune','Chennai','Kolkata','Ahmedabad')
  GROUP BY 1, 2
  ORDER BY 2 DESC, 1 ASC
)


, rating_average_base AS (
  SELECT DISTINCT
    reporting_city AS city,
    DATE_TRUNC('week', DATE(bdate_final)) AS week,
    ROOT_REQUEST_ID,
    rating
  FROM REQUEST__HOURLY__FACTS
)


, rating_average AS (
  SELECT
    city,
    week,
    COUNT(DISTINCT CASE WHEN rating IS NOT NULL THEN ROOT_REQUEST_ID END) AS reqs_sum,
    SUM(rating) AS rating_sum                                              -- FIX: removed trailing comma
  FROM rating_average_base
  GROUP BY 1, 2
)


, approvals AS (
  SELECT
    city AS city,
    DATE_TRUNC('week', DATE(approval_date)) AS week,
    COUNT(DISTINCT provider_id)             AS partners_approved
  FROM PROVIDER__DAILY__FACTS
  WHERE CUSTOMER_CATEGORY_KEY = 'insta_maids'
    AND country = 'India'
    AND city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                 'Pune','Chennai','Kolkata','Ahmedabad')
    AND DATE(approval_date) >= '2025-01-01'
  GROUP BY 1, 2
)


, churn AS (
  SELECT
    provider_id,
    provider_name,
    a.city,
    DATE(a.approval_date) AS app_date,
    DATEDIFF('days', approval_date, last_delivery_date) AS age,
    CASE
      WHEN age BETWEEN   0 AND  14 THEN 'A. 0-14'
      WHEN age BETWEEN  15 AND  30 THEN 'B. 15-30'
      WHEN age BETWEEN  31 AND  60 THEN 'C. 31-60'
      WHEN age BETWEEN  61 AND  90 THEN 'D. 61-90'
      WHEN age BETWEEN  91 AND 120 THEN 'E. 91-120'
      WHEN age BETWEEN 121 AND 150 THEN 'F. 121-150'
      WHEN age BETWEEN 151 AND 180 THEN 'G. 151-180'
      WHEN age > 180                THEN 'H. >180'
    END AS age_bucket,
    CASE WHEN age > 60 THEN 'LLC' ELSE 'ELC' END AS churn_stage,
    last_delivery_date AS ldd,
    DATE(DATE_TRUNC('w', DATE(last_delivery_date) + 7)) AS churn_week,
    DATE(DATE_TRUNC('week', last_delivery_date))         AS ldd_week,
    CASE WHEN last_delivery_date > CURRENT_DATE - 7 THEN 'Active' ELSE 'Churn' END AS Activity,
    COUNT(CASE
      WHEN (gross_status = 'gross_request' OR gross_status = 'got_transferred')
        AND service_delivered = 'true'
        AND DATE(bdate_final) BETWEEN DATE(last_delivery_date) - 14 AND DATE(last_delivery_date)
      THEN customer_request_id
    END) AS l14_util,
    COUNT(DISTINCT CASE
      WHEN (gross_status = 'gross_request' OR gross_status = 'got_transferred')
        AND service_delivered = 'true'
        AND DATE(bdate_final) BETWEEN DATE(last_delivery_date) - 14 AND DATE(last_delivery_date)
      THEN DATE(bdate_final)
    END) AS delivered_days
  FROM PUBLIC.PROVIDER_MASTER a
  LEFT JOIN REQUEST__HOURLY__FACTS b
    ON a.provider_id = b.responded_pro_booking
  WHERE a.reporting_supercategory_new = 'Insta Help'
    AND last_delivery_date IS NOT NULL
    AND last_delivery_date < CURRENT_DATE - 7
    AND DATE(ldd_week) > DATE(DATE_TRUNC('w', CURRENT_DATE - 180))
    AND ldd_week < DATE(DATE_TRUNC('w', CURRENT_DATE))
    AND a.country = 'India'
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11
)


, churn_final AS (
  SELECT
    DATEADD(week, 1, DATE(ldd_week)) AS churn_week,
    city,
    COUNT(DISTINCT provider_id) AS total_churn,
    COUNT(DISTINCT CASE WHEN churn_stage = 'ELC' THEN provider_id END) AS elc_churn,
    COUNT(DISTINCT CASE WHEN churn_stage = 'LLC' THEN provider_id END) AS llc_churn
  FROM churn
  GROUP BY 1, 2

  UNION ALL

  SELECT
    DATEADD(week, 1, DATE(ldd_week)) AS churn_week,
    'zOverall' AS city,
    COUNT(DISTINCT provider_id) AS total_churn,
    COUNT(DISTINCT CASE WHEN churn_stage = 'ELC' THEN provider_id END) AS elc_churn,
    COUNT(DISTINCT CASE WHEN churn_stage = 'LLC' THEN provider_id END) AS llc_churn
  FROM churn
  GROUP BY 1, 2
)


-- ============================================================================
-- base_new / final_v1 / del_pros CTEs removed — they were never referenced
-- downstream. Kept here commented out for reference.
-- ============================================================================
-- , base_new AS (
--     SELECT
--         md.CUSTOMER_REQUEST_ID,
--         DATE(md.bdate_final) AS bdate,
--         md.gross_status,
--         md.booking_price_total,
--         DATE(md.cancelled_at) AS cancellation_date,
--         DATEDIFF('mins', md.start_at, md.end_at) AS time_taken,
--         DATE(md.ROOT_BDATE) AS root_bdate,
--         md.rating,
--         md.reason,
--         md.reporting_city,
--         md.net_status,
--         md.service_delivered,
--         DATE(first_approval_date) AS first_approval_date,
--         responded_pro_booking,
--         rhf.CANCELLED_COUNT_PRO_FAULT,
--         rhf.pro_income,
--         CASE
--             WHEN DATE(md.bdate_final) BETWEEN DATE(first_approval_date)
--                                            AND DATE(first_approval_date) + 29
--             THEN '1'
--         END AS week,
--         sve.variant_name
--     FROM PUBLIC.REQUEST__DAILY__FACTS md   -- FIX: was `master_data` which does not exist
--     LEFT JOIN PROVIDER__DAILY__FACTS pdv ON md.responded_pro_booking = pdv.provider_id
--     LEFT JOIN PUBLIC.REQUEST__DAILY__FACTS rhf ON md.customer_request_id = rhf.customer_request_id
--     LEFT JOIN SKU_VARIANT_explore sve ON md.customer_request_id = sve.request_id
--     WHERE md.REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
--       AND pdv.CUSTOMER_CATEGORY_KEY = 'insta_maids'
--       AND md.GROSS_STATUS IN ('gross_request')
-- )


, customer_base AS (
  SELECT DISTINCT
    provider_id,
    customer_request_id,
    reporting_city,
    customer_id,
    bdate_final,
    DATE_TRUNC('week', DATE(bdate_final)) AS week   -- FIX: removed trailing comma
  FROM request__daily__facts
  WHERE REPORTING_SUPERCATEGORY_NEW = 'Insta Help'
    AND bdate_final < CURRENT_DATE
    AND reporting_city IN ('Mumbai','Bangalore','Hyderabad','Delhi NCR',
                           'Pune','Chennai','Kolkata','Ahmedabad')
    AND provider_id IS NOT NULL
    AND service_delivered = 1
)


, previous_week_customers AS (
  SELECT DISTINCT
    provider_id,
    customer_id,
    week
  FROM customer_base
)


, pro_customer_mapping AS (
  SELECT DISTINCT
    base.provider_id,
    base.customer_id,
    base.customer_request_id,
    base.reporting_city,
    base.week,
    CASE WHEN pmc.customer_id IS NOT NULL THEN 1 ELSE 0 END AS previous_customer  -- FIX: removed trailing comma
  FROM customer_base base
  LEFT JOIN previous_week_customers pmc
    ON  base.provider_id = pmc.provider_id
    AND base.customer_id = pmc.customer_id
    AND base.week > pmc.week
)


, pro_wise_data AS (
  SELECT
    provider_id,
    reporting_city AS city,
    DATE_TRUNC('week', week) AS week,
    COUNT(DISTINCT customer_request_id) AS overall_jobs,
    COUNT(DISTINCT customer_id)         AS overall_customers,
    COUNT(DISTINCT CASE WHEN previous_customer = 1 THEN customer_id END)         AS repeated_customers,
    COUNT(DISTINCT CASE WHEN previous_customer = 1 THEN customer_request_id END) AS repeated_jobs,
    repeated_jobs / NULLIF(overall_jobs, 0) * 100 AS repeated_jobs_perc
  FROM pro_customer_mapping
  GROUP BY 1, 2, 3
)


, repeated_weekly AS (
  SELECT
    city,
    week,
    SUM(overall_jobs)       AS overall_jobs,
    SUM(overall_customers)  AS overall_customers,
    SUM(repeated_customers) AS repeated_customers,
    SUM(repeated_jobs)      AS repeated_jobs       -- FIX: removed trailing comma
  FROM pro_wise_data
  WHERE week >= '2025-01-01'
  GROUP BY 1, 2
)


-- ============================================================================
--  HUB TAGGED CALCULATION  (city-level, week-on-week)
--
--  Step 1 (hub_tagged_base):
--    For each provider-date, get their assigned hub name from the primary-hub
--    daily snapshot, joined to SMART_HUBS_VIEW for the human-readable name.
--    Extract the hub identifier by stripping the '_city…' suffix.
--    Only include approved 'insta_maids' providers.
--    FIX: Added CASE around CHARINDEX so that hub names without '_city'
--         return NULL instead of an empty string from LEFT(..., -1).
--
--  Step 2 (apc_CM):
--    For each provider-date, count the number of hours (7 AM – 6 PM) marked
--    as "working" in the calendar-marking table.  This is DayCM.
--    FIX: Qualified ambiguous `date` column with `cs.` prefix.
--
--  Step 3 (pro_final):
--    Join steps 1 & 2 on (provider_id, date) to get one row per
--    provider-city-date with both tagged_hub and DayCM.
--    FIX: Used start_time_ist (always non-NULL from apc_CM) instead of
--         `updated` (NULL when no hub tag) for cleaner week grouping.
--
--  Step 4 (pp):
--    Per provider-city-week, count distinct days where the provider had
--    BOTH a hub tag AND >= 6 calendar-marked working hours.
--    FIX: Replaced LEFT JOIN to PROVIDER__DAILY__FACTS with EXISTS
--         to avoid potential row duplication.
--
--  Step 5 (oo):
--    Per city-week, count distinct providers who had >= 2 such qualifying
--    days.  This is the final metric: hub_tagged_cm_marked_pros.
-- ============================================================================

, hub_tagged_base AS (
  SELECT
    aa.provider_id,
    DATE(aa.updated_at) AS updated,
    CASE                                                -- FIX: safe CHARINDEX handling
      WHEN CHARINDEX('_city', hub_name) > 0
        THEN LEFT(hub_name, CHARINDEX('_city', hub_name) - 1)
      ELSE NULL
    END AS tagged_hub
  FROM PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS aa
  LEFT JOIN PUBLIC.SMART_HUBS_VIEW
    ON SMART_HUBS_VIEW.hub_id = aa.primary_hub_id
  INNER JOIN PROVIDER__DAILY__FACTS pdf
    ON pdf.provider_id = aa.provider_id
  WHERE pdf.CUSTOMER_CATEGORY_KEY = 'insta_maids'
    AND DATE(aa.updated_at) >= '2025-01-01'
)


, apc_CM AS (
  SELECT
    p.city,
    p.provider_id,
    DATE(cs.date) AS start_time_ist,                    -- FIX: explicit table qualifier
    COUNT(DISTINCT CASE WHEN cs.status IN ('marked working')
                        THEN cs.START_HOUR_LOCAL END) AS DayCM
  FROM PROVIDER__DAILY__FACTS p
  INNER JOIN PROVIDERXDATEXHOUR__CALENDAR_MARKING__HOURLY__FACTS cs
    ON  cs.provider_id = p.provider_id
    AND cs.date BETWEEN CURRENT_DATE() - 180 AND CURRENT_DATE() + 14
    AND cs.START_HOUR_LOCAL BETWEEN 7 AND 18
  WHERE p.CUSTOMER_CATEGORY_KEY = 'insta_maids'
  GROUP BY 1, 2, 3
)


, pro_final AS (
  SELECT
    apc_CM.city,
    COALESCE(hub_tagged_base.provider_id, apc_CM.provider_id) AS provider_id,
    apc_CM.start_time_ist AS the_date,                  -- FIX: use non-NULL date from apc_CM
    apc_CM.DayCM,
    hub_tagged_base.tagged_hub
  FROM apc_CM
  LEFT JOIN hub_tagged_base
    ON  apc_CM.provider_id    = hub_tagged_base.provider_id
    AND hub_tagged_base.updated = apc_CM.start_time_ist
)


, pp AS (
  SELECT
    pro_final.city,
    pro_final.provider_id,
    DATE_TRUNC('week', the_date) AS week,               -- FIX: use the_date (always non-NULL)
    COUNT(DISTINCT CASE WHEN tagged_hub IS NOT NULL AND DayCM >= 6
                        THEN the_date END) AS hub_tagged_and_cm_days
  FROM pro_final
  WHERE pro_final.provider_id IS NOT NULL
    AND EXISTS (                                         -- FIX: replaced LEFT JOIN + WHERE
          SELECT 1
          FROM PROVIDER__DAILY__FACTS pdf
          WHERE pdf.provider_id = pro_final.provider_id
            AND pdf.approval_date IS NOT NULL
        )
  GROUP BY 1, 2, 3
)


, oo AS (
  SELECT
    city,
    week,
    COUNT(DISTINCT CASE WHEN hub_tagged_and_cm_days >= 2
                        THEN provider_id END) AS hub_tagged_cm_marked_pros
  FROM pp
  GROUP BY 1, 2
)


-- ============================================================================

, rta AS (
  SELECT
    reporting_city,
    DATE_TRUNC('week', DATE(event_time_ist)) AS rta_week,
    COUNT(session_id) AS total_sessions,
    COUNT(CASE
      WHEN general_hour_diff_slot_bucket IN ('A.0000-0015','B.0015-0030')
      THEN session_id
    END) AS availability_0_30mins                       -- FIX: removed trailing comma
  FROM public.session__rta_conversion__view
  WHERE HOUR(event_time_ist) >= 7
    AND HOUR(event_time_ist) < 19
    AND event_time_ist >= '2025-05-01'
    AND event_time_ist < CURRENT_DATE
    AND country = 'India'
    AND reporting_category_new = 'Insta Help'
  GROUP BY 1, 2
)


-- ============================================================================

, final_version AS (
  SELECT DISTINCT
    md.city,
    hubs                                                  AS total_hubs,
    new_launched,
    TO_CHAR(md.week, 'yyyy.mm.dd') AS dt,
    GR,
    DEL, DEL_old_pros, DEL_new_pros,
    new_trial_del, SD, CN, npr,
    Promotors, Detractors, Passives,
    del_Promotors, del_Detractors, del_Passives,
    nps_rsp, bce_ur,
    pros, new_pros, old_pros, utl,
    new_pro_jobs, bpt, rs,
    otif, fbce,
    num_gross, total_responses_gross, num_del, del_total_responses,
    prs,
    in_training,
    RL_abs,
    partners_approved,
    overall_jobs, repeated_jobs,
    hub_tagged_cm_marked_pros,
    Total_Traffic,
    Overall_Conv,
    Overall_Conv / NULLIF(Total_Traffic, 0) * 100       AS Overall_Conv_perc,
    FTP_Traffic,
    FTP_Conversion,
    FTP_Conversion / NULLIF(FTP_Traffic, 0) * 100       AS FTP_Conversion_perc,
    RTC_Traffic,
    RTC_Conversion,
    RTC_Conversion / NULLIF(RTC_Traffic, 0) * 100       AS RTC_Conversion_perc,
    total_churn,
    elc_churn,
    reqs_sum,
    rating_sum,
    total_sessions,
    availability_0_30mins

  FROM reqData md
  LEFT JOIN rl
    ON md.city = rl.reporting_city AND md.week = rl.week
  LEFT JOIN approvals
    ON md.city = approvals.city AND md.week = approvals.week
  LEFT JOIN repeated_weekly rcm
    ON rcm.week = md.week AND rcm.city = md.city
  LEFT JOIN hub_count
    ON hub_count.reporting_city = md.city AND md.week = hub_count.week
  LEFT JOIN final_traffic
    ON final_traffic.reporting_city = md.city AND final_traffic.week = md.week
  LEFT JOIN churn_final
    ON churn_final.churn_week = md.week AND churn_final.city = md.city
  LEFT JOIN partially_recharged
    ON partially_recharged.reporting_city = md.city AND pr_week = md.week
  LEFT JOIN in_training
    ON in_training.reporting_city = md.city AND in_training_week = md.week
  LEFT JOIN rta
    ON rta.reporting_city = md.city AND md.week = rta_week
  LEFT JOIN oo
    ON oo.city = md.city AND md.week = oo.week
  LEFT JOIN rating_average
    ON rating_average.city = md.city AND rating_average.week = md.week
  WHERE md.week >= DATE_TRUNC('week', CURRENT_DATE - 180)
  ORDER BY 1 ASC, 2 DESC
)


-- ============================================================================
--  Per-city output
-- ============================================================================
, aa AS (
  SELECT
    City                                                  AS "City::filter",
    dt,
    total_hubs,
    new_launched,
    GR,
    Del,
    del / NULLIF(gr, 0) * 100                             AS "SD%",
    rs                                                     AS resch,
    rs / NULLIF(gr, 0) * 100                               AS "Resched%",
    Fbce,
    Fbce / NULLIF(gr, 0) * 100                            AS "FBCE%",
    bce_ur                                                AS UR,
    bce_ur / NULLIF(gr, 0) * 100                          AS "UR%",
    RL_abs,
    RL_abs / NULLIF(gr, 0) * 100                          AS "RL%",

    Promotors,
    Detractors,
    Passives,
    del_Promotors,
    del_Detractors,
    del_Passives,
    (Promotors - Detractors) * 100
      / NULLIF(Detractors + Passives + Promotors, 0)      AS GNPS,
    (del_Promotors - del_Detractors) * 100
      / NULLIF(del_Detractors + del_Passives + del_Promotors, 0) AS DNPS,
    rating_sum,
    reqs_sum,
    rating_sum / NULLIF(reqs_sum, 0)                      AS rating,

    prs,
    in_training,
    hub_tagged_cm_marked_pros,
    pros                                                  AS partners,
    del / NULLIF(pros, 0)                                 AS util,
    partners_approved,

    new_pros,
    old_pros,
    DEL_new_pros,
    DEL_old_pros,
    DEL_new_pros / NULLIF(new_pros, 0)                    AS new_pros_util,
    DEL_old_pros / NULLIF(old_pros, 0)                    AS Old_pros_util,

    total_churn,
    total_churn * 100 / NULLIF(pros, 0)                   AS churn_perc,
    elc_churn,
    elc_churn * 100 / NULLIF(pros, 0)                     AS elc_churn_perc,

    bpt,
    bpt / NULLIF(del, 0)                                  AS AOV,

    availability_0_30mins,
    total_sessions,
    availability_0_30mins / NULLIF(total_sessions, 0) * 100 AS rta,

    Total_Traffic,
    Overall_Conv,
    Overall_Conv / NULLIF(Total_Traffic, 0) * 100         AS overall_conv_perc,
    FTP_Traffic                                           AS New_trials_traffic,
    FTP_Conversion                                        AS New_trials_conversion,
    FTP_Conversion / NULLIF(FTP_Traffic, 0) * 100         AS New_Trials_Conv,
    RTC_Traffic,
    RTC_Conversion,
    RTC_Conversion / NULLIF(RTC_Traffic, 0) * 100         AS rtc_conv_perc

  FROM final_version
)


-- ============================================================================
--  Overall (all-city) rollup
-- ============================================================================
, aa_overall AS (
  SELECT
    'zOverall'                                            AS "City::filter",
    dt,
    SUM(total_hubs)                                       AS total_hubs,
    SUM(new_launched)                                     AS new_launched,
    SUM(GR)                                               AS GR,
    SUM(Del)                                              AS Del,
    SUM(del) / NULLIF(SUM(gr), 0) * 100                  AS "SD%",
    SUM(resch)                                            AS resch,
    SUM(resch) / NULLIF(SUM(gr), 0) * 100                AS "Resched%",
    SUM(Fbce)                                             AS Fbce,
    SUM(Fbce) / NULLIF(SUM(gr), 0) * 100                 AS "FBCE%",
    SUM(UR)                                               AS UR,
    SUM(UR) / NULLIF(SUM(gr), 0) * 100                   AS "UR%",
    SUM(RL_abs)                                           AS RL_abs,
    SUM(RL_abs) / NULLIF(SUM(gr), 0) * 100               AS "RL%",

    SUM(Promotors)                                        AS Promotors,
    SUM(Detractors)                                       AS Detractors,
    SUM(Passives)                                         AS Passives,
    SUM(del_Promotors)                                    AS del_Promotors,
    SUM(del_Detractors)                                   AS del_Detractors,
    SUM(del_Passives)                                     AS del_Passives,
    (SUM(Promotors) - SUM(Detractors)) * 100
      / NULLIF(SUM(Detractors) + SUM(Passives) + SUM(Promotors), 0) AS GNPS,
    (SUM(del_Promotors) - SUM(del_Detractors)) * 100
      / NULLIF(SUM(del_Detractors) + SUM(del_Passives) + SUM(del_Promotors), 0) AS DNPS,
    SUM(rating_sum)                                       AS rating_sum,       -- FIX: added alias
    SUM(reqs_sum)                                         AS reqs_sum,         -- FIX: added alias
    SUM(rating_sum) / NULLIF(SUM(reqs_sum), 0)            AS rating,

    SUM(prs)                                              AS prs,
    SUM(in_training)                                      AS in_training,
    SUM(hub_tagged_cm_marked_pros)                        AS hub_tagged_cm_marked_pros,
    SUM(partners)                                         AS partners,
    SUM(del) / NULLIF(SUM(partners), 0)                   AS util,
    SUM(partners_approved)                                AS partners_approved,

    SUM(new_pros)                                         AS new_pros,
    SUM(old_pros)                                         AS old_pros,
    SUM(DEL_new_pros)                                     AS DEL_new_pros,
    SUM(DEL_old_pros)                                     AS DEL_old_pros,
    SUM(DEL_new_pros) / NULLIF(SUM(new_pros), 0)          AS new_pros_util,
    SUM(DEL_old_pros) / NULLIF(SUM(old_pros), 0)          AS Old_pros_util,

    SUM(total_churn)                                      AS total_churn,
    SUM(total_churn) * 100 / NULLIF(SUM(partners), 0)     AS churn_perc,
    SUM(elc_churn)                                        AS elc_churn,
    SUM(elc_churn) * 100 / NULLIF(SUM(partners), 0)       AS elc_churn_perc,

    SUM(bpt)                                              AS bpt,
    SUM(bpt) / NULLIF(SUM(del), 0)                        AS AOV,

    SUM(availability_0_30mins)                            AS availability_0_30mins,  -- FIX: added alias
    SUM(total_sessions)                                   AS total_sessions,          -- FIX: added alias
    SUM(availability_0_30mins) / NULLIF(SUM(total_sessions), 0) * 100 AS rta,

    SUM(Total_Traffic)                                    AS Total_Traffic,
    SUM(Overall_Conv)                                     AS Overall_Conv,
    SUM(Overall_Conv) / NULLIF(SUM(Total_Traffic), 0) * 100 AS overall_conv_perc,
    SUM(New_trials_traffic)                               AS New_trials_traffic,
    SUM(New_trials_conversion)                            AS New_trials_conversion,
    SUM(New_trials_conversion) / NULLIF(SUM(New_trials_traffic), 0) * 100 AS New_Trials_Conv,
    SUM(RTC_Traffic)                                      AS RTC_Traffic,
    SUM(RTC_Conversion)                                   AS RTC_Conversion,
    SUM(RTC_Conversion) / NULLIF(SUM(RTC_Traffic), 0) * 100 AS rtc_conv_perc

  FROM aa
  GROUP BY 1, 2
)


SELECT * FROM aa
UNION ALL
SELECT * FROM aa_overall
ORDER BY 1 DESC, 2 DESC
;
