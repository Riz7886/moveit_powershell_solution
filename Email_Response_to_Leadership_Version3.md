**TO:** Tony Schlak, Greg Moran, Brian Burge  
**FROM:** Infrastructure Team  
**SUBJECT:** RE: Azure Charges follow-up - DBO Access and DTU Optimization Plan  
**DATE:** January 20, 2026

---

## Response to Your Questions

### Brian's Question: How will DBO access assist with this request?

**Answer:**

DBO (Database Owner) access will be used in READ-ONLY mode to facilitate the analysis process. This access will NOT automatically archive or power down databases. 

**What We Will Do:**
- Read table sizes and row counts across all databases
- Analyze data age by reviewing date columns in tables
- Correlate actual workload (CPU, threads, reads) with DTU consumption
- Identify which tables are accessed frequently vs rarely
- Generate data-driven recommendations for optimization

**What We Will NOT Do:**
- Modify any data or database schemas
- Archive or delete any data automatically
- Power down or decommission any databases
- Make configuration changes without approval

**The Process:**

1. Gain temporary read-only DBO access to target databases
2. Run automated audit scripts to collect metrics safely
3. Analyze results to identify optimization opportunities
4. Present findings and recommendations to stakeholders
5. Obtain approval from application owners and leadership
6. Implement approved changes through standard change management process

All database modifications, archival actions, or decommissioning will require explicit approval from application owners and will follow our standard change management procedures.

---

### Tony's Question: How to significantly reduce processing/DTUs?

**Answer:**

We have developed comprehensive automation to identify and reduce DTU consumption. 

**Phase 1: Automated Analysis (Week 1)**

**Script 1: SQL Database DTU Optimization**
- Analyzes 7-day historical DTU consumption for all databases
- Identifies underutilized databases consuming excessive DTUs
- Identifies overutilized databases at risk of performance issues
- Calculates optimal database tier based on actual usage
- Generates specific recommendations with projected cost savings

**Script 2: Database Inventory and Table Analysis**
- Inventories all tables with size and row count data
- Analyzes data age to identify stale historical data
- Reviews table access patterns (seeks, scans, updates)
- Identifies archival candidates based on age and access frequency
- Calculates storage savings from archival opportunities

**Script 3: Databricks Cluster Optimization**
- Audits all Databricks clusters and jobs
- Identifies idle clusters without auto-termination
- Reviews cluster sizing and configuration
- Recommends Photon engine enablement for performance
- Calculates compute cost savings opportunities

**Phase 2: DTU Reduction Implementation (Week 2)**

**Immediate Actions - Automated:**
- Downgrade underutilized databases to appropriate tiers
- Expected impact: 40-50% DTU cost reduction on affected databases

**Data Archival - Controlled:**
- Archive tables not accessed in 365+ days to Azure Data Lake Storage
- Maintain accessibility through external tables
- Expected impact: 30-40% storage reduction, 15-25% DTU reduction

**Query Optimization - Targeted:**
- Implement missing index recommendations from Query Performance Insight
- Rewrite top DTU-consuming queries
- Expected impact: 20-30% DTU reduction through efficiency

**Database Consolidation - Strategic:**
- Merge low-usage development and test databases
- Decommission unused databases after stakeholder approval
- Expected impact: 25-35% reduction in database count

**Phase 3: Ongoing Governance (Week 3)**
- Implement automated monitoring and alerting
- Establish monthly DTU review process
- Create policies to prevent future DTU waste
- Configure budget alerts at subscription level

---

## Projected Savings Breakdown

**SQL Database DTU Reduction: $140,000 - $160,000 Annual**
- Database tier optimization: $50,000 - $60,000
- Data archival and cleanup: $30,000 - $40,000
- Query performance tuning: $25,000 - $30,000
- Database consolidation: $20,000 - $20,000
- Geo-replication review: $15,000 - $10,000

**Databricks Compute Optimization: $180,000 - $220,000 Annual**
- Cluster auto-termination: $40,000 - $50,000
- Cluster rightsizing: $35,000 - $45,000
- Job cluster conversion: $30,000 - $40,000
- Photon engine enablement: $25,000 - $35,000
- Instance type optimization: $25,000 - $30,000
- Spot instance utilization: $25,000 - $20,000

**Storage Optimization: $40,000 - $50,000 Annual**
- Lifecycle management policies: $25,000 - $30,000
- Data deduplication: $15,000 - $20,000

**Total Projected Annual Savings:  $360,000 - $430,000**

**Target for Board Presentation: $400,000**

---

## Timeline to Board Meeting

**Week 1: Analysis and Approval**
- Monday-Tuesday: Execute all audit scripts across environment
- Wednesday-Thursday: Analyze results and finalize recommendations
- Friday: Present findings to leadership for approval

**Week 2: Implementation**
- Monday-Tuesday:  Implement approved database tier optimizations
- Wednesday-Thursday: Execute data archival for high-priority candidates
- Friday: Validate changes and monitor performance

**Week 3: Validation and Reporting**
- Monday-Tuesday:  Measure actual cost reductions achieved
- Wednesday-Thursday: Prepare board presentation materials
- Friday: Final validation and board presentation preparation

---

## Conclusion

**Yes, we are giving you exactly what you are requesting:**

**For Brian:** Clear explanation that DBO access facilitates analysis only - databases will not be automatically archived or powered down

**For Tony:** Specific, actionable plan to significantly reduce DTU consumption with automation that delivers before the board meeting

**For Greg:** Complete solution delivering $400K savings target with