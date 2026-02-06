# Weekly Trainer Performance - Pivoted View

## 📊 Overview

This repository contains SQL queries to analyze trainer performance with a **pivoted view** showing weekly metrics for trainers in the **Early Life Cycle (ELC)** - those with less than 60 days of experience.

## 🎯 What This Solves

Transforms detailed trainer-level data into a weekly summary showing:
1. **Total ELC Trainers** in each week
2. **Trainers with Score > 75** (high performers)
3. **Trainers with ELC PIP % < 20** (low PIP rate)
4. **Trainers < 60 Days** (new trainers)

## 📁 Files

| File | Description | When to Use |
|------|-------------|-------------|
| **`weekly_trainer_performance_pivot_final.sql`** ⭐ | **RECOMMENDED** - Weeks as rows, metrics as columns | Most use cases, easy to read, works in all BI tools |
| `weekly_trainer_performance_pivot.sql` | Metrics as rows, weeks as columns (static) | Fixed reporting periods, transposed view |
| `weekly_trainer_performance_pivot_dynamic.sql` | Experimental dynamic pivot | Testing purposes only |
| **`SOLUTION_GUIDE.md`** 📖 | Complete documentation | Understanding metrics, customization, troubleshooting |
| `CHANGES_SUMMARY.md` | What changed from original query | See transformation details |
| `README.md` | This file | Quick start guide |

## 🚀 Quick Start

### 1. Run the Query

**Option A: Direct Execution**
```sql
-- Copy the entire content of weekly_trainer_performance_pivot_final.sql
-- Paste into Snowflake SQL editor
-- Execute
```

**Option B: Create a View**
```sql
CREATE OR REPLACE VIEW trainer_performance_weekly AS
-- Paste the entire query from weekly_trainer_performance_pivot_final.sql here
;

-- Query the view
SELECT * FROM trainer_performance_weekly
WHERE "Week" >= '2025-01-01'
ORDER BY "Week" DESC;
```

### 2. Expected Output

```
Week       | Total_ELC_Trainers | Trainers_Score_GT_75 | Trainers_ELC_PIP_LT_20_PCT | Trainers_LT_60_Days
-----------|--------------------|-----------------------|----------------------------|---------------------
2025-02-03 | 45                 | 28                    | 35                         | 45
2025-01-27 | 42                 | 25                    | 33                         | 42
2025-01-20 | 38                 | 22                    | 30                         | 38
```

## 📊 Metrics Explained

### 1️⃣ Total ELC Trainers
Count of trainers in Early Life Cycle (< 60 days since first screening)

### 2️⃣ Trainers with Score > 75
Count of trainers with composite performance score above 75

**Score Formula:**
```
Score = (10% × Screening Pass %) 
      + (15% × Screening to Training Pass %)
      + (15% × Training Pass %)
      + (60% × (100 - ELC PIP %))
```

### 3️⃣ Trainers with ELC PIP % < 20
Count of trainers with Performance Improvement Plan rate below 20%

### 4️⃣ Trainers < 60 Days
Count of trainers with less than 60 days experience (same as metric #1)

## 🛠️ Customization

### Change Score Threshold (from 75 to 80)
```sql
COUNT(DISTINCT CASE WHEN score > 80 THEN trainer END)
```

### Change PIP Threshold (from 20% to 15%)
```sql
COUNT(DISTINCT CASE WHEN elc_pip_pct < 15 THEN trainer END)
```

### Change Days Threshold (from 60 to 90 days)
In the `tm_age` CTE:
```sql
CASE 
    WHEN tmm > 90 THEN 'LLC Trainer'  -- Changed from 60
    ELSE 'ELC Trainer'
END AS age_tm
```

### Add More Metrics
```sql
SELECT 
    week,
    COUNT(DISTINCT CASE WHEN age_tm = 'ELC Trainer' THEN trainer END) AS "Total_ELC_Trainers",
    -- ... existing metrics ...
    AVG(score) AS "Average_Score",  -- NEW
    MAX(score) AS "Top_Score",      -- NEW
    COUNT(DISTINCT trainer) AS "Total_Trainers"  -- NEW
FROM base_data
GROUP BY week
```

## 📈 Use Cases

### Executive Dashboard
```sql
-- Weekly snapshot for leadership
SELECT * FROM trainer_performance_weekly
WHERE "Week" >= DATEADD('week', -8, CURRENT_DATE())
ORDER BY "Week" DESC;
```

### Trend Analysis
```sql
-- Compare week-over-week changes
SELECT 
    "Week",
    "Total_ELC_Trainers",
    LAG("Total_ELC_Trainers") OVER (ORDER BY "Week") AS prev_week,
    "Total_ELC_Trainers" - LAG("Total_ELC_Trainers") OVER (ORDER BY "Week") AS change
FROM trainer_performance_weekly
ORDER BY "Week" DESC;
```

### Performance Benchmarking
```sql
-- Weeks where performance exceeded targets
SELECT * FROM trainer_performance_weekly
WHERE "Trainers_Score_GT_75" >= 25
  AND "Trainers_ELC_PIP_LT_20_PCT" >= 30
ORDER BY "Week" DESC;
```

## 🔍 Troubleshooting

| Issue | Solution |
|-------|----------|
| Query runs slow | Add date filters early in CTEs, check indexes |
| Missing weeks | Verify `hh_eligible > 20` filter, check base data |
| Incorrect counts | Validate `DISTINCT` is used, check trainer mapping |
| Null values | Expected when no data exists, review NULLIF usage |

## 📚 Documentation

- **Complete Guide:** See [`SOLUTION_GUIDE.md`](SOLUTION_GUIDE.md)
- **Transformation Details:** See [`CHANGES_SUMMARY.md`](CHANGES_SUMMARY.md)
- **Original Query:** Available in your existing codebase

## ⚡ Performance Tips

1. **Add date filters** at the earliest CTEs
2. **Create indexes** on `provider_id`, `customer_category_key`, date columns
3. **Materialize intermediate results** for large datasets
4. **Use clustering** for frequently queried tables
5. **Limit date range** to last 12-16 weeks for faster results

## 🎓 Key Concepts

### ELC (Early Life Cycle)
Trainers with ≤ 60 days since their first screening. These are new trainers requiring close monitoring.

### LLC (Late Life Cycle)
Trainers with > 60 days experience. More established trainers.

### PIP (Performance Improvement Plan)
Partners/providers who don't meet performance standards (rating errors, PAF errors, or excessive leaves).

### Composite Score
Weighted performance metric combining screening, training, and PIP metrics.

## 🔗 Integration

### Tableau / Power BI
1. Connect to Snowflake
2. Use Custom SQL
3. Paste query from `weekly_trainer_performance_pivot_final.sql`
4. Create visualizations

### Looker
```lkml
view: trainer_performance_weekly {
  sql_table_name: (
    -- Paste query here
  ) ;;
  
  dimension: week {
    type: date
    sql: ${TABLE}."Week" ;;
  }
  
  measure: total_elc_trainers {
    type: sum
    sql: ${TABLE}."Total_ELC_Trainers" ;;
  }
  
  # ... more dimensions and measures
}
```

### Python / Pandas
```python
import snowflake.connector
import pandas as pd

# Read query from file
with open('weekly_trainer_performance_pivot_final.sql', 'r') as f:
    query = f.read()

# Execute query
conn = snowflake.connector.connect(...)
df = pd.read_sql(query, conn)

# Analyze
print(df.head())
df.plot(x='Week', y='Total_ELC_Trainers')
```

## 📊 Example Visualizations

### Time Series Chart
- X-axis: Week
- Y-axis: Counts
- Lines: Each of the 4 metrics
- Shows trends over time

### KPI Cards
- Large numbers showing latest week's metrics
- Week-over-week % change
- Color coded (green/red) based on targets

### Heat Map
- Rows: Metrics
- Columns: Weeks
- Color intensity: Metric values
- Quick pattern identification

## 🎯 Business Questions Answered

1. **"How many new trainers do we have each week?"**
   → `Total_ELC_Trainers` column

2. **"What % of trainers are high performers?"**
   → `Trainers_Score_GT_75 / Total_ELC_Trainers × 100`

3. **"Is our training program improving?"**
   → Trend of `Trainers_Score_GT_75` over weeks

4. **"Are we reducing PIP rates?"**
   → Trend of `Trainers_ELC_PIP_LT_20_PCT` over weeks

5. **"What's our trainer retention?"**
   → Compare week-over-week `Total_ELC_Trainers` changes

## 🚦 Success Metrics

**Good Performance Indicators:**
- ✅ `Trainers_Score_GT_75` > 60% of `Total_ELC_Trainers`
- ✅ `Trainers_ELC_PIP_LT_20_PCT` > 80% of `Total_ELC_Trainers`
- ✅ Increasing trend in high performers over time

**Warning Signs:**
- ⚠️ Decreasing `Trainers_Score_GT_75` over consecutive weeks
- ⚠️ Decreasing `Trainers_ELC_PIP_LT_20_PCT` percentage
- ⚠️ Large week-over-week drops in `Total_ELC_Trainers`

## 📞 Support

For questions or issues:
1. Check [`SOLUTION_GUIDE.md`](SOLUTION_GUIDE.md) for detailed documentation
2. Review [`CHANGES_SUMMARY.md`](CHANGES_SUMMARY.md) for transformation details
3. Validate base table data quality
4. Test with small date ranges first

## 📝 Version

**Version:** 1.0  
**Last Updated:** February 2025  
**Database:** Snowflake  
**Schema:** insta_maids category

---

## 🏁 Getting Started Checklist

- [ ] Read this README
- [ ] Review SOLUTION_GUIDE.md
- [ ] Copy `weekly_trainer_performance_pivot_final.sql`
- [ ] Test on small date range (e.g., last 4 weeks)
- [ ] Validate counts match expectations
- [ ] Create Snowflake view or integrate with BI tool
- [ ] Set up automated weekly refresh
- [ ] Create dashboard visualizations
- [ ] Share with stakeholders

---

**Need help?** Start with the [SOLUTION_GUIDE.md](SOLUTION_GUIDE.md) for comprehensive documentation.
