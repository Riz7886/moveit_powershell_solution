# PYX Databricks Cost Analysis & SQL Performance
## Runaway Cost Scenarios + SQL Warehouse Optimization Guide

---

**Prepared For:** Preyash Patel - PYX Health  
**Date:** February 20, 2026  
**Subject:** Databricks Compute Runaway Cost Analysis & SQL Performance Solutions  
**Environments:** PreProd & Production (pyx-warehouse-prod, pyxlake-databricks)  

---

## 📊 Executive Summary

Based on your current Databricks usage and recent cost baseline, this document provides:

✅ **Current Cost Baseline** - Your actual costs right now  
✅ **Minimum Utilization Scenario** - Best case with optimizations  
✅ **Maximum Utilization Scenario** - Worst case runaway costs  
✅ **SQL Warehouse Upgrade Analysis** - Cost of going one tier higher  
✅ **SQL Performance Solutions** - Fix slow query complaints  

**Your Current Baseline (from cost summary):**
```
PreProd:
- Processing Cluster: $175 → $350 (+$175)
- Other Resources: -$300 → -$300 ($0)

Production:
- Processing Cluster: $175 → $350 (+$175)
- SQL Warehouses: -$480 → -$480 ($0)
- Other Resources: -$100 → -$100 ($0)

TOTAL (Both Environments): -$1,130 → -$1,480 (+$350 increase)
```

---

## 💰 PART 1: Runaway Cost Analysis

### 1.1 Understanding Databricks Cost Components

| Component | Your Environments | Cost Impact |
|-----------|------------------|-------------|
| **Processing Clusters** | PreProd + Production | 🔴 HIGHEST ($350 each) |
| **SQL Warehouses** | Production only | 🔴 HIGH ($480 total) |
| **DBU Consumption** | All compute | 🔴 HIGH (usage-based) |
| **Cluster Runtime** | How long clusters run | 🟡 MEDIUM |
| **Storage (Delta Lake)** | Data storage | 🟢 LOW (~$50-100) |
| **Network Egress** | Data transfer out | 🟢 LOW (~$20-50) |

---

### 1.2 SCENARIO 1: MINIMUM Utilization (Best Case - Optimized)

**Assumptions:**
- ✅ Clusters run only during business hours (8 hours/day, M-F)
- ✅ Auto-termination enabled (15-30 min idle timeout)
- ✅ Autoscaling at minimum workers
- ✅ No ad-hoc clusters left running
- ✅ SQL Warehouses auto-stop after 15 min idle
- ✅ Queries optimized for performance
- ✅ Scheduled jobs run efficiently

**Monthly Cost Breakdown - MINIMUM:**

| Environment | Resource | Configuration | Hours/Month | Est. Cost |
|-------------|----------|---------------|-------------|-----------|
| **PreProd** | Processing Cluster | Small (2 workers) | ~170 hrs | $200 |
| PreProd | Other Resources | Minimal usage | - | $150 |
| **PreProd Subtotal** | | | | **$350** |
| | | | | |
| **Production** | Processing Cluster | Small (2-4 workers) | ~180 hrs | $250 |
| Production | SQL Warehouse (primary) | 2X-Small | ~200 hrs | $300 |
| Production | SQL Warehouse (backup) | X-Small | ~80 hrs | $100 |
| Production | Other Resources | Minimal | - | $80 |
| **Production Subtotal** | | | | **$730** |
| | | | | |
| **TOTAL MINIMUM** | | | | **$1,080/month** |

**Savings vs Current:** $1,480 - $1,080 = **$400/month savings** ✅

---

### 1.3 SCENARIO 2: MAXIMUM Utilization (Worst Case - RUNAWAY 🔥)

**Assumptions:**
- ❌ Clusters run 24/7 (no auto-termination)
- ❌ Autoscaling at maximum workers
- ❌ Multiple ad-hoc clusters created and left running
- ❌ SQL Warehouses running continuously
- ❌ Inefficient queries causing long runtimes
- ❌ Oversized cluster selections
- ❌ No query optimization

**Monthly Cost Breakdown - MAXIMUM:**

| Environment | Resource | Configuration | Hours/Month | Est. Cost |
|-------------|----------|---------------|-------------|-----------|
| **PreProd** | Processing Cluster | Large (8 workers) | ~730 hrs | $1,600 |
| PreProd | Ad-hoc Clusters | Multiple (3-5) | ~400 hrs | $550 |
| PreProd | Other Resources | High usage | - | $250 |
| **PreProd Subtotal** | | | | **$2,400** |
| | | | | |
| **Production** | Processing Cluster | Large (8-12 workers) | ~730 hrs | $2,200 |
| Production | SQL Warehouse (primary) | Large | ~730 hrs | $2,800 |
| Production | SQL Warehouse (backup) | Medium | ~730 hrs | $1,400 |
| Production | Ad-hoc Clusters | Multiple (2-4) | ~300 hrs | $450 |
| Production | Other Resources | High usage | - | $200 |
| **Production Subtotal** | | | | **$7,050** |
| | | | | |
| **TOTAL MAXIMUM** | | | | **$9,450/month** 🔥 |

**Increase vs Current:** $9,450 - $1,480 = **$7,970/month MORE** ⚠️  
**That's a 6.4X INCREASE from current baseline!**

---

### 1.4 Common Runaway Cost Triggers

#### 🔥 **Trigger #1: Clusters Running 24/7**
**Monthly Impact:** +$2,000 - $4,000

**What causes this:**
- Auto-termination disabled or timeout set too high (>2 hours)
- Interactive clusters left running overnight/weekends
- Job clusters configured with "keep alive after job completion"

**Real Example:**
```
Small Processing Cluster:
- Business hours only (170 hrs): $250/month ✓
- Running 24/7 (730 hrs): $1,100/month ❌
- WASTE: $850/month
```

---

#### 🔥 **Trigger #2: Oversized Clusters**
**Monthly Impact:** +$1,000 - $2,500

**What causes this:**
- Selecting "Large" cluster for small workload
- Not using autoscaling (fixed large cluster size)
- Max workers set too high in autoscaling config

**Real Example:**
```
SQL Warehouse for 5 concurrent users:
- Right size (2X-Small, 2 workers): $300/month ✓
- Oversized (Large, 8 workers): $1,400/month ❌
- WASTE: $1,100/month
```

---

#### 🔥 **Trigger #3: Inefficient SQL Queries**
**Monthly Impact:** +$500 - $1,500

**What causes this:**
- Full table scans instead of partitioned reads
- Missing or unused indexes
- Queries pulling unnecessary columns (SELECT *)
- No query result caching
- Complex joins on large tables

**Real Example:**
```
Daily report query:
- Optimized (2 min runtime): $0.05/run → $1.50/month ✓
- Unoptimized (1 hour runtime): $1.50/run → $45/month ❌
- WASTE per query: $43.50/month
- 10 slow queries = $435/month waste
```

---

#### 🔥 **Trigger #4: Ad-Hoc Clusters Forgotten**
**Monthly Impact:** +$300 - $1,000

**What causes this:**
- Data scientists/analysts create clusters for testing
- Clusters not terminated after work session
- No organization-wide auto-termination policy

**Real Example:**
```
3 ad-hoc clusters left running:
- Properly terminated after use: $50/month ✓
- Running 24/7 for 30 days: $550/month ❌
- WASTE: $500/month
```

---

## 💵 PART 2: SQL Warehouse Tier Upgrade Cost Analysis

### 2.1 Current SQL Warehouse Configuration

Based on your cost baseline, here's what you're running:

**Production SQL Warehouses: $480/month total**

Estimated current setup:
- **Primary Warehouse:** 2X-Small (1 cluster, ~200 hours/month) = ~$300
- **Secondary Warehouse:** X-Small (1 cluster, ~80 hours/month) = ~$180

---

### 2.2 Cost of Going ONE TIER HIGHER

**Option A: Upgrade Primary Warehouse Only (Most Common)**

| Current Size | Upgraded Size | Current Cost | New Cost | Increase |
|--------------|---------------|--------------|----------|----------|
| 2X-Small | **X-Small** | $300 | $550 | **+$250/month** |
| 2X-Small | **Small** | $300 | $850 | **+$550/month** |

**Option B: Upgrade Both Warehouses**

| Warehouse | Current | Upgraded | Current Cost | New Cost | Increase |
|-----------|---------|----------|--------------|----------|----------|
| Primary | 2X-Small | **X-Small** | $300 | $550 | +$250 |
| Secondary | X-Small | **Small** | $180 | $350 | +$170 |
| **TOTAL** | | | **$480** | **$900** | **+$420/month** |

---

### 2.3 Azure Databricks SQL Warehouse Pricing (Current)

**Based on Azure East US 2 pricing (typical for PYX):**

| Warehouse Size | DBUs/Hour | $/Hour (approx) | 200 hrs/mo | 400 hrs/mo | 730 hrs/mo (24/7) |
|----------------|-----------|-----------------|------------|------------|-------------------|
| **2X-Small** | 2 | $0.44 | $88 | $176 | $321 |
| **X-Small** | 4 | $0.88 | $176 | $352 | $642 |
| **Small** | 8 | $1.76 | $352 | $704 | $1,285 |
| **Medium** | 16 | $3.52 | $704 | $1,408 | $2,570 |
| **Large** | 32 | $7.04 | $1,408 | $2,816 | $5,139 |

**Note:** Actual costs may vary based on:
- Your specific Azure subscription/pricing
- Region (East US, West US, etc.)
- Auto-stop settings
- Actual usage hours

---

### 2.4 Upgrade Recommendation Based on Use Case

**If you have 5-10 concurrent users:**
```
CURRENT: 2X-Small ($300/month)
RECOMMENDED: X-Small ($550/month) = +$250/month
BENEFIT: 2x performance, better concurrency
```

**If you have 10-20 concurrent users or slow queries:**
```
CURRENT: 2X-Small ($300/month)
RECOMMENDED: Small ($850/month) = +$550/month
BENEFIT: 4x performance, handles more users
```

**If you have 20+ concurrent users:**
```
CURRENT: 2X-Small ($300/month)
RECOMMENDED: Medium ($1,400/month) = +$1,100/month
BENEFIT: 8x performance, enterprise-grade
```

---

## 🚀 PART 3: SQL Performance Optimization (No Cost)

### 3.1 Addressing Slow SQL Warehouse Queries

**Common Complaints:**
- "Queries are taking too long"
- "Dashboard loads slowly"
- "Reports timeout"
- "Users complaining about delays"

---

### 3.2 FREE Performance Improvements (Before Upgrading Tier)

#### ✅ **Solution 1: Optimize Query Structure**

**Problem:** Full table scans on large tables

**Fix:**
```sql
-- BAD: Scans entire table
SELECT * FROM large_table WHERE date = '2026-02-20'

-- GOOD: Uses partition pruning
SELECT col1, col2, col3 
FROM large_table 
WHERE date_partition = '2026-02-20'
AND col1 IS NOT NULL
```

**Impact:** 5-10x faster queries, no cost increase

---

#### ✅ **Solution 2: Enable Query Result Caching**

**Problem:** Same query runs multiple times, recomputing each time

**Fix:** Enable result caching in SQL Warehouse settings

```
Settings → SQL Warehouse → Advanced → Result Caching: ON
Cache duration: 24 hours
```

**Impact:** Instant results for repeated queries, saves DBUs

---

#### ✅ **Solution 3: Use Delta Lake Optimization**

**Problem:** Small files causing slow reads

**Fix:**
```sql
-- Run weekly on large tables
OPTIMIZE your_table_name;

-- For tables with frequent updates
OPTIMIZE your_table_name ZORDER BY (commonly_filtered_column);
```

**Impact:** 2-3x faster queries, better compression

---

#### ✅ **Solution 4: Create Materialized Views**

**Problem:** Complex joins/aggregations run every time

**Fix:**
```sql
-- Create pre-computed view for heavy queries
CREATE OR REFRESH MATERIALIZED VIEW daily_summary AS
SELECT 
  date,
  category,
  SUM(amount) as total_amount,
  COUNT(*) as record_count
FROM transactions
GROUP BY date, category;

-- Use materialized view instead of base tables
SELECT * FROM daily_summary WHERE date = '2026-02-20';
```

**Impact:** 10-100x faster, runs on schedule

---

#### ✅ **Solution 5: Add Strategic Indexes**

**Problem:** Slow lookups on large tables

**Fix:**
```sql
-- For Delta tables in Unity Catalog
CREATE BLOOMFILTER INDEX ON table_name(frequently_filtered_column);
```

**Impact:** 3-5x faster point lookups

---

#### ✅ **Solution 6: Enable Auto-Scaling for SQL Warehouse**

**Problem:** Query queuing during peak times

**Fix:**
```
Current: 1 cluster, fixed
Recommended: Min 1, Max 2-3 clusters (auto-scale)
```

**Settings:**
- Min clusters: 1
- Max clusters: 2 (for moderate load) or 3 (for high load)
- Auto-stop: 15 minutes

**Cost Impact:** Only pay for extra clusters when actually needed  
**Performance Impact:** No query queuing, better user experience

---

### 3.3 Query Performance Monitoring

**Set up monitoring to identify slow queries:**

```sql
-- Find slowest queries (run in SQL Editor)
SELECT 
  query_text,
  execution_time_ms / 1000.0 as execution_seconds,
  rows_produced,
  user_name,
  start_time
FROM system.query.history
WHERE warehouse_id = '<your_warehouse_id>'
  AND start_time > current_date() - 7
ORDER BY execution_time_ms DESC
LIMIT 20;
```

**Identify:**
- Queries taking >30 seconds
- Queries with full table scans
- Queries called frequently but not cached

---

## 📋 PART 4: Cost Control Strategies

### 4.1 Immediate Actions (Zero Cost)

| Action | Impact | How To |
|--------|--------|--------|
| **Enable Auto-Termination** | -30% cost | Set 30 min timeout on all clusters |
| **Auto-Stop SQL Warehouses** | -20% cost | Set 15 min auto-stop timeout |
| **Optimize Heavy Queries** | -15% cost | Apply fixes from Section 3.2 |
| **Remove Unused Clusters** | -10% cost | Delete inactive/test clusters |
| **Schedule Jobs Properly** | -10% cost | Avoid overlapping job runs |

**Total Potential Savings: ~$400-600/month**

---

### 4.2 Cluster Configuration Best Practices

#### **Processing Clusters:**

```json
Recommended Config:
{
  "autoscale": {
    "min_workers": 2,
    "max_workers": 6
  },
  "autotermination_minutes": 30,
  "spark_conf": {
    "spark.databricks.adaptive.autoOptimizeShuffle.enabled": "true"
  }
}
```

#### **SQL Warehouses:**

```
Size: 2X-Small or X-Small (for <20 users)
Clusters: Min 1, Max 2
Auto-stop: 15 minutes
Serverless: Disabled (to avoid cost spikes)
```

---

### 4.3 Set Up Cost Alerts

**Create Azure Budget Alerts:**

1. Go to Azure Portal → Cost Management → Budgets
2. Create budget for Databricks resource group:
   - **Warning Threshold:** $1,800/month (120% of baseline)
   - **Critical Threshold:** $2,500/month (170% of baseline)
3. Alert recipients: Your team + finance
4. Check budget: Weekly

---

### 4.4 Monthly Cost Review Checklist

**Run this check first Monday of each month:**

- [ ] Review top 10 most expensive clusters
- [ ] Check for clusters running >400 hours/month
- [ ] Identify queries taking >1 minute
- [ ] Remove unused/stale clusters
- [ ] Verify auto-termination is enabled
- [ ] Check SQL Warehouse utilization
- [ ] Review DBU consumption trends

---

## 🎯 PART 5: Recommended Action Plan

### Phase 1: Quick Wins (This Week) - FREE

1. ✅ Enable auto-termination on all clusters (30 min timeout)
2. ✅ Set SQL Warehouse auto-stop to 15 minutes
3. ✅ Enable query result caching
4. ✅ Run OPTIMIZE on top 5 largest tables
5. ✅ Set up Azure budget alerts

**Expected Savings:** $300-400/month

---

### Phase 2: Query Optimization (Next 2 Weeks) - FREE

1. ✅ Identify top 10 slowest queries
2. ✅ Add partition filters to slow queries
3. ✅ Create materialized views for heavy dashboards
4. ✅ Implement ZORDER on frequently filtered columns
5. ✅ Train team on query best practices

**Expected Result:** 2-5x faster queries, no cost increase

---

### Phase 3: If Still Slow - Consider Tier Upgrade

**Only upgrade if Steps 1-2 don't solve performance issues**

**Conservative Option:**
- Upgrade Primary SQL Warehouse: 2X-Small → X-Small
- Cost increase: +$250/month
- Performance gain: 2x faster

**Aggressive Option:**
- Upgrade Primary SQL Warehouse: 2X-Small → Small
- Cost increase: +$550/month
- Performance gain: 4x faster

---

## 📊 Summary Table: Cost Scenarios

| Scenario | Monthly Cost | vs Current | Description |
|----------|--------------|------------|-------------|
| **Current Baseline** | $1,480 | - | Your current spend |
| **Minimum (Optimized)** | $1,080 | **-$400** ✅ | Best practices applied |
| **Current + SQL Upgrade (X-Small)** | $1,730 | **+$250** | 2x SQL performance |
| **Current + SQL Upgrade (Small)** | $2,030 | **+$550** | 4x SQL performance |
| **Maximum (Runaway)** | $9,450 | **+$7,970** 🔥 | Worst case scenario |

---

## 📝 Final Recommendations for Preyash

### 1. **Start with FREE optimizations** (Phases 1-2)
   - Apply quick wins this week
   - Optimize queries over next 2 weeks
   - Measure performance improvement

### 2. **Monitor for 2-4 weeks**
   - Track query performance
   - Gather user feedback
   - Check if complaints decrease

### 3. **Only upgrade tier if needed**
   - If still slow after optimizations → Upgrade to X-Small (+$250/month)
   - If handling more users → Consider Small (+$550/month)
   - If performance is good → Stay current, save money

### 4. **Set up cost controls**
   - Enable all auto-termination settings
   - Set up budget alerts
   - Monthly cost review meetings

---

## 🆘 Quick Reference: Key Numbers

```
BASELINE COSTS:
- PreProd: $350/month
- Production: $1,130/month
- TOTAL: $1,480/month

OPTIMIZED (BEST CASE):
- PreProd: $350/month
- Production: $730/month
- TOTAL: $1,080/month (-$400 savings)

RUNAWAY (WORST CASE):
- PreProd: $2,400/month
- Production: $7,050/month
- TOTAL: $9,450/month (+$7,970 increase!)

SQL WAREHOUSE UPGRADES:
- 2X-Small → X-Small: +$250/month
- 2X-Small → Small: +$550/month
- 2X-Small → Medium: +$1,100/month
```

---

**Document Prepared By:** Syed Rizvi  
**For:** Preyash Patel - PYX Health  
**Date:** February 20, 2026  
**Version:** 1.0  

---

**Need Help?** Contact Azure support or Databricks team for:
- Detailed usage reports
- Query optimization consultation
- Cost analysis reviews
