# 🔧 MANUAL DATADOG AGENT INSTALLATION GUIDE

## 📋 FOR VMs THAT FAILED AUTOMATED INSTALLATION

Based on your audit report, you have **10 VMs without agents**. Here's how to install manually.

---

## 🎯 WHICH VMs NEED MANUAL INSTALLATION?

### ✅ Regular VMs (Install via RDP/SSH):
These VMs failed automated installation and need manual approach:

**Check your report for VMs showing:**
- Status: Running
- Agent Status: Not Installed
- OS Type: Windows or Linux (NOT "Unknown")
- NOT Databricks VMs

### ❌ Databricks VMs (Use Databricks Integration):
- VMs with long hash names (4b01f3db78cf46798f7ed5682c048c17, etc.)
- VMs in DATABRICKS resource groups
- Agent Status: "Cannot Install (Databricks)"

**For Databricks VMs → See Databricks section below**

### ⚠️ Stopped VMs:
- Need to be started first before any installation

---

## 🪟 WINDOWS VMs - MANUAL INSTALLATION

### Method 1: RDP + MSI Installer (Easiest)

**Step 1: RDP into the VM**
```powershell
# From Azure Portal: VM → Connect → RDP → Download RDP file
```

**Step 2: Download the Datadog Agent**
Open PowerShell as Administrator and run:
```powershell
# Download the installer
$url = "https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\datadog-agent.msi"

# Install with your API key
$apiKey = "YOUR-DATADOG-API-KEY-HERE"
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\datadog-agent.msi`" APIKEY=`"$apiKey`" /quiet" -Wait

# Start the service
Start-Service datadogagent

# Check status
Get-Service datadogagent
```

**Step 3: Verify Installation**
```powershell
# Check if agent is running
& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" status

# You should see connection to Datadog and metrics being collected
```

### Method 2: Azure Run Command (No RDP needed)

From your local PowerShell with Azure access:

```powershell
$vmName = "YOUR-VM-NAME"
$resourceGroup = "YOUR-RESOURCE-GROUP"
$apiKey = "YOUR-DATADOG-API-KEY"

Invoke-AzVMRunCommand `
    -ResourceGroupName $resourceGroup `
    -VMName $vmName `
    -CommandId "RunPowerShellScript" `
    -Script @"
`$url = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
Invoke-WebRequest -Uri `$url -OutFile "C:\Temp\datadog-agent.msi"
Start-Process msiexec.exe -ArgumentList "/i C:\Temp\datadog-agent.msi APIKEY=$apiKey /quiet" -Wait
Start-Service datadogagent
"@
```

---

## 🐧 LINUX VMs - MANUAL INSTALLATION

### Method 1: SSH + Installation Script (Easiest)

**Step 1: SSH into the VM**
```bash
# From Azure Portal: VM → Connect → SSH
# Or from terminal:
ssh azureuser@<VM-PUBLIC-IP>
```

**Step 2: Run the Datadog Installation Script**
```bash
# Set your API key
export DD_API_KEY="YOUR-DATADOG-API-KEY-HERE"
export DD_SITE="datadoghq.com"  # or datadoghq.eu if EU

# Run the official installation script
DD_API_KEY=$DD_API_KEY DD_SITE=$DD_SITE bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
```

**Step 3: Verify Installation**
```bash
# Check if agent is running
sudo systemctl status datadog-agent

# Check agent status
sudo datadog-agent status

# You should see connection to Datadog and metrics being collected
```

### Method 2: Azure Run Command (No SSH needed)

From your local PowerShell with Azure access:

```powershell
$vmName = "YOUR-VM-NAME"
$resourceGroup = "YOUR-RESOURCE-GROUP"
$apiKey = "YOUR-DATADOG-API-KEY"

Invoke-AzVMRunCommand `
    -ResourceGroupName $resourceGroup `
    -VMName $vmName `
    -CommandId "RunShellScript" `
    -Script @"
export DD_API_KEY=$apiKey
export DD_SITE=datadoghq.com
bash -c "\$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
"@
```

---

## 🧱 DATABRICKS VMs - SPECIAL HANDLING

**IMPORTANT:** Databricks VMs CANNOT have VM extensions installed due to system deny assignments!

### Option 1: Datadog-Databricks Integration (Recommended)

This monitors Databricks at the platform level - no VM agents needed!

**Setup Steps:**

1. **In Datadog:**
   - Go to Integrations → Databricks
   - Follow the setup wizard
   - Configure Azure Databricks connection

2. **In Azure Databricks:**
   - Create a Personal Access Token
   - Configure webhook integration
   - Set up monitoring for workspace, clusters, jobs

3. **Benefits:**
   - Monitors cluster metrics
   - Job execution tracking
   - Notebook performance
   - Cost monitoring
   - No VM-level agents needed

**Documentation:** https://docs.datadoghq.com/integrations/databricks/

### Option 2: Databricks Init Scripts (For detailed monitoring)

If you need more detailed metrics from Databricks clusters:

**Step 1: Create Init Script**

Create file `/dbfs/datadog/install-datadog.sh`:

```bash
#!/bin/bash

# Install Datadog agent on Databricks cluster
export DD_API_KEY="YOUR-DATADOG-API-KEY"
export DD_SITE="datadoghq.com"

# Install agent
DD_API_KEY=$DD_API_KEY DD_SITE=$DD_SITE bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"

# Configure for Spark monitoring
cat <<EOF > /etc/datadog-agent/conf.d/spark.d/conf.yaml
init_config:
instances:
  - resourcemanager_uri: http://localhost:8088
    spark_cluster_mode: spark_standalone_mode
    cluster_name: databricks_cluster
EOF

# Restart agent
sudo systemctl restart datadog-agent
```

**Step 2: Configure Cluster**

In Databricks workspace:
1. Go to Compute → Your Cluster → Edit
2. Under "Advanced Options" → "Init Scripts"
3. Add: `dbfs:/datadog/install-datadog.sh`
4. Restart cluster

**Step 3: Verify**
- Check Datadog dashboard for Spark metrics
- Verify cluster appears in Infrastructure List

---

## ⚙️ TROUBLESHOOTING MANUAL INSTALLATION

### Windows Issues:

**Agent won't start:**
```powershell
# Check logs
Get-Content "C:\ProgramData\Datadog\logs\agent.log" -Tail 50

# Common fix: Restart service
Restart-Service datadogagent

# Check firewall
New-NetFirewallRule -DisplayName "Datadog Agent" -Direction Outbound -Action Allow -RemoteAddress Any
```

**Wrong API key:**
```powershell
# Edit config file
notepad "C:\ProgramData\Datadog\datadog.yaml"
# Find: api_key: YOUR_KEY
# Save and restart service
```

### Linux Issues:

**Agent won't start:**
```bash
# Check logs
sudo tail -f /var/log/datadog/agent.log

# Common fix: Restart service
sudo systemctl restart datadog-agent

# Check status
sudo datadog-agent status
```

**Permission issues:**
```bash
# Fix permissions
sudo chown -R dd-agent:dd-agent /etc/datadog-agent/
sudo chown -R dd-agent:dd-agent /var/log/datadog/
sudo systemctl restart datadog-agent
```

**Firewall blocking:**
```bash
# Ubuntu/Debian
sudo ufw allow out to any port 443
sudo ufw reload

# RHEL/CentOS
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

---

## ✅ VERIFICATION CHECKLIST

After installing, verify for each VM:

**1. Agent is Running:**
- Windows: `Get-Service datadogagent` should show "Running"
- Linux: `sudo systemctl status datadog-agent` should show "active (running)"

**2. Agent is Connected to Datadog:**
- Windows: `& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" status`
- Linux: `sudo datadog-agent status`
- Look for: "Status: Connected"

**3. VM Appears in Datadog Dashboard:**
- Login to Datadog
- Go to Infrastructure → Host Map
- Search for your VM name
- Should appear within 5-10 minutes

**4. Metrics are Being Collected:**
- In Datadog, click on the host
- Should see CPU, Memory, Disk, Network metrics
- Metrics update every 15 seconds

---

## 📊 BATCH INSTALLATION SCRIPT

If you have multiple VMs to do manually, use this batch script:

```powershell
# Define your VMs
$vmsToInstall = @(
    @{Name="vm-name-1"; ResourceGroup="rg-name-1"; OS="Windows"},
    @{Name="vm-name-2"; ResourceGroup="rg-name-2"; OS="Linux"},
    @{Name="vm-name-3"; ResourceGroup="rg-name-3"; OS="Windows"}
)

$apiKey = "YOUR-DATADOG-API-KEY"

foreach ($vm in $vmsToInstall) {
    Write-Host "Installing Datadog on $($vm.Name)..." -ForegroundColor Cyan
    
    if ($vm.OS -eq "Windows") {
        Invoke-AzVMRunCommand `
            -ResourceGroupName $vm.ResourceGroup `
            -VMName $vm.Name `
            -CommandId "RunPowerShellScript" `
            -Script @"
`$url = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
Invoke-WebRequest -Uri `$url -OutFile "C:\Temp\datadog-agent.msi"
Start-Process msiexec.exe -ArgumentList "/i C:\Temp\datadog-agent.msi APIKEY=$apiKey /quiet" -Wait
Start-Service datadogagent
"@
    } else {
        Invoke-AzVMRunCommand `
            -ResourceGroupName $vm.ResourceGroup `
            -VMName $vm.Name `
            -CommandId "RunShellScript" `
            -Script @"
export DD_API_KEY=$apiKey
export DD_SITE=datadoghq.com
bash -c "\$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
"@
    }
    
    Write-Host "Completed: $($vm.Name)" -ForegroundColor Green
    Start-Sleep -Seconds 5
}

Write-Host "`nAll installations initiated!" -ForegroundColor Green
Write-Host "Check Datadog dashboard in 5-10 minutes to verify." -ForegroundColor Yellow
```

---

## 📞 NEXT STEPS

### For Regular VMs:
1. ✅ Use Azure Run Command method (easiest, no RDP/SSH needed)
2. ✅ Or RDP/SSH in and run installation commands
3. ✅ Verify in Datadog dashboard
4. ✅ Update your audit report by re-running the audit script

### For Databricks VMs:
1. ✅ Set up Datadog-Databricks integration (platform-level monitoring)
2. ✅ Or use Init Scripts for detailed cluster monitoring
3. ✅ Verify in Datadog Integrations page

### For Stopped VMs:
1. ✅ Start the VMs first
2. ✅ Then run automated or manual installation
3. ✅ Or leave stopped if they're not in use

---

## 💡 PRO TIPS

1. **Use Azure Run Command** - No need to RDP/SSH, works from your local machine
2. **Batch install** - Use the batch script above for multiple VMs
3. **Databricks = Different approach** - Don't waste time trying VM extensions
4. **Verify quickly** - Run the audit script again after installation to check status
5. **Document exceptions** - Keep track of VMs that can't have agents and why

---

## 🎯 WHAT TO TELL YOUR CLIENT

**Current Status:**
- ✅ 10 VMs successfully monitored with Datadog agents
- ⚠️ 6 Databricks VMs require platform-level integration (not VM agents)
- ⚠️ 4 regular VMs need manual installation (failed automated method)
- 🛑 10 VMs currently stopped (can install when started)

**Approach:**
- Regular VMs: Manual installation via Azure Run Command (no RDP/SSH needed)
- Databricks VMs: Set up Datadog-Databricks integration for platform monitoring
- Stopped VMs: Start and install, or leave as-is if not actively used

**Timeline:**
- Manual installations: ~5 minutes per VM
- Databricks integration setup: ~30 minutes one-time setup
- All monitoring active within 1 hour

---

**YOU'RE ALMOST DONE! JUST NEED TO MANUALLY INSTALL ON THE REMAINING FEW VMs! 🚀**
