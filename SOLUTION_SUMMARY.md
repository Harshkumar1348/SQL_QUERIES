# Solution Summary: L50 Average Rating Implementation

## Problem Statement
You needed to add `l50_avg_rating` to your trainer metrics query with specific conditional logic:
- **Before Jan 19, 2026**: Use rolling average of last 50 ratings
- **From Jan 19, 2026 onwards**: Use that week's average rating only

## Solution Implemented

### New CTEs Added

1. **`rating_events`**
   - Extracts all rating data from `MASTER_DATA_EXPLORE_TABLE`
   - Filters for valid ratings where service was delivered
   - Creates weekly grouping using `DATE_TRUNC('WEEK', DATE(bdate))`

2. **`rating_rolling_calc`**
   - Calculates rolling L50 average using window function
   - Formula: `AVG(rating) OVER (PARTITION BY provider_id ORDER BY bdate ROWS BETWEEN 49 PRECEDING AND CURRENT ROW)`
   - This gives the average of current rating + previous 49 ratings

3. **`rolling_l50_per_week`**
   - Gets the latest rolling L50 value for each provider for each week
   - Uses `QUALIFY ROW_NUMBER()` to pick the last record per week

4. **`weekly_avg_rating`**
   - Calculates simple weekly average: `AVG(rating)` grouped by provider and week
   - This is used for weeks from Jan 19, 2026 onwards

5. **`l50_avg_rating_final`**
   - **KEY LOGIC**: Implements the conditional calculation
   ```sql
   CASE 
       WHEN rating_week >= DATE_TRUNC('WEEK', DATE('2026-01-19'))
       THEN weekly_avg_rating
       ELSE rolling_l50_average
   END AS l50_avg_rating
   ```

6. **`latest_l50_rating`**
   - Gets the most recent L50 rating per provider
   - Uses `QUALIFY ROW_NUMBER()` ordered by rating_week DESC

### Changes to Existing Query

- Modified `base` CTE to include `l50_avg_rating` via LEFT JOIN with `latest_l50_rating`
- Added `avg_l50_rating` to final SELECT statement
- Formula: `ROUND(AVG(l50_avg_rating), 2)`

## Final Output Columns

Your query now returns:
1. `trainer` - Trainer name
2. `total_px` - Total providers
3. `paf_pct` - PAF percentage
4. `avg_leaves` - Average leaves
5. `ls_pct` - Live status percentage
6. **`avg_l50_rating`** - ✨ NEW: Average L50 rating per trainer

## How to Modify the Cutoff Date

If you need to change the January 19, 2026 cutoff date, modify this line in the `l50_avg_rating_final` CTE:

```sql
WHEN COALESCE(r.rating_week, w.rating_week) >= DATE_TRUNC('WEEK', DATE('2026-01-19'))
```

Change `'2026-01-19'` to your desired cutoff date.

## Key SQL Techniques Used

1. **Window Functions**: `AVG() OVER()` with `ROWS BETWEEN`
2. **QUALIFY Clause**: Efficient row filtering in Snowflake
3. **FULL OUTER JOIN**: Ensures all providers are included
4. **COALESCE**: Handles NULL values gracefully
5. **DATE_TRUNC**: Week-level aggregation
6. **Conditional Logic**: CASE statement for cutoff date

## Testing Recommendations

To verify the query works correctly:

1. **Check Pre-Jan 19 weeks**: Verify that L50 uses rolling 50 ratings
2. **Check Post-Jan 19 weeks**: Verify that L50 uses only that week's average
3. **Edge cases**: 
   - Providers with < 50 ratings (rolling will use available ratings)
   - Providers with no ratings in recent weeks
   - Providers who joined after Jan 19, 2026

## Files Created

1. **`provider_trainer_metrics_with_l50_rating.sql`** - Complete working query
2. **`README.md`** - Detailed documentation
3. **`SOLUTION_SUMMARY.md`** - This file

All files have been committed and pushed to branch: `cursor/provider-l50-average-rating-1c08`
