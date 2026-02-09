# PIP Percentage Calculation - Issue Analysis

## Problem Summary

The original query was producing inaccurate PIP percentages because it was counting churned providers in the PIP count (`pip_px`) but excluding them from the total active providers count (`active_px`).

## Root Cause

### Original Logic (INCORRECT):

```sql
pip_tm AS (
  SELECT
    tm.trainer_name AS tm,
    COUNT(
      DISTINCT CASE
        WHEN pb.is_pip = 1 THEN pb.provider_id  -- ❌ Includes churned providers
      END
    ) AS pip_px,
    COUNT(
      DISTINCT CASE
        WHEN COALESCE(c.churn_status, 'active') <> 'churn' THEN pb.provider_id
      END
    ) AS active_px
  ...
)
```

**What was happening:**
- `pip_px`: Counted ALL providers where `is_pip = 1` → Could include churned providers
- `active_px`: Counted only providers where `churn_status <> 'churn'`

**Example of incorrect calculation:**
- Trainer has 10 total providers
- 3 are on PIP (2 active, 1 churned)
- 8 are active (not churned)

Original calculation:
- `pip_px` = 3 (includes 1 churned)
- `active_px` = 8
- `pip%` = 3/8 = **37.5%** ❌

Correct calculation:
- `pip_px` = 2 (only active PIP providers)
- `active_px` = 8
- `pip%` = 2/8 = **25.0%** ✅

## Solution

### Corrected Logic:

```sql
pip_tm AS (
  SELECT
    tm.trainer_name AS tm,
    COUNT(
      DISTINCT CASE
        WHEN pb.is_pip = 1 
        AND COALESCE(c.churn_status, 'active') <> 'churn'  -- ✅ Only active providers
        THEN pb.provider_id
      END
    ) AS pip_px,
    COUNT(
      DISTINCT CASE
        WHEN COALESCE(c.churn_status, 'active') <> 'churn' 
        THEN pb.provider_id
      END
    ) AS active_px
  ...
)
```

**Now both metrics:**
- Exclude churned providers
- Are directly comparable
- Produce accurate PIP percentages

## Key Changes

1. **Added churn status check to pip_px**: Now only counts active providers on PIP
2. **Added direct pip_percentage calculation**: Eliminates external calculation errors
3. **Added zero-division protection**: Returns 0% when no active providers exist

## Testing Recommendations

To verify the fix:

1. Check trainers with known churned PIP providers
2. Compare old vs new pip_percentage values
3. Validate that pip_px ≤ active_px in all cases (must be true)
4. Verify edge cases (trainers with no active providers)
