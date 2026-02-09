# SQL Query Fix Summary

## Problem
The query had a `do_d7` CTE that calculated churn buckets (D0 churn, D7 churn, etc.) but this CTE was never used in the final query. You wanted to add `d0_churn_count` and `d7_churn_count` columns grouped by `ldd_week` and `city`.

## Changes Made

### 1. **Added `do_d7` CTE to the `weeks` CTE**
```sql
weeks as (
select distinct week_val from (
    ...
    union select ldd_week from do_d7  -- ADDED THIS LINE
)
where week_val is not null
)
```
This ensures that weeks from `ldd_week` are included in the week list.

### 2. **Joined `do_d7` to the main query**
In both the city-specific query and the overall query:
```sql
left join do_d7 dd on f.provider_id = dd.provider_id and lower(f.city) = lower(dd.city)
```
For the overall query (without city filtering):
```sql
left join do_d7 dd on f.provider_id = dd.provider_id
```

### 3. **Added D0 and D7 Churn Count Columns**
Added these two new columns in both SELECT statements:
```sql
count(distinct case when dd.churn_bucket = '3. D0 churn' and dd.ldd_week = w.week_val then dd.provider_id end) as d0_churn_count,
count(distinct case when dd.churn_bucket = '4. D7 churn' and dd.ldd_week = w.week_val then dd.provider_id end) as d7_churn_count,
```

### 4. **Fixed table aliases**
Changed `provider_id` references to `f.provider_id` in the SELECT statements to avoid ambiguity after adding the join.

## How It Works

1. **`do_d7` CTE** calculates the churn status and bucket for each provider based on their last delivery date (ldd)
2. The churn bucket is determined by the age (days between approval and last delivery):
   - `'3. D0 churn'`: age = 0 and churned
   - `'4. D7 churn'`: age <= 7 and churned
   - Other buckets for D15, D30, D60, D90, D120, and >D120

3. **The join** connects providers in the final dataset with their churn information
4. **The counts** aggregate how many providers churned at D0 or D7 for each week and city combination
5. Results are **grouped by** `ldd_week` (from do_d7) and `city`, matching when `dd.ldd_week = w.week_val`

## Result Columns Added
- `d0_churn_count`: Count of providers who churned on day 0 (same day as approval)
- `d7_churn_count`: Count of providers who churned within 7 days of approval

Both columns are now available in:
- City-specific breakdown
- Overall ('zOverall') summary

The query now properly groups churn counts by `ldd_week` and `city` as requested.
