with dump as (
with base as (select distinct lead_id,a.PROVIDER_ID,b.provider_name,date(b.approval_date) as approval_date,city,
date_trunc(week,date(WALKED_IN)) as wi_week,
WALKED_IN as wi_date,
SCREENING_DATE,
SCREENING_QUALIFIED,PARTIALLY_RECHARGED,
SCHEDULED_FOR_TRAINING,
SCHEDULING_TRIGGERED_FOR_TRAINING,
IN_TRAINING,
TRAINING_PASSED,TRAINING_FAILED
from PUBLIC.LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
left join provider__daily__facts b on a.provider_id=b.provider_id
where a.customer_category_key ='insta_maids'
and wi_week>'2025-05-01'
and walked_in is not null),

training_centre AS (
    SELECT 
        provider_id, 
        CASE 
            WHEN module_key = 'Objective criteria - Bangalore' THEN
                CASE 
                    WHEN answer = 'QQ1' THEN 'Krimson'
                    WHEN answer = 'QQ2' THEN 'Marathalli'
                    when answer = 'QQ3' then 'HRBR layout'
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
            when module_key = 'Objective Criteria- Pune' then 
            case when answer = 'QQ1' then 'Baner Training Center'
            end 
            
        END AS training_center
    FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
    WHERE statement ILIKE '%Pro''s screening center ?%'
       OR statement ILIKE '%What is partners screening center?%'
       or statement ilike '%What is partners screening center ?%'
),

p_source_name as (

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
      a.source_id       AS source_id,
      pm.provider_name as source_name,
      a.provider_id as provider_id
  FROM LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
  join base b on b.provider_id=a.provider_id
  left join PUBLIC.PROVIDER_MASTER pm on pm.provider_id=a.source_id
  WHERE a.reporting_supercategory_new = 'Insta Help'

)
,
 p_source as (
 with 
 base1 AS (
  SELECT distinct
    a.*,
    source_Data.REPORTING_SUPERCATEGORY_NEW as source_cat,
    amb.categorykey as mastercat_key,
    case 
        when source_type in('reference','referral_share') then 'Referral'
        when source_type ='fmf' then 'Fmf'
        when source_type in('organic_signup','organic_signup_wa') then '01. Organic'
        else '02. Third Party'
    end as source,
    case 
        when amb.AMBASSADOR_PROVIDER_ID is not null and source='Referral' and amb.status='true' and amb.ambassadortype='referral_ambassador' and amb.AMBASSADOR_PROVIDER_ID is not null then 'Ambassador_referral'
        when source='Referral' then 'Manual_referral'
        when source='Fmf' then '03. FMF'
        else source 
    end as final_source_base,
    case
        when a.source_id in (
        '6826fe11190ee0002dc68a57',
'682703f536adeb002871300d',
'67267959aeae3d002392f863',
'64f564597c4f7d0029068fe8',
'682984c4684b670024968400',
'6826f1a1a25d0800259cd969',
'682c0a714c9596002292d098',
'681f62eb59077c0024ac1b2d',
'682ac288ade5420025f4fd3e',
'6852b04e1889070021d4b0c2',
'683eac497e0914002443af85',
'68384403bf273c0025f4afdb',
'68400c863c21eb0024f3a3f9',
'64b64bd5bd55c60024579120',
'683d69bd79bee20026bbc20d',
'683ffade4d18c0002611ade3',
'683ffab21beaa20026d739a1',
'682ef79f117faf002309111d',
'682984c4684b670024968400',
'625a72a3d88faf0029282b94',
'6843e0168ec2fe00234ea820',
'68639789e21130002541f30f',
'6864c2fe39217d002458d0c4',
'686611f3034b0500243d8864',
'68300a1659110e00231970f6',
'6831acfda910f40025867614',
'68300e03740cb40024978638',
'6839a79664e93c00275bbb30',
'683819c63508be00232dcf92',
'683ec28bfa6c31002829d981',
'6838197f0fc755002a57ff38',
'681853068787510025c4de1c',
'682c4f9313cff4002432ad20',
'683c3e362bdace002262a5c2',
'682fd98300024c0028220a6e',
'682c4fdc1c38730026548807',
'682c52b196c75b00260aabf4',
'682c4f9e21915800237e5727',
'6830783c23f6840024f691a9',
'68382f4e03d7c20021f69dd3',
'6838387302cb020022a22d29',
'65805bf31d530e0025c53ce2',
'68567ab4b71edb00250a5b71',
'685e284c478e6f00293747c5',
'6862492605e0e100262ed613',
'685d3b291aca480022791b87',
'683d548482773100279f99d9',
'6839a79664e93c00275bbb30',
'684a9454c61a940028a574e6',
'684bd10c3b08b00027f4734d',
'684ad164a0ff2c00258ba051',
'68493aee4f18f400236cd63e',
'68595760b255380025d8b082',
'6686cbdd0581900024e53a2b',
'5faf2e19399b8428008c23d0',
'682846259131a10025c66efe',
'68284895b073c5002467557c',
'682846399c235600248ec6a0',
'68284d6bf20a170022abda03',
'64ace508a5bb570028245589',
'682ad162181e7a00243c1135',
'682c22771bbbcc0026b6f864',
'682c255d2d9ac100220530e6',
'6826f4f4431ad000254370b3',
'6826f48239df19002434dc3e',
'682c254a94f3f6002466f2af',
'680a6e77ba6e2e0022d4be71',
'6666fda80dd8720029c7d106',
'683544006cde3300221c4a16',
'67c2fd4b1f246f002461fd61',
'68516f2ff14b9c00230c3b1e',
'685a88aadacbe90026b4ffa9',
'68516cadf14b9c00230bfe32',
'682586c0beae450027e8b80a',
'6825eaa6c87d3c0027e67d19',
'6825ebc46527600024201c65',
'6825b87f94a16c0028308e36',
'6843d1fab31c8300259cad8f',
'68564c37b7555c0026cb1543',
'68564b3c53d4dc0025268a8a',
'67b24f7c4002db0025e323c5',
'6842834e487d9e00242e0753',
'6847d74b39318b0026a99b09',
'6847d54cfddce200252e80eb',
'68493fd93d469200253d4c2d',
'684d59c5c1b4c90024ef9a89',
'684fbbad01058f0023ebb458',
'6855542ffe1ba10025ea7651',
'68555469cd81770024e0a46b',
'685be2766d861e0025861c29',
'6864db911815dc002384a751',
'68677049c9fb59002428c0f0',
'686b65f838c1ee002878cefa',
'67cfdfbc2c607b00249d5af5',
'686e825fbaddea0024daed9f',
'68692631c5c6b500245f6952',
'686f4ff73b5fc00028617e4b',
'68625ea6572e0c0023678d65',
'686264eda457f80026fdf824',
'686243d92cfeff0025cf1337',
'686241e334dafa00240cb34a',
'68484a028acd3b0025e9a990',
'68676885f212830022a62ecc',
'686cb31071b908002987ed4e',
'686571980456e90023a32f34',
'686cc1e907c2280023d361d6',
'686fa9129339590028896528',
'68767c6e8ee9d2002170094e',
'686e2f9bdd0d0e00238974a0',
'6241880fea015d002b33a930',
'686cc37e08136900235107f3',
'685d6c9b16ec560026b6216e',
'6870c11044c33a00258f5c10',
'68677281cb0bb100243698c5',
'63170390f64661002faad8c8',
'686e23d991c6a300228ffd92',
'68833134ea353a00277f6ecb',
'6880778386b5a30026d2c709',
'688709559016af002598ca80',
'688231bc45621500261ba4c3',
'686cbdc707c2280023d2fd65',
'685a86d82cce3000247d1eb8'
) then '10. BTL'

when final_source_base='Ambassador_referral' AND a.source_id in ('64356db9b9689b00272255a3',
'637f16ff23489000279f2012',
'65f739d9e796f0002802b434',
'669913603f08bf002347324e',

'6572e14eb057c80021462493',
'658bc3ba99f3ba00247f562e',
'6648339168eaf20028961062',
'65d43b73aa379d00245d4df0',
'65cdc84769ccd9002338865c',
'66d5710e0d193e00242cab45',
'66f26aa3aa9c2e00232ddc16',
'66a9c4a6bc99350024fc9d2d',
'66d01a259358eb0022639452',
'6848337030966a0023a58885',
'674964f3f17f0b0025fe4505') then '09. BSS SuperMaster'

when final_source_base='Ambassador_referral' and ( mastercat_key in ('instant_maids_l3') ) then '06. Same Cat Master'
when final_source_base='Ambassador_referral' and mastercat_key in ('routines_bathroom_cleaning_l3') then '07. BSS Master'
when final_source_base='Ambassador_referral' and ( mastercat_key not in ('instant_maids_l3', 'routines_bathroom_cleaning_l3') ) then '08. Other Cat Master'

when final_source_base='Manual_referral' and ( source_cat in ('Insta Help')  or source_Data.PROVIDER_CATEGORY_KEY='instant_maids_l3' ) and source_Data.approval_date is not null then '04. Approved Same Cat Referral'
when final_source_base='Manual_referral' and ( source_cat in ('Insta Help')  or source_Data.PROVIDER_CATEGORY_KEY='instant_maids_l3' ) and source_Data.approval_date is null then '04. Unapproved Same Cat Referral'
when final_source_base='Manual_referral' and ( source_cat not in ('Insta Help') or source_cat is null) then '05. Cross-Cat Referral'
else final_source_base
end as final_source
FROM LEAD__ONBOARDING_FUNNEL__DAILY__FACTS a
left join PROVIDERXCAMPAIGNXCATEGORYXSTATUS__AMBASSADOR_PROVIDER__DAILY__FACTS amb on a.source_id=amb.AMBASSADOR_PROVIDER_ID
left join PROVIDERXCAMPAIGNXCATEGORYXSTATUS__AMBASSADOR_PROVIDER__DAILY__FACTS b on b.AMBASSADOR_PROVIDER_ID = amb.AMBASSADOR_PROVIDER_ID and date(a.CREATED_AT_IST)>=date(b.CAMPAIGNSTARTTIME) and date(a.CREATED_AT_IST)<=date(b.CAMPAIGNENDTIME)
left join PROVIDER__DAILY__FACTS source_Data on a.source_id = source_Data.provider_id
WHERE a.REPORTING_SUPERCATEGORY_NEW='Insta Help'
AND reporting_city <> 'Singapore'
and date(WALKED_IN)>='2025-01-01'
)



  SELECT 
    provider_id,
    reporting_city,
    DATE_TRUNC('week', CREATED_AT_IST) AS week,
    final_source,
    COUNT(DISTINCT LEAD_ID) AS lead_created,
    COUNT(DISTINCT CASE WHEN SCHEDULED IS NOT NULL THEN LEAD_ID END) AS lineups
  FROM base1
  where reporting_city <> 'Singapore'
  GROUP BY 1,2,3,4
),

screening AS (
WITH S_provider_details AS (
  SELECT DISTINCT 
    pmpr.provider_id as pro_id,pm.provider_name as pro_name,pmpr.created_at_ist as sdate,pmpr.created_by as s_trainer,pmpr.evaluation as "Result::multi-filter",
    pm.city as "City::multi-filter",
    DATE_TRUNC('WEEK', pmpr.created_at_ist) as "week::multi-filter"
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW pmpr
  LEFT JOIN provider__daily__facts pm ON pmpr.provider_id = pm.provider_id
  WHERE pmpr.customer_category_key = 'insta_maids'
    AND pmpr.module_type = 'screening'
    AND pmpr.module_key in ('instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai','Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune','Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD')
    
),
s_fail_reason AS (
  SELECT 
    provider_id,
    LISTAGG(statement, '; ') WITHIN GROUP (ORDER BY statement) AS fail_reason
  FROM PROVIDER_MODULE_PROVIDER_RESPONSE__VIEW
  WHERE customer_category_key = 'insta_maids'
    AND module_type = 'screening'
    AND module_key in   ('instahelp_screening','Objective criteria delhi','Objective Criteria - Mumbai','Objective criteria - Bangalore','Objective Criteria Hyd','Objective Criteria- Pune','Objective Criteria-Chennai', 'Objective Criteria KOL', 'Objective Criteria - AMD')
    AND (score < 0 OR answer = 'fail')
  GROUP BY provider_id
),
prioritized AS (
  SELECT 
    spd.pro_id as partner_id,spd.pro_name,spd.sdate as scr_date,spd.s_trainer as s_poc,spd."Result::multi-filter" as s_result,spd."City::multi-filter",spd."week::multi-filter",
    sfr.fail_reason as fail,row_number() over( partition by spd.pro_id order by spd.sdate desc) as bundle_num,
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
  LEFT JOIN s_fail_reason sfr ON spd.pro_id = sfr.provider_id)
  
SELECT * FROM prioritized
qualify bundle_num = 1
    ),

pre_screening as(
WITH ps_provider_details AS (
  SELECT DISTINCT 
    pmpr.provider_id as pro_id,pm.provider_name,pmpr.created_at_ist as psdate,pmpr.created_by as pst,pmpr.evaluation as pre_screening_result,
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
    ppd.pro_id as pro__id,ppd.psdate as pdate,ppd.pst as ps_poc,ppd.pre_screening_result as ps_result,
    pfr.fail_reason as fail,row_number() over( partition by ppd.pro_id order by ppd.psdate desc) as ps_bundle_num,
    pfr.fail_reason as psfail,
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
qualify ps_bundle_num = 1
)
,
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

trainer_mapping as (

select distinct e.event_slot_id,
    e.event_key, 
    p.provider_id,
    dateadd(min,30,dateadd(hour,5,try_to_timestamp(e.CREATED_AT::string))) as pro_booked_at,
    e.start_date_ist as training_start_date,
    e.end_date_ist as training_end_date, 
   coalesce(s.TRAINER_NAME, p.TRAINER_NAME ) as trainer_name,
    rank() over(partition by p.provider_id order by e.start_date_ist desc) as rnk
    
from PUBLIC.TRAINERXDATE__TRAINING_EVENTS__DAILY__FACTS e
left join PROVIDERXEVENTXDATE__DAILY__FACTS p on e.EVENT_SLOT_ID = p.event_slot_id 
left join provider_master pm on pm.provider_id=p.provider_id
left join src s on pm.provider_id = s.provider_id
    where 
    e.event_key in ('insta_maids_training')
    qualify rnk = 1
order by start_date_ist desc


),

final as (select b.city,b.provider_id,b.provider_name,wi_week,wi_date,ps.final_source,
pdate,b.SCREENING_DATE,s.scr_date as sdate,
SCREENING_QUALIFIED,PARTIALLY_RECHARGED,
SCHEDULING_TRIGGERED_FOR_TRAINING,SCHEDULED_FOR_TRAINING,
t.training_start_date as IN_TRAINING,
TRAINING_PASSED,TRAINING_FAILED,
h.training_center,
t.TRAINER_NAME,
x.source_name,
approval_date ,p.ps_poc,s.s_poc,p.final_fail_reason as p_fail,s.final_fail_reason as s_fail,
case when p_fail is null then s_fail else p_fail end as final_fail_reason
from base b
left join pre_screening p on b.provider_id=p.pro__id
left join screening s on b.provider_id = s.partner_id
left join trainer_mapping t on b.provider_id = t.provider_id
left join p_source ps on b.provider_id = ps.provider_id
left join p_source_name x on x.provider_id = b.provider_id
left join training_centre h on b.provider_id = h.provider_id
),

pip_base AS (
   select * from ( SELECT
        provider_id,
        DATE_TRUNC('week', tier_end_date) AS tew,
        tier,
        tier_start_date,STATUS,
        tier_end_date,
        paf_cancellation_at_tier AS paf_error,
        rating_error_at_tier AS rating_error,
        graded_leave_days_at_tier AS total_graded_leaves,
        ROW_NUMBER() OVER (
            PARTITION BY provider_id
            ORDER BY DATE(tier_start_date)
        ) AS cycle_no,      COUNT(*) OVER (
                PARTITION BY 
                    provider_id, 
                    tier_start_date, 
                    tier_end_date
            ) AS duplicate_count
    FROM provider_promise_plan__daily__metrics
    WHERE category = 'instant_maids_l3'
      AND tier IS NOT NULL) x
       where ( (duplicate_count > 1 AND status = 'completed')
        OR duplicate_count = 1 )
),
 tier_status AS (
    SELECT
        provider_id,
        tier_end_date,
        tew,tier,
        cycle_no,
        CASE
            WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 0 THEN 'diamond'
            WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 1 THEN 'gold'
            WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves = 2 THEN 'silver'
            WHEN rating_error < 4 AND paf_error < 4 AND total_graded_leaves BETWEEN 3 AND 4 THEN 'bronze'
            ELSE 'pip'
        END AS potential_tier
    FROM pip_base
),provider_base AS (
    SELECT DISTINCT
        pdf.provider_id,
        DATE(pdf.approval_date) AS app_date,
        pdf.last_delivery_date AS ldd
    FROM provider__daily__facts pdf
    WHERE pdf.approval_date >= '2025-01-01'
      AND pdf.provider_name NOT ILIKE '%test%'
      AND pdf.reporting_supercategory_new = 'Insta Help'
),
l7d AS (
    SELECT
        pdf.provider_id,
        CASE
            WHEN SUM(CASE WHEN acm.status = 'marked working' THEN 1 ELSE 0 END) > 8 THEN 'Working'
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
    GROUP BY pdf.provider_id
),

ranked AS (
    SELECT
        provider_id,
        reason,
        temporary_block,
        temp_block_since_date,
        DATE_TRUNC('week', DATE(temp_block_since_date)) AS ldd_week,
        CASE
            WHEN DATEDIFF(day, temp_block_since_date, CURRENT_DATE()) > 7
                 AND temporary_block = 'true'
            THEN 'churn'
            ELSE 'active'
        END AS status_pro,
        ROW_NUMBER() OVER (
            PARTITION BY provider_id
            ORDER BY date DESC
        ) AS rn
    FROM PROVIDERXDATE__ACTIVE_PROFILE__HOURLY__FACTS
    WHERE customer_category_key = 'insta_maids'
),

ranked_latest AS (
    SELECT *
    FROM ranked
    WHERE rn = 1
),

churn_bucket AS (
    SELECT distinct 
        pb.provider_id,ldd,
        pb.app_date,rl.ldd_week,
        COALESCE(rl.ldd_week, DATE_TRUNC('week', CURRENT_DATE)) AS churn_week,
        CASE
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Not Working'
                  OR rl.status_pro = 'churn'
            THEN '3. Churn'
            WHEN COALESCE(l7d.L7D_status, 'Unknown') = 'Working'
                  OR rl.status_pro = 'active'
            THEN '1. Active'
            WHEN pb.ldd IS NULL
                 AND DATE(pb.app_date) >= CURRENT_DATE - 7
            THEN '1. Active'
        END AS churn_status,
          CASE 
            WHEN ldd IS NULL THEN 0 
            ELSE (DATE(ldd) - DATE(app_date)) 
        END AS age,
   
CASE    WHEN churn_status='1. Active' then '1. Active'
    WHEN age = 0 and churn_status='3. Churn' THEN '3. D0 churn'
    WHEN age <= 7 and churn_status='3. Churn' THEN '4. D7 churn'
    WHEN age <= 17 and churn_status='3. Churn' THEN '5. D15 churn'
    WHEN age <= 30 and churn_status='3. Churn' THEN '6. D30 churn'
    WHEN age <= 60 and churn_status='3. Churn' THEN '7. D60 churn'
    WHEN age <= 90 and churn_status='3. Churn' THEN '8. D90 churn'
    WHEN age <= 120 and churn_status='3. Churn' THEN '9. D120 churn'
    ELSE '10. >D120 churn'
END AS churn_bucket
    FROM provider_base pb
    LEFT JOIN l7d
        ON pb.provider_id = l7d.provider_id
    LEFT JOIN ranked_latest rl
        ON pb.provider_id = rl.provider_id
)

select distinct f.*,z.app_date,date(z.ldd) as ldd,churn_status,age,churn_bucket, date(tier_end_date) as tier_end_date ,
        tew,tier,
        cycle_no, potential_tier
        from final f left join churn_bucket z on f.provider_id = z.provider_id
        full outer join tier_status x on f.provider_id = x.provider_id
)

select distinct
    CASE
        WHEN LOWER(REPLACE(REPLACE(REGEXP_REPLACE(TRAINER_NAME, '@urbancompany\\.com', ''), '.ext', ''), ' ', ''))
             IN ('sanjibkumarsaha', 'sanjibsaha') THEN 'sanjibsaha'
        WHEN LOWER(REPLACE(REPLACE(REGEXP_REPLACE(TRAINER_NAME, '@urbancompany\\.com', ''), '.ext', ''), ' ', ''))
             IN ('yuvrajthapachhetri', 'yuvrajchhetri') THEN 'yuvrajchhetri'
        WHEN LOWER(REPLACE(REPLACE(REGEXP_REPLACE(TRAINER_NAME, '@urbancompany\\.com', ''), '.ext', ''), ' ', ''))
             IN ('abhishekkumar3', 'abhishekkumar') THEN 'abhishekkumar'
        ELSE LOWER(REPLACE(REPLACE(REGEXP_REPLACE(TRAINER_NAME, '@urbancompany\\.com', ''), '.ext', ''), ' ', ''))
    END AS Trainer,
    date_trunc('week',date(in_training)) as "week::multi-filter",
    city as "city::filter",
    COUNT(DISTINCT CASE WHEN in_training IS NOT NULL THEN provider_id END) as IT,
    COUNT(DISTINCT CASE WHEN training_passed IS NOT NULL THEN provider_id END) as TP,
    (IT-TP- COUNT(DISTINCT CASE WHEN training_failed IS NOT NULL THEN provider_id END) ) as Drop_offs,
    ROUND(COUNT(DISTINCT CASE WHEN training_passed IS NOT NULL THEN provider_id END)::FLOAT 
        / NULLIF(COUNT(DISTINCT CASE WHEN in_training IS NOT NULL THEN provider_id END), 0), 2) * 100 AS tp_pct,
    ROUND(
        COUNT(DISTINCT CASE WHEN cycle_no IN (1,2) AND potential_tier = 'pip' THEN provider_id END)::FLOAT
        / NULLIF(COUNT(DISTINCT CASE WHEN cycle_no IN (1,2) THEN provider_id END),0) * 100,
    2) AS elc_pip_pct,
    SUM(CASE 
            WHEN churn_status = '3. Churn' AND age = 0 
            THEN 1 ELSE 0 
        END) AS d0_churn_cnt,
    SUM(CASE 
            WHEN churn_status = '3. Churn' AND age BETWEEN 1 AND 7 
            THEN 1 ELSE 0 
        END) AS d7_churn_cnt,
    SUM(CASE 
            WHEN churn_status = '3. Churn' AND age BETWEEN 8 AND 17 
            THEN 1 ELSE 0 
        END) AS d15_churn_cnt,
    SUM(CASE 
            WHEN churn_status = '3. Churn' AND age BETWEEN 18 AND 30 
            THEN 1 ELSE 0 
        END) AS d30_churn_cnt,
    SUM(CASE 
            WHEN churn_status = '3. Churn' AND age > 30
            THEN 1 ELSE 0 
        END) AS llc_churn_cnt
from dump 
group by 1,2,3
