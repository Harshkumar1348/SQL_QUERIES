# Query A Fix — Excluding Partners Blocked for 'verification failed'

## The Problem

The `NOT EXISTS` clause in the `base` CTE was intended to exclude partners whose ID
was blocked for reason **'verification failed'** within a 15-day window starting from
their `approval_date`. However, the original condition only had an **upper bound** and
was **missing the lower bound**, meaning it also excluded partners blocked *before*
their approval date.

## Original (Buggy) Condition

```sql
AND REGEXP_SUBSTR(t.value:created_at::STRING, '[0-9]+')::TIMESTAMP
    <= DATE(b.approval_date) + INTERVAL '15 days'
```

This reads: "block timestamp is any time up to approval_date + 15 days." It has **no
lower bound**, so a block that occurred years before the approval date would still
cause the partner to be excluded — which is not the intended behavior.

## Fixed Condition

```sql
AND REGEXP_SUBSTR(t.value:created_at::STRING, '[0-9]+')::TIMESTAMP
    BETWEEN DATE(b.approval_date) AND DATE(b.approval_date) + INTERVAL '15 days'
```

This reads: "block timestamp falls within the window from `approval_date` to
`approval_date + 15 days`." Only blocks that occurred in this exact window will cause
the partner to be excluded.

## Summary of the Business Rule

> If a partner is approved today, check from today to the next 15 days whether they
> were blocked due to 'verification failed'. If yes, exclude that partner from the
> results.

The `BETWEEN` operator correctly enforces both the start (`approval_date`) and end
(`approval_date + 15 days`) of the window.
