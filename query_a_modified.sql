WITH base AS (
SELECT DISTINCT
lead_id,
a.provider_id,
b.provider_name,
DATE(b.approval_date) AS approval_date,
city,
DATE_TRUNC('month', DATE(walked_in)) AS wi_month,
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
AND DATE_TRUNC('month', DATE(walked_in)) > '2025-05-01'
),

blocked_verification_failed_15d AS (
    SELECT DISTINCT
    b.provider_id
    FROM base b
    JOIN PROVIDERXDATE__ACTIVE_PROFILE__HOURLY__FACTS ap
    ON ap.provider_id = b.provider_id
    AND ap.customer_category_key = 'insta_maids'
    AND LOWER(TRIM(ap.reason)) = 'verification failed'
    AND LOWER(TRIM(TO_VARCHAR(ap.temporary_block))) = 'true'
    AND ap.temp_block_since_date::TIMESTAMP_NTZ >= b.approval_date::TIMESTAMP_NTZ
    AND ap.temp_block_since_date::TIMESTAMP_NTZ <  DATEADD(day, 31, b.approval_date::TIMESTAMP_NTZ)
),

training_centre AS (
    SELECT 
        provider_id, 
        CASE 
            WHEN module_key = 'Objective criteria - Bangalore' THEN
                CASE 
                    WHEN answer = 'QQ1' THEN 'Krimson'
                    WHEN answer = 'QQ2' THEN 'Marathalli'
                    WHEN answer = 'QQ3' THEN 'HRBR layout'
                END
            WHEN module_key = 'Objective Criteria - Mumbai' THEN
                CASE
                    WHEN answer = 'QQ1' THEN 'Goregaon old center'
                    WHEN answer = 'QQ2' THEN 'Vikroli Training Center'
                    WHEN answer = 'QQ3' THEN 'Thane Training Center'
                END
            WHEN module_key = 'Objective criteria delhi' THEN
                CASE
                    WHEN answer = 'QQ1' THEN 'Badshahpur'
                    WHEN answer = 'QQ2' THEN 'Noida'
                    WHEN answer = 'QQ3' THEN 'Gaur City'
                    WHEN answer = 'QQ4' THEN 'Gurgaon 121'
                    WHEN answer = 'QQ5' THEN 'Chattarpur'
                END
            WHEN module_key = 'Objective Criteria Hyd' THEN
                CASE
                    WHEN answer = 'QQ1' THEN 'Kondapur'
                    WHEN answer = 'QQ2' THEN 'Manikonda'
                    WHEN answer = 'QQ3' THEN 'Madhapur'
                    WHEN answer = 'QQ4' THEN 'Kukatpally'
                END
            WHEN module_key = 'Objective Criteria- Pune' THEN 
                CASE WHEN answer = 'QQ1' THEN 'Baner Training Center' END 
        END AS training_center
    FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
    WHERE statement ILIKE '%Pro''s screening center ?%'
       OR statement ILIKE '%What is partners screening center?%'
       OR statement ILIKE '%What is partners screening center ?%'
),

p_source_name AS (
    WITH base AS (
        SELECT DISTINCT
            provider_id,
            provider_name,
            city,
            avg_rating,
            DATE(approval_date) AS app_date
        FROM provider__daily__facts 
        WHERE customer_category_key = 'insta_maids'
          AND country = 'India'
    )
    SELECT DISTINCT
        a.source_id AS source_id,
        pm.provider_name AS source_name,
        a.provider_id AS provider_id
    FROM LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
    JOIN base b ON b.provider_id = a.provider_id
    LEFT JOIN PUBLIC.PROVIDER_MASTER pm ON pm.provider_id = a.source_id
    WHERE a.reporting_supercategory_new = 'Insta Help'
),

p_source AS (
    WITH base1 AS (
        SELECT DISTINCT
            a.*,
            source_Data.REPORTING_SUPERCATEGORY_NEW AS source_cat,
            amb.categorykey AS mastercat_key,
            CASE 
                WHEN source_type IN ('reference','referral_share') THEN 'Referral'
                WHEN source_type = 'fmf' THEN 'Fmf'
                WHEN source_type IN ('organic_signup','organic_signup_wa') THEN '01. Organic'
                ELSE '02. Third Party'
            END AS source,
            CASE 
                WHEN amb.AMBASSADOR_PROVIDER_ID IS NOT NULL AND source='Referral' AND amb.status='true' AND amb.ambassadortype='referral_ambassador' AND amb.AMBASSADOR_PROVIDER_ID IS NOT NULL THEN 'Ambassador_referral'
                WHEN source='Referral' THEN 'Manual_referral'
                WHEN source='Fmf' THEN '03. FMF'
                ELSE source 
            END AS final_source_base,
            CASE
                WHEN a.source_id IN (
                    '6826fe11190ee0002dc68a57','682703f536adeb002871300d','67267959aeae3d002392f863','64f564597c4f7d0029068fe8','682984c4684b670024968400',
                    '6826f1a1a25d0800259cd969','682c0a714c9596002292d098','681f62eb59077c0024ac1b2d','682ac288ade5420025f4fd3e','6852b04e1889070021d4b0c2',
                    '683eac497e0914002443af85','68384403bf273c0025f4afdb','68400c863c21eb0024f3a3f9','64b64bd5bd55c60024579120','683d69bd79bee20026bbc20d',
                    '683ffade4d18c0002611ade3','683ffab21beaa20026d739a1','682ef79f117faf002309111d','682984c4684b670024968400','625a72a3d88faf0029282b94',
                    '6843e0168ec2fe00234ea820','68639789e21130002541f30f','6864c2fe39217d002458d0c4','686611f3034b0500243d8864','68300a1659110e00231970f6',
                    '6831acfda910f40025867614','68300e03740cb40024978638','6839a79664e93c00275bbb30','683819c63508be00232dcf92','683ec28bfa6c31002829d981',
                    '6838197f0fc755002a57ff38','681853068787510025c4de1c','682c4f9313cff4002432ad20','683c3e362bdace002262a5c2','682fd98300024c0028220a6e',
                    '682c4fdc1c38730026548807','682c52b196c75b00260aabf4','682c4f9e21915800237e5727','6830783c23f6840024f691a9','68382f4e03d7c20021f69dd3',
                    '6838387302cb020022a22d29','65805bf31d530e0025c53ce2','68567ab4b71edb00250a5b71','685e284c478e6f00293747c5','6862492605e0e100262ed613',
                    '685d3b291aca480022791b87','683d548482773100279f99d9','6839a79664e93c00275bbb30','684a9454c61a940028a574e6','684bd10c3b08b00027f4734d',
                    '684ad164a0ff2c00258ba051','68493aee4f18f400236cd63e','68595760b255380025d8b082','6686cbdd0581900024e53a2b','5faf2e19399b8428008c23d0',
                    '682846259131a10025c66efe','68284895b073c5002467557c','682846399c235600248ec6a0','68284d6bf20a170022abda03','64ace508a5bb570028245589',
                    '682ad162181e7a00243c1135','682c22771bbbcc0026b6f864','682c255d2d9ac100220530e6','6826f4f4431ad000254370b3','6826f48239df19002434dc3e',
                    '682c254a94f3f6002466f2af','680a6e77ba6e2e0022d4be71','6666fda80dd8720029c7d106','683544006cde3300221c4a16','67c2fd4b1f246f002461fd61',
                    '68516f2ff14b9c00230c3b1e','685a88aadacbe90026b4ffa9','68516cadf14b9c00230bfe32','682586c0beae450027e8b80a','6825eaa6c87d3c0027e67d19',
                    '6825ebc46527600024201c65','6825b87f94a16c0028308e36','6843d1fab31c8300259cad8f','68564c37b7555c0026cb1543','68564b3c53d4dc0025268a8a',
                    '67b24f7c4002db0025e323c5','6842834e487d9e00242e0753','6847d74b39318b0026a99b09','6847d54cfddce200252e80eb','68493fd93d469200253d4c2d',
                    '684d59c5c1b4c90024ef9a89','684fbbad01058f0023ebb458','6855542ffe1ba10025ea7651','68555469cd81770024e0a46b','685be2766d861e0025861c29',
                    '6864db911815dc002384a751','68677049c9fb59002428c0f0','686b65f838c1ee002878cefa','67cfdfbc2c607b00249d5af5','686e825fbaddea0024daed9f',
                    '68692631c5c6b500245f6952','686f4ff73b5fc00028617e4b','68625ea6572e0c0023678d65','686264eda457f80026fdf824','686243d92cfeff0025cf1337',
                    '686241e334dafa00240cb34a','68484a028acd3b0025e9a990','68676885f212830022a62ecc','686cb31071b908002987ed4e','686571980456e90023a32f34',
                    '686cc1e907c2280023d361d6','686fa9129339590028896528','68767c6e8ee9d2002170094e','686e2f9bdd0d0e00238974a0','6241880fea015d002b33a930',
                    '686cc37e08136900235107f3','685d6c9b16ec560026b6216e','6870c11044c33a00258f5c10','68677281cb0bb100243698c5','63170390f64661002faad8c8',
                    '686e23d991c6a300228ffd92','68833134ea353a00277f6ecb','6880778386b5a30026d2c709','688709559016af002598ca80','688231bc45621500261ba4c3',
                    '686cbdc707c2280023d2fd65','685a86d82cce3000247d1eb8'
                ) THEN '10. BTL'
                WHEN final_source_base='Ambassador_referral' AND a.source_id IN (
                    '64356db9b9689b00272255a3','637f16ff23489000279f2012','65f739d9e796f0002802b434','669913603f08bf002347324e',
                    '6572e14eb057c80021462493','658bc3ba99f3ba00247f562e','6648339168eaf20028961062','65d43b73aa379d00245d4df0',
                    '65cdc84769ccd9002338865c','66d5710e0d193e00242cab45','66f26aa3aa9c2e00232ddc16','66a9c4a6bc99350024fc9d2d',
                    '66d01a259358eb0022639452','6848337030966a0023a58885','674964f3f17f0b0025fe4505'
                ) THEN '09. BSS SuperMaster'
                WHEN final_source_base='Ambassador_referral' AND (mastercat_key IN ('instant_maids_l3')) THEN '06. Same Cat Master'
                WHEN final_source_base='Ambassador_referral' AND mastercat_key IN ('routines_bathroom_cleaning_l3') THEN '07. BSS Master'
                WHEN final_source_base='Ambassador_referral' AND (mastercat_key NOT IN ('instant_maids_l3', 'routines_bathroom_cleaning_l3')) THEN '08. Other Cat Master'
                WHEN final_source_base='Manual_referral' AND (source_cat IN ('Insta Help') OR source_Data.PROVIDER_CATEGORY_KEY='instant_maids_l3') AND source_Data.approval_date IS NOT NULL THEN '04. Approved Same Cat Referral'
                WHEN final_source_base='Manual_referral' AND (source_cat IN ('Insta Help') OR source_Data.PROVIDER_CATEGORY_KEY='instant_maids_l3') AND source_Data.approval_date IS NULL THEN '04. Unapproved Same Cat Referral'
                WHEN final_source_base='Manual_referral' AND (source_cat NOT IN ('Insta Help') OR source_cat IS NULL) THEN '05. Cross-Cat Referral'
                ELSE final_source_base
            END AS final_source
        FROM LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
        LEFT JOIN PROVIDERXCAMPAIGNXCATEGORYXSTATUS__AMBASSADOR_PROVIDER__DAILY__FACTS amb ON a.source_id=amb.AMBASSADOR_PROVIDER_ID
        LEFT JOIN PROVIDERXCAMPAIGNXCATEGORYXSTATUS__AMBASSADOR_PROVIDER__DAILY__FACTS b ON b.AMBASSADOR_PROVIDER_ID = amb.AMBASSADOR_PROVIDER_ID
             AND DATE(a.CREATED_AT_IST) >= DATE(b.CAMPAIGNSTARTTIME) 
             AND DATE(a.CREATED_AT_IST) <= DATE(b.CAMPAIGNENDTIME)
        LEFT JOIN PROVIDER__DAILY__FACTS source_Data ON a.source_id = source_Data.provider_id
        WHERE a.REPORTING_SUPERCATEGORY_NEW='Insta Help'
          AND reporting_city <> 'Singapore'
          AND DATE(WALKED_IN) >= '2025-01-01'
    )
    SELECT 
        provider_id,
        reporting_city,
        DATE_TRUNC('week', CREATED_AT_IST) AS week,
        final_source,
        COUNT(DISTINCT LEAD_ID) AS lead_created,
        COUNT(DISTINCT CASE WHEN SCHEDULED IS NOT NULL THEN LEAD_ID END) AS lineups
    FROM base1
    WHERE reporting_city <> 'Singapore'
    GROUP BY 1,2,3,4
),

screening AS (
    WITH S_provider_details AS (
        SELECT DISTINCT 
            pmpr.provider_id AS pro_id,
            pm.provider_name AS pro_name,
            pmpr.created_at_ist AS sdate,
            pmpr.created_by AS s_trainer,
            pmpr.evaluation AS "Result::multi-filter",
            pm.city AS "City::multi-filter",
            DATE_TRUNC('WEEK', pmpr.created_at_ist) AS "week::multi-filter"
        FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
        LEFT JOIN provider__daily__facts pm ON pmpr.provider_id = pm.provider_id
        WHERE pmpr.customer_category_key = 'insta_maids'
          AND pmpr.module_type = 'screening'
          AND pmpr.module_key IN (
            'instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai',
            'Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune',
            'Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD'
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
            'instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai',
            'Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune',
            'Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD'
          )
          AND (score < 0 OR answer = 'fail')
        GROUP BY provider_id
    ),
    prioritized AS (
        SELECT 
            spd.pro_id AS partner_id,
            spd.pro_name,
            spd.sdate AS scr_date,
            spd.s_trainer AS s_poc,
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
                WHEN sfr.fail_reason ILIKE 'Based on the below list, is the partner fit to work? (Back pain, Stomach pain, Knee pain, Arthritis, Movement-limiting injuries, Recent major surgeries, Chronic surgery effects, Asthma, Breathing issues, Vision problems,Skin allergies, pregnancy%' THEN 'partner not fit to work'
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
            pmpr.created_by AS pst,
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
            ppd.pst AS ps_poc,
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

src AS (
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

trainer_mapping AS (
    SELECT DISTINCT
        e.event_slot_id,
        e.event_key, 
        p.provider_id,
        DATEADD(min,30,DATEADD(hour,5,TRY_TO_TIMESTAMP(e.CREATED_AT::string))) AS pro_booked_at,
        e.start_date_ist AS training_start_date,
        e.end_date_ist AS training_end_date, 
        s.TRAINER_NAME,
        RANK() OVER (PARTITION BY e.EVENT_SLOT_ID,p.provider_id,e.start_date_ist ORDER BY e.start_date_ist DESC) AS rnk
    FROM PUBLIC.TRAINERXDATE__TRAINING_EVENTS__DAILY__FACTS e
    LEFT JOIN PROVIDERXEVENTXDATE__DAILY__FACTS p ON e.EVENT_SLOT_ID = p.event_slot_id 
    LEFT JOIN provider_master pm ON pm.provider_id = p.provider_id
    LEFT JOIN src s ON pm.provider_id = s.provider_id
    WHERE e.event_key IN ('insta_maids_training')
    QUALIFY rnk = 1
    ORDER BY start_date_ist DESC
),

pip_metrics AS (
    WITH pip_base AS (
      SELECT 
          provider_id,
          city,
          DATE_TRUNC('month', approval_date) AS app_month,
          tier,
          tier_start_date,
          tier_end_date,
          paf_cancellation_at_tier AS paf_error,
          rating_error_at_tier AS rating_error,
          graded_leave_days_at_tier AS total_graded_leaves,
          ROW_NUMBER() OVER (
              PARTITION BY provider_id 
              ORDER BY DATE(tier_start_date), DATE(tier_end_date)
          ) AS cycle_no
      FROM provider_promise_plan__daily__metrics
      WHERE category = 'instant_maids_l3'
        AND tier IS NOT NULL
    ),
     
    tier_status AS (
       SELECT
            provider_id,
            city,
            app_month,
            cycle_no,
            tier_start_date,
            tier_end_date,
            CASE WHEN tier_end_date <= CURRENT_DATE THEN 1 ELSE 0 END AS completion_flag
        FROM pip_base
        WHERE cycle_no IN (1, 2)
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
                ppp.tier_start_date  AS start_date,
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
                    WHEN ppp.city IN ('city_gurgaon_v2', 'city_noida_v2') THEN 'city_delhi_v2' 
                    ELSE ppp.city 
                END AS city,
                ROW_NUMBER() OVER (
                    PARTITION BY ppp.provider_id, ppp.tier_start_date, ppp.tier_end_date
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
            ta.rating_error_at_tier      AS tm_rating_error,
            ta.graded_leave_days_at_tier AS tm_leave_days,
            ta.paf_cancellation_at_tier  AS tm_paf_cancellation,
            ta.CM_ERROR_AT_TIER          AS tm_cm_error,
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
        LEFT JOIN provider_master pm ON pm.provider_id = ppp.provider_id,
        LATERAL FLATTEN(
             INPUT => ppp.PROVIDER_REFERENCE_METRICS_ARRAY__METADATA,
             OUTER => TRUE
         ) m
        WHERE ppp.provider_id IN (
            SELECT DISTINCT providerid FROM psp_data_raw
        )
        GROUP BY ppp.provider_id, ppp.tier_start_date, ppp.tier_end_date
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
            COALESCE(ls.late_show_count, 0) AS late_show_count,
            COALESCE(pa.cancellations_in_tier, 0) AS cancellations_in_tier,
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
        WHERE tm.providerid NOT IN (
            SELECT provider_id FROM blocked_verification_failed_15d
        )
    ),
    
    S_provider_details AS (
        SELECT
            pmpr.provider_id,
            pmpr.created_by AS s_trainer,
            TO_CHAR(DATE_TRUNC('WEEK',pmpr.created_at_ist), 'DD-Mon-YYYY') AS S_WEEK,
            TO_CHAR(DATE_TRUNC('MONTH',pmpr.created_at_ist), 'Mon-YYYY') AS S_MONTH,
            ROW_NUMBER() OVER (
                PARTITION BY pmpr.provider_id
                ORDER BY pmpr.created_at_ist DESC
            ) AS rn
        FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
        LEFT JOIN provider__daily__facts pm
            ON pmpr.provider_id = pm.provider_id
        WHERE pmpr.customer_category_key = 'insta_maids'
          AND pmpr.module_type = 'screening'
          AND pmpr.module_key IN (
            'instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai',
            'Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune',
            'Objective Criteria-Chennai','Objective Criteria KOL','Objective Criteria - AMD'
          )
    ),
    
    latest_s_trainer AS (
        SELECT provider_id, s_trainer, S_WEEK, S_MONTH
        FROM S_provider_details
        WHERE rn = 1
    ),
    
    training_src AS (
        SELECT
            a.provider_id,
            f.value:"questionnaire_created_by"::string AS training_trainer,
            TO_CHAR(DATE_TRUNC('WEEK', a.updated_at_ist), 'DD-Mon-YYYY') AS training_week,
            TO_CHAR(DATE_TRUNC('MONTH', a.updated_at_ist), 'Mon-YYYY') AS training_month,
            ROW_NUMBER() OVER (
                PARTITION BY a.provider_id
                ORDER BY a.updated_at_ist DESC
            ) AS rn
        FROM providerxcoursexchapterxassessment__provider_training__daily__facts a,
             LATERAL FLATTEN(input => a.questionnaire_info) f
        WHERE a.customer_category_key = 'insta_maids'
          AND f.value:"questionnaire_key"::string = 'IH_FA_Module'
          AND f.value:"questionnaire_status"::string = 'completed'
    ),
    
    latest_training AS (
        SELECT
            provider_id,
            training_trainer,
            training_week,
            training_month
        FROM training_src
        WHERE rn = 1
    ),
    
    provider_avg_rating AS (
        SELECT
            provider_id,
            ROUND(AVG(avg_rating), 2) AS avg_rating
        FROM provider__daily__facts
        WHERE customer_category_key = 'insta_maids'
          AND avg_rating IS NOT NULL
        GROUP BY provider_id
    ),
    
   final_pip_metrics AS (
       SELECT
            ts.provider_id,
            MAX(par.avg_rating) AS avg_rating,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ts.completion_flag END) AS c1_completion_flag,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ft.flipped_tier END)    AS c1_potential_tier,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ts.completion_flag END) AS c2_completion_flag,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ft.flipped_tier END)    AS c2_potential_tier,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ft.late_show_count END) AS c1_late_show_count,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ft.late_show_count END)  AS c2_late_show_count,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ft.cancellations_in_tier END)AS c1_cancellations_in_tier,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ft.cancellations_in_tier END)AS c2_cancellations_in_tier,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ft.tm_leave_days END)AS c1_tm_leave_days,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ft.tm_leave_days END)AS c2_tm_leave_days,
            MAX(CASE WHEN ts.cycle_no = 1 THEN ft.l50_rating END) AS c1_l50_rating_before_tier_end,
            MAX(CASE WHEN ts.cycle_no = 2 THEN ft.l50_rating END) AS c2_l50_rating_before_tier_end
       FROM tier_status ts
       LEFT JOIN flip_tier ft
          ON ft.providerid = ts.provider_id
         AND ft.start_date = ts.tier_start_date
         AND ft.tier_end_date = ts.tier_end_date
       LEFT JOIN provider_avg_rating par
          ON par.provider_id = ts.provider_id 
       GROUP BY ts.provider_id
    )
    
    SELECT
        provider_id,
        avg_rating,
        c1_completion_flag,
        c1_potential_tier,
        c2_completion_flag,
        c2_potential_tier,
        c1_late_show_count,
        c2_late_show_count,
        c1_cancellations_in_tier,
        c2_cancellations_in_tier,
        c1_tm_leave_days,
        c2_tm_leave_days,
        c1_l50_rating_before_tier_end,
        c2_l50_rating_before_tier_end
    FROM final_pip_metrics
),

final AS (
    SELECT
        b.city,
        b.provider_id,
        b.provider_name,
        wi_week,
        b.SCREENING_DATE,
        s.scr_date,
        SCREENING_QUALIFIED,
        PARTIALLY_RECHARGED,
        IN_TRAINING,
        TRAINING_PASSED,
        training_start_date,
        training_end_date,
        h.training_center,
        t.TRAINER_NAME,
        x.source_name,
        approval_date,
        s.s_poc AS "s_poc::multi-filter",
        s.s_poc,
        pm.c1_completion_flag,
        pm.c2_completion_flag,
        pm.c1_potential_tier,
        pm.c2_potential_tier,
        pm.avg_rating,
        pm.c1_late_show_count,
        pm.c2_late_show_count,
        pm.c1_cancellations_in_tier as c1_cancellation,
        pm.c2_cancellations_in_tier as c2_cancellation,
        pm.c1_tm_leave_days as c1_leaves,
        pm.c2_tm_leave_days as c2_leaves,
        pm.c1_l50_rating_before_tier_end as c1_l50_rating,
        pm.c2_l50_rating_before_tier_end as c2_l50_rating
    FROM base b
    LEFT JOIN pre_screening p ON b.provider_id = p.pro__id
    LEFT JOIN screening s ON b.provider_id = s.partner_id
    LEFT JOIN trainer_mapping t ON b.provider_id = t.provider_id
    LEFT JOIN p_source ps ON b.provider_id = ps.provider_id
    LEFT JOIN p_source_name x ON x.provider_id = b.provider_id
    LEFT JOIN training_centre h ON b.provider_id = h.provider_id
    LEFT JOIN pip_metrics pm ON pm.provider_id = b.provider_id
)

SELECT DISTINCT 
        city,
        f.provider_id,
        f.provider_name,
        IN_TRAINING,
        TRAINING_PASSED,
        training_start_date,
        training_end_date,
        training_center,
        TRAINER_NAME AS "Trainer::multi-filter",
        approval_date,
        s_poc ,
        avg_rating,
        c1_completion_flag,
        c2_completion_flag,
        c1_potential_tier,
        c2_potential_tier,
        c1_late_show_count,
        c2_late_show_count,
        c1_cancellation,
        c2_cancellation,
        c1_leaves,
        c2_leaves,
        c1_l50_rating,
        c2_l50_rating
FROM final f;
