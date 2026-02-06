# Weekly Trainer Performance - Pivoted View Solution

## Problem Statement
You needed a view where **weeks are displayed horizontally** with the following metrics in columns:
1. **Total Trainers in ELC** (Early Life Cycle - trainers with < 60 days experience)
2. **Trainers with Score > 75**
3. **Trainers with ELC PIP % < 20**
4. **Trainers < 60 Days** (same as ELC trainers)

## Solution Overview

I've created **3 SQL query files** with different approaches to solve your pivoting requirement:

### 1. `weekly_trainer_performance_pivot_final.sql` ⭐ **RECOMMENDED**

This is the **best solution** for most use cases.

**Output Format:**
```
Week          | Total_ELC_Trainers | Trainers_Score_GT_75 | Trainers_ELC_PIP_LT_20_PCT | Trainers_LT_60_Days
------------- | ------------------ | -------------------- | -------------------------- | -------------------
2025-02-03    | 45                 | 28                   | 35                         | 45
2025-01-27    | 42                 | 25                   | 33                         | 42
2025-01-20    | 38                 | 22                   | 30                         | 38
```

**Advantages:**
- ✅ Works dynamically with any number of weeks
- ✅ Easy to read and understand
- ✅ No need to hardcode week dates
- ✅ Works in all BI tools (Tableau, Power BI, Looker, etc.)
- ✅ Can be easily transposed in Excel or your BI tool if you need weeks as columns

**How to Use:**
Simply run this query as-is. The weeks will appear as rows with all metrics as columns.

---

### 2. `weekly_trainer_performance_pivot.sql` 

This version shows **weeks as actual column names** using static UNION ALL approach.

**Output Format:**
```
Metric                          | 2025-01-06 | 2025-01-13 | 2025-01-20 | 2025-01-27 | 2025-02-03
------------------------------- | ---------- | ---------- | ---------- | ---------- | ----------
Total ELC Trainers              | 38         | 40         | 38         | 42         | 45
Trainers with Score > 75        | 20         | 23         | 22         | 25         | 28
Trainers with ELC PIP % < 20    | 28         | 31         | 30         | 33         | 35
Trainers < 60 Days              | 38         | 40         | 38         | 42         | 45
```

**How to Customize:**
You need to manually update the week dates in the query:
```sql
MAX(CASE WHEN week = '2025-01-06' THEN total_elc_trainers END) AS "2025-01-06",
MAX(CASE WHEN week = '2025-01-13' THEN total_elc_trainers END) AS "2025-01-13",
-- Add more weeks as needed
```

**Use When:**
- You need a fixed set of weeks
- You're exporting to a static report
- You want metrics as rows and weeks as columns

---

### 3. `weekly_trainer_performance_pivot_dynamic.sql`

This was an experimental dynamic pivot approach. **Use the FINAL version instead** as it's more reliable.

---

## Key Metrics Explained

### 1. Total_ELC_Trainers
Count of distinct trainers who are in **Early Life Cycle** (less than 60 days since first screening) in that week.

**Calculation:**
```sql
COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END)
```

Where `age_tm = 'ELC Trainer'` means: `DATEDIFF('day', first_screening, CURRENT_DATE()) <= 60`

---

### 2. Trainers_Score_GT_75
Count of distinct trainers whose **composite score is greater than 75** in that week.

**Score Formula:**
```sql
(0.1  × sp_pct) +           -- 10% weight on Screening Pass %
(0.15 × sp_tp_pct) +        -- 15% weight on Screening to Training Pass %
(0.15 × tp_pct) +           -- 15% weight on Training Pass %
(0.6  × (100 - elc_pip_pct)) -- 60% weight on Non-PIP % (100 - PIP%)
```

**Calculation:**
```sql
COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END)
```

---

### 3. Trainers_ELC_PIP_LT_20_PCT
Count of distinct trainers whose **ELC PIP percentage is less than 20%** in that week.

**ELC PIP % Formula:**
```sql
100 × (Partners in PIP in Cycle 1 & 2) / (Total Partners in Cycle 1 & 2)
```

Where PIP status is determined by:
- Rating errors ≥ 4, OR
- PAF errors ≥ 4, OR  
- Graded leaves ≥ 5

**Calculation:**
```sql
COUNT(DISTINCT CASE WHEN elc_pip_pct < 20 THEN trainer END)
```

---

### 4. Trainers_LT_60_Days
Count of distinct trainers with **less than 60 days** since their first screening.

**Note:** This is the **same as Total_ELC_Trainers** since both use the same logic.

---

## How to Run These Queries

### Option 1: Direct Execution (Recommended)
```sql
-- Copy and paste the entire content of weekly_trainer_performance_pivot_final.sql
-- into your Snowflake SQL editor and run it
```

### Option 2: Create a View
```sql
CREATE OR REPLACE VIEW trainer_performance_weekly AS
-- Paste the entire query from weekly_trainer_performance_pivot_final.sql here
;

-- Then query it:
SELECT * FROM trainer_performance_weekly
WHERE "Week" >= '2025-01-01'
ORDER BY "Week" DESC;
```

### Option 3: Use in BI Tools
Connect your BI tool (Tableau, Looker, Power BI, etc.) to Snowflake and use the query as a **Custom SQL** data source.

---

## Filtering and Modifications

### Filter by Date Range
Add a `WHERE` clause before the final `GROUP BY`:
```sql
-- At the end of base_data CTE, add:
WHERE week BETWEEN '2025-01-01' AND '2025-02-28'
```

### Change Score Threshold
Modify the condition in the aggregation:
```sql
-- Change from score > 75 to score > 80:
COUNT(DISTINCT CASE WHEN score > 80 THEN trainer END) AS "Trainers_Score_GT_80"
```

### Change ELC PIP Threshold
Modify the condition:
```sql
-- Change from < 20 to < 15:
COUNT(DISTINCT CASE WHEN elc_pip_pct < 15 THEN trainer END) AS "Trainers_ELC_PIP_LT_15_PCT"
```

### Change Days Threshold (60 Days)
Modify the `tm_age` CTE:
```sql
tm_age AS (
    SELECT 
        created_by,
        MIN(DATE(created_at_ist)) AS first_screening,
        DATEDIFF('day', first_screening, CURRENT_DATE()) AS tmm,
        CASE 
            WHEN tmm > 90 THEN 'LLC Trainer'  -- Changed from 60 to 90
            ELSE 'ELC Trainer'
        END AS age_tm
    FROM poco
    GROUP BY 1
)
```

---

## Additional Metrics You Can Add

If you want to add more metrics to the pivoted view, add them to the final `SELECT` statement:

```sql
SELECT 
    week AS "Week",
    COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END) AS "Total_ELC_Trainers",
    COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END) AS "Trainers_Score_GT_75",
    COUNT(DISTINCT CASE WHEN elc_pip_pct < 20 THEN trainer END) AS "Trainers_ELC_PIP_LT_20_PCT",
    COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END) AS "Trainers_LT_60_Days",
    
    -- NEW METRICS:
    AVG(score) AS "Avg_Score",
    AVG(elc_pip_pct) AS "Avg_ELC_PIP_PCT",
    COUNT(DISTINCT trainer) AS "Total_Trainers",
    SUM(hh_eligible) AS "Total_HH_Eligible"
FROM base_data
GROUP BY week
ORDER BY week DESC;
```

---

## Performance Optimization Tips

1. **Add Indexes:** Ensure your base tables have indexes on:
   - `provider_id`
   - `customer_category_key`
   - Date columns used for filtering

2. **Limit Date Range:** Add date filters early in the CTEs to reduce data processing:
   ```sql
   WHERE approval_date >= '2025-01-01'
   ```

3. **Materialize CTEs:** For very large datasets, consider creating temporary tables for intermediate results.

4. **Use Clustering:** If you run this query frequently, consider clustering the base tables by date and category.

---

## Troubleshooting

### Query Takes Too Long
- Add date range filters at the earliest CTEs (base, view1, view2)
- Check if indexes exist on join columns
- Review the execution plan for bottlenecks

### Missing Data for Some Weeks
- Check if `hh_eligible > 20` filter is excluding weeks
- Verify data exists in base tables for those weeks
- Check the `WHERE walked_in IS NOT NULL AND DATE_TRUNC('week', DATE(walked_in)) > '2025-01-01'` condition

### Null Values in Results
- This is expected when trainers don't have data for certain metrics
- The query uses `NULLIF` to prevent division by zero
- COALESCEs are in place for most calculations

---

## Contact & Support

If you need further modifications or have questions:
1. Review the comments in the SQL file
2. Check the metric explanations above
3. Test with a small date range first
4. Verify base table data quality

---

## Version History

- **v1.0** - Initial pivot implementation with 3 query variants
- Focus on ELC trainers (< 60 days)
- 4 key metrics: Total ELC, Score>75, PIP<20%, <60 Days
