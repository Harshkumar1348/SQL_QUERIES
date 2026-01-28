WITH base AS (
    SELECT
        provider_id,
        city,
        RATING,
        BDATE
    FROM PUBLIC.MASTER_DATA_EXPLORE_TABLE
),
current_hub AS (
    SELECT
        e.provider_id,
        e.primary_hub_id,
        s.hub_name,
        ROW_NUMBER() OVER (PARTITION BY e.provider_id ORDER BY e.updated_at DESC) AS rn
    FROM PUBLIC.PROVIDERXPRIMARY_HUBXDATE__DAILY__FACTS e
    LEFT JOIN PUBLIC.SMART_HUBS_VIEW s ON e.primary_hub_id = s.hub_id
    QUALIFY rn = 1
)
SELECT
    ch.hub_name,
    AVG(b.RATING) AS average_rating
FROM base b
JOIN current_hub ch ON b.provider_id = ch.provider_id
WHERE b.city = 'Bangalore'
GROUP BY ch.hub_name;
