# Changes Summary: Original Query → Pivoted View

## What Changed

### Original Query Output
Your original query returned **one row per trainer per week**:

```
trainer  | week       | hh_eligible | sp_pct | score | elc_pip_pct | score_range     | TM_AGE       | FINAL_RANK
---------|------------|-------------|--------|-------|-------------|-----------------|--------------|------------
John     | 2025-01-06 | 25          | 85.5   | 78.3  | 15.2        | Greater than 75 | ELC Trainer  | 1
Sarah    | 2025-01-06 | 30          | 90.2   | 82.1  | 12.5        | Greater than 75 | ELC Trainer  | 2
Mike     | 2025-01-06 | 22          | 70.1   | 68.5  | 25.3        | Less than 75    | LLC Trainer  | 3
John     | 2025-01-13 | 28          | 87.0   | 79.5  | 14.8        | Greater than 75 | ELC Trainer  | 1
...
```

### New Pivoted Query Output
The new query returns **one row per week with aggregated metrics**:

```
Week       | Total_ELC_Trainers | Trainers_Score_GT_75 | Trainers_ELC_PIP_LT_20_PCT | Trainers_LT_60_Days
-----------|--------------------|-----------------------|----------------------------|---------------------
2025-02-03 | 45                 | 28                    | 35                         | 45
2025-01-27 | 42                 | 25                    | 33                         | 42
2025-01-20 | 38                 | 22                    | 30                         | 38
2025-01-13 | 40                 | 23                    | 31                         | 40
2025-01-06 | 38                 | 20                    | 28                         | 38
```

---

## Key Transformations

### 1. Added Aggregation Layer
**Before:**
```sql
SELECT trainer, week, hh_eligible, score, elc_pip_pct, ...
FROM final
```

**After:**
```sql
SELECT 
    week,
    COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END) AS total_elc_trainers,
    COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END) AS trainers_score_gt_75,
    ...
FROM base_data
GROUP BY week
```

---

### 2. Metric Transformations

#### Total ELC Trainers
**Original:** Row-level data showing `TM_AGE` for each trainer
```sql
-- Each row shows: John | ELC Trainer
```

**New:** Aggregated count of ELC trainers per week
```sql
COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END)
-- Result: 45 (total ELC trainers in that week)
```

---

#### Trainers with Score > 75
**Original:** Row-level data showing `score_range` for each trainer
```sql
CASE WHEN score > 75 THEN 'Greater than 75' ELSE 'Less than 75' END
-- Result: "Greater than 75" (for one trainer)
```

**New:** Count of trainers with score > 75 per week
```sql
COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END)
-- Result: 28 (trainers with score > 75 in that week)
```

---

#### Trainers with ELC PIP % < 20
**Original:** Row-level data showing `ELC_PIP_LESS_20` for each trainer
```sql
CASE WHEN elc_pip_pct < 20 THEN 'Less Than 20' ELSE 'Greater than 20' END
-- Result: "Less Than 20" (for one trainer)
```

**New:** Count of trainers with PIP < 20% per week
```sql
COUNT(DISTINCT CASE WHEN elc_pip_pct < 20 THEN trainer END)
-- Result: 35 (trainers with PIP < 20% in that week)
```

---

#### Trainers < 60 Days
**Original:** Row-level `tmm` (days since first screening)
```sql
DATEDIFF('day', first_screening, CURRENT_DATE()) AS tmm
-- Result: 45 (days for one trainer)
```

**New:** Count of trainers with < 60 days experience
```sql
COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END)
-- Where age_tm = 'ELC Trainer' means tmm <= 60
-- Result: 45 (total trainers < 60 days in that week)
```

---

## What Stayed the Same

### 1. Base Data Logic
All the underlying CTEs remain unchanged:
- `view1` - Pre-training and post-training metrics
- `view2` - Provider performance and lifecycle metrics
- `final` - Joins view1 and view2
- `tm_age` - Trainer age calculation

### 2. Metric Calculations
All core metrics are calculated the same way:
- **Score formula:** `(0.1 × sp_pct) + (0.15 × sp_tp_pct) + (0.15 × tp_pct) + (0.6 × (100 - elc_pip_pct))`
- **ELC PIP %:** Based on cycle 1 & 2 PIP status
- **Trainer Age:** `DATEDIFF('day', first_screening, CURRENT_DATE())`
- **ELC Definition:** Trainers with <= 60 days since first screening

### 3. Filters
- `hh_eligible > 20` (only trainers managing > 20 eligible partners)
- `customer_category_key = 'insta_maids'`
- Date filters: `> '2025-01-01'`

---

## SQL Structure Comparison

### Original Query Structure
```
WITH view1 AS (...)
   , view2 AS (...)
   , final AS (...)
   , POCO AS (...)
   , tm_age AS (...)
SELECT trainer, week, hh_eligible, score, elc_pip_pct, ...
FROM final
LEFT JOIN tm_age
WHERE hh_eligible > 20
```

### New Query Structure
```
WITH view1 AS (...)
   , view2 AS (...)
   , final AS (...)
   , POCO AS (...)
   , tm_age AS (...)
   , base_data AS (
       SELECT trainer, week, score, elc_pip_pct, age_tm, ...
       FROM final
       LEFT JOIN tm_age
       WHERE hh_eligible > 20
   )
SELECT 
    week,
    COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END),
    COUNT(DISTINCT CASE WHEN score > 75 THEN trainer END),
    ...
FROM base_data
GROUP BY week
```

**Key Addition:** 
- Added `base_data` CTE (same as your original final SELECT)
- Added final aggregation layer with `GROUP BY week`

---

## Example Data Transformation

### Input (base_data - same as your original output)
| trainer | week       | age_tm      | score | elc_pip_pct | hh_eligible |
|---------|------------|-------------|-------|-------------|-------------|
| John    | 2025-01-06 | ELC Trainer | 78.3  | 15.2        | 25          |
| Sarah   | 2025-01-06 | ELC Trainer | 82.1  | 12.5        | 30          |
| Mike    | 2025-01-06 | LLC Trainer | 68.5  | 25.3        | 22          |
| Lisa    | 2025-01-06 | ELC Trainer | 72.0  | 18.5        | 28          |
| Alex    | 2025-01-06 | ELC Trainer | 65.0  | 22.0        | 24          |

### Output (pivoted view)
| Week       | Total_ELC_Trainers | Trainers_Score_GT_75 | Trainers_ELC_PIP_LT_20_PCT | Trainers_LT_60_Days |
|------------|--------------------|-----------------------|----------------------------|---------------------|
| 2025-01-06 | 4                  | 2                     | 3                          | 4                   |

**Breakdown:**
- **Total_ELC_Trainers = 4:** John, Sarah, Lisa, Alex (all have age_tm = 'ELC Trainer')
- **Trainers_Score_GT_75 = 2:** John (78.3), Sarah (82.1)
- **Trainers_ELC_PIP_LT_20_PCT = 3:** John (15.2), Sarah (12.5), Lisa (18.5)
- **Trainers_LT_60_Days = 4:** Same as Total_ELC_Trainers

---

## How to Revert to Original Format

If you need the original trainer-level detail view, simply remove the aggregation:

```sql
-- Instead of the final aggregation:
SELECT 
    trainer,
    week,
    hh_eligible,
    age_tm,
    score,
    elc_pip_pct,
    CASE WHEN score > 75 THEN 'Greater than 75' ELSE 'Less than 75' END AS score_range,
    DENSE_RANK() OVER(PARTITION BY week ORDER BY score DESC) AS FINAL_RANK
FROM base_data
ORDER BY week DESC, FINAL_RANK ASC;
```

---

## Files Reference

1. **`weekly_trainer_performance_pivot_final.sql`** - Main pivoted query (weeks as rows, metrics as columns)
2. **`weekly_trainer_performance_pivot.sql`** - Static pivot (metrics as rows, weeks as columns)
3. **`SOLUTION_GUIDE.md`** - Comprehensive documentation
4. **`CHANGES_SUMMARY.md`** - This file (transformation details)

---

## Quick Decision Guide

**Use the ORIGINAL query when:**
- You need trainer-level details
- You want to see individual scores and rankings
- You're drilling down into specific trainers
- You need all the intermediate metrics (sp_pct, sp_tp_pct, tp_pct)

**Use the NEW PIVOTED query when:**
- You need weekly summary statistics
- You're tracking trends over time
- You want to see overall team performance
- You're creating executive dashboards
- You need a quick weekly snapshot

---

## Next Steps

1. **Test the query:** Run `weekly_trainer_performance_pivot_final.sql` on a small date range
2. **Validate numbers:** Compare aggregated counts with original query results
3. **Customize:** Modify thresholds (75, 20, 60) based on your needs
4. **Integrate:** Connect to your BI tool or create a Snowflake view
5. **Automate:** Schedule the query to run weekly

---

## Questions?

If you need to:
- Add more metrics → See "Additional Metrics" in SOLUTION_GUIDE.md
- Change thresholds → See "Filtering and Modifications" in SOLUTION_GUIDE.md
- Optimize performance → See "Performance Optimization Tips" in SOLUTION_GUIDE.md
- Troubleshoot issues → See "Troubleshooting" in SOLUTION_GUIDE.md
