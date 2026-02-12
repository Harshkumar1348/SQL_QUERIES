WITH date_spine AS (
    SELECT DISTINCT
        DATE_TRUNC('week', r.bdate_final) AS week_start
    FROM PUBLIC.REQUEST__HOURLY__FACTS r
    WHERE r.reporting_supercategory_new = 'Insta Help'
      AND r.bdate_final >= '2025-08-01'  
      AND r.country = 'India'
),

provider_ratings AS (
    -- Get provider-level ratings from requests within the week itself
    SELECT 
        DATE_TRUNC('week', r.bdate_final) AS week_start,
        r.reporting_city AS city,
        r.responded_pro_booking AS provider_id,
        AVG(r.rating) AS avg_provider_rating,
        COUNT(CASE WHEN r.rating IS NOT NULL THEN 1 END) AS rating_count
    FROM PUBLIC.REQUEST__HOURLY__FACTS r
    WHERE r.reporting_supercategory_new = 'Insta Help'
      AND r.country = 'India'
      AND r.responded_pro_booking IS NOT NULL
      AND r.service_delivered = 'true'
      AND r.bdate_final >= '2025-08-01'
    GROUP BY 1, 2, 3
),

l15d_metrics AS (
    SELECT 
        ds.week_start,
        r.reporting_city AS city,
        COUNT(CASE WHEN (r.gross_status = 'gross_request' OR r.gross_status = 'got_transferred') 
                   THEN r.customer_request_id END) AS GRs,
        COUNT(CASE WHEN ((r.gross_status = 'gross_request' OR r.gross_status = 'got_transferred') 
                         AND r.service_delivered = 'true') 
                   THEN r.customer_request_id END) AS SD,
        SUM(CASE 
            WHEN r.service_rating >= 9 THEN 1
            WHEN r.service_rating <= 6 THEN -1
            ELSE 0
        END) AS nps_score,
        COUNT(CASE WHEN r.service_rating IS NOT NULL THEN 1 END) AS nps_responses,
        SUM(CASE 
            WHEN r.service_rating >= 9 AND r.service_delivered = 'true' THEN 1
            WHEN r.service_rating <= 6 AND r.service_delivered = 'true' THEN -1
            ELSE 0
        END) AS d_nps_score,
        COUNT(CASE 
            WHEN r.service_rating IS NOT NULL AND r.service_delivered = 'true' THEN 1 
        END) AS d_nps_responses
    FROM date_spine ds
    CROSS JOIN PUBLIC.REQUEST__HOURLY__FACTS r
    WHERE r.reporting_supercategory_new = 'Insta Help'
      AND r.country = 'India'
      AND r.bdate_final >= DATEADD(day, -15, ds.week_start)
      AND r.bdate_final < ds.week_start
    GROUP BY 1, 2
),

cancellation_data AS (
    SELECT
        ds.week_start,
        rhf.reporting_city AS city,
        COUNT(DISTINCT rhf.customer_request_id) AS cancellation_count,
        COUNT(DISTINCT CASE 
            WHEN LOWER(COALESCE(rhf.reason, '')) IN (
                'pro_not_arrived_bot_resolution',
                'pro_refused_to_serve',
                'pro_asked_to_cancel',
                'noshow_pro_didnt_inform_sherlock_feedback',
                'pro_reschedule_due_to_illness',
                'pro_didnt_come_with_required_supplies',
                'pro_refused_to_delivery_distance_or_price',
                'pro_refused_to_delivery_behaviour',
                'pro_misconduct_sherlock_feedback',
                'auto_cancel_personal_reasons_reschedule_failed',
                'pro_reschedule_due_to_change_of_plans',
                'noshow_pro_informed_sherlock_feedback',
                'noshow_pro_lied_sherlock_feedback',
                'pro_denied_service_ops_feedback'
            ) THEN rhf.customer_request_id
            ELSE NULL
        END) AS cancellation_paf,
        COUNT(DISTINCT CASE 
            WHEN LOWER(COALESCE(rhf.reason, '')) NOT IN (
                'pro_not_arrived_bot_resolution',
                'pro_refused_to_serve',
                'pro_asked_to_cancel',
                'noshow_pro_didnt_inform_sherlock_feedback',
                'pro_reschedule_due_to_illness',
                'pro_didnt_come_with_required_supplies',
                'pro_refused_to_delivery_distance_or_price',
                'pro_refused_to_delivery_behaviour',
                'pro_misconduct_sherlock_feedback',
                'auto_cancel_personal_reasons_reschedule_failed',
                'pro_reschedule_due_to_change_of_plans',
                'noshow_pro_informed_sherlock_feedback',
                'noshow_pro_lied_sherlock_feedback',
                'pro_denied_service_ops_feedback'
            ) THEN rhf.customer_request_id
            ELSE NULL
        END) AS cancellation_caf
    FROM date_spine ds
    CROSS JOIN PUBLIC.REQUEST__HOURLY__FACTS rhf
    WHERE rhf.reporting_supercategory_new = 'Insta Help'
      AND rhf.country = 'India'
      AND rhf.net_status = 'cancelled'
      AND rhf.bdate_final >= DATEADD(day, -15, ds.week_start)
      AND rhf.bdate_final < ds.week_start
    GROUP BY 1, 2
),

provider_summary AS (
    SELECT
        week_start,
        city,
        COUNT(DISTINCT provider_id) AS total_providers,
        SUM(avg_provider_rating * rating_count)
          / NULLIF(SUM(rating_count), 0) AS overall_avg_rating,
        COUNT(DISTINCT CASE 
            WHEN avg_provider_rating < 4.5 THEN provider_id 
        END) AS providers_below_4_5,
        COUNT(DISTINCT CASE 
            WHEN avg_provider_rating > 4.7 THEN provider_id 
        END) AS providers_above_4_7
    FROM provider_ratings
    GROUP BY 1, 2
)

SELECT
    INITCAP(l.city) AS "city::filter",
    DATE(l.week_start) AS week,
    ROUND((l.nps_score * 100.0) / NULLIF(l.nps_responses, 0), 2) AS l15d_gnps,
    ROUND((l.d_nps_score * 100.0) / NULLIF(l.d_nps_responses, 0), 2) AS l15d_dnps,
    ROUND((l.SD * 100.0) / NULLIF(l.GRs, 0), 1) AS l15d_sd_pct,
    ROUND(p.overall_avg_rating, 2) AS avg_provider_rating,
    ROUND((p.providers_below_4_5 * 100.0) / NULLIF(p.total_providers, 0), 1) AS pct_below_4_5,
    ROUND((p.providers_above_4_7 * 100.0) / NULLIF(p.total_providers, 0), 1) AS pct_above_4_7,
    ROUND((COALESCE(cd.cancellation_paf, 0) * 100.0) / NULLIF(l.GRs, 0), 2) AS "PAF %",
    p.total_providers,
    l.GRs,
    l.SD
FROM l15d_metrics l
LEFT JOIN provider_summary p 
    ON l.week_start = p.week_start
    AND l.city = p.city
LEFT JOIN cancellation_data cd 
    ON l.week_start = cd.week_start
    AND l.city = cd.city

UNION ALL

SELECT
    'ZOverall' AS "city::filter",
    DATE(l.week_start) AS week,
    ROUND((SUM(l.nps_score) * 100.0) / NULLIF(SUM(l.nps_responses), 0), 2) AS l15d_gnps,
    ROUND((SUM(l.d_nps_score) * 100.0) / NULLIF(SUM(l.d_nps_responses), 0), 2) AS l15d_dnps,
    ROUND((SUM(l.SD) * 100.0) / NULLIF(SUM(l.GRs), 0), 1) AS l15d_sd_pct,
    ROUND(
        SUM(p.overall_avg_rating * p.total_providers) / NULLIF(SUM(p.total_providers), 0), 2
    ) AS avg_provider_rating,
    ROUND((SUM(p.providers_below_4_5) * 100.0) / NULLIF(SUM(p.total_providers), 0), 1) AS pct_below_4_5,
    ROUND((SUM(p.providers_above_4_7) * 100.0) / NULLIF(SUM(p.total_providers), 0), 1) AS pct_above_4_7,
    ROUND((SUM(COALESCE(cd.cancellation_paf, 0)) * 100.0) / NULLIF(SUM(l.GRs), 0), 2) AS "PAF %",
    SUM(p.total_providers) AS total_providers,
    SUM(l.GRs) AS GRs,
    SUM(l.SD) AS SD
FROM l15d_metrics l
LEFT JOIN provider_summary p 
    ON l.week_start = p.week_start
    AND l.city = p.city
LEFT JOIN cancellation_data cd 
    ON l.week_start = cd.week_start
    AND l.city = cd.city
GROUP BY 2

ORDER BY week DESC
