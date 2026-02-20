DATABRICKS COST ANALYSIS & SQL PERFORMANCE OPTIMIZATION
PYX Health - Azure Databricks Environments

========================================================================

DOCUMENT INFORMATION
Prepared By: Syed Rizvi, Senior Systems Administrator
Prepared For: Preyash Patel, PYX Health
Date: February 20, 2026
Subject: Databricks Compute Cost Analysis & SQL Warehouse Performance
Environments: PreProd & Production (pyx-warehouse-prod, pyxlake-databricks)

========================================================================

EXECUTIVE SUMMARY

This document provides a comprehensive analysis of Databricks compute costs across PYX Health environments, including minimum and maximum utilization scenarios, SQL Warehouse upgrade cost projections, and performance optimization recommendations.

Key Analysis Components:
- Current cost baseline analysis
- Minimum utilization scenario (optimized configuration)
- Maximum utilization scenario (runaway cost projection)
- SQL Warehouse tier upgrade cost analysis
- SQL query performance optimization strategies
- Cost control and monitoring recommendations

Current Cost Baseline Summary:

PreProd Environment:
- Processing Cluster: $175 to $350 (increase of $175)
- Other Resources: $300 (no change)

Production Environment:
- Processing Cluster: $175 to $350 (increase of $175)
- SQL Warehouses: $480 (no change)
- Other Resources: $100 (no change)

Total Monthly Cost (Both Environments): $1,480 (increase of $350 from previous baseline)

========================================================================

SECTION 1: COST COMPONENT ANALYSIS

1.1 Databricks Cost Components

The following table outlines the primary cost drivers for PYX Health Databricks environments:

Component                   Environment              Impact Level    Monthly Cost Range
Processing Clusters         PreProd + Production     High           $350 each
SQL Warehouses             Production only          High           $480 total
DBU Consumption            All compute              High           Usage-based
Cluster Runtime            All environments         Medium         Variable
Storage (Delta Lake)       All environments         Low            $50-$100
Network Egress             All environments         Low            $20-$50


========================================================================

SECTION 2: UTILIZATION SCENARIOS

2.1 SCENARIO 1 - MINIMUM UTILIZATION (Optimized Configuration)

This scenario represents best-case cost optimization with the following assumptions:

Assumptions:
- Clusters operate during business hours only (8 hours/day, Monday-Friday)
- Auto-termination enabled with 15-30 minute idle timeout
- Autoscaling configured at minimum worker count
- No ad-hoc clusters left running
- SQL Warehouses configured with 15-minute auto-stop
- Queries optimized for performance
- Scheduled jobs configured for efficient execution

Monthly Cost Breakdown - Minimum Utilization Scenario:


Environment      Resource                 Configuration            Hours/Month    Est. Cost
PreProd          Processing Cluster       Small (2 workers)        170 hrs        $200
PreProd          Other Resources          Minimal usage            -              $150
PreProd Subtotal                                                                  $350

Production       Processing Cluster       Small (2-4 workers)      180 hrs        $250
Production       SQL Warehouse (primary)  2X-Small                 200 hrs        $300
Production       SQL Warehouse (backup)   X-Small                  80 hrs         $100
Production       Other Resources          Minimal                  -              $80
Production Subtotal                                                               $730

TOTAL MINIMUM UTILIZATION                                                         $1,080/month

Potential Savings vs Current Baseline: $400 per month


========================================================================

2.2 SCENARIO 2 - MAXIMUM UTILIZATION (Runaway Cost Projection)

This scenario represents worst-case cost escalation with the following conditions:

Assumptions:
- Clusters running continuously (24 hours/day, 7 days/week)
- Autoscaling configured at maximum worker count
- Multiple ad-hoc clusters created and left running
- SQL Warehouses running continuously without auto-stop
- Inefficient queries causing extended runtimes
- Oversized cluster selections for workload requirements
- No query optimization implemented

Monthly Cost Breakdown - Maximum Utilization Scenario:

Environment      Resource                 Configuration            Hours/Month    Est. Cost
PreProd          Processing Cluster       Large (8 workers)        730 hrs        $1,600
PreProd          Ad-hoc Clusters          Multiple (3-5 clusters)  400 hrs        $550
PreProd          Other Resources          High usage               -              $250
PreProd Subtotal                                                                  $2,400

Production       Processing Cluster       Large (8-12 workers)     730 hrs        $2,200
Production       SQL Warehouse (primary)  Large                    730 hrs        $2,800
Production       SQL Warehouse (backup)   Medium                   730 hrs        $1,400
Production       Ad-hoc Clusters          Multiple (2-4 clusters)  300 hrs        $450
Production       Other Resources          High usage               -              $200
Production Subtotal                                                               $7,050

TOTAL MAXIMUM UTILIZATION                                                         $9,450/month

Cost Increase vs Current Baseline: $7,970 per month (6.4X increase)


========================================================================

SECTION 3: RUNAWAY COST TRIGGERS AND MITIGATION

3.1 Critical Cost Escalation Factors

The following factors represent the most significant contributors to unexpected cost increases:


TRIGGER 1: Clusters Running Continuously (24/7)
Monthly Impact: $2,000 - $4,000

Root Causes:
- Auto-termination disabled or timeout configured above 2 hours
- Interactive clusters left running overnight and weekends
- Job clusters configured with "keep alive after completion" setting

Cost Example:
Small Processing Cluster operating during business hours (170 hours): $250/month
Same cluster running 24/7 (730 hours): $1,100/month
Cost Waste: $850/month


TRIGGER 2: Oversized Cluster Configuration
Monthly Impact: $1,000 - $2,500

Root Causes:
- Large cluster size selected for small workload requirements
- Autoscaling not utilized (fixed large cluster size)
- Maximum worker count set excessively high in autoscaling configuration

Cost Example:
SQL Warehouse for 5 concurrent users (2X-Small, 2 workers): $300/month
Oversized configuration (Large, 8 workers): $1,400/month
Cost Waste: $1,100/month


TRIGGER 3: Inefficient SQL Query Execution
Monthly Impact: $500 - $1,500

Root Causes:
- Full table scans instead of partition-based queries
- Missing or unused database indexes
- Queries pulling unnecessary columns (SELECT * operations)
- Query result caching not enabled
- Complex joins on large unoptimized tables

Cost Example:
Optimized daily report query (2 minute runtime): $0.05 per execution = $1.50/month
Unoptimized query (1 hour runtime): $1.50 per execution = $45/month
Cost Waste per query: $43.50/month
Impact across 10 slow queries: $435/month


TRIGGER 4: Abandoned Ad-Hoc Clusters
Monthly Impact: $300 - $1,000

Root Causes:
- Data science/analytics teams create clusters for testing
- Clusters not terminated after work session completion
- No organization-wide auto-termination policy enforcement

Cost Example:
Three ad-hoc clusters properly terminated after use: $50/month
Same clusters running continuously for 30 days: $550/month
Cost Waste: $500/month


========================================================================

SECTION 4: SQL WAREHOUSE TIER UPGRADE ANALYSIS

4.1 Current SQL Warehouse Configuration

Based on the cost baseline provided, the estimated current configuration is:

Production SQL Warehouses: $480/month total

Estimated breakdown:
- Primary Warehouse: 2X-Small (1 cluster, approximately 200 hours/month) = $300
- Secondary Warehouse: X-Small (1 cluster, approximately 80 hours/month) = $180


4.2 Cost Analysis for Tier Upgrades

OPTION A: Upgrade Primary Warehouse Only

Current Size    Upgraded Size    Current Monthly Cost    New Monthly Cost    Monthly Increase
2X-Small        X-Small          $300                    $550                $250
2X-Small        Small            $300                    $850                $550


OPTION B: Upgrade Both Warehouses

Warehouse     Current Size    Upgraded Size    Current Cost    New Cost    Monthly Increase
Primary       2X-Small        X-Small          $300            $550        $250
Secondary     X-Small         Small            $180            $350        $170
TOTAL                                          $480            $900        $420


4.3 Azure Databricks SQL Warehouse Pricing Reference

Based on Azure East US 2 pricing (typical for PYX Health deployments):

Warehouse Size    DBUs/Hour    $/Hour (approx)    200 hrs/mo    400 hrs/mo    730 hrs/mo (24/7)
2X-Small          2            $0.44              $88           $176          $321
X-Small           4            $0.88              $176          $352          $642
Small             8            $1.76              $352          $704          $1,285
Medium            16           $3.52              $704          $1,408        $2,570
Large             32           $7.04              $1,408        $2,816        $5,139

Note: Actual costs may vary based on specific Azure subscription pricing, geographic region, 
auto-stop settings, and actual usage hours.


4.4 Tier Upgrade Recommendations by Use Case

For 5-10 Concurrent Users:
Current Configuration: 2X-Small ($300/month)
Recommended Upgrade: X-Small ($550/month)
Monthly Cost Increase: $250
Performance Benefit: 2x performance improvement, better concurrency handling

For 10-20 Concurrent Users or Slow Query Performance:
Current Configuration: 2X-Small ($300/month)
Recommended Upgrade: Small ($850/month)
Monthly Cost Increase: $550
Performance Benefit: 4x performance improvement, handles significantly more users

For 20+ Concurrent Users:
Current Configuration: 2X-Small ($300/month)
Recommended Upgrade: Medium ($1,400/month)
Monthly Cost Increase: $1,100
Performance Benefit: 8x performance improvement, enterprise-grade capacity


========================================================================

SECTION 5: SQL QUERY PERFORMANCE OPTIMIZATION

5.1 Addressing SQL Warehouse Performance Issues

Common performance complaints include:
- Extended query execution times
- Slow dashboard loading
- Report timeout errors
- User-reported delays in data access


5.2 Performance Optimization Strategies (Zero Cost Implementation)


OPTIMIZATION 1: Query Structure Refinement

Problem: Full table scans on large datasets

Solution - Before:
SELECT * FROM large_table WHERE date = '2026-02-20'

Solution - After:
SELECT col1, col2, col3 
FROM large_table 
WHERE date_partition = '2026-02-20'
AND col1 IS NOT NULL

Performance Impact: 5-10x faster query execution, no cost increase


OPTIMIZATION 2: Query Result Caching

Problem: Identical queries re-execute and recompute results

Implementation:
Navigate to Settings → SQL Warehouse → Advanced → Result Caching: Enable
Configure cache duration: 24 hours

Performance Impact: Instant results for repeated queries, reduces DBU consumption


OPTIMIZATION 3: Delta Lake Table Optimization

Problem: Small file accumulation causing slow read performance

Implementation:
Run weekly on large tables:
OPTIMIZE your_table_name;

For frequently updated tables:
OPTIMIZE your_table_name ZORDER BY (commonly_filtered_column);

Performance Impact: 2-3x faster queries, improved compression


OPTIMIZATION 4: Materialized View Implementation

Problem: Complex joins and aggregations execute on every query

Implementation:
CREATE OR REFRESH MATERIALIZED VIEW daily_summary AS
SELECT 
  date,
  category,
  SUM(amount) as total_amount,
  COUNT(*) as record_count
FROM transactions
GROUP BY date, category;

Query using materialized view:
SELECT * FROM daily_summary WHERE date = '2026-02-20';

Performance Impact: 10-100x faster execution, runs on predefined schedule


OPTIMIZATION 5: Strategic Index Creation

Problem: Slow lookup operations on large tables

Implementation:
For Delta tables in Unity Catalog:
CREATE BLOOMFILTER INDEX ON table_name(frequently_filtered_column);

Performance Impact: 3-5x faster point lookups


OPTIMIZATION 6: SQL Warehouse Auto-Scaling

Problem: Query queuing during peak usage periods

Current Configuration: 1 cluster, fixed
Recommended Configuration: Minimum 1, Maximum 2-3 clusters (auto-scale)

Configuration Settings:
- Minimum clusters: 1
- Maximum clusters: 2 (moderate load) or 3 (high load)
- Auto-stop timeout: 15 minutes

Cost Impact: Additional clusters billed only during active use
Performance Impact: Eliminates query queuing, improved user experience


5.3 Query Performance Monitoring

Execute the following query to identify performance bottlenecks:

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

Analysis Focus:
- Queries exceeding 30 seconds execution time
- Queries performing full table scans
- Frequently executed queries without caching


========================================================================

SECTION 6: COST CONTROL AND MONITORING STRATEGIES

6.1 Immediate Cost Reduction Actions (Zero Additional Cost)

Action                          Cost Impact    Implementation
Enable Auto-Termination         -30%          Configure 30-minute timeout on all clusters
Auto-Stop SQL Warehouses        -20%          Configure 15-minute auto-stop timeout
Optimize Resource-Intensive     -15%          Apply optimizations from Section 5.2
Remove Unused Clusters          -10%          Delete inactive and test clusters
Schedule Job Optimization       -10%          Prevent overlapping job executions

Estimated Total Monthly Savings: $400-$600


6.2 Cluster Configuration Best Practices

Processing Clusters - Recommended Configuration:

Autoscale Settings:
  Minimum Workers: 2
  Maximum Workers: 6

Auto-termination: 30 minutes

Spark Configuration:
  spark.databricks.adaptive.autoOptimizeShuffle.enabled: true


SQL Warehouses - Recommended Configuration:

Size: 2X-Small or X-Small (for user base under 20)
Cluster Configuration: Minimum 1, Maximum 2
Auto-stop Timeout: 15 minutes
Serverless Compute: Disabled (prevents cost spikes)


6.3 Cost Alert Configuration

Azure Budget Alert Setup:

1. Navigate to Azure Portal → Cost Management → Budgets
2. Create budget for Databricks resource group
3. Configure alert thresholds:
   - Warning Threshold: $1,800/month (120% of baseline)
   - Critical Threshold: $2,500/month (170% of baseline)
4. Configure alert recipients: Team members and finance department
5. Review frequency: Weekly


6.4 Monthly Cost Review Checklist

Execute the following review on the first Monday of each month:

- Review top 10 highest-cost clusters
- Identify clusters exceeding 400 hours monthly runtime
- Analyze queries with execution time exceeding 1 minute
- Remove unused or obsolete clusters
- Verify auto-termination is enabled across all clusters
- Review SQL Warehouse utilization metrics
- Analyze DBU consumption trends and patterns


========================================================================

SECTION 7: RECOMMENDED IMPLEMENTATION PLAN

Phase 1: Immediate Actions (Current Week) - Zero Cost

1. Enable auto-termination on all clusters (30-minute timeout)
2. Configure SQL Warehouse auto-stop to 15 minutes
3. Enable query result caching
4. Execute OPTIMIZE command on five largest tables
5. Configure Azure budget alerts

Expected Monthly Savings: $300-$400


Phase 2: Query Optimization (2-Week Implementation) - Zero Cost

1. Identify ten slowest-performing queries
2. Add partition filters to slow queries
3. Create materialized views for resource-intensive dashboards
4. Implement ZORDER on frequently filtered columns
5. Conduct team training on query best practices

Expected Result: 2-5x faster query execution, no cost increase


Phase 3: Tier Upgrade Evaluation (If Required After Phases 1-2)

Only proceed with tier upgrade if performance issues persist after implementing 
Phases 1 and 2.

Conservative Approach:
- Upgrade Primary SQL Warehouse: 2X-Small to X-Small
- Monthly cost increase: $250
- Performance improvement: 2x faster

Aggressive Approach:
- Upgrade Primary SQL Warehouse: 2X-Small to Small
- Monthly cost increase: $550
- Performance improvement: 4x faster


========================================================================

SECTION 8: COST SCENARIO SUMMARY

Scenario                                  Monthly Cost    vs Current    Description
Current Baseline                          $1,480          -             Current expenditure
Minimum Utilization (Optimized)           $1,080          -$400         Best practices implemented
Current + SQL Upgrade (X-Small)           $1,730          +$250         2x SQL performance
Current + SQL Upgrade (Small)             $2,030          +$550         4x SQL performance
Maximum Utilization (Runaway)             $9,450          +$7,970       Worst-case scenario


========================================================================

RECOMMENDATIONS

Based on the analysis conducted, the following approach is recommended:

1. Implement Zero-Cost Optimizations First
   - Execute Phase 1 and Phase 2 actions outlined in Section 7
   - Monitor performance improvements over 2-4 week period
   - Measure impact on user-reported performance issues

2. Performance Monitoring Period
   - Track query execution metrics
   - Collect user feedback on performance
   - Assess reduction in performance complaints

3. Tier Upgrade Decision
   - If performance issues persist after optimizations: Upgrade to X-Small (+$250/month)
   - If supporting increased user base: Consider Small tier (+$550/month)
   - If performance meets requirements: Maintain current configuration

4. Ongoing Cost Control
   - Enforce auto-termination settings across all environments
   - Maintain active budget alert monitoring
   - Conduct monthly cost review meetings


========================================================================

QUICK REFERENCE - KEY COST METRICS

BASELINE COSTS:
PreProd Environment: $350/month
Production Environment: $1,130/month
Total Monthly Cost: $1,480/month

OPTIMIZED SCENARIO (BEST CASE):
PreProd Environment: $350/month
Production Environment: $730/month
Total Monthly Cost: $1,080/month (Savings: $400/month)

RUNAWAY SCENARIO (WORST CASE):
PreProd Environment: $2,400/month
Production Environment: $7,050/month
Total Monthly Cost: $9,450/month (Increase: $7,970/month)

SQL WAREHOUSE UPGRADE COSTS:
2X-Small to X-Small: +$250/month
2X-Small to Small: +$550/month
2X-Small to Medium: +$1,100/month


========================================================================

Document Prepared By: Syed Rizvi, Senior Systems Administrator
Prepared For: Preyash Patel, PYX Health
Date: February 20, 2026
Version: 1.0

========================================================================
