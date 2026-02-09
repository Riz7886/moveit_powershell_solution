# HOW TO USE - DATABRICKS QUOTA ANALYZER WITH HTML REPORTS

## 🎯 YOU NOW HAVE 2 SCRIPTS:

### 1. **DatabricksQuotaRootCause-AutoFix.ps1** (Main Script - UNCHANGED)
   - Finds root cause
   - Applies fixes
   - Does NOT break anything
   
### 2. **Generate-HTMLReport.ps1** (NEW - HTML Report Generator)
   - Checks if quota increased from 10 → 64
   - Creates professional HTML report
   - Shows SQL warehouses status
   - Auto-opens in browser

## 🚀 RECOMMENDED WORKFLOW:

### STEP 1: Run Root Cause Analysis
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode rootcause
```
**This WON'T change anything - just analyzes**

### STEP 2: Generate HTML Report
```powershell
.\Generate-HTMLReport.ps1
```
**This creates the HTML report and checks quota increase**

### STEP 3: Review Report
- Report auto-opens in your browser
- Shows if quota was increased (10 → 64)
- Shows all clusters, jobs, SQL warehouses
- Professional report you can share with management

### STEP 4: Apply Fixes (Optional)
```powershell
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode fix
```
**Only if needed - script asks for confirmation before changing anything**

---

## 📊 WHAT THE HTML REPORT SHOWS:

✅ **Quota Increase Confirmation**
   - Checks if any VM family has 64 vCPU limit
   - Shows green banner if increase detected
   - Lists all quota limits and usage

✅ **Cluster Status**
   - All clusters and their states
   - Autoscale configuration
   - Auto-termination settings
   - Node types

✅ **SQL Warehouses**
   - Shows all 3 SQL warehouses you have
   - Their sizes and states
   - Auto-stop configurations

✅ **Summary Metrics**
   - Total clusters
   - Running clusters
   - Clusters without autoscale
   - Total jobs
   - SQL warehouses

✅ **Recommendations**
   - What to do next
   - Monitoring tips
   - Optimization suggestions

---

## 🔒 SAFETY FEATURES:

### Main Script (DatabricksQuotaRootCause-AutoFix.ps1):
- ✅ Mode "rootcause" = NO CHANGES
- ✅ Mode "fix" = ASK for confirmation before changes
- ✅ Only changes cluster configs when you say YES
- ✅ Won't touch running SQL warehouses
- ✅ Won't break anything

### HTML Report Generator:
- ✅ READ-ONLY - never changes anything
- ✅ Just collects data and makes report
- ✅ Safe to run anytime

---

## 💡 TYPICAL USE CASE:

**SCENARIO: You want to check quota status and get a report**

```powershell
# Step 1: Quick analysis (no changes)
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode rootcause

# Step 2: Generate HTML report
.\Generate-HTMLReport.ps1

# Step 3: Review report in browser (auto-opens)
# - Check if quota increased
# - See all clusters/warehouses
# - Get recommendations

# Step 4: If fixes needed, apply them
.\DatabricksQuotaRootCause-AutoFix.ps1 -Mode fix
```

---

## ✅ WHAT GETS CHECKED FOR QUOTA INCREASE:

The HTML report generator looks for:
- VM families with **exactly 64 vCPU limit**
- This is the telltale sign of 10 → 64 increase
- Shows green ✓ if found
- Lists all quotas so you can verify

Example output in report:
```
VM Family                    Current  Limit  Usage%  Increased?
Standard DSv3 Family            12      64    18.8%   ✓ YES
Standard Dv3 Family             8       64    12.5%   ✓ YES
```

---

## 📁 FILES GENERATED:

After running both scripts:

1. **DatabricksRootCause_YYYYMMDD_HHMMSS.log**
   - Complete log from main script
   - Root cause analysis details

2. **DatabricksQuotaReport_YYYYMMDD_HHMMSS.html**
   - Professional HTML report
   - Can share with team/management
   - Has charts and tables

---

## 🎨 HTML REPORT FEATURES:

- **Professional Design**: Clean, modern look
- **Color-Coded**: Green = good, Red = issues, Orange = warnings
- **Tables**: Sortable data for clusters, quotas, warehouses
- **Metrics**: Big numbers showing key stats
- **Auto-Opens**: Opens in browser automatically
- **Shareable**: Send to team/management

---

## ⚠️ IMPORTANT NOTES:

1. **The main script is UNCHANGED**
   - All the root cause analysis works the same
   - All the fix logic works the same
   - Nothing broken

2. **HTML report is ADDON**
   - Run it separately
   - Doesn't interfere with main script
   - Just reads data and makes pretty report

3. **SQL Warehouses are SAFE**
   - Neither script touches SQL warehouses
   - They just show status
   - Your 3 warehouses stay running

4. **Quota check is AUTOMATIC**
   - HTML report checks quotas
   - Tells you if 10 → 64 happened
   - No manual work needed

---

## 🔧 TROUBLESHOOTING:

**"No quota increase detected"**
- Run: `Get-AzVMUsage -Location eastus`
- Check manually if any family shows 64 limit
- Might be different VM family than expected

**"Can't connect to Databricks"**
- Check you're logged into Azure
- Make sure workspace URL is correct
- Token might have expired - script will ask for new one

**"HTML report doesn't open"**
- Check the file path shown
- Open manually from the file location
- Use any web browser

---

## 🎯 BOTTOM LINE:

✅ **Main script finds WHY quota was breached**
✅ **HTML report shows IF quota was increased**  
✅ **Both scripts are SAFE and won't break anything**
✅ **Run them separately or together**
✅ **Get professional reports for management**

**You're good to go!**
