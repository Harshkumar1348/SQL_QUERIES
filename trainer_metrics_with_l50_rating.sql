-- Trainer Metrics Query with L50 Average Rating Logic
-- Logic: 
--   - Before 2026-01-19: avg_l50_rating = average of last 50 ratings (ranked by bdate DESC)
--   - From 2026-01-19 onwards: avg_l50_rating = SUM(rating) / COUNT(DISTINCT customer_request_id where service_delivered=1 and rating is not null)

WITH manual_mapping AS (
    SELECT
        column1::STRING AS provider_id,
        column2::STRING AS trainer_name
    FROM VALUES
        ('683163a5506ee90025d36d0e','Anandi'),
        ('693d1d779c2d3c00228caec4','Aditi'),
        ('6874ab6732b7530025fc703d','Aditi'),
        ('6867d5022a7ccd0023bed7d9','Anandi'),
        ('68c2a8b84facbf0026a6e047','Aditi'),
        ('685bd95fbaecf700232f6f4e','Anandi'),
        ('686f921c3d45510025908a46','Aditi'),
        ('683840770009400029b81a9b','Aditi'),
        ('684d26aed5f1c500234bb647','Aditi'),
        ('69202f646eca6200282c276d','Aditi'),
        ('68d661270100bb00230fd382','Anandi'),
        ('689d9dec7b4b43002745ab3c','Anandi'),
        ('68298a533b6e240023b5b094','Aditi'),
        ('6856b3d12c14a3002605a21d','Aditi'),
        ('68f0b817f7bdc30027ecd2bd','Anandi'),
        ('6840104b43f218002611c90a','Anandi'),
        ('6814b1d4528b8f0025d874ed','Anandi'),
        ('68fca9e93b0eb7002716c2a7','Aditi'),
        ('6855428edaadcc002a282e5a','Anandi'),
        ('68df8b4a0393640026632c7e','Aditi'),
        ('69144662ee85550025e1d0ec','Anandi'),
        ('681097c5bb4aba002257e4fc','Anandi'),
        ('683d4be181025d00276540e6','Aditi'),
        ('6841320667cf5800242d8c63','Anandi'),
        ('6863bf52ae2ef90025f2285d','Aditi'),
        ('68d8de9c60d24a00250f81de','Aditi'),
        ('682c3c42cde6cd0022092f86','Aditi'),
        ('691c4e21bac6c20024e7105a','Anandi'),
        ('683943c5f04c63002499d5dc','Anandi'),
        ('6891ddcb0a1d3000260df47d','Aditi'),
        ('68c155c8948af500258c0d4a','Aditi'),
        ('681da6bce5f9b40024090469','Anandi'),
        ('68c3e0e515fd3700254e8751','Aditi'),
        ('68ca26f14e13d80024cee005','Anuja Rakshe'),
        ('691d9ab342685d0024c96b44','Anuja Rakshe'),
        ('687882762ddfe10025b30183','Anuja Rakshe'),
        ('688d9628bd32a7002338051d','Anuja Rakshe'),
        ('68c90edbf98ad50026e435e7','Aditi'),
        ('6930033c963f5e0028aa4dfd','Anuja Rakshe'),
        ('68722be7dd7e1e00288c2bf1','Anuja Rakshe'),
        ('68777a710e79d900276388cd','Anuja Rakshe'),
        ('68f0933c3b21c10023b43c53','Anandi'),
        ('68cbc4107c658400258ec779','Shirisha'),
        ('68e9ed9b7741a00024112833','Shirisha'),
        ('689c4aa1676ce70025cce490','Shirisha'),
        ('68c7e9568ca468002480139d','Shirisha'),
        ('68c7c529f28c890027d3056b','Shirisha'),
        ('6904617591057d0026c277f8','Shirisha'),
        ('68cd8ed638f83b0022abe380','Shirisha'),
        ('68d2555d1b31660025838b1b','Shirisha'),
        ('6903436e84fc62002596ca48','Shirisha'),
        ('6932cc09bb8a4400256cbee9','Shirisha'),
        ('692428ff6acf6300260a69f4','Shirisha'),
        ('68ff10b1b493840022be3e27','Shirisha'),
        ('691444a1dbd871002463edb9','Shirisha'),
        ('6924099ba3d0cf00275c25e4','Anuja Rakshe'),
        ('690996f0eaa4570025a87a39','Anuja Rakshe'),
        ('67d7adb97c83c6002510e798','Anuja Rakshe'),
        ('6868d118e680c3002539e662','Geethu'),
        ('6889dba074765e00221fa6d6','Geethu'),
        ('68b696eed684c00026d765a1','Geethu'),
        ('68bff2962639a90025dde9e2','Geethu'),
        ('68a42eb114f0c900254ae4d0','Geethu'),
        ('68b2852b90b02f002836d82a','Geethu'),
        ('693a7caaac9a1200266e6f0f','Geethu'),
        ('68772dfb8e68da002522b0bd','Geethu'),
        ('68e6285ad5736600237a6438','Geethu'),
        ('68c263bfe0b233002465ffc9','Geethu'),
        ('68a7fa4ce151440024ebb7dc','Geethu'),
        ('6874e7575977f10024c32971','Geethu'),
        ('68cba682f9888b0024b65d0d','Geethu'),
        ('69311e4ed7341d002bdcc947','Geethu'),
        ('68be98e8692d1d0024695f7d','Ambati'),
        ('68c1366244a3420026d5c456','Ambati'),
        ('68e3685fc596470023894da7','Ambati'),
        ('691d99d2898960002aa0826a','Ambati'),
        ('68a9801a5fea8d0026e2c876','Ambati'),
        ('68b550a8ff805700251e0f7f','Ambati'),
        ('690dcefbb6ed640023dc02fe','Ambati'),
        ('68da8e263414e80021595365','Ambati'),
        ('6901b6d1849b9d0025f37b23','Ambati'),
        ('68a80ea469d9a50026268c88','Ambati'),
        ('68b29381d2e7220026884b24','Ambati'),
        ('68cba0e3d4c09600247f7136','Ambati'),
        ('68afe399d40a6d00242aef76','Ambati'),
        ('68c3efc03cf4330024388861','Srujan'),
        ('6894674f55fa8a0025d16c26','Srujan'),
        ('68f9b70d77217e002456a3b2','Srujan'),
        ('68be8445ec068900244df3b8','Srujan'),
        ('693919402cb1d600228aa844','Srujan'),
        ('68d0fb9d2597f200281c3b48','Srujan'),
        ('68d5244ce2a56a00261532f8','Srujan'),
        ('68b0034024ea0f0025057008','Srujan'),
        ('68a83eb0a683c00022d9e2ff','Srujan'),
        ('6915a7c2307ffd0025ccb059','Srujan'),
        ('68747d7c3af0ed0025eb2bab','Srujan'),
        ('68df342747999b0025700678','Srujan'),
        ('68886e15c919f00023ae94bf','Srujan'),
        ('68b82f4e1b59780022e16266','Srujan'),
        ('68bfad7c24ca5e0027d61b36','Ambati'),
        ('68f71568423d05002759a650','Ambati'),
        ('68c12d0ac6c175002434a3f9','Ambati'),
        ('6921a19e63ce9f0026918065','Ambati'),
        ('68d421f774c43d0024f9b7ce','Ambati'),
        ('68998d6f193a750025b95c53','Ambati'),
        ('68bbd4dae2db73002a4b8c52','Ambati'),
        ('68e75b4511a28c00245bfb7e','Ambati'),
        ('687de24299d3d200277b6e3c','Ambati'),
        ('68f9798d2f40c9002795525c','Ambati'),
        ('68e77e2705bc1f0024b5fcd7','Ambati'),
        ('68e774cac89c5b002c60c7e8','Ambati'),
        ('689adbad48c3ec0025b26791','Ambati'),
        ('68c2c5514facbf0026aa3c07','Srujan'),
        ('69045fcf274e1100289e51ec','Srujan'),
        ('68c8fed2bddbb0002963991c','Srujan'),
        ('68e367a964f2b800280a7539','Srujan'),
        ('68c952c93719d100236c79a0','Srujan'),
        ('69294b62107add0027be6e39','Srujan'),
        ('69315062a71a940026cd4eca','Srujan'),
        ('6909deb5a7102c002527e00d','Geethu'),
        ('689db52416f80b002bbcccce','Geethu'),
        ('689db47a197c0400271f69f6','Geethu'),
        ('68d58826e2a56a00261ee153','Geethu'),
        ('68b2bd339630dc002970bf35','Geethu'),
        ('6874b5c60fdde80023df0fbc','Geethu'),
        ('6881b859c60cb10025521cd0','Geethu'),
        ('68e9eb378fa07400233bdb8b','Geethu'),
        ('68e6849574dd2700264e6f56','Geethu'),
        ('6889a00d4f8edc002249506b','Geethu'),
        ('69083fdf66bc0800245b27a0','Geethu'),
        ('69059493d01bce002dc85abb','Geethu'),
        ('693fc140345b6000245786d5','Geethu'),
        ('68e4be760746f9002636fe0f','Geethu'),
        ('686caf5bf0fab900237a0ced','Geethu'),
        ('68cd54860fddf100256dc520','Geethu'),
        ('689b2265b0bb5b002739fe5a','Geethu'),
        ('688c5a437b92900024594c97','Geethu'),
        ('692157abf4320a0024c22706','Anandi'),
        ('68ef679872c06600258e7372','Anandi'),
        ('691ff8dc3accf30027728f6f','Anandi'),
        ('690af44b91e9e000250a09a0','Anandi'),
        ('68e0d8d652e4bf0024129972','Anandi'),
        ('68d7a1a3ce75920024ef0ee6','Anandi'),
        ('693412075b43df0022d21d7f','Anandi'),
        ('685645fa9609de002699c780','Anandi'),
        ('68e8e8fe6a20f500226285f8','Shirisha'),
        ('686793d7cdb2160028c00f6e','Shirisha'),
        ('691ed8f2b5b52800263f3e08','Shirisha'),
        ('69242d629fb04000286e0d8c','Shirisha'),
        ('684cfde651a707002a477005','Shirisha'),
        ('68c932404db2be002879ea81','Shirisha'),
        ('686f5994f0e42300241c8eac','Shirisha'),
        ('685bb8a454d3ef0025ae8743','Shirisha'),
        ('68f0a520692f8400241567f0','Shirisha'),
        ('684ac3bc2fb79d0023d56ec0','Shirisha'),
        ('68e9e756a3f4c20023d62bc3','Shirisha'),
        ('68e39517ebb4450028132d63','Shirisha'),
        ('690864bb794654002ae83994','Shirisha'),
        ('68edecddab1c62002525fbba','Shirisha'),
        ('6878ce354d007900235b4393','Shirisha'),
        ('67e794ac9ac06400241a3e6d','Aditi'),
        ('684918c4617cd700235800ba','Aditi'),
        ('683bfad681025d0027478dc5','Aditi'),
        ('683d388f7a25630027b3623b','Aditi'),
        ('692e780d7cad1b00275c5751','Aditi'),
        ('692430660f337400286d9d8a','Aditi'),
        ('684932e1f5b98500228f60bf','Aditi'),
        ('68ef369687da43002531072a','Aditi'),
        ('68a19d753686170024307915','Aditi'),
        ('6864eaeb147c350025983ec4','Aditi'),
        ('692acd9dfd4e6a0025c9aa2d','Aditi'),
        ('690893a38a649200231a1c18','Aditi'),
        ('692aaae513dbc20029a168a8','Aditi'),
        ('68428b680f851300295c9d22','Aditi'),
        ('683aa04c739ddd0029e11be3','Swati'),
        ('691c6151514f650027f6608d','Swati'),
        ('683ee7b09738670022018194','Swati'),
        ('68d62b5c64ea0100238095a7','Swati'),
        ('6851224cf7e7320024942ace','Swati'),
        ('686cc108a30db10023e6c65d','Swati'),
        ('68da78a5797f330025b8f5d4','Swati'),
        ('68e9eedcb8ca410025ecc40b','Swati'),
        ('6440aa739646b00025e396bc','Swati'),
        ('6821c54e63e72d00241ed1bd','Swati'),
        ('684a5adb215db100259a6538','Swati'),
        ('694398b32d6f6e002349cf6f','Swati'),
        ('692d2323a2ef24002955c0ac','Swati'),
        ('6904624d2abdbb00221356d7','Neerav'),
        ('691acf42e797d800246da5d8','Neerav'),
        ('6870bb7a91b09a0021da61aa','Neerav'),
        ('6915b0aeb268bf0024b8a0d7','Neerav'),
        ('693a8582bb762200282b12d0','Neerav'),
        ('6875f09abe25af002961a79a','Neerav'),
        ('693276a652c4d300253c49e6','Neerav'),
        ('68d2323851730e00269cc38d','Neerav'),
        ('6926e36f4119de0025574c16','Neerav'),
        ('69118c2f25a09500263fda0e','Neerav'),
        ('684573858e4429002425443d','Neerav'),
        ('693f851872d2c90023fe21c8','Naina'),
        ('68d234ba7bcb230022a9df66','Naina'),
        ('68aff88312984e002313b531','Naina'),
        ('68d3be9366990300264efac3','Naina'),
        ('692537f506986c0022374c86','Naina'),
        ('68d23ca37ba9d50023e4bc82','Naina'),
        ('68c2664bfd65bd00288ae0f4','Naina'),
        ('68c8f1babe1eec002ba0f39e','Naina'),
        ('682c434679161300256fbddc','Naina'),
        ('68830eecdde51e00222d9b05','Naina'),
        ('68d26b34908b240028e467fc','Naina'),
        ('68cbd55aa4d8f60027e6421c','Naina'),
        ('68da23675b480b002561d6bb','Naina'),
        ('6856472e04fa8d00243925b4','Naina'),
        ('69208f5fabfab400237413f6','Nisha Singh'),
        ('68e35d5fca0ebf0023ac93a0','Nisha Singh'),
        ('690442f7dfcab5002d59f5e7','Nisha Singh'),
        ('688a08c5fd575b002b09970f','Nisha Singh'),
        ('69393fcb30bb3a00241bbba7','Nisha Singh'),
        ('68d110346f1b4a00236437d2','Nisha Singh'),
        ('69318b0fd9f0e4002450a1f9','Nisha Singh'),
        ('6864f1fe502c7800238b00a9','Nisha Singh'),
        ('690ebf1f7c4cb600258d1218','Nisha Singh'),
        ('69213c2ebca05800268553d8','Nisha Singh'),
        ('6864a9f68dcb5500261dfe2c','Nisha Singh'),
        ('693bdd2a638ee3002523ea44','Nisha Singh'),
        ('68b923018150a20026f206d6','Nisha Singh'),
        ('6895c42aba8c930025c98bc7','Nisha Singh'),
        ('6932da9e7b05cc00248a9ee5','Tarique Neshat'),
        ('68d4f7098eacdb0027995a71','Tarique Neshat'),
        ('68da18b90b01cc0024fb8a5d','Tarique Neshat'),
        ('68e20db80977710029ef1c08','Tarique Neshat'),
        ('68df91b1903fad0025014204','Tarique Neshat'),
        ('694b9c274022e20025105da4','Tarique Neshat'),
        ('693006bcf29836002508f196','Tarique Neshat'),
        ('68e4bdbc60a8d80024dddd94','Tarique Neshat'),
        ('686399622d079e00286d274d','Tarique Neshat'),
        ('685f9fa86711260021297768','Tarique Neshat'),
        ('69005362d4742f0022cd6f9b','Tarique Neshat'),
        ('6868a1c37b07fe0029dc9947','Tarique Neshat'),
        ('6926e5f00fbb15002d0ccadf','Tarique Neshat'),
        ('68380841cb713300275b9129','Tarique Neshat'),
        ('692d48d052f3600023741c7f','Tarique Neshat'),
        ('68ede715586f0b002656a3f3','Tarique Neshat'),
        ('6909884f0f5d2d0022a8e255','Tarique Neshat')
),

-- PAF and Leaves data
paf_leaves AS (
    SELECT
        provider_id,
        paf,
        leaves
    FROM (
        SELECT
            provider_id,
            paf_cancellation_at_tier AS paf,
            graded_leave_days_at_tier AS leaves,
            ROW_NUMBER() OVER (
                PARTITION BY provider_id
                ORDER BY tier_start_date DESC
            ) AS rn
        FROM provider_promise_plan__daily__metrics
    ) t
    WHERE rn = 1
),

-- L7D Working status for late show percentage
l7d AS (
    SELECT
        provider_id,
        CASE
            WHEN SUM(CASE WHEN status = 'marked working' THEN 1 ELSE 0 END) > 8
                THEN 1
            ELSE 0
        END AS is_working
    FROM public.providerXdateXhour__calendar_marking__hourly__facts
    WHERE start_hour_local BETWEEN 8 AND 19
    GROUP BY provider_id
),

-- =====================================================
-- L50 RATING LOGIC (BEFORE 2026-01-19)
-- Ranked ratings: last 50 ratings per provider
-- =====================================================
ranked_ratings AS (
    SELECT
        provider_id,
        rating,
        DATE_TRUNC('WEEK', BDATE) AS week,
        ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY bdate DESC) AS rating_rank
    FROM public.MASTER_DATA_EXPLORE_TABLE
    WHERE rating IS NOT NULL 
      AND service_delivered = 1
),

-- Average of last 50 ratings per provider per week (for weeks before 2026-01-19)
avg_rating_last_50 AS (
    SELECT
        provider_id,
        week,
        ROUND(SUM(rating) / NULLIF(COUNT(rating), 0), 2) AS avg_rating_l50
    FROM ranked_ratings
    WHERE rating_rank <= 50
    GROUP BY provider_id, week
),

-- =====================================================
-- WEEKLY RATING LOGIC (FROM 2026-01-19 ONWARDS)
-- Rating received in that week: total_rating / count(distinct customer_request_id)
-- where service_delivered = 1 and rating is not null
-- =====================================================
weekly_rating AS (
    SELECT
        provider_id,
        DATE_TRUNC('WEEK', BDATE) AS week,
        ROUND(
            SUM(rating) / NULLIF(COUNT(DISTINCT CASE 
                WHEN service_delivered = 1 AND rating IS NOT NULL 
                THEN customer_request_id 
            END), 0), 
        2) AS avg_rating_weekly
    FROM public.MASTER_DATA_EXPLORE_TABLE
    WHERE rating IS NOT NULL 
      AND service_delivered = 1
    GROUP BY provider_id, DATE_TRUNC('WEEK', BDATE)
),

-- =====================================================
-- COMBINED RATING LOGIC
-- Use L50 for weeks before 2026-01-19
-- Use Weekly rating for weeks from 2026-01-19 onwards
-- =====================================================
combined_rating AS (
    SELECT
        COALESCE(l50.provider_id, wr.provider_id) AS provider_id,
        COALESCE(l50.week, wr.week) AS week,
        CASE 
            -- From 19th January 2026 (week starting 2026-01-19), use weekly rating
            WHEN COALESCE(l50.week, wr.week) >= DATE_TRUNC('WEEK', DATE '2026-01-19')
                THEN wr.avg_rating_weekly
            -- Before 19th January 2026, use L50 rating
            ELSE l50.avg_rating_l50
        END AS avg_l50_rating
    FROM avg_rating_last_50 l50
    FULL OUTER JOIN weekly_rating wr 
        ON l50.provider_id = wr.provider_id 
        AND l50.week = wr.week
),

-- Base query joining all components
base AS (
    SELECT
        mm.trainer_name,
        mm.provider_id,
        cr.week,
        cr.avg_l50_rating,
        pl.paf,
        pl.leaves,
        l7d.is_working
    FROM manual_mapping mm
    LEFT JOIN paf_leaves pl
        ON mm.provider_id = pl.provider_id
    LEFT JOIN l7d
        ON mm.provider_id = l7d.provider_id
    LEFT JOIN combined_rating cr 
        ON mm.provider_id = cr.provider_id
)

-- Final Output: trainer name, total partners, l50_avg_rating, paf, leaves, late_show_pct
SELECT
    trainer_name AS trainer,
    week AS "week::multi-filter",
    COUNT(DISTINCT provider_id) AS total_partners,
    ROUND(AVG(avg_l50_rating), 2) AS l50_avg_rating,
    ROUND(
        COUNT(DISTINCT CASE WHEN paf > 0 THEN provider_id END)
        / NULLIF(COUNT(DISTINCT provider_id), 0),
    2) AS paf_pct,
    ROUND(AVG(leaves), 2) AS avg_leaves,
    ROUND(
        COUNT(DISTINCT CASE WHEN is_working = 1 THEN provider_id END)
        / NULLIF(COUNT(DISTINCT provider_id), 0),
    2) AS late_show_pct
FROM base
WHERE week IS NOT NULL
GROUP BY 1, 2
ORDER BY trainer_name, week;
