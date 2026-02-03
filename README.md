# Provider L50 Average Rating Query

## Overview
This SQL query calculates trainer performance metrics including the L50 average rating with conditional logic based on the week.

## Key Changes

### L50 Average Rating Logic
The `l50_avg_rating` metric is calculated with the following conditional logic:

- **Before January 19, 2026 week**: Uses rolling average of last 50 ratings per provider
- **From January 19, 2026 week onwards**: Uses simple weekly average rating for that specific week

### How It Works

1. **rating_events CTE**: Extracts all rating records from `MASTER_DATA_EXPLORE_TABLE` where:
   - Rating is not null
   - Service was delivered (`service_delivered = 1`)
   - Customer category is 'insta_maids'
   - Groups by week using `DATE_TRUNC('WEEK', DATE(bdate))`

2. **rating_rolling_calc CTE**: Calculates rolling average using window function:
   - `ROWS BETWEEN 49 PRECEDING AND CURRENT ROW` to get last 50 ratings
   - Partitioned by provider_id and ordered by bdate

3. **rolling_l50_per_week CTE**: Gets the last rolling L50 value per provider per week using `QUALIFY ROW_NUMBER()`

4. **weekly_avg_rating CTE**: Calculates simple weekly average rating for all weeks

5. **l50_avg_rating_final CTE**: Combines both metrics with conditional logic:
   - If rating_week >= '2026-01-19' week: use weekly average
   - Otherwise: use rolling L50 average

6. **latest_l50_rating CTE**: Gets the most recent L50 rating per provider

## Output Metrics

The query outputs the following metrics per trainer:

- `trainer`: Trainer name
- `total_px`: Total number of unique providers
- `paf_pct`: Percentage of providers with PAF (Provider Acceptance Factor) > 0
- `avg_leaves`: Average leave days
- `ls_pct`: Live status percentage (providers working > 8 hours)
- `avg_l50_rating`: Average L50 rating across all providers for that trainer

## Tables Used

- `public.MASTER_DATA_EXPLORE_TABLE`: Source of rating events
- `provider_promise_plan__daily__metrics`: PAF and leave metrics
- `public.providerXdateXhour__calendar_marking__hourly__facts`: Working hours data

## Notes

- The January 19, 2026 cutoff date can be modified in the `CASE` statement within the `l50_avg_rating_final` CTE
- All ratings are rounded to 2 decimal places
- The query uses `FULL OUTER JOIN` to ensure all providers with ratings are included regardless of whether they have rolling or weekly averages
