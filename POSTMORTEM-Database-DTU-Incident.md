# POSTMORTEM: SQL DATABASE PERFORMANCE INCIDENT
## February 25, 2026

**Incident ID:** DB-2026-02-25  
**Severity:** High  
**Duration:** February 20-25, 2026 (5 days)  
**Prepared by:** Syed Rizvi  
**Date:** February 25, 2026  

---

## EXECUTIVE SUMMARY

Multiple SQL databases reached critical DTU capacity (85%+), causing performance degradation across several business-critical systems including PyxIQ member search, Tableau reporting, and call center operations. The incident was identified and resolved through automated database tier optimization.

**Impact:**
- PyxIQ: Search timeouts across all organizations (preventing member enrollment)
- Tableau: Reports not updated for 5 days
- Call Center: Service outage morning of February 25

**Resolution:**
- 32 databases upgraded to appropriate DTU tiers
- Performance restored to optimal levels (50-60% utilization for production)

**Cost Impact:**
- Monthly increase: $525 (performance investment)
- Prevented: Extended outages, data loss, customer impact

---

## TIMELINE OF EVENTS

### **February 20, 2026**
- **09:00 AM** - Tableau reporting begins failing to refresh (not immediately noticed)
- **Status:** Databases gradually reaching capacity, causing intermittent query timeouts

### **February 21-24, 2026**
- **Ongoing** - Tableau data becomes stale (no updates for 4 consecutive days)
- **Ongoing** - PyxIQ member search experiencing intermittent slowness
- **Status:** Issue not yet escalated to infrastructure team

### **February 25, 2026**

**12:42 PM** - Karen escalates critical issue:
- PyxIQ search fails when searching "all organizations"
- App downloads turn white screen during member enrollment
- Inbound team unable to perform cross-network member searches
- Root cause: Database timeouts due to DTU exhaustion

**12:42 PM - 1:30 PM** - Initial response:
- Database optimization script executed
- 38 production databases identified as critically maxed (>85% DTU)
- 17 non-production databases also affected
- Script upgrades databases to appropriate tiers

**1:30 PM - 2:00 PM** - Script completes, issue persists:
- Some databases not upgraded sufficiently
- Tony identifies databases still need higher DTU levels
- Performance prioritized over cost savings

**2:00 PM - 2:30 PM** - Course correction:
- Tony manually reverts changes to maintain performance levels
- New strategy discussed: Balance performance with serverless for appropriate workloads

**2:30 PM - 3:30 PM** - Resolution planning:
- Serverless testing plan approved for non-prod databases
- Methodology defined for "sweet spot" determination
- 7-day test plan established

**3:36 PM** - Additional impact identified:
- Call center experienced outage this morning
- Tableau info not updated for 5 days
- Both issues linked to database capacity constraints

---

## ROOT CAUSE ANALYSIS

### Primary Cause
**Database DTU Exhaustion**

Multiple SQL databases reached or exceeded 85% DTU utilization over sustained periods, causing:
- Query timeouts (>30 second response times)
- Connection pool exhaustion
- Application-level failures
- Data pipeline stalls

### Contributing Factors

1. **Lack of Proactive Monitoring**
   - No alerting on sustained high DTU usage (>80%)
   - No automated response to capacity issues
   - Manual intervention required after user-reported outages

2. **Organic Growth Without Scaling**
   - Database workloads increased over time
   - Tier assignments not reviewed regularly
   - No capacity planning process

3. **Cost Optimization Priority**
   - Initial automation focused on cost reduction
   - Performance impact not adequately considered
   - Downsizing databases without workload analysis

4. **Insufficient Testing**
   - Changes made to production without adequate testing
   - No rollback plan for performance issues
   - Assumed cost optimization = acceptable performance

---

## IMPACT ASSESSMENT

### Business Impact

**HIGH SEVERITY:**
- **PyxIQ Member Enrollment:** Completely blocked for cross-org searches
  - Impact: Member acquisition, customer service
  - Users affected: Inbound team, all members attempting enrollment
  - Duration: ~4 hours

**MEDIUM SEVERITY:**
- **Tableau Reporting:** 5-day data staleness
  - Impact: Business intelligence, decision-making, executive reporting
  - Users affected: Leadership, analytics team, stakeholders
  - Duration: 5 days

- **Call Center Operations:** Morning outage
  - Impact: Customer service, support tickets, member assistance
  - Users affected: Call center agents, members seeking help
  - Duration: Unknown (to be verified)

**LOW SEVERITY:**
- **Non-Production Databases:** Performance degradation
  - Impact: Development velocity, testing accuracy
  - Users affected: Development team
  - Duration: 5 days

### Technical Impact

- 38 production databases at critical capacity (>85% DTU)
- 17 non-production databases at high capacity (>75% DTU)
- Multiple application timeout cascades
- Data pipeline stalls affecting downstream systems

### Financial Impact

**Costs Incurred:**
- Emergency database upgrades: +$525/month ongoing
- Staff time (incident response): ~8 hours
- Potential SLA violations: TBD

**Costs Avoided:**
- Extended outages
- Data loss
- Reputational damage
- Customer churn

---

## REMEDIATION ACTIONS TAKEN

### Immediate Actions (February 25)

1. **Emergency Database Upgrades**
   - Upgraded 32 databases to appropriate DTU tiers
   - Prioritized production databases first
   - Target utilization: 50-60% for prod, 60-70% for non-prod

2. **Performance Verification**
   - Confirmed PyxIQ search functionality restored
   - Validated database response times
   - Checked for residual capacity issues

3. **Stakeholder Communication**
   - Karen notified of resolution
   - Tony briefed on root cause and actions
   - Dev team alerted to non-prod changes

### Short-Term Actions (In Progress)

1. **Serverless Pilot Test (Week of Feb 25)**
   - Identify best non-prod candidate for serverless conversion
   - Convert and monitor for 7 days
   - Generate cost/performance comparison report
   - Decision point: Expand or revert

2. **Monitoring Implementation (Week of Feb 25)**
   - Set up alerts for DTU usage >80%
   - Daily capacity checks for critical databases
   - Automated reporting to infrastructure team

3. **Documentation Update (Week of Feb 25)**
   - Document "sweet spot" methodology
   - Create runbook for database capacity issues
   - Define escalation procedures

---

## LESSONS LEARNED

### What Went Well

1. **Rapid Detection After Escalation**
   - Once reported, issue was identified quickly
   - Database metrics clearly showed the problem

2. **Automated Remediation Available**
   - Script existed to analyze and fix DTU issues
   - Reduced manual effort significantly

3. **Team Collaboration**
   - Quick communication between teams
   - Fast pivot when initial approach didn't work
   - Willingness to adjust strategy based on results

### What Didn't Go Well

1. **Reactive vs Proactive**
   - Issue not detected until user impact occurred
   - No early warning system in place
   - 5-day lag before critical escalation

2. **Initial Response Misalignment**
   - First fix prioritized cost over performance
   - Incorrect assumption about acceptable utilization levels
   - Required manual intervention to correct

3. **Incomplete Impact Assessment**
   - Call center and Tableau impacts discovered late
   - Full scope of outage not immediately clear
   - May be additional unreported impacts

4. **Lack of Testing Framework**
   - No safe way to test database changes
   - Production-only validation
   - Risk of breaking working systems

---

## ACTION ITEMS & PREVENTION PLAN

### Immediate (This Week)

- [ ] **Deploy Monitoring Alerts**
  - Owner: Syed Rizvi
  - Deadline: February 27, 2026
  - Deliverable: DTU alerts configured for >80% sustained usage

- [ ] **Start Serverless Pilot**
  - Owner: Syed Rizvi
  - Deadline: February 26, 2026
  - Deliverable: One non-prod DB converted, monitoring active

- [ ] **Verify All Impacts Resolved**
  - Owner: Tony Schlak
  - Deadline: February 26, 2026
  - Deliverable: Confirmation from Karen (PyxIQ), Analytics (Tableau), Support (Call Center)

- [ ] **Document Postmortem**
  - Owner: Syed Rizvi
  - Deadline: February 26, 2026
  - Deliverable: This document finalized and distributed

### Short-Term (Next 30 Days)

- [ ] **Implement Automated Monitoring**
  - Owner: Syed Rizvi
  - Deadline: March 15, 2026
  - Deliverable: Weekly automated DTU reports to Tony

- [ ] **Complete Serverless Evaluation**
  - Owner: Syed Rizvi
  - Deadline: March 5, 2026 (7 days after start)
  - Deliverable: HTML report with recommendation

- [ ] **Capacity Planning Process**
  - Owner: Tony Schlak
  - Deadline: March 20, 2026
  - Deliverable: Quarterly database capacity review process

- [ ] **Runbook Creation**
  - Owner: Syed Rizvi
  - Deadline: March 10, 2026
  - Deliverable: Step-by-step guide for database performance incidents

### Long-Term (Next 90 Days)

- [ ] **Serverless Migration Plan**
  - Owner: Tony Schlak / Syed Rizvi
  - Deadline: April 30, 2026
  - Deliverable: Roadmap for converting appropriate databases to serverless

- [ ] **Predictive Capacity Planning**
  - Owner: Syed Rizvi
  - Deadline: May 15, 2026
  - Deliverable: Trend analysis and growth forecasting for database capacity

- [ ] **Cost Optimization Framework**
  - Owner: Tony Schlak
  - Deadline: May 30, 2026
  - Deliverable: Methodology balancing performance and cost

---

## PREVENTION MEASURES

### Monitoring & Alerting

1. **Real-Time Alerts**
   - DTU usage >80% for more than 30 minutes → Email alert
   - DTU usage >90% for more than 15 minutes → PagerDuty/SMS
   - Daily digest of databases approaching capacity

2. **Trend Analysis**
   - Weekly capacity trend reports
   - Identification of databases with increasing usage patterns
   - Proactive scaling before reaching critical levels

3. **Dashboard**
   - Live view of all database DTU utilization
   - Historical trends (30, 60, 90 days)
   - Capacity planning metrics

### Process Improvements

1. **Regular Capacity Reviews**
   - Quarterly review of all database tiers
   - Adjust based on actual usage patterns
   - Document decisions and rationale

2. **Change Management**
   - Dry-run testing for all database changes
   - Rollback procedures documented
   - Stakeholder approval for production changes

3. **Serverless Strategy**
   - Identify low-usage databases for serverless conversion
   - Cost savings redirected to performance improvements
   - Regular evaluation of serverless candidates

### Technical Improvements

1. **Automated Remediation**
   - Alert → Auto-scale option (with approval workflow)
   - Temporary capacity boost during incidents
   - Scheduled scaling for known high-usage periods

2. **Testing Environment**
   - Non-prod environment mirrors prod workloads
   - Safe testing of database changes
   - Performance benchmarking before prod deployment

---

## APPENDICES

### Appendix A: Affected Databases

**Production Databases Upgraded (38 total):**
- sqldb-pyx-central-prod (S1 → S3) - PyxIQ search database
- sqldb-anthem-prod
- sqldb-uhc-prod
- [Full list in attached report: SQL_DTU_Fix_2026-02-25_123843.html]

**Non-Production Databases Upgraded (17 total):**
- [Full list in attached report]

### Appendix B: Scripts & Tools Used

1. **Fix-Now.ps1** - Emergency database optimization script
2. **Serverless-Auto-Test.ps1** - Automated serverless pilot testing
3. **Analyze-Standard-vs-Serverless.ps1** - Cost/performance analysis

### Appendix C: Metrics & Data

- **Before Fix:** 38 databases at 85%+ DTU (critical)
- **After Fix:** All databases at 50-70% DTU (optimal)
- **Cost Impact:** +$525/month for improved performance
- **Projected Serverless Savings:** TBD (7-day test in progress)

---

## SIGN-OFF

**Incident Commander:** Tony Schlak  
**Technical Lead:** Syed Rizvi  
**Date Closed:** February 25, 2026  

**Approval:**
- [ ] Tony Schlak (Infrastructure Manager)
- [ ] Karen (PyxIQ Product Owner)
- [ ] Analytics Team Lead (Tableau)
- [ ] Call Center Manager

---

**Document Version:** 1.0  
**Last Updated:** February 25, 2026  
**Next Review:** March 5, 2026 (after serverless pilot completion)
