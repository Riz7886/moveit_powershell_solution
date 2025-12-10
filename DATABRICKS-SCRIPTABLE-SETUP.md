# 🚀 DATABRICKS SCRIPTABLE SETUP GUIDE

## YES! YOU CAN SCRIPT DATABRICKS MONITORING! 

I created a PowerShell script that **automates everything** for Databricks!

---

## 🎯 WHAT THE SCRIPT DOES

The `Configure-Databricks-Datadog.ps1` script:

1. ✅ Creates a Datadog init script
2. ✅ Uploads it to Databricks DBFS
3. ✅ Configures ALL your Databricks clusters automatically
4. ✅ Sets up Spark monitoring
5. ✅ Installs Datadog agent on every cluster node

**NO MANUAL WORK NEEDED!**

---

## 📋 PREREQUISITES (5 minutes setup)

You need 3 things:

### 1. Datadog API Key
You already have this: `YOUR-DATADOG-API-KEY`

### 2. Databricks Workspace URL
Find this in Azure Portal:

**Steps:**
1. Azure Portal → Resource Groups
2. Find your Databricks resource group (has "DATABRICKS" in name)
3. Click on the Databricks Workspace resource
4. Copy the "URL" field

**Format:** `https://adb-1234567890123456.7.azuredatabricks.net`

### 3. Databricks Personal Access Token

**Steps:**
1. Open your Databricks workspace (click the URL above)
2. Click your username in top right → **User Settings**
3. Click **Developer** → **Access Tokens**
4. Click **Generate New Token**
5. Give it a name: "Datadog Integration"
6. Lifetime: 90 days (or whatever you want)
7. Click **Generate**
8. **COPY THE TOKEN** (you won't see it again!)

**Format:** `dapi1234567890abcdef1234567890ab`

---

## 🚀 RUNNING THE SCRIPT

Once you have those 3 things:

```powershell
.\Configure-Databricks-Datadog.ps1 `
    -DatadogApiKey "YOUR-DATADOG-API-KEY" `
    -DatabricksWorkspaceUrl "https://adb-123456789.azuredatabricks.net" `
    -DatabricksToken "dapi1234567890abcdef1234567890ab"
```

**That's it!** The script will:
- ✅ Upload init script to all Databricks workspaces
- ✅ Configure all clusters automatically
- ✅ Ask if you want to restart running clusters
- ✅ Show you a summary of what was done

---

## ⚙️ ADVANCED OPTIONS

### Configure Specific Clusters Only

If you only want to configure certain clusters:

```powershell
.\Configure-Databricks-Datadog.ps1 `
    -DatadogApiKey "YOUR-KEY" `
    -DatabricksWorkspaceUrl "https://adb-123.azuredatabricks.net" `
    -DatabricksToken "dapi123..." `
    -ClusterIds @("cluster-id-1", "cluster-id-2")
```

**Get cluster IDs:**
1. Open Databricks workspace
2. Go to Compute → Clusters
3. Click on a cluster
4. Copy the ID from the URL: `.../clusters/1234-567890-abcde123`

### EU Datadog Site

If you use Datadog EU:

```powershell
.\Configure-Databricks-Datadog.ps1 `
    -DatadogApiKey "YOUR-KEY" `
    -DatabricksWorkspaceUrl "https://adb-123.azuredatabricks.net" `
    -DatabricksToken "dapi123..." `
    -DatadogSite "datadoghq.eu"
```

---

## 🔍 WHAT HAPPENS AFTER

### When Clusters Start:
1. Init script runs automatically
2. Installs Datadog agent (takes ~2 minutes)
3. Configures Spark monitoring
4. Agent starts sending metrics to Datadog

### In Datadog (5-10 minutes later):
- **Infrastructure → Host Map**: See cluster nodes appear
- **Integrations → Spark**: See Spark metrics
- **APM → Services**: See Databricks jobs

---

## ✅ VERIFICATION

### Check Init Script Was Added:

1. Databricks workspace → **Compute**
2. Click on a cluster
3. Click **Edit**
4. Scroll to **Advanced Options**
5. Expand **Init Scripts**
6. You should see: `dbfs:/databricks/datadog/install-datadog-agent.sh`

### Check Agent Is Running:

After cluster starts, in Databricks notebook:

```python
# Run this in a notebook cell
%sh
sudo systemctl status datadog-agent
sudo datadog-agent status
```

Should show: "Status: Connected to Datadog"

### Check Datadog Dashboard:

1. Login to Datadog
2. Go to **Infrastructure → Host Map**
3. Search for your cluster name
4. Should see cluster driver and worker nodes

---

## 🔧 TROUBLESHOOTING

### Error: "Invalid token"
- Your Databricks token may have expired
- Generate a new one (User Settings → Access Tokens)

### Error: "Workspace not found"
- Check workspace URL is correct
- Make sure you have access to the workspace
- Remove any trailing slashes from URL

### Init Script Not Running:
- Check cluster is restarted after configuration
- Look at cluster Event Log (Compute → Cluster → Event Log)
- Check init script logs in cluster logs

### Agent Not Appearing in Datadog:
- Wait 10 minutes (initial connection takes time)
- Check Databricks cluster logs for errors
- Verify API key is correct
- Check firewall rules (port 443 to Datadog must be open)

---

## 💡 MULTIPLE DATABRICKS WORKSPACES?

If you have multiple Databricks workspaces (which you probably do based on your resource groups):

**Option 1: Run script for each workspace**
```powershell
# Workspace 1
.\Configure-Databricks-Datadog.ps1 -DatadogApiKey "KEY" -DatabricksWorkspaceUrl "URL1" -DatabricksToken "TOKEN1"

# Workspace 2  
.\Configure-Databricks-Datadog.ps1 -DatadogApiKey "KEY" -DatabricksWorkspaceUrl "URL2" -DatabricksToken "TOKEN2"
```

**Option 2: Create a batch script**

Create `Configure-All-Databricks.ps1`:

```powershell
$datadogApiKey = "YOUR-DATADOG-API-KEY"

$workspaces = @(
    @{Url="https://adb-workspace1.azuredatabricks.net"; Token="token1"},
    @{Url="https://adb-workspace2.azuredatabricks.net"; Token="token2"},
    @{Url="https://adb-workspace3.azuredatabricks.net"; Token="token3"}
)

foreach ($workspace in $workspaces) {
    Write-Host "`nConfiguring workspace: $($workspace.Url)" -ForegroundColor Cyan
    .\Configure-Databricks-Datadog.ps1 `
        -DatadogApiKey $datadogApiKey `
        -DatabricksWorkspaceUrl $workspace.Url `
        -DatabricksToken $workspace.Token
}

Write-Host "`n✅ All workspaces configured!" -ForegroundColor Green
```

---

## 📊 WHAT GETS MONITORED

Once configured, you'll see in Datadog:

### Infrastructure Metrics:
- CPU usage per node
- Memory usage per node
- Disk I/O
- Network traffic
- Node health status

### Spark Metrics:
- Active jobs
- Active tasks
- Completed stages
- Failed tasks
- Executor memory
- Driver memory
- Shuffle read/write
- Task execution time

### Custom Metrics:
- You can add custom metrics via Spark listeners
- Configure in the init script

---

## 🎯 COMPARISON WITH OTHER APPROACHES

| Approach | Scriptable? | Coverage | Setup Time |
|----------|------------|----------|------------|
| **Init Scripts (This approach)** | ✅ YES | Every cluster node | 5 min |
| Platform Integration | ⚠️ Partial | Workspace-level only | 30 min |
| Manual Installation | ❌ NO | Per VM | Hours |
| VM Extensions | ❌ BLOCKED | N/A | Impossible |

**Init Scripts = BEST for your use case!**

---

## 🎉 SUMMARY

### What You Get:
- ✅ **Fully automated** Databricks monitoring setup
- ✅ **One script** configures everything
- ✅ **All clusters** get Datadog automatically
- ✅ **Spark metrics** included
- ✅ **No manual work** on each cluster

### Time Investment:
- Setup: 5 minutes (get token & URL)
- Execution: 2 minutes (run script)
- Verification: 10 minutes (check Datadog)
- **Total: ~17 minutes for ALL Databricks clusters!**

---

## 📞 NEED HELP?

### Common Questions:

**Q: Do I need to run this on every cluster?**
A: No! The script configures ALL clusters at once. Init script runs automatically when any cluster starts.

**Q: What if I add new clusters later?**
A: New clusters won't have the init script. Just run the script again, and it will add the init script to new clusters.

**Q: Can I remove Datadog later?**
A: Yes! Edit cluster → Advanced Options → Init Scripts → Remove the Datadog init script.

**Q: Does this affect cluster performance?**
A: Minimal impact (~1-2% CPU for agent). Datadog is designed for production use.

**Q: Will this break my existing clusters?**
A: No! The script only adds an init script. Your cluster config remains unchanged. You can restart at your convenience.

---

**YOU CAN 100% SCRIPT THIS! JUST RUN THE SCRIPT I GAVE YOU! 🚀**
