-- Trainer-wise Training Passed & ELC Churn Report
-- Columns: raw_trainer, t_month, total_training_passed, elc_churn_count

WITH
base AS (
    SELECT DISTINCT
        lead_id,
        a.provider_id,
        b.provider_name,
        DATE(b.approval_date) AS approval_date,
        city,
        DATE_TRUNC('month', DATE(walked_in)) AS wi_month,
        walked_in AS wi_date,
        screening_date,
        screening_qualified,
        partially_recharged,
        scheduled_for_training,
        scheduling_triggered_for_training,
        in_training,
        training_passed,
        training_failed
    FROM public.lead__onboarding_funnel__daily__facts a
    LEFT JOIN provider__daily__facts b 
        ON a.provider_id = b.provider_id
    WHERE a.customer_category_key = 'insta_maids'
      AND walked_in IS NOT NULL
      AND DATE_TRUNC('month', DATE(walked_in)) > '2025-05-01'
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

-- Provider level data with trainer info and training status
post_training AS (
    SELECT
        s.raw_trainer,
        s.provider_id,
        DATE_TRUNC('month', s.updated_at_ist) AS t_month,
        b.training_passed  -- Keep as column, not aggregated yet
    FROM src s
    LEFT JOIN base b ON s.provider_id = b.provider_id
    WHERE DATE_TRUNC('month', s.updated_at_ist) >= '2025-05-01'
),

-- L7D status and age calculation
l7d AS (
    SELECT 
        pdf.provider_id,
        pdf.last_delivery_date,
        pdf.approval_date,
        CASE 
            WHEN SUM(CASE WHEN status = 'marked working' THEN 1 ELSE 0 END) > 8 THEN 'Working'
            ELSE 'Not Working'
        END AS L7D_status,
        CASE 
            WHEN pdf.last_delivery_date IS NULL THEN 0 
            ELSE DATEDIFF('day', DATE(pdf.approval_date), DATE(pdf.last_delivery_date))
        END AS age
    FROM provider__daily__facts pdf
    LEFT JOIN PUBLIC.providerXdateXhour__calendar_marking__hourly__facts acm
        ON pdf.provider_id = acm.provider_id
        AND DATE(acm.date) BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
        AND start_hour_local BETWEEN 8 AND 19
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
    GROUP BY pdf.provider_id, pdf.last_delivery_date, pdf.approval_date
),

-- Combine post_training with l7d to get ELC/LLC status
final_raw AS (
    SELECT 
        post.provider_id,
        post.raw_trainer,
        post.t_month,
        post.training_passed,
        CASE 
            WHEN COALESCE(l7.L7D_status, 'Unknown') = 'Working' THEN '1. Active'
            WHEN l7.last_delivery_date IS NULL AND l7.approval_date >= CURRENT_DATE - 7 THEN '1. Active'
            WHEN l7.age <= 30 THEN 'ELC churn'
            ELSE 'LLC churn' 
        END AS ELC_LLC
    FROM post_training post
    LEFT JOIN l7d l7 ON post.provider_id = l7.provider_id
)

-- Final aggregation: Trainer + Month level
SELECT 
    raw_trainer,
    t_month,
    COUNT(DISTINCT CASE WHEN training_passed IS NOT NULL THEN provider_id END) AS total_training_passed,
    COUNT(DISTINCT CASE WHEN ELC_LLC = 'ELC churn' THEN provider_id END) AS elc_churn_count
FROM final_raw
GROUP BY raw_trainer, t_month
ORDER BY raw_trainer, t_month DESC;
