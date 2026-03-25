/*
  Churn Pros Count Metrics — Insta Help (Mumbai & Bangalore)

  Churn definition:
    A partner (pro) who DELIVERED in the previous week but did NOT deliver
    in the current week is counted as "churned" in the current week.

    Example: delivered in the week of March 16 but not in the week of
    March 23 → churned in the March 23 week.

  State machine per provider-week:
    active   = delivered prev week AND delivered this week
    churn    = delivered prev week AND did NOT deliver this week
    reactive = did NOT deliver prev week, but delivered before that,
               AND delivered this week (came back)
    no_delivery_churn = approved but never delivered at all

  Reactivation tracking:
    For every churn event we find the first subsequent "reactive" week
    and flag whether reactivation happened within 15 d, 30 d, or ever.
*/

WITH clusters AS (
  SELECT * FROM VALUES
    ('kandivali w jaswanti gold_city_mumbai_v2_insta_maids','Kandivali'),
    ('borivali w the nail deck_city_mumbai_v2_insta_maids','Borivali'),
    ('andheri e triveni chs_city_mumbai_v2_insta_maids','Andheri East'),
    ('kandivali w kesar aashish_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w panchshil apartments_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w solitaire paradise_city_mumbai_v2_insta_maids','Kandivali'),
    ('malad w unity apartments_city_mumbai_v2_insta_maids','Malad'),
    ('kandivali w madhupuri apartment_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e acme oasis_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e whisper palms_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e orchid tower_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e shankar enclave_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e suncity tower_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e dheeraj enclave_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e evershine milenium_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e shivalik tower_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e oberoi gardens_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e ekta meadows_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e vasant sagar_city_mumbai_v2_insta_maids','Kandivali'),
    ('chembur bhakti park_city_mumbai_v2_insta_maids','Wadala'),
    ('malad w rustomjee elanza_city_mumbai_v2_insta_maids','Malad'),
    ('andheri w lotus grandeur_city_mumbai_v2_insta_maids','Andheri West'),
    ('malad velentine apartment_city_mumbai_v2_insta_maids','Malad'),
    ('malad omkar alta monte_city_mumbai_v2_insta_maids','Malad'),
    ('malad w mittal homes_city_mumbai_v2_insta_maids','Malad'),
    ('gokuldham ivy tower_city_mumbai_v2_insta_maids','Goregaon'),
    ('malad w kalpataru yugdharma_city_mumbai_v2_insta_maids','Malad'),
    ('dahisar norhern lights_city_mumbai_v2_insta_maids','Mira Road'),
    ('malad w blue horizon_city_mumbai_v2_insta_maids','Malad'),
    ('borivali w utopian garden_city_mumbai_v2_insta_maids','Borivali'),
    ('mira bhayander jp north_city_mumbai_v2_insta_maids','Mira Road'),
    ('kandivali w dosti oro_city_mumbai_v2_insta_maids','Kandivali'),
    ('mira road aaradhya high park_city_mumbai_v2_insta_maids','Mira Road'),
    ('dahisar e chandak nishchay_city_mumbai_v2_insta_maids','Mira Road'),
    ('borivali w paradise heights_city_mumbai_v2_insta_maids','Borivali'),
    ('kandiwali w sunrise charkop_city_mumbai_v2_insta_maids','Kandivali'),
    ('malad w bhoomi park_city_mumbai_v2_insta_maids','Malad'),
    ('byculla planet godrej_city_mumbai_v2_insta_maids','SOBO'),
    ('malad w marina enclave_city_mumbai_v2_insta_maids','Malad'),
    ('cuff parade jolly maker_city_mumbai_v2_insta_maids','SOBO'),
    ('kandivali w ruparel elara_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w hiranandani_city_mumbai_v2_insta_maids','Kandivali'),
    ('jogeshwari lodha florenza_city_mumbai_v2_insta_maids','Andheri East'),
    ('vidyavihar neelkanth_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('worli parimal house_city_mumbai_v2_insta_maids','SOBO'),
    ('marol kanakia rainforest_city_mumbai_v2_insta_maids','Andheri East'),
    ('parel lodha kiara_city_mumbai_v2_insta_maids','Parel'),
    ('cuff parade cusrow baug_city_mumbai_v2_insta_maids','SOBO'),
    ('prabhadevi chaitanya tower_city_mumbai_v2_insta_maids','SOBO'),
    ('byculla laxmi residency_city_mumbai_v2_insta_maids','SOBO'),
    ('worli merryland_city_mumbai_v2_insta_maids','SOBO'),
    ('worli indiabulls blue_city_mumbai_v2_insta_maids','SOBO'),
    ('parel lodha world one_city_mumbai_v2_insta_maids','Parel'),
    ('parel century mill_city_mumbai_v2_insta_maids','Parel'),
    ('andheri e kanakia wallstreet_city_mumbai_v2_insta_maids','Andheri East'),
    ('wadala icc island city centrer_city_mumbai_v2_insta_maids','Wadala'),
    ('wadala l&t crescent_city_mumbai_v2_insta_maids','Wadala'),
    ('andheri w atlantis_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w kabra metro_city_mumbai_v2_insta_maids','Andheri West'),
    ('juhu imperial regency_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('juhu kabra premier_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('andheri w rustomjee elements_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w samudra darshan_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w pancham society_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri e mahindra vivante_city_mumbai_v2_insta_maids','Andheri East'),
    ('kalina insignia_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bkc kanakia paris_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('sakinaka akruti orchid_city_mumbai_v2_insta_maids','Andheri East'),
    ('marol kanakia seven_city_mumbai_v2_insta_maids','Andheri East'),
    ('kamothe mansarovar complex_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar adhiraj aqua_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul seawoods darave_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul nilgiri garden_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vikhroli e godrej platinum_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('ghatkopar mahindra park_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('kurla omkar meridian_city_mumbai_v2_insta_maids','Chembur'),
    ('thane parimal vaikunth_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane highland gardens_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane kalpataru paramount_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('chembur tilak nagar_city_mumbai_v2_insta_maids','Chembur'),
    ('mulund heritage apt_city_mumbai_v2_insta_maids','Mulund'),
    ('mulund lok everest chs_city_mumbai_v2_insta_maids','Mulund'),
    ('bhandup sunshine sra_city_mumbai_v2_insta_maids','Bhandup'),
    ('chembur augustus_city_mumbai_v2_insta_maids','Chembur'),
    ('vasant oasis_city_mumbai_v2_insta_maids','Andheri East'),
    ('marol ashok vihar_city_mumbai_v2_insta_maids','Andheri East'),
    ('nahar shapoorji vicinia_city_mumbai_v2_insta_maids','Powai'),
    ('oberoi splendor buildings_city_mumbai_v2_insta_maids','Andheri East'),
    ('nahar amrit buildings_city_mumbai_v2_insta_maids','Powai'),
    ('mulund runwal greens_city_mumbai_v2_insta_maids','Mulund'),
    ('powai l&t emerald isle_city_mumbai_v2_insta_maids','Powai'),
    ('jogeshwari kalpataru estate_city_mumbai_v2_insta_maids','Andheri East'),
    ('ghatkopar kalpataru aura_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('bhandup runwal forest_city_mumbai_v2_insta_maids','Bhandup'),
    ('thane lodha amara_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('jogeshwari whitefield_city_mumbai_v2_insta_maids','Andheri East'),
    ('mulund senroofs_city_mumbai_v2_insta_maids','Mulund'),
    ('mulund runwal anthurium_city_mumbai_v2_insta_maids','Mulund'),
    ('andheri w raheja classique_city_mumbai_v2_insta_maids','Andheri West'),
    ('mulund w oberoi eternia_city_mumbai_v2_insta_maids','Mulund'),
    ('andheri western heights_city_mumbai_v2_insta_maids','Andheri West'),
    ('kanjurmarg lodha aurum_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('kanjurmarg runwal bliss_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('ghatkopar godrej one_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('thane kalpataru sunrise_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane dosti_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane pride palms_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane lodha luxuria_city_mumbai_v2_insta_maids','Thane-Majiwada'),
    ('andheri w beverly hills_city_mumbai_v2_insta_maids','Andheri West'),
    ('thane lodha paradise_city_mumbai_v2_insta_maids','Thane-Majiwada'),
    ('thane lodha grande_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('thane rustomjee azziano_city_mumbai_v2_insta_maids','Thane-Majiwada'),
    ('andheri dlh darpan_city_mumbai_v2_insta_maids','Andheri West'),
    ('powai raheja vihar_city_mumbai_v2_insta_maids','Powai'),
    ('thane everest tulip_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('andheri w windsor_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w tarapore_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w highland park_city_mumbai_v2_insta_maids','Andheri West'),
    ('versova bianca_city_mumbai_v2_insta_maids','Andheri West'),
    ('versova amarnath_city_mumbai_v2_insta_maids','Andheri West'),
    ('bhandup dreams_city_mumbai_v2_insta_maids','Bhandup'),
    ('thane runwal pearl_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('mulund nirmal lifestyle_city_mumbai_v2_insta_maids','Mulund'),
    ('hiranandani rodas_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('hiranandani chesterton_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('hiranandani one_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane neelkanth_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('powai glen atlantis_city_mumbai_v2_insta_maids','Powai'),
    ('bhandup kalpataru crest_city_mumbai_v2_insta_maids','Bhandup'),
    ('mulund golden willows_city_mumbai_v2_insta_maids','Mulund'),
    ('thane dosti vihar_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane raymond ten x_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane vasant lawns_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane hiranandani meadows_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('thane oakwood_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('hiranandani bhoomi acres_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('hiranandani jangid galaxy_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('hiranandani ace aviana_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('hiranandani regency tower_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane godbunder lodha splendora_city_mumbai_v2_insta_maids','Thane- Lodha Splendora'),
    ('thane siddhanchal housing_city_mumbai_v2_insta_maids','Old Thane'),
    ('goregon w imperial heights_city_mumbai_v2_insta_maids','Goregaon'),
    ('goregaon w vasant galaxy_city_mumbai_v2_insta_maids','Goregaon'),
    ('chembur godrej central_city_mumbai_v2_insta_maids','Chembur'),
    ('goregaon w kalpataru radiance_city_mumbai_v2_insta_maids','Goregaon'),
    ('goregaon w galaxy heights_city_mumbai_v2_insta_maids','Goregaon'),
    ('gokuldham oberoi woods_city_mumbai_v2_insta_maids','Goregaon'),
    ('chembur altavista_city_mumbai_v2_insta_maids','Chembur'),
    ('gokuldham db woods_city_mumbai_v2_insta_maids','Goregaon'),
    ('gokuldham satellite royale_city_mumbai_v2_insta_maids','Goregaon'),
    ('bkc rustomjee oriano_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('thane haware city_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('wadala lodha supremum_city_mumbai_v2_insta_maids','Wadala'),
    ('wadala dosti ambrosia_city_mumbai_v2_insta_maids','Wadala'),
    ('hiranandani eden woods thane_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('lokhandwala movie tower_city_mumbai_v2_insta_maids','Andheri West'),
    ('lokhandwala oberoi sky garden_city_mumbai_v2_insta_maids','Andheri West'),
    ('goregaon w anmol fortune_city_mumbai_v2_insta_maids','Goregaon'),
    ('goregaon w mahindra gardens_city_mumbai_v2_insta_maids','Goregaon'),
    ('malad w interface heights_city_mumbai_v2_insta_maids','Malad'),
    ('malad w auris serenity_city_mumbai_v2_insta_maids','Malad'),
    ('malad w evershine_city_mumbai_v2_insta_maids','Malad'),
    ('goregaon w sunder nagar_city_mumbai_v2_insta_maids','Goregaon'),
    ('goregaon w dheeraj diamond_city_mumbai_v2_insta_maids','Goregaon'),
    ('malad w vastu tower_city_mumbai_v2_insta_maids','Malad'),
    ('malad w lotus sky garden_city_mumbai_v2_insta_maids','Malad'),
    ('malad w adarsh heights_city_mumbai_v2_insta_maids','Malad'),
    ('malad w an appartment_city_mumbai_v2_insta_maids','Malad'),
    ('malad e the park residence_city_mumbai_v2_insta_maids','Malad'),
    ('chembur nehru nagar_city_mumbai_v2_insta_maids','Chembur'),
    ('chembur trishabh greens_city_mumbai_v2_insta_maids','Chembur'),
    ('chembur runwal grandeur_city_mumbai_v2_insta_maids','Chembur'),
    ('chembur rna continental_city_mumbai_v2_insta_maids','Chembur'),
    ('chembur gnga tower_city_mumbai_v2_insta_maids','Chembur'),
    ('chembur maitri park_city_mumbai_v2_insta_maids','Chembur'),
    ('bkc signature island_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('kalina silver square_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('ghatkopar e yash park_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('kurla kohinoor city_city_mumbai_v2_insta_maids','Chembur'),
    ('ghatkopar e avdhan epitome_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('oshiwara ornate tower_city_mumbai_v2_insta_maids','Andheri West'),
    ('goregaon w rna exotica_city_mumbai_v2_insta_maids','Goregaon'),
    ('andheri w lodha bel air_city_mumbai_v2_insta_maids','Andheri West'),
    ('kandivali e silver leaf_city_mumbai_v2_insta_maids','Kandivali'),
    ('bhandup lodha imperia_city_mumbai_v2_insta_maids','Bhandup'),
    ('vikhroli e agastya signature_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('mulund nagraj chs_city_mumbai_v2_insta_maids','Mulund'),
    ('ghatkopar w neelkanth niketan_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('thane siddachal elite_city_mumbai_v2_insta_maids','Old Thane'),
    ('bhandup lords_city_mumbai_v2_insta_maids','Bhandup'),
    ('sion e kalpatru royale_city_mumbai_v2_insta_maids','Chembur'),
    ('dadar e krishna kunj_city_mumbai_v2_insta_maids','Dadar'),
    ('dadar e amrut apartment_city_mumbai_v2_insta_maids','Dadar'),
    ('dadar e mont kiara_city_mumbai_v2_insta_maids','Dadar'),
    ('dadar e balaji tower_city_mumbai_v2_insta_maids','Dadar'),
    ('thane kores nakshtra_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane ashar metro towers_city_mumbai_v2_insta_maids','Old Thane'),
    ('mulund brighton towers_city_mumbai_v2_insta_maids','Mulund'),
    ('dadar e rustomjee gardens_city_mumbai_v2_insta_maids','Dadar'),
    ('chembur nellai apartments_city_mumbai_v2_insta_maids','Chembur'),
    ('mahalaxmi raheja vivarea_city_mumbai_v2_insta_maids','SOBO'),
    ('borivali w oberoi sky city_city_mumbai_v2_insta_maids','Borivali'),
    ('borivali e raheja estate_city_mumbai_v2_insta_maids','Borivali'),
    ('kandivali e gayatri avenue_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali e highway park chs_city_mumbai_v2_insta_maids','Kandivali'),
    ('thane hiranandani swastik enclave_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane hiranandani kabra galaxy_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane hiranandani caviana_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane hiranandani vasant leela_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('thane hiranandani prestige hillview_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('kandivali w jaydev tower_city_mumbai_v2_insta_maids','Kandivali'),
    ('dahisar w anand heritage_city_mumbai_v2_insta_maids','Mira Road'),
    ('borivali w fressia_city_mumbai_v2_insta_maids','Borivali'),
    ('borivali w club acquaria_city_mumbai_v2_insta_maids','Borivali'),
    ('borivali w akashdeep chs_city_mumbai_v2_insta_maids','Borivali'),
    ('andheri w seven bunglow_city_mumbai_v2_insta_maids','Andheri West'),
    ('borivali w saffron apartment_city_mumbai_v2_insta_maids','Borivali'),
    ('borivali w rustomjee reserve_city_mumbai_v2_insta_maids','Borivali'),
    ('andheri w gulmohar apt_city_mumbai_v2_insta_maids','Andheri West'),
    ('nerul galhot majestry_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('malad e radha nagar_city_mumbai_v2_insta_maids','Malad'),
    ('malad w pvr milap_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w dekho studio_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w mahavir nagar_city_mumbai_v2_insta_maids','Kandivali'),
    ('borivali e raj tarang chs_city_mumbai_v2_insta_maids','Borivali'),
    ('malad w nakshatra heights_city_mumbai_v2_insta_maids','Malad'),
    ('kandivali e rizvi towers_city_mumbai_v2_insta_maids','Kandivali'),
    ('goregaon e mansarovar society_city_mumbai_v2_insta_maids','Goregaon'),
    ('malad e royal crystal_city_mumbai_v2_insta_maids','Malad'),
    ('goregaon e dheeraj valley_city_mumbai_v2_insta_maids','Goregaon'),
    ('kandivali e sahyadri co-operative_city_mumbai_v2_insta_maids','Kandivali'),
    ('kandivali w vaswani vista_city_mumbai_v2_insta_maids','Kandivali'),
    ('borivali e nandan dham palace_city_mumbai_v2_insta_maids','Borivali'),
    ('kandivali w ashiana chs_city_mumbai_v2_insta_maids','Kandivali'),
    ('malad w kabra divine towers_city_mumbai_v2_insta_maids','Malad'),
    ('sewri dosti flamingo_city_mumbai_v2_insta_maids','SOBO'),
    ('malad mantri park_city_mumbai_v2_insta_maids','Malad'),
    ('kharghar sector 10_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 6_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('belapur sector 15_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 21_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 20_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 14_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar tharwani heights_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 13_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('mahalaxmi lodha bellissimo_city_mumbai_v2_insta_maids','SOBO'),
    ('nerul seawoods estates_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul yaytri apartment_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 35 sai solitaire_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar omkar heights_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 35 maple hills_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 34_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 27_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 19_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 11_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('seawoods sector 50 old_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sector 6 shiv shakti_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sector 6 palm residency_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('sanpada sector 13_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('sanpada khitij towers_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('sanpada sector 8 millennium towers_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vashi sector 17 nalanda university_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vashi sector 18_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('lake buildings_city_mumbai_v2_insta_maids','Powai'),
    ('hiranandani hospital buildings_city_mumbai_v2_insta_maids','Powai'),
    ('nerul sector 40_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('andheri e sher e punjab_city_mumbai_v2_insta_maids','Andheri East'),
    ('goregaon w govardhan giri_city_mumbai_v2_insta_maids','Goregaon'),
    ('thane hiranandani prestige valley_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('andheri e pearl heaven_city_mumbai_v2_insta_maids','Andheri East'),
    ('andheri e lodha enternis_city_mumbai_v2_insta_maids','Andheri East'),
    ('nerul sector 27_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sector 19_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sector 21_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sbi colony_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('belapur sector 11_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('bandra w sealite apartmentâ _city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w vintage pearl_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w palmera aprt_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w ariane apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w silver isle apts_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w silver clophil_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w blue diamond_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('santacruz w ajinkya apts_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('santacruz w aristo sapphire_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w sadhana apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w anupama heights_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('santacruz w krimson aurum_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w nivan apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('santacruz e silver square_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w pacific enclave_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w rajgruha_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w corner view_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w fortune crown_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('pali_hill sea croft_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('pali_hill continental towers_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('pali_hill vastu apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('pali_hill friendship apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('pali_hill samarpan_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w kekee manzil_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w raheja bey_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w united classic_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w peter apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w seabird_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('versova dhawani estate_city_mumbai_v2_insta_maids','Andheri West'),
    ('andheri w vinayak tower_city_mumbai_v2_insta_maids','Andheri West'),
    ('santacruz w kakad villa_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w samudra darshan_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('bandra w tulip_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w mohini heights_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w platinum aura_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('khar w anand bhavan_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('santacruz e shivganga chs_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('prabhadevi santrose apartments_city_mumbai_v2_insta_maids','SOBO'),
    ('prabhadevi silver dunes_city_mumbai_v2_insta_maids','SOBO'),
    ('parel falcon castle_city_mumbai_v2_insta_maids','Parel'),
    ('prabhadevi the mariano_city_mumbai_v2_insta_maids','SOBO'),
    ('mahim utpal park_city_mumbai_v2_insta_maids','SOBO'),
    ('mahim rizvi heights_city_mumbai_v2_insta_maids','SOBO'),
    ('mahim dluna apartment_city_mumbai_v2_insta_maids','SOBO'),
    ('mahim sinddhi sangat_city_mumbai_v2_insta_maids','SOBO'),
    ('mahim dsilva dell_city_mumbai_v2_insta_maids','SOBO'),
    ('lalbug lodha venezia_city_mumbai_v2_insta_maids','Parel'),
    ('dadar w sumit atulyam_city_mumbai_v2_insta_maids','Dadar'),
    ('dadar la sonrisa_city_mumbai_v2_insta_maids','Dadar'),
    ('worli viraj tiara_city_mumbai_v2_insta_maids','SOBO'),
    ('prabhadevi avarsekar shrushti_city_mumbai_v2_insta_maids','SOBO'),
    ('prabhadevi beaumonde towers_city_mumbai_v2_insta_maids','SOBO'),
    ('dadar w purushottam tomwer_city_mumbai_v2_insta_maids','Dadar'),
    ('cumballa_hill navroz apartment_city_mumbai_v2_insta_maids','SOBO'),
    ('cumballa_hill ajanta apartment_city_mumbai_v2_insta_maids','SOBO'),
    ('cumballa_hill sky scraper_city_mumbai_v2_insta_maids','SOBO'),
    ('santacruz e parvati apartment_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('malabar_hill poornanad chs_city_mumbai_v2_insta_maids','SOBO'),
    ('malabar_hill jeevan vihar_city_mumbai_v2_insta_maids','SOBO'),
    ('malabar_hill avanti apartments_city_mumbai_v2_insta_maids','SOBO'),
    ('malabar_hill the residence_city_mumbai_v2_insta_maids','SOBO'),
    ('ghansoli satyam heights_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul mohan palms_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('juhu raheja haven_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('juhu gymkhana_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('andheri e atharv aaradhyam_city_mumbai_v2_insta_maids','Andheri East'),
    ('andheri e omkar darshan_city_mumbai_v2_insta_maids','Andheri East'),
    ('andheri e vaastu siddhi_city_mumbai_v2_insta_maids','Andheri East'),
    ('chembur krishna heights_city_mumbai_v2_insta_maids','Chembur'),
    ('santacruz w maker kundan gardens_city_mumbai_v2_insta_maids','Bandra-Santacruz'),
    ('malabar_hill palazzo_city_mumbai_v2_insta_maids','SOBO'),
    ('malabar_hill gitanjali gardens_city_mumbai_v2_insta_maids','SOBO'),
    ('cumballa_hill 9a residences_city_mumbai_v2_insta_maids','SOBO'),
    ('ghansoli sector 7_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kopar khairane sector 11_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kopar khairane sector 14_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('malad e raheja heights_city_mumbai_v2_insta_maids','Malad'),
    ('airoli sector 8_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('thane highland park_city_mumbai_v2_insta_maids','Thane-Kolshet'),
    ('parel one avighna park_city_mumbai_v2_insta_maids','Parel'),
    ('chembur runwal hills_city_mumbai_v2_insta_maids','Chembur'),
    ('vashi sector 28_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul regency palms_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vashi neel sidi towers_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('airoli sector 18_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar sector 18_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kharghar swarnapurti_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('kalwa greenworld_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane thane_one_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('thane tata glendale_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('thane lotus upvan_city_mumbai_v2_insta_maids','Old Thane'),
    ('kalwa evergreen heights_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w larkins 315_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w ananda villa chs_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w indrapuri chs_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w giriraj heightsâ _city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w kapila vastu_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w sheth zuri_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w happy valley_city_mumbai_v2_insta_maids','Thane-Manpada'),
    ('thane w auralis apartment_city_mumbai_v2_insta_maids','Old Thane'),
    ('malabar_hill tytan_city_mumbai_v2_insta_maids','SOBO'),
    ('altamount_road lincoln lodge_city_mumbai_v2_insta_maids','SOBO'),
    ('ghansoli aurum q park_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('mulund runwal heights_city_mumbai_v2_insta_maids','Mulund'),
    ('andheri w nalanda_city_mumbai_v2_insta_maids','Andheri West'),
    ('thane w shravan building_city_mumbai_v2_insta_maids','Old Thane'),
    ('marol hill view_city_mumbai_v2_insta_maids','Andheri East'),
    ('marol police camp_city_mumbai_v2_insta_maids','Andheri East'),
    ('powai suncity_city_mumbai_v2_insta_maids','Powai'),
    ('powai lodha supremus_city_mumbai_v2_insta_maids','Powai'),
    ('hiranandani vijay garden_city_mumbai_v2_insta_maids','Thane-Hiranandani'),
    ('mulund neelkanth heights_city_mumbai_v2_insta_maids','Mulund'),
    ('mulund ranjit society_city_mumbai_v2_insta_maids','Mulund'),
    ('mulund prestige hillview_city_mumbai_v2_insta_maids','Mulund'),
    ('bhandup paranjape garden_city_mumbai_v2_insta_maids','Bhandup'),
    ('powai l&t elixir reserve_city_mumbai_v2_insta_maids','Powai'),
    ('bhandup panchmukhi_city_mumbai_v2_insta_maids','Bhandup'),
    ('thane vihang shantivan_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane golden park complex_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane new hill view_city_mumbai_v2_insta_maids','Thane-Majiwada'),
    ('vashi loksagar chs_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vashi marina bay_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('vashi rohini chs_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('nerul sector 25_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('marol rajkaml hiltop chs_city_mumbai_v2_insta_maids','Andheri East'),
    ('ghatkopar dipak kunj_city_mumbai_v2_insta_maids','Ghatkopar'),
    ('powai rambug_city_mumbai_v2_insta_maids','Powai'),
    ('nerul saidham chs_city_mumbai_v2_insta_maids','Navi mumbai'),
    ('lalbug magnum tower_city_mumbai_v2_insta_maids','Parel'),
    ('mulund mahavir galaxy_city_mumbai_v2_insta_maids','Mulund'),
    ('vikhroli e swastik platinum_city_mumbai_v2_insta_maids','Kanjurmarg'),
    ('hiranandani vihang woods_city_mumbai_v2_insta_maids','Thane- Lodha Splendora'),
    ('dombivali lodhaâ majestic_city_mumbai_v2_insta_maids','Thane - Palava'),
    ('hiranandani puranik city_city_mumbai_v2_insta_maids','Thane- Lodha Splendora'),
    ('dombivali palava casabella_city_mumbai_v2_insta_maids','Thane - Palava'),
    ('hiranandani pristine tower_city_mumbai_v2_insta_maids','Thane- Lodha Splendora'),
    ('thane w dhanashree chs_city_mumbai_v2_insta_maids','Old Thane'),
    ('thane w raheja gardens_city_mumbai_v2_insta_maids','Old Thane'),
    ('andheri w runwal elegante_city_mumbai_v2_insta_maids','Andheri West'),
    ('cuff marine drive_city_mumbai_v2_insta_maids','SOBO'),
    ('banashankari_padmanabhanagar_city_bangalore_v2_insta_maids','Banashankari'),
    ('banashankari_prestige_south_ridge_city_bangalore_v2_insta_maids','Banashankari'),
    ('bharath_nagar_stage_1_city_bangalore_v2_insta_maids','Naagarabhaavi'),
    ('bikasipura_gopalan_jewels_city_bangalore_v2_insta_maids','Vasanthapura'),
    ('binnipete_shapoorji_pallonji_parkwest_city_bangalore_v2_insta_maids','Vijayanagar'),
    ('cholurpalya_gopal_residency_city_bangalore_v2_insta_maids','Vijayanagar'),
    ('jp_nagar_8th_phase_tirumala_ambience_city_bangalore_v2_insta_maids','Vasanthapura'),
    ('jp_nagar_greenline_apartments_city_bangalore_v2_insta_maids','Vasanthapura'),
    ('kanakpura_road_mantri_tranquil_city_bangalore_v2_insta_maids','Vasanthapura'),
    ('kengeri_supreme_sapphire_city_bangalore_v2_insta_maids','Hosakerehalli'),
    ('konanakunte_cross_falcon_city_city_bangalore_v2_insta_maids','Vasanthapura'),
    ('nagarbhavi_ds_max_senorita_city_bangalore_v2_insta_maids','Naagarabhaavi'),
    ('rr_nagar_sattva_divinity_city_bangalore_v2_insta_maids','Hosakerehalli'),
    ('satellite_town_bda_indraprastha_city_bangalore_v2_insta_maids','Hosakerehalli'),
    ('uttarahalli_chartered_madhura_city_bangalore_v2_insta_maids','Banashankari'),
    ('uttarahalli_ds_max_savera_city_bangalore_v2_insta_maids','Banashankari'),
    ('adugodi_koramangala_8th_block_city_bangalore_v2_insta_maids','Tavarekere'),
    ('akshaya_nagar_dlf_westend_heights_city_bangalore_v2_insta_maids','Hongasandra'),
    ('akshaya_nagar_house_of_hiranandani_city_bangalore_v2_insta_maids','Arekere'),
    ('akshaya_nagar_prabhavathi_residency_city_bangalore_v2_insta_maids','Hongasandra'),
    ('akshayanagar_mahaveer_rhythm_city_bangalore_v2_insta_maids','Arekere'),
    ('anjanapura_mangalya_prosper_city_bangalore_v2_insta_maids','Avalahalii'),
    ('anjanapura_road_80ft_road_city_bangalore_v2_insta_maids','Avalahalii'),
    ('arekere_mahaveer_rhyolite_city_bangalore_v2_insta_maids','Arekere'),
    ('arekere_ms_royal_apartments_city_bangalore_v2_insta_maids','Arekere'),
    ('arekere_sarvabhoumanagar_city_bangalore_v2_insta_maids','Arekere'),
    ('banneraghatta_prestige_park_square_city_bangalore_v2_insta_maids','Avalahalii'),
    ('basapura_concorde_midway_city_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('begur_aashrayaa_eternia_city_bangalore_v2_insta_maids','Hongasandra'),
    ('begur_aratt_vivera_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('begur_jahnavi_nivas_city_bangalore_v2_insta_maids','Hulimavu'),
    ('begur_windsor_troika_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('bilekahalli_ranka_colony_city_bangalore_v2_insta_maids','BTM Layout'),
    ('bilekahalli_sumukha_tropical_garden_city_bangalore_v2_insta_maids','BTM Layout'),
    ('bilekahalli_vijaya_enclave_city_bangalore_v2_insta_maids','Hongasandra'),
    ('bommanahalli_mahaveer_marvel_city_bangalore_v2_insta_maids','Hongasandra'),
    ('bommanahalli_roopena_agrahara_city_bangalore_v2_insta_maids','Hongasandra'),
    ('bommanahalli_snn_raj_grandeur_city_bangalore_v2_insta_maids','Hongasandra'),
    ('bommanhalli_salarpuria_greenage_city_bangalore_v2_insta_maids','Hongasandra'),
    ('bommasandra_mahendra_apartments_city_bangalore_v2_insta_maids','Thirupalya'),
    ('btm_1st_stage_keb_colony_city_bangalore_v2_insta_maids','Tavarekere'),
    ('btm_1st_stage_krishna_prakash_apt_city_bangalore_v2_insta_maids','Tavarekere'),
    ('btm_2nd_stage_city_bangalore_v2_insta_maids','BTM Layout'),
    ('btm_layout_4th_main_road_city_bangalore_v2_insta_maids','BTM Layout'),
    ('btm_layout_kuvempu_nagar_city_bangalore_v2_insta_maids','BTM Layout'),
    ('btm_layout_mantri_elegance_city_bangalore_v2_insta_maids','BTM Layout'),
    ('btm_layout_ram_sridhar_apartments_city_bangalore_v2_insta_maids','BTM Layout'),
    ('carmelaram_arcadia_apartments_city_bangalore_v2_insta_maids','Silicon Town'),
    ('carmelaram_dsr_parkway_city_bangalore_v2_insta_maids','Silicon Town'),
    ('chikkabellandur_windchimes_apartments_city_bangalore_v2_insta_maids','Silicon Town'),
    ('choodasandraa_mahaveer_ranches_city_bangalore_v2_insta_maids','Choodasandra'),
    ('devarachikkanahalli_mbr_steeple_city_bangalore_v2_insta_maids','Hongasandra'),
    ('devarachikkanahalli_sapthagiri_splendor_city_bangalore_v2_insta_maids','Arekere'),
    ('ecity_ajmera_infinity_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_celebrity_signature_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('ecity_concorde_tech_turf_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_gm_infinity_phase_2_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_godrej_apartments_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('ecity_gopalan_lakefront_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_phase1_concorde_manhattans_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_phase1_smondoville_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_phase2_concorde_windrush_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_phase2_gpr_royale_city_bangalore_v2_insta_maids','Choodasandra'),
    ('ecity_phase2_prakruthi_solitaire_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_phase2_shriram_liberty_square_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_prestige_sunrise_wipro_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_ramky_karnival_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_shriram_summit_city_bangalore_v2_insta_maids','Thirupalya'),
    ('ecity_sjr_fiesta_city_bangalore_v2_insta_maids','Choodasandra'),
    ('ecity_snn_raj_greenbay_city_bangalore_v2_insta_maids','Choodasandra'),
    ('ejipura_kodandarama_temple_city_bangalore_v2_insta_maids','Tavarekere'),
    ('ejipura_sony_signal_city_bangalore_v2_insta_maids','Tavarekere'),
    ('gottigere_nandi_retreat_city_bangalore_v2_insta_maids','Hulimavu'),
    ('gottigere_nydhile_residency_city_bangalore_v2_insta_maids','Hulimavu'),
    ('haralur_dsr_ultima_city_bangalore_v2_insta_maids','Kudlu'),
    ('haralur_ozone_evergreens_city_bangalore_v2_insta_maids','Haralur'),
    ('haralur_prestige_ferns_residency_city_bangalore_v2_insta_maids','Haralur'),
    ('haralur_rbd_stillwaters_city_bangalore_v2_insta_maids','Haralur'),
    ('haralur_sjr_watermark_city_bangalore_v2_insta_maids','Haralur'),
    ('haralur_zonasha_elegance_city_bangalore_v2_insta_maids','Haralur'),
    ('hongasandra_individual_hh_city_bangalore_v2_insta_maids','Hongasandra'),
    ('hongasandra_metro_station_city_bangalore_v2_insta_maids','ITI Layout'),
    ('hongasandra_muneshwara_layout_city_bangalore_v2_insta_maids','Arekere'),
    ('hongasandra_slv_bhanu_classic_city_bangalore_v2_insta_maids','Hongasandra'),
    ('hosa_road_fern_blue_bells_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosa_road_gr_sankalpa_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosa_road_mahaveer_orchids_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosa_road_mana_tropicale_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosa_road_silicon_oasis_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosur_road_keerthi_royal_palms_city_bangalore_v2_insta_maids','Choodasandra'),
    ('hosur_road_krishna_mystiq_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('hsr_bda_complex_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_fernhill_gardens_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_iti_layout_city_bangalore_v2_insta_maids','ITI Layout'),
    ('hsr_mantri_sarovar_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_purva_fairmont_apartments_city_bangalore_v2_insta_maids','ITI Layout'),
    ('hsr_salarpuria_serenity_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_sector_1_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_sector_2_city_bangalore_v2_insta_maids','HSR'),
    ('hsr_sector_3_city_bangalore_v2_insta_maids','ITI Layout'),
    ('hsr_sobha_daffodil_city_bangalore_v2_insta_maids','Kudlu'),
    ('hsr_water_tank_city_bangalore_v2_insta_maids','HSR'),
    ('hulimavu_krishna_layout_city_bangalore_v2_insta_maids','Arekere'),
    ('hulimavu_nitesh_hyde_park_city_bangalore_v2_insta_maids','Hulimavu'),
    ('hulimavu_raja_aristos_city_bangalore_v2_insta_maids','Hulimavu'),
    ('hulimavu_walmark_apas_city_bangalore_v2_insta_maids','Arekere'),
    ('jakkasandra_extension_agara_lake_city_bangalore_v2_insta_maids','HSR'),
    ('jakkasandra_teachers_colony_city_bangalore_v2_insta_maids','HSR'),
    ('jayanagar_4th_t_block_east_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jayanagar_4th_t_block_oakyard_apartment_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jayanagar_shanthi_park_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jigani_dlf_woodland_heights_city_bangalore_v2_insta_maids','Thirupalya extension'),
    ('jp_nagar_2nd_phase_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jp_nagar_3rd_phase_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jp_nagar_4th_phase_dollars_colony_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jp_nagar_8th_phase_epitome_elan_city_bangalore_v2_insta_maids','Avalahalii'),
    ('jp_nagar_adarsh_rhythm_city_bangalore_v2_insta_maids','BTM Layout'),
    ('jp_nagar_hm_world_city_city_bangalore_v2_insta_maids','Avalahalii'),
    ('jp_nagar_platinum_lifestyle_city_bangalore_v2_insta_maids','Avalahalii'),
    ('junnasandra_keerthi_regalia_city_bangalore_v2_insta_maids','Junnasandra'),
    ('kammasandra_ecity_icon_happy_living_city_bangalore_v2_insta_maids','Thirupalya'),
    ('kasavanahalli_bren_imperia_city_bangalore_v2_insta_maids','Haralur'),
    ('kasavanahalli_klassic_landmark_city_bangalore_v2_insta_maids','Junnasandra'),
    ('kasavanahalli_oceanus_vista_city_bangalore_v2_insta_maids','Haralur'),
    ('kasavanahalli_sattva_signet_city_bangalore_v2_insta_maids','Junnasandra'),
    ('kasavanahalli_snn_raj_eternia_city_bangalore_v2_insta_maids','Choodasandra'),
    ('koramangala_3rd_4th_block_city_bangalore_v2_insta_maids','HSR'),
    ('koramangala_5th_6th_block_city_bangalore_v2_insta_maids','Tavarekere'),
    ('koramangala_ngv_godavari_block_city_bangalore_v2_insta_maids','Tavarekere'),
    ('koramangala_prestige_pinewood_city_bangalore_v2_insta_maids','HSR'),
    ('koramangala_prestige_st_johns_wood_city_bangalore_v2_insta_maids','Tavarekere'),
    ('kothnur_bagmane_hills_city_bangalore_v2_insta_maids','Avalahalii'),
    ('kothnur_himagiri_meadows_city_bangalore_v2_insta_maids','Hulimavu'),
    ('kothnur_purva_panorama_city_bangalore_v2_insta_maids','Hulimavu'),
    ('kudlu_aecs_layout_a_block_city_bangalore_v2_insta_maids','Kudlu'),
    ('kudlu_purva_skywood_city_bangalore_v2_insta_maids','Kudlu'),
    ('kudlu_purva_westend_city_bangalore_v2_insta_maids','ITI Layout'),
    ('kudlu_sai_poorna_luxuria_city_bangalore_v2_insta_maids','Kudlu'),
    ('kudlu_sai_poorna_premier_city_bangalore_v2_insta_maids','Kudlu'),
    ('kudlu_sumo_sonnet_city_bangalore_v2_insta_maids','Kudlu'),
    ('manipal_county_rd_sumadhura_anantham_city_bangalore_v2_insta_maids','Hongasandra'),
    ('rayasandra_sjr_hamilton_homes_city_bangalore_v2_insta_maids','Choodasandra'),
    ('rayasandra_sjr_parkway_homes_city_bangalore_v2_insta_maids','Choodasandra'),
    ('sarjapur_ahad_euphoria_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_assetz_degree_apartments_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_brigade_gem_city_bangalore_v2_insta_maids','Choodasandra'),
    ('sarjapur_confident_atik_apartments_city_bangalore_v2_insta_maids','Sarjapur extension'),
    ('sarjapur_ds_max_sprinkles_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_dsr_eden_gardens_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_mana_jardin_city_bangalore_v2_insta_maids','Junnasandra'),
    ('sarjapur_senorita_city_bangalore_v2_insta_maids','Junnasandra'),
    ('sarjapur_silicon_shine_apartments_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_sjr_plazza_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_sobha_royal_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_springfields_apartments_city_bangalore_v2_insta_maids','Haralur'),
    ('sarjapur_suncity_gloria_apartments_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_uber_verdant_city_bangalore_v2_insta_maids','Silicon Town'),
    ('sarjapur_wonderwall_apartments_city_bangalore_v2_insta_maids','Sarjapur extension'),
    ('singasandra_aecs_b_block_city_bangalore_v2_insta_maids','Hongasandra'),
    ('singasandra_aecs_layout_city_bangalore_v2_insta_maids','Kudlu'),
    ('singasandra_tirumala_sarovar_city_bangalore_v2_insta_maids','Kudlu'),
    ('tavarakere_individual_hh_city_bangalore_v2_insta_maids','Tavarekere'),
    ('virat_nagar_alpine_park_apartments_city_bangalore_v2_insta_maids','Hongasandra'),
    ('yelanahalli_nandi_citadel_city_bangalore_v2_insta_maids','Hulimavu'),
    ('yelanehalli_prestige_song_of_south_city_bangalore_v2_insta_maids','Hulimavu'),
    ('yelanehalli_snn_raj_serenity_city_bangalore_v2_insta_maids','HRBR Layout'),
    ('bagalur_sattva_exotic_city_bangalore_v2_insta_maids','Jakkuru'),
    ('banaswadi_gopalan_aristocrat_city_bangalore_v2_insta_maids','Dooravani Nagar'),
    ('banaswadi_sena_vihar_city_bangalore_v2_insta_maids','Kalyan Nagar'),
    ('banaswadi_sycon_cressida_city_bangalore_v2_insta_maids','NRI Layout'),
    ('banaswadi_the_canopy_city_bangalore_v2_insta_maids','Kalyan Nagar'),
    ('bayappanahalli_jaya_vayu_towers_city_bangalore_v2_insta_maids','Dooravani Nagar'),
    ('budigere_prestige_tranquility_city_bangalore_v2_insta_maids','Budigere'),
    ('chikka_banaswadi_individual_hh_city_bangalore_v2_insta_maids','Dooravani Nagar'),
    ('chikkabanavara_ds_max_sonata_city_bangalore_v2_insta_maids','Nagasandra'),
    ('chikkabidarakallu_godrej_tumkur_apartments_city_bangalore_v2_insta_maids','Nagasandra'),
    ('dasarahalli_shoba_moonstone_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('dasarahalli_vaishnavi_rathnam_city_bangalore_v2_insta_maids','Nagasandra'),
    ('geddalahalli_mantri_splendor_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('goraguntepalya_golden_grand_apartments_city_bangalore_v2_insta_maids','Hebbal'),
    ('hebbal_arvind_sporcia_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('hebbal_embassy_lake_terraces_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('hebbal_l&t_raintree_boulevard_city_bangalore_v2_insta_maids','Devinagar'),
    ('hebbal_prestige_misty_waters_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('hebbal_siroya_environ_city_bangalore_v2_insta_maids','Hebbal'),
    ('hebbal_ultima_smart_homes_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('hegde_nagar_lilium_gardenia_city_bangalore_v2_insta_maids','Jakkuru'),
    ('hennur_mantri_webcity_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('hennur_purva_palm_beach_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('hennur_regency_magnum_city_bangalore_v2_insta_maids','Kalyan Nagar'),
    ('hennur_sattva_gold_summit_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('hesaraghatta_salarpuria_sattva_laurel_hieghts_city_bangalore_v2_insta_maids','Nagasandra'),
    ('horamavu_ds_max_solitaire_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('jakkur_elegant_pride_apartments_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('jalahalli_shriram_sameeksha_city_bangalore_v2_insta_maids','Nagasandra'),
    ('jalahalli_west_kumar_princetown_apartments_city_bangalore_v2_insta_maids','Nagasandra'),
    ('kadamba_brigade_courtyard_city_bangalore_v2_insta_maids','Nagasandra'),
    ('kalkere_prestige_gulmohar_city_bangalore_v2_insta_maids','NRI Layout'),
    ('kalyan_nagar_harmony_homes_city_bangalore_v2_insta_maids','Kalyan Nagar'),
    ('maragondanahalli_oceanus_tranquil_city_bangalore_v2_insta_maids','NRI Layout'),
    ('mathikere_jp_nagar_park_city_bangalore_v2_insta_maids','Hebbal'),
    ('nagasandra_prestige_jindal_city_bangalore_v2_insta_maids','Nagasandra'),
    ('nagasandra_sobha_ruby_platinum_city_bangalore_v2_insta_maids','Nagasandra'),
    ('new_bel_road_dollars_colony_city_bangalore_v2_insta_maids','Hebbal'),
    ('new_bel_road_reva_institute_city_bangalore_v2_insta_maids','Hebbal'),
    ('rt_nagar_dmart_individual_hh_city_bangalore_v2_insta_maids','Hebbal'),
    ('rt_nagar_shriram_whitehouse_city_bangalore_v2_insta_maids','Hebbal'),
    ('sanjay_nagar_80ft_road_city_bangalore_v2_insta_maids','Hebbal'),
    ('shampura_individual_hh_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('tc_palya_casagrand_luxus_apartments_city_bangalore_v2_insta_maids','Rampura'),
    ('thanisandra_golden_palms_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('thanisandra_icon_north_city_bangalore_v2_insta_maids','Ashwath Nagar'),
    ('thanisandra_monarch_serenity_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('thanisandra_sobha_city_city_bangalore_v2_insta_maids','Rammana Layout'),
    ('vidyaranyapura_individual_hh_city_bangalore_v2_insta_maids','Yelahanka'),
    ('yelahanka_purva_venezia_city_bangalore_v2_insta_maids','Yelahanka'),
    ('yelahanka_ramky_one_north_city_bangalore_v2_insta_maids','Yelahanka'),
    ('yelahanka_satellite_town_city_bangalore_v2_insta_maids','Yelahanka'),
    ('yeswanthpur_platinum_city_city_bangalore_v2_insta_maids','Nagasandra'),
    ('balagere_sda_sc_city_bangalore_v2_insta_maids','Varthur'),
    ('balegere_rjr_patel_residency_city_bangalore_v2_insta_maids','Varthur'),
    ('batrahalli_sattva_celesta_city_bangalore_v2_insta_maids','KR Puram'),
    ('battarahalli_jrk_gardens_city_bangalore_v2_insta_maids','KR Puram'),
    ('belathur_jeevan_exotica_city_bangalore_v2_insta_maids','Kadugodi'),
    ('belathur_mahaveer_promenade_city_bangalore_v2_insta_maids','Kadugodi'),
    ('belathur_shilpitha_royal_apartment_city_bangalore_v2_insta_maids','Kadugodi'),
    ('belathur_sls_silicon_valley_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('bellandur_akme_harmony_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('bellandur_ilife_apartments_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('bellandur_mantri_espana_city_bangalore_v2_insta_maids','Bellandur'),
    ('bellandur_orchid_lakeview_city_bangalore_v2_insta_maids','Bellandur'),
    ('bellandur_pranavas_bsr_gitaaar_city_bangalore_v2_insta_maids','Bellandur'),
    ('bellandur_sls_signature_city_bangalore_v2_insta_maids','Bellandur'),
    ('bellandur_sobha_carnation_city_bangalore_v2_insta_maids','Bellandur'),
    ('bellandur_suncity_apartments_city_bangalore_v2_insta_maids','Bellandur'),
    ('brookefield_aecs_layout_2_city_bangalore_v2_insta_maids','Marathalli'),
    ('brookefield_aecs_layout_city_bangalore_v2_insta_maids','Marathalli'),
    ('brookefield_beml_layout_city_bangalore_v2_insta_maids','Brookefield'),
    ('brookefield_divyasree_republic_city_bangalore_v2_insta_maids','Brookefield'),
    ('brookfield_bren_avalon_city_bangalore_v2_insta_maids','Marathalli'),
    ('brookfield_bren_unity_apartments_city_bangalore_v2_insta_maids','Marathalli'),
    ('brookfield_brigade_lakefront_city_bangalore_v2_insta_maids','Hoodi'),
    ('brookfield_parimala_sunridge_city_bangalore_v2_insta_maids','Brookefield'),
    ('brookfield_united_meadows_city_bangalore_v2_insta_maids','Brookefield'),
    ('budigere_cross_brigade_exotica_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('doddakannelli_adarsh_palmtree_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('doddakannelli_assetz_east_point_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('doddakannelli_prestige_ivy_terraces_city_bangalore_v2_insta_maids','Bellandur'),
    ('doddanekundi_durga_petals_city_bangalore_v2_insta_maids','Hoodi'),
    ('doddanekundi_orr_road_city_bangalore_v2_insta_maids','Basavananagar'),
    ('garudacharpalya_brigade_metropolis_city_bangalore_v2_insta_maids','Hoodi'),
    ('hoodi_alpine_fiesta_city_bangalore_v2_insta_maids','ITPL Road'),
    ('hoodi_casagrand_royce_city_bangalore_v2_insta_maids','Basavanapura'),
    ('hoodi_gopalan_grandeur_city_bangalore_v2_insta_maids','Hoodi'),
    ('hoodi_gopalan_urban_woods_city_bangalore_v2_insta_maids','Hoodi'),
    ('hoodi_mahaveer_tuscan_city_bangalore_v2_insta_maids','Hoodi'),
    ('hoodi_nexus_shanthinikethan_apartments_city_bangalore_v2_insta_maids','ITPL Road'),
    ('hoodi_windmills_of_your_mind_city_bangalore_v2_insta_maids','Hoodi'),
    ('hoskote_brigade_golden_triangle_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('kadubeesanahalli_individual_hh_city_bangalore_v2_insta_maids','Bellandur'),
    ('kadubeesanahalli_rohan_iksha_city_bangalore_v2_insta_maids','Bellandur'),
    ('kadubeeshanahalli_cansa_dhiya_city_bangalore_v2_insta_maids','Varthur'),
    ('kadugodi_aashrayaa_citadel_city_bangalore_v2_insta_maids','Kadugodi'),
    ('kadugodi_alembic_urban_apartments_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('kadugodi_ark_cloud_city_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('kadugodi_gk_tropical_springs_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('kadugodi_golden_blossom_apartments_city_bangalore_v2_insta_maids','Kadugodi'),
    ('kadugodi_nandi_park_residency_city_bangalore_v2_insta_maids','Kadugodi'),
    ('kadugodi_prestige_palm_apartments_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('kaggadasapura_d_mart_individual_hh_city_bangalore_v2_insta_maids','Basavananagar'),
    ('kannamangala_assetz_marq_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('kannamangala_awho_sandeep_vihar_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('kannamangala_sobha_amethyst_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('kempapura_kew_gardens_city_bangalore_v2_insta_maids','Bellandur'),
    ('kr_puram_garuda_royal_home_city_bangalore_v2_insta_maids','Basavanapura'),
    ('kr_puram_mangalam_ecstasy_city_bangalore_v2_insta_maids','Basavanapura'),
    ('kr_puram_sobha_lake_gardens_city_bangalore_v2_insta_maids','Basavanapura'),
    ('madhuranagara_unicca_emporis_city_bangalore_v2_insta_maids','Varthur'),
    ('mahadevapura_durga_rainbow_city_bangalore_v2_insta_maids','Hoodi'),
    ('mahadevapura_ncc_maple_heights_city_bangalore_v2_insta_maids','Basavananagar'),
    ('mahadevapura_nester_raga_city_bangalore_v2_insta_maids','Basavananagar'),
    ('mahadevapura_trifecta_starlight_city_bangalore_v2_insta_maids','Hoodi'),
    ('marathahalli_amara_courtyard_city_bangalore_v2_insta_maids','Marathalli'),
    ('marathahalli_individual_hh_city_bangalore_v2_insta_maids','Marathalli'),
    ('marathahalli_klm_city_bangalore_v2_insta_maids','Basavananagar'),
    ('marathahalli_munnekollal_city_bangalore_v2_insta_maids','Marathalli'),
    ('marathahalli_sjr_spencer_city_bangalore_v2_insta_maids','Marathalli'),
    ('marathahalli_uiiduds_breeze_city_bangalore_v2_insta_maids','Brookefield'),
    ('marathalli_purva_fs_city_bangalore_v2_insta_maids','Marathalli'),
    ('sarjapur_divyasree_elan_homes_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('sarjapur_dsr_woodwinds_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('sarjapur_purva_sunshine_city_bangalore_v2_insta_maids','Kaikondrahalli'),
    ('seegehalli_mera_homes_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('seegehalli_nitesh_meadows_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('tc_palya_garden_city_university_city_bangalore_v2_insta_maids','KR Puram'),
    ('tc_palya_individual_hh_city_bangalore_v2_insta_maids','KR Puram'),
    ('tc_palya_pashmina_waterfront_city_bangalore_v2_insta_maids','KR Puram'),
    ('thubarahalli_keerthi_gardenia_city_bangalore_v2_insta_maids','Brookefield'),
    ('thubarahalli_saranya_sunshine_city_bangalore_v2_insta_maids','Marathalli'),
    ('thubarahalli_ukn_esperanza_city_bangalore_v2_insta_maids','Brookefield'),
    ('tin_factory_individual_hh_city_bangalore_v2_insta_maids','Basavananagar'),
    ('varthur_brigade_utopia_city_bangalore_v2_insta_maids','Varthur'),
    ('varthur_candeur_landmark_city_bangalore_v2_insta_maids','Varthur'),
    ('varthur_ds_max_sterling_city_bangalore_v2_insta_maids','Varthur'),
    ('varthur_prestige_lakeside_habitat_city_bangalore_v2_insta_maids','Varthur'),
    ('vibhutipura_extension_city_bangalore_v2_insta_maids','Basavananagar'),
    ('whitefield_adarsh_palm_meadows_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_balaji_sunflower_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_dsr_green_fields_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('whitefield_gopalan_atlantis_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_gopalan_habitat_splendour_city_bangalore_v2_insta_maids','Marathalli'),
    ('whitefield_goyal_orchid_apartments_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_key_around_the_life_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('whitefield_mahaveer_tranquil_city_bangalore_v2_insta_maids','Brookefield'),
    ('whitefield_midtown_rhythm_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_prestige_ozone_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_prestige_white_meadows_city_bangalore_v2_insta_maids','Dommarapalya'),
    ('whitefield_samudhara_eden_gardens_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('whitefield_slv_central_park_city_bangalore_v2_insta_maids','Doddabanahalli'),
    ('whitefield_sobha_rose_city_bangalore_v2_insta_maids','Whitefiled'),
    ('whitefield_spectra_palmwoods_city_bangalore_v2_insta_maids','Brookefield'),
    ('whitefield_sumadhura_apartments_city_bangalore_v2_insta_maids','Whitefiled'),
    ('yemalur_divyasree_apartments_city_bangalore_v2_insta_maids','Bellandur'),
    ('arekere_gr_lavender_city_bangalore_v2_insta_maids','JP Nagar'),
    ('arekere_l&t_south_city_city_bangalore_v2_insta_maids','JP Nagar'),
    ('banashankari_adarsh_hill_city_bangalore_v2_insta_maids','Jayanagar'),
    ('banaswadi_prestige_woodland_park_city_bangalore_v2_insta_maids','Frazer Town'),
    ('basavanagudi_lalbagh_metro_station_city_bangalore_v2_insta_maids','Jayanagar'),
    ('basavanagudi_south_end_circle_city_bangalore_v2_insta_maids','Jayanagar'),
    ('cv_raman_nagar_drdo_phase1_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('cv_raman_nagar_jeevanadi_presidency_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('cv_raman_nagar_purva_270_degrees_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('frazer_town_coles_park_city_bangalore_v2_insta_maids','Frazer Town'),
    ('hal_housing_complex_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('hal_krishna_ikon_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('halasuru_metro_station_city_bangalore_v2_insta_maids','Indiranagar'),
    ('indira_nagar_14th_main_city_bangalore_v2_insta_maids','Indiranagar'),
    ('indira_nagar_indus_signature_city_bangalore_v2_insta_maids','Indiranagar'),
    ('indiranagar_eshwara_layout_city_bangalore_v2_insta_maids','Indiranagar'),
    ('indiranagar_kodihalli_individual_hh_city_bangalore_v2_insta_maids','HAL'),
    ('indiranagar_metro_station_city_bangalore_v2_insta_maids','Indiranagar'),
    ('indiranagar_ranka_heights_city_bangalore_v2_insta_maids','HAL'),
    ('jaya_nagar_dmart_garuda_mall_city_bangalore_v2_insta_maids','Lalbagh'),
    ('jayanagar_2nd_block_city_bangalore_v2_insta_maids','Lalbagh'),
    ('jayanagar_7th_block_city_bangalore_v2_insta_maids','Jayanagar'),
    ('jp_nagar_1st_phase_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_5th_kr_layout_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_5th_phase_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_6th_phase_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_6th_phase_purva_belmont_city_bangalore_v2_insta_maids','Jayanagar'),
    ('jp_nagar_7th_phase_brigade_gardenia_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_8th_phase_axis_aspira_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_brigade_millennium_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_lic_apartments_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_mantri_paradise_city_bangalore_v2_insta_maids','JP Nagar'),
    ('jp_nagar_nagarjuna_enclave_city_bangalore_v2_insta_maids','JP Nagar'),
    ('kaggadasapura_ittina_abby_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('kaggadasapura_malleshpalya_individual_hh_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('kothnur_classic_orchards_city_bangalore_v2_insta_maids','JP Nagar'),
    ('kurubarahalli_kempegowda_park_city_bangalore_v2_insta_maids','Rajaji Nagar'),
    ('lakkasandra_individual_hh_city_bangalore_v2_insta_maids','Lalbagh'),
    ('murageshpalya_diamond_district_city_bangalore_v2_insta_maids','HAL'),
    ('murgeshpalya_individual_hh_city_bangalore_v2_insta_maids','HAL'),
    ('murugeshpalya_golden_enclave_apartments_city_bangalore_v2_insta_maids','HAL'),
    ('richmond_town_bheemanna_garden_city_bangalore_v2_insta_maids','Lalbagh'),
    ('richmond_town_city_bangalore_v2_insta_maids','Lalbagh'),
    ('sandal_soap_factory_metro_station_city_bangalore_v2_insta_maids','Rajaji Nagar'),
    ('tin_factory_sattva_magnificia_city_bangalore_v2_insta_maids','CV Raman Nagar'),
    ('vibhutipura_fortuna_blue_wings_city_bangalore_v2_insta_maids','CV Raman Nagar')
  AS t(hub_name, cluster)
),

-- Step 1: All deliveries per provider per week
delivery_log AS (
    SELECT DISTINCT
        r.provider_id,
        pm.city,
        DATE_TRUNC('week', DATE(r.bdate_final)) AS delivery_week
    FROM request__daily__facts r
    INNER JOIN provider_master pm
        ON r.provider_id = pm.provider_id
    WHERE pm.reporting_supercategory_new = 'Insta Help'
        AND pm.country = 'India'
        AND r.reporting_supercategory_new = 'Insta Help'
        AND r.service_delivered = 1
        AND DATE(r.bdate_final) >= DATE('2025-01-01')
),

-- Step 2: Current hub assignment (latest record per provider)
current_hub AS (
    SELECT
        e.provider_id,
        e.primary_hub_id,
        s.hub_name,
        COALESCE(c.cluster, 'Not Mapped') AS cluster,
        ROW_NUMBER() OVER (PARTITION BY e.provider_id ORDER BY e.updated_at DESC) AS rn
    FROM PUBLIC.PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS e
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW s
        ON e.primary_hub_id = s.hub_id
    LEFT JOIN clusters c
        ON LOWER(s.hub_name) = LOWER(c.hub_name)
    QUALIFY rn = 1
),

-- Step 3: All approved providers with hub + MG bucket
all_providers AS (
    SELECT
        a.provider_id,
        a.city,
        DATE(a.approval_date) AS approval_date,
        a.last_delivery_date,
        b.hub_name,
        b.cluster,
        CASE
            WHEN a.city = 'Bangalore' AND DATE(a.approval_date) >= DATE('2025-08-05') THEN '27k'
            WHEN a.city = 'Bangalore' AND DATE(a.approval_date) <  DATE('2025-08-05') THEN '32k'
            WHEN a.city = 'Mumbai'    AND DATE(a.approval_date) >= DATE('2025-07-26') THEN '25k'
            WHEN a.city = 'Mumbai'    AND DATE(a.approval_date) <  DATE('2025-07-26') THEN '30k'
        END AS ming
    FROM provider_master a
    LEFT JOIN current_hub b
        ON a.provider_id = b.provider_id
    WHERE a.reporting_supercategory_new = 'Insta Help'
        AND a.country = 'India'
        AND a.approval_date IS NOT NULL
        AND DATE(a.approval_date) >= DATE('2025-01-01')
),

-- Step 4: Distinct delivery weeks
all_weeks AS (
    SELECT DISTINCT delivery_week AS week
    FROM delivery_log
),

-- Step 5: Provider × Week grid (only weeks on or after approval)
provider_week_grid AS (
    SELECT
        p.provider_id,
        p.city,
        p.hub_name,
        p.cluster,
        p.ming,
        w.week
    FROM all_providers p
    CROSS JOIN all_weeks w
    WHERE DATE_TRUNC('week', p.approval_date) <= w.week
),

-- Step 6: Mark whether each provider delivered in each week
provider_weekly_activity AS (
    SELECT
        g.provider_id,
        g.city,
        g.hub_name,
        g.cluster,
        g.ming,
        g.week,
        CASE WHEN d.delivery_week IS NOT NULL THEN 1 ELSE 0 END AS delivered
    FROM provider_week_grid g
    LEFT JOIN delivery_log d
        ON g.provider_id = d.provider_id
        AND g.week = d.delivery_week
),

-- Step 7: Compute previous-week delivery and ever-delivered-before flags
provider_weekly_status AS (
    SELECT
        provider_id,
        city,
        hub_name,
        cluster,
        ming,
        week,
        delivered AS current_week_delivered,
        LAG(delivered, 1) OVER (PARTITION BY provider_id ORDER BY week) AS prev_week_delivered,
        MAX(delivered) OVER (
            PARTITION BY provider_id
            ORDER BY week
            ROWS BETWEEN UNBOUNDED PRECEDING AND 2 PRECEDING
        ) AS ever_delivered_before_prev_week
    FROM provider_weekly_activity
),

/*
  Step 8: Classify each provider-week

  Churn logic (matches the requirement):
    prev_week_delivered = 1  AND  current_week_delivered = 0  →  'churn'

  Example walk-through:
    Week of 2025-03-10 (W11): partner delivers   → prev_week_delivered will be 1 for W12
    Week of 2025-03-17 (W12): partner does NOT deliver
      → prev_week_delivered = 1, current_week_delivered = 0
      → classified as 'churn' in W12  ✓
*/
provider_week_classified AS (
    SELECT
        provider_id,
        city,
        hub_name,
        cluster,
        ming,
        week,
        CASE
            WHEN prev_week_delivered = 1 AND current_week_delivered = 1 THEN 'active'
            WHEN prev_week_delivered = 1 AND current_week_delivered = 0 THEN 'churn'
            WHEN ever_delivered_before_prev_week = 1
                AND prev_week_delivered = 0
                AND current_week_delivered = 1 THEN 'reactive'
            ELSE 'other'
        END AS fulfilment_state
    FROM provider_weekly_status
    WHERE prev_week_delivered IS NOT NULL
),

-- Step 9: For each churn event, find the earliest reactivation
churn_with_reactivation AS (
    SELECT
        c.provider_id,
        c.city,
        c.hub_name,
        c.cluster,
        c.ming,
        c.week AS churn_week,
        MIN(r.week) AS first_reactivation_week
    FROM provider_week_classified c
    LEFT JOIN provider_week_classified r
        ON c.provider_id = r.provider_id
        AND r.fulfilment_state = 'reactive'
        AND r.week > c.week
    WHERE c.fulfilment_state = 'churn'
    GROUP BY 1, 2, 3, 4, 5, 6
),

-- Step 10: Flag reactivation within 15 d / 30 d / ever
churn_reactivation_flags AS (
    SELECT
        provider_id,
        city,
        hub_name,
        cluster,
        ming,
        churn_week AS week,
        CASE
            WHEN first_reactivation_week IS NOT NULL
                 AND DATEDIFF('day', churn_week, first_reactivation_week) <= 15
            THEN 1 ELSE 0
        END AS react_15d,
        CASE
            WHEN first_reactivation_week IS NOT NULL
                 AND DATEDIFF('day', churn_week, first_reactivation_week) <= 30
            THEN 1 ELSE 0
        END AS react_30d,
        CASE
            WHEN first_reactivation_week IS NOT NULL
            THEN 1 ELSE 0
        END AS react_ever
    FROM churn_with_reactivation
),

-- Step 11: Zero-delivery churn (approved but never delivered)
zero_delivery_churn AS (
    SELECT
        provider_id,
        city,
        hub_name,
        cluster,
        ming,
        DATE_TRUNC('week', approval_date) AS week,
        'no_delivery_churn' AS fulfilment_state
    FROM all_providers
    WHERE last_delivery_date IS NULL
),

-- Step 12: Union all classified events
all_events AS (
    SELECT provider_id, city, hub_name, cluster, ming, week, fulfilment_state
    FROM provider_week_classified
    WHERE fulfilment_state IN ('active', 'churn', 'reactive')

    UNION ALL

    SELECT provider_id, city, hub_name, cluster, ming, week, fulfilment_state
    FROM zero_delivery_churn
),

-- Step 13: Active base (providers who delivered prev week) by city/cluster/ming/week
active_base_by_week AS (
    SELECT
        city,
        cluster,
        ming,
        week,
        COUNT(DISTINCT CASE WHEN prev_week_delivered = 1 THEN provider_id END) AS prev_week_active_pros
    FROM provider_weekly_status
    WHERE prev_week_delivered IS NOT NULL
    GROUP BY 1, 2, 3, 4
),

-- Step 14: City-cluster level aggregation
weekly_cohorts_city AS (
    SELECT
        e.city,
        e.cluster,
        e.ming,
        e.week,
        COUNT(DISTINCT CASE WHEN fulfilment_state = 'active'           THEN e.provider_id END) AS week_active_pros,
        COUNT(DISTINCT CASE WHEN fulfilment_state = 'churn'            THEN e.provider_id END) AS churned_pros,
        COUNT(DISTINCT CASE WHEN fulfilment_state = 'reactive'         THEN e.provider_id END) AS reactivated_pros,
        COUNT(DISTINCT CASE WHEN fulfilment_state = 'no_delivery_churn' THEN e.provider_id END) AS no_delivery_churned_pros,
        COUNT(DISTINCT CASE WHEN cr.react_15d  = 1 THEN e.provider_id END) AS churn_reactivated_15d,
        COUNT(DISTINCT CASE WHEN cr.react_30d  = 1 THEN e.provider_id END) AS churn_reactivated_30d,
        COUNT(DISTINCT CASE WHEN cr.react_ever = 1 THEN e.provider_id END) AS churn_reactivated_ever
    FROM all_events e
    LEFT JOIN churn_reactivation_flags cr
        ON e.provider_id = cr.provider_id
        AND e.week = cr.week
    GROUP BY 1, 2, 3, 4
),

-- Step 15: Overall (all clusters) rollup per city
weekly_cohorts_overall AS (
    SELECT
        city,
        'zOverall' AS cluster,
        ming,
        week,
        SUM(week_active_pros)        AS week_active_pros,
        SUM(churned_pros)            AS churned_pros,
        SUM(reactivated_pros)        AS reactivated_pros,
        SUM(no_delivery_churned_pros) AS no_delivery_churned_pros,
        SUM(churn_reactivated_15d)   AS churn_reactivated_15d,
        SUM(churn_reactivated_30d)   AS churn_reactivated_30d,
        SUM(churn_reactivated_ever)  AS churn_reactivated_ever
    FROM weekly_cohorts_city
    GROUP BY 1, 2, 3, 4
),

-- Step 16: Active base overall rollup
active_base_overall AS (
    SELECT
        city,
        'zOverall' AS cluster,
        ming,
        week,
        SUM(prev_week_active_pros) AS prev_week_active_pros
    FROM active_base_by_week
    GROUP BY 1, 2, 3, 4
),

-- Step 17: Combine cluster-level + overall into one result set
final_combined AS (
    SELECT
        c.city,
        c.cluster,
        c.ming,
        c.week,
        c.week_active_pros,
        c.prev_week_active_pros,
        c.churned_pros,
        c.reactivated_pros,
        c.no_delivery_churned_pros,
        c.churn_reactivated_15d,
        c.churn_reactivated_30d,
        c.churn_reactivated_ever
    FROM (
        SELECT c.*, b.prev_week_active_pros
        FROM weekly_cohorts_city c
        LEFT JOIN active_base_by_week b
            ON  c.city    = b.city
            AND c.cluster = b.cluster
            AND c.ming    = b.ming
            AND c.week    = b.week
    ) c

    UNION ALL

    SELECT
        c.city,
        c.cluster,
        c.ming,
        c.week,
        c.week_active_pros,
        b.prev_week_active_pros,
        c.churned_pros,
        c.reactivated_pros,
        c.no_delivery_churned_pros,
        c.churn_reactivated_15d,
        c.churn_reactivated_30d,
        c.churn_reactivated_ever
    FROM weekly_cohorts_overall c
    LEFT JOIN active_base_overall b
        ON  c.city    = b.city
        AND c.cluster = b.cluster
        AND c.ming    = b.ming
        AND c.week    = b.week
)

-- Final output with derived percentages
SELECT
    'Insta Help' AS reporting_supercategory_new,
    city    AS "city::filter",
    cluster AS "Cluster::multi-filter",
    ming,
    TO_CHAR(week, 'YYYY-MM-DD') AS Week,
    DENSE_RANK() OVER (PARTITION BY city ORDER BY week DESC) AS number,
    week_active_pros,
    prev_week_active_pros,
    churned_pros,
    reactivated_pros,
    no_delivery_churned_pros,
    churn_reactivated_15d,
    churn_reactivated_30d,
    churn_reactivated_ever,

    ROUND(COALESCE(churn_reactivated_15d, 0) * 100.0
        / NULLIF(churned_pros, 0), 2) AS churn_reactivated_15d_perc,

    ROUND(COALESCE(churn_reactivated_30d, 0) * 100.0
        / NULLIF(churned_pros, 0), 2) AS churn_reactivated_30d_perc,

    ROUND(COALESCE(churn_reactivated_ever, 0) * 100.0
        / NULLIF(churned_pros, 0), 2) AS churn_reactivated_ever_perc,

    ROUND(COALESCE(churned_pros, 0) * 100.0
        / NULLIF(prev_week_active_pros, 0), 2) AS gross_churn_perc,

    ROUND((COALESCE(churned_pros, 0) - COALESCE(reactivated_pros, 0)) * 100.0
        / NULLIF(prev_week_active_pros, 0), 2) AS net_churn_perc,

    ROUND((COALESCE(churned_pros, 0) + COALESCE(no_delivery_churned_pros, 0)
         - COALESCE(reactivated_pros, 0)) * 100.0
        / NULLIF(prev_week_active_pros, 0), 2) AS net_churn_incl_zero_del_app_perc

FROM final_combined
WHERE week >= DATEADD('week', -100, DATE_TRUNC('week', CURRENT_DATE))
    AND week < DATE_TRUNC('week', CURRENT_DATE)
    AND city IN ('Bangalore', 'Mumbai')
ORDER BY city, week DESC;
