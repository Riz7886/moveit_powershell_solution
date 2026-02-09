# DATABRICKS QUOTA ROOT CAUSE ANALYZER - HOW TO USE

## 🔥 WHAT THIS SCRIPT DOES

This is a **FULLY AUTOMATED** script that:

1. **FINDS THE ROOT CAUSE** of your quota breach by analyzing:
   - Which jobs consumed the most resources
   - Which clusters scaled out of control
   - When the quota spike happened
   - What triggered the autoscaling
   - Which queries are inefficient

2. **APPLIES PERMANENT FIXES**:
   - Enables autoscaling where missing
   - Reduces excessive max worker limits
   - Enables auto-termination (stops idle clusters)
   - Adds Spark optimizations for better resource usage
   - Creates quota-safe cluster policies

3. **PREVENTS IT FROM HAPPENING AGAIN**:
   - Sets up monitoring recommendations
   - Creates cluster policies that limit scaling
   - Identifies jobs that need optimization

## 🚀 HOW TO RUN IT

### Option 1: FULL ANALYSIS + AUTO-FIX (Recommended)
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode all
```

This will:
- Find what caused the quota breach
- Apply all permanent fixes
- Give you a complete report

### Option 2: ROOT CAUSE ONLY (Just Investigate)
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode rootcause
```

This will:
- Analyze your environment
- Tell you EXACTLY what caused the quota issue
- NOT make any changes

### Option 3: APPLY FIXES ONLY
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode fix
```

This will:
- Apply permanent fixes to clusters
- Skip the analysis

### Advanced Options

**Export detailed reports to CSV:**
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode all -ExportReport
```

**Analyze more history (default is 7 days):**
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode all -AnalysisDays 14
```

**Preview changes without applying (WhatIf):**
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode fix -WhatIf
```

## 📊 WHAT YOU'LL GET

### Root Cause Report Shows:
- **Top 10 resource-consuming jobs** (which jobs ate your quota)
- **Long-running jobs** (jobs that ran for hours)
- **Failed jobs** (what crashed and why)
- **Autoscaling events** (when clusters scaled up/down)
- **Quota usage** (which VM families are maxed out)
- **Clusters without autoscaling** (waste resources)
- **Clusters without auto-termination** (run forever)

### Fixes Applied:
- ✅ Autoscaling enabled on all clusters
- ✅ Max workers capped at safe limits (12 workers max)
- ✅ Auto-termination enabled (30 min default)
- ✅ Spark optimizations added (better resource usage)
- ✅ Cluster policy created (prevents quota exhaustion)

## 🛠️ NO SETUP REQUIRED

The script **auto-discovers everything**:
- ✅ Finds your Databricks workspace automatically
- ✅ Gets your Azure subscription automatically
- ✅ Generates API tokens automatically
- ✅ Connects to Databricks API automatically

**You just run it. That's it.**

## 📝 EXAMPLE OUTPUT

```
=== ROOT CAUSES IDENTIFIED ===
1. Job 'ETL-DailyImport' consumed 1,247 minutes of cluster time
2. Cluster 'prod-cluster-01' max workers = 50 (very high, likely caused quota breach)
3. Cluster 'analytics-cluster' has NO AUTO-TERMINATION - runs indefinitely
4. QUOTA BREACH: Standard DSv3 Family at 94% (376/400 vCPUs)
5. Cluster 'prod-cluster-01' experienced rapid autoscaling (23 events)

=== RECOMMENDATIONS ===
1. Enable autoscaling on: analytics-cluster, reporting-cluster
2. Enable auto-termination on: analytics-cluster
3. Request quota increase for Standard DSv3 Family: 400 -> 800 vCPUs
4. Optimize job: ETL-DailyImport (avg 89 mins runtime)

=== FIXES APPLIED ===
1. Cluster 'prod-cluster-01': REDUCED max workers 50 -> 12; ADDED 7 Spark optimizations
2. Cluster 'analytics-cluster': ENABLED autoscaling 1-8 workers; ENABLED auto-termination 30min
3. Created cluster policy: policy_id_12345
```

## ⚠️ IMPORTANT NOTES

1. **The script will ASK before making changes**
   - You'll see what it wants to change
   - You must type "YES" to confirm
   - Use `-WhatIf` to preview without changes

2. **Running clusters may restart**
   - When cluster configs are changed, they restart
   - Plan accordingly (off-hours recommended)

3. **You need Azure permissions**
   - Must be logged into Azure (`Connect-AzAccount`)
   - Need permissions on the Databricks workspace
   - Need permissions to check Azure quotas

## 🎯 WHAT TO DO WITH THE RESULTS

### 1. REPLY TO DATABRICKS SUPPORT
Use the root cause findings in your ticket response:
- "We identified that job X consumed Y hours of cluster time"
- "We found cluster Z was scaling to 50 workers"
- "We've applied permanent fixes including autoscaling and auto-termination"

### 2. REQUEST QUOTA INCREASE (If Needed)
The script tells you EXACTLY what to request:
- Go to: https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade/~/myQuotas
- Filter by the VM family shown in the report
- Request the recommended amount (usually 2x current)

### 3. OPTIMIZE THE RESOURCE HOGS
Focus on the jobs the script identified:
- Review the top 10 resource-consuming jobs
- Check for inefficient queries
- Add caching where appropriate
- Use smaller clusters for smaller jobs

### 4. MONITOR
The script creates a log file with all details:
- Keep it for your records
- Use it to track improvements
- Run the script again in 1 week to compare

## 🔍 FILES GENERATED

After running, you'll get:
- `DatabricksRootCause_YYYYMMDD_HHMMSS.log` - Complete log
- `DatabricksReports_YYYYMMDD_HHMMSS/` - Folder with CSV reports (if -ExportReport used)
  - `JobExecutionHistory.csv` - All job runs analyzed
  - `RootCauseReport.txt` - Summary of findings

## 💡 PRO TIPS

1. **Run this after every quota issue** to track patterns
2. **Use `-ExportReport`** to keep historical data
3. **Run monthly** as a health check (Mode: rootcause)
4. **Share the report** with your team to show improvements
5. **Keep the log files** for audit trail

## 🆘 TROUBLESHOOTING

**"No Databricks workspaces found"**
- Make sure you're logged into Azure: `Connect-AzAccount`
- Check you have access to the subscription

**"Token acquisition failed"**
- The script will prompt for manual token
- Go to Databricks > Settings > Developer > Access Tokens
- Generate a new token and paste it

**"Permission denied"**
- You need admin/contributor on the Databricks workspace
- Contact your Azure admin for permissions

**"Script doesn't run"**
- Make sure you're using PowerShell 5.1 or later
- Run as Administrator if needed
- Install Az module: `Install-Module Az -Force`

## 📞 NEED HELP?

If the script finds issues it can't fix automatically, it will tell you exactly what to do. Follow the "NEXT STEPS" section in the output.

---

**BOTTOM LINE:** This script finds WHY your quota was breached and fixes it permanently. Just run it.
