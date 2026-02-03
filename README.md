# Trainer Performance Query with L50 Rating Logic

## Overview
This SQL query analyzes trainer performance metrics including the average L50 rating (average rating from the last 50 bookings), PAF percentage, leaves, and late show percentage.

## Key Features

### 1. **avg_l50_rating Calculation**
The query implements conditional logic for calculating `avg_l50_rating`:

#### Before Week of January 19, 2026:
- Calculates the average rating from the **last 50 bookings** per provider
- Uses `ranked_ratings` CTE to rank bookings by date (most recent first)
- Filters for bookings where `rating IS NOT NULL` and `service_delivered = 1`
- Takes only the top 50 bookings (rating_rank <= 50)
- Calculates the average: `SUM(rating) / COUNT(rating)`

#### From Week of January 19, 2026 onwards:
- Switches to **weekly average rating**
- Calculates: `SUM(rating where service_delivered=1 and rating is not null) / COUNT(DISTINCT customer_request_id where service_delivered=1 and rating is not null)`
- Provides more recent performance data on a weekly basis

### 2. **Output Columns**
The final query returns:
- `trainer` - Trainer name
- `week::multi-filter` - Week for filtering
- `total_px` - Total number of distinct partners/providers under that trainer for that week
- `avg_l50_rating` - Average L50 rating (conditional logic based on week)
- `paf_pct` - Percentage of providers with PAF > 0
- `avg_leaves` - Average leave days
- `ls_pct` - Late show percentage (percentage of working providers)

## Query Structure

### CTEs (Common Table Expressions):
1. **manual_mapping** - Maps provider IDs to trainer names
2. **paf_leaves** - Gets latest PAF and leave data for each provider
3. **ranked_ratings** - Ranks all bookings by date for each provider
4. **avg_rating_last_50** - Calculates average rating from last 50 bookings
5. **weekly_avg_rating** - Calculates weekly average rating (for weeks >= 2026-01-19)
6. **booking_avg_rating** - Calculates weekly booking averages from REQUEST__DAILY__FACTS
7. **l7d** - Determines if provider is working (marked working > 8 hours)
8. **base** - Joins all data and applies conditional logic for avg_l50_rating

### Conditional Logic:
```sql
CASE 
    WHEN bar.week >= '2026-01-19' THEN COALESCE(war.weekly_avg, bar.avg_rating)
    ELSE COALESCE(arl50.avg_rating_l50, bar.avg_rating)
END AS avg_l50_rating
```

## Data Sources
- `public.MASTER_DATA_EXPLORE_TABLE` - Main source for ratings and service delivery data
- `provider_promise_plan__daily__metrics` - PAF and leave information
- `public.providerXdateXhour__calendar_marking__hourly__facts` - Working status data
- `PUBLIC.REQUEST__DAILY__FACTS` - Booking and rating data

## Usage
Run this query in your Snowflake environment. The query automatically handles the date-based conditional logic for L50 rating calculation.

## Notes
- Week truncation uses `DATE_TRUNC('WEEK', BDATE)`
- The threshold date is **January 19, 2026** (week 3 of 2026)
- All ratings are rounded to 2 decimal places
- The query groups results by trainer and week
