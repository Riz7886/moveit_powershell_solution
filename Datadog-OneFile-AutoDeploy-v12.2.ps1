<#
    Datadog-OneFile-AutoDeploy-v12.2.ps1
    FULL SAFE MODE + AUTO DISCOVERY + HYBRID METRICS + FIXED LOGIN

    Notes:
    - Run in Windows PowerShell or PowerShell 7 with Az modules installed.
    - Make sure you replace DD_API_KEY and DD_APP_KEY with real values.
    - Script does NOT delete or modify any Azure resources. It only reads, installs agents, and creates Datadog monitors.
#>

Write-Host "`n=== DATADOG AUTO-DEPLOY V12.2 STARTED ===`n" -ForegroundColor Cyan

# ===========================
# 1. CONFIGURATION BLOCK
# ===========================

$DD_API_KEY = "PUT_YOUR_API_KEY_HERE"
$DD_APP_KEY = "PUT_YOUR_APP_KEY_HERE"

$DatadogSite = "us3"
$BaseUrl = "https://api.us3.datadoghq.com/api/v1/monitor"

$Headers = @{
    "DD-API-KEY"         = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type"       = "application/json"
}

$ErrorActionPreference = "Stop"

# Basic validation for keys
$DatadogConfigured = $true
if ([string]::IsNullOrWhiteSpace($DD_API_KEY) -or $DD_API_KEY -like "*PUT_YOUR_API_KEY*") {
    Write-Host "WARNING: Datadog API key is not set. Monitors will NOT be created." -ForegroundColor Yellow
    $DatadogConfigured = $false
}
if ([string]::IsNullOrWhiteSpace($DD_APP_KEY) -or $DD_APP_KEY -like "*PUT_YOUR_APP_KEY*") {
    Write-Host "WARNING: Datadog APP key is not set. Monitors will NOT be created." -ForegroundColor Yellow
    $DatadogConfigured = $false
}

# ===========================
# 2. AZURE LOGIN (HARDENED)
# ===========================

Write-Host "Connecting to Azure..." -ForegroundColor Yellow

try {
    Disable-AzContextAutosave -Scope Process -ErrorAction SilentlyContinue | Out-Null
    Enable-AzContextAutosave  -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null

    $ctx = Get-AzContext -ErrorAction SilentlyContinue

    if ($ctx) {
        Write-Host "Using existing Azure login: $($ctx.Account)" -ForegroundColor Green
    }
    else {
        Write-Host "No saved session found. Attempting device login..." -ForegroundColor Yellow
        try {
            Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "Device login failed. Falling back to interactive login..." -ForegroundColor Yellow
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
    }
}
catch {
    Write-Host "Azure login failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ===========================
# 3. SUBSCRIPTION SELECTION
# ===========================

Write-Host "`nFinding all Azure subscriptions..." -ForegroundColor Yellow

try {
    $Subs = Get-AzSubscription | Sort-Object -Property Name
}
catch {
    Write-Host "Failed to list subscriptions: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $Subs -or $Subs.Count -eq 0) {
    Write-Host "No subscriptions found for this account." -ForegroundColor Red
    exit 1
}

Write-Host "`nAvailable Subscriptions:`n"
$index = 1
foreach ($s in $Subs) {
    Write-Host ("[{0}] {1} ({2})" -f $index, $s.Name, $s.Id)
    $index++
}

$choice = Read-Host "`nEnter subscription number to run deployment on"
if (-not [int]::TryParse($choice, [ref]0)) {
    Write-Host "Invalid selection. Not a number." -ForegroundColor Red
    exit 1
}

$choiceInt = [int]$choice
if ($choiceInt -lt 1 -or $choiceInt -gt $Subs.Count) {
    Write-Host "Invalid selection. Out of range." -ForegroundColor Red
    exit 1
}

$SelectedSub = $Subs[$choiceInt - 1]

try {
    Set-AzContext -Subscription $SelectedSub.Id | Out-Null
}
catch {
    Write-Host "Failed to set subscription context: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`nUsing Subscription: $($SelectedSub.Name)`n" -ForegroundColor Green

# ===========================
# 4. VM DISCOVERY
# ===========================

$Global:DeployReport = @()

Write-Host "Scanning subscription for Virtual Machines..." -ForegroundColor Yellow

try {
    $VMs = Get-AzVM -Status
}
catch {
    Write-Host "Failed to query VMs: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $VMs -or $VMs.Count -eq 0) {
    Write-Host "No VMs found in this subscription." -ForegroundColor Red
    exit 0
}

Write-Host ("`nFound {0} VMs:`n" -f $VMs.Count) -ForegroundColor Green
foreach ($vm in $VMs) {
    Write-Host ("- {0} ({1})" -f $vm.Name, $vm.StorageProfile.OsDisk.OsType)
}

# ===========================
# 5. HELPER FUNCTIONS
# ===========================

function Add-DeployLog {
    param(
        [string]$VM,
        [string]$OS,
        [string]$Result
    )
    $Global:DeployReport += [pscustomobject]@{
        Timestamp = (Get-Date)
        VM        = $VM
        OS        = $OS
        Status    = $Result
    }
}

function Run-VMCommand {
    param(
        [string]$ResourceGroup,
        [string]$VMName,
        [string]$CommandID,
        [string]$ScriptBlock
    )

    try {
        $output = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroup `
            -Name $VMName `
            -CommandId $CommandID `
            -ScriptString $ScriptBlock `
            -ErrorAction Stop
        return $output
    }
    catch {
        return $_.Exception.Message
    }
}

# ===========================
# 6. DATADOG AGENT INSTALLERS
# ===========================

Write-Host "`nInitializing Datadog Agent Installer (Windows + Linux)..." -ForegroundColor Cyan

function Install-DDWindowsAgent {
    param(
        [string]$ResourceGroup,
        [string]$VMName
    )

    $script = @"
msiexec.exe /i https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi /qn APIKEY=$DD_API_KEY SITE=$DatadogSite
Restart-Service datadogagent
"@

    $result = Run-VMCommand -ResourceGroup $ResourceGroup -VMName $VMName -CommandID "RunPowerShellScript" -ScriptBlock $script

    if ($result -is [string]) {
        Add-DeployLog -VM $VMName -OS "Windows" -Result ("FAIL: {0}" -f $result)
        Write-Host ("[FAILED] {0} — Windows agent install failed." -f $VMName) -ForegroundColor Red
    }
    else {
        Add-DeployLog -VM $VMName -OS "Windows" -Result "Installed"
        Write-Host ("[OK] {0} — Windows agent installed." -f $VMName) -ForegroundColor Green
    }
}

function Install-DDLinuxAgent {
    param(
        [string]$ResourceGroup,
        [string]$VMName
    )

    $script = @"
DD_API_KEY=$DD_API_KEY DD_SITE=$DatadogSite bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@

    $result = Run-VMCommand -ResourceGroup $ResourceGroup -VMName $VMName -CommandID "RunShellScript" -ScriptBlock $script

    if ($result -is [string]) {
        Add-DeployLog -VM $VMName -OS "Linux" -Result ("FAIL: {0}" -f $result)
        Write-Host ("[FAILED] {0} — Linux agent install failed." -f $VMName) -ForegroundColor Red
    }
    else {
        Add-DeployLog -VM $VMName -OS "Linux" -Result "Installed"
        Write-Host ("[OK] {0} — Linux agent installed." -f $VMName) -ForegroundColor Green
    }
}

# ===========================
# 7. INSTALL AGENTS ON ALL VMS
# ===========================

Write-Host "`nInstalling Datadog Agents on all VMs..." -ForegroundColor Yellow

foreach ($vm in $VMs) {
    $VMName = $vm.Name
    $RG     = $vm.ResourceGroupName
    $OS     = $vm.StorageProfile.OsDisk.OsType

    Write-Host ("`n--- Processing VM: {0} ({1}) ---" -f $VMName, $OS) -ForegroundColor Cyan

    if ($OS -eq "Windows") {
        Install-DDWindowsAgent -ResourceGroup $RG -VMName $VMName
    }
    elseif ($OS -eq "Linux") {
        Install-DDLinuxAgent -ResourceGroup $RG -VMName $VMName
    }
    else {
        Add-DeployLog -VM $VMName -OS $OS -Result "Skipped: Unknown OS"
        Write-Host ("[SKIPPED] {0} — Unknown OS type {1}" -f $VMName, $OS) -ForegroundColor DarkYellow
    }
}

Write-Host "`n=== Agent Installation Phase Completed ===`n" -ForegroundColor Green

# ===========================
# 8. DATADOG MONITOR ENGINE
# ===========================

if (-not $DatadogConfigured) {
    Write-Host "`nDatadog keys not configured. Skipping monitor creation step." -ForegroundColor Yellow
}
else {
    Write-Host "`nCreating Datadog Hybrid Monitors..." -ForegroundColor Cyan

    function New-DDMonitor {
        param(
            [string]$Name,
            [string]$Query,
            [string]$Message,
            [string]$Tags
        )

        $body = @{
            name    = $Name
            type    = "metric alert"
            query   = $Query
            message = $Message
            tags    = $Tags.Split(",")
            options = @{
                evaluation_delay    = 300
                notify_no_data      = $true
                no_data_timeframe   = 10
                require_full_window = $false
            }
        } | ConvertTo-Json -Depth 10

        try {
            Invoke-RestMethod -Uri $BaseUrl -Method Post -Headers $Headers -Body $body -ErrorAction Stop | Out-Null
            Write-Host ("[OK] Monitor created: {0}" -f $Name) -ForegroundColor Green
        }
        catch {
            Write-Host ("[FAILED] {0} — {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
        }
    }

    # Core hybrid alerts
    $cpuQuery = "avg(last_5m):(avg:system.cpu.user{*} OR avg:azure.vm.cpu_percentage{*}) > 85"
    New-DDMonitor -Name "CPU High Usage (Hybrid v12.2)" -Query $cpuQuery -Message "CPU usage exceeded 85%." -Tags "env:prod,metric:cpu,hybrid:true"

    $memQuery = "avg(last_5m):(avg:system.mem.pct_usable{*} OR (1 - avg:azure.vm.memory_available_bytes{*}/avg:azure.vm.memory_total_bytes{*})) < 0.20"
    New-DDMonitor -Name "Memory Low (Hybrid v12.2)" -Query $memQuery -Message "Available memory below 20%." -Tags "env:prod,metric:memory,hybrid:true"

    $diskQuery = "avg(last_5m):(avg:system.disk.in_use{*} OR avg:azure.vm.disk_used_percentage{*}) > 85"
    New-DDMonitor -Name "Disk Space High (Hybrid v12.2)" -Query $diskQuery -Message "Disk usage above 85%." -Tags "env:prod,metric:disk,hybrid:true"

    $networkQuery = "avg(last_5m):(avg:azure.vm.network_in_total{*} + avg:azure.vm.network_out_total{*}) > 50000000"
    New-DDMonitor -Name "Network High (Hybrid v12.2)" -Query $networkQuery -Message "Network throughput high." -Tags "env:prod,metric:network,hybrid:true"

    # MOVEit
    $moveitServiceQuery = "service_check('moveit.service.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{tags:moveit} > 90"
    New-DDMonitor -Name "MOVEit Service Down (Hybrid v12.2)" -Query $moveitServiceQuery -Message "MOVEit service down or CPU overloaded." -Tags "env:prod,app:moveit,hybrid:true"

    # API
    $apiHeartbeatQuery = "avg(last_5m):(avg:synthetics.api.status{*} OR service_check('api.heartbeat'){*}.over('last_5m')) != 0"
    New-DDMonitor -Name "API Heartbeat Failure (Hybrid v12.2)" -Query $apiHeartbeatQuery -Message "API heartbeat failed." -Tags "env:prod,app:api,hybrid:true"

    # DB
    $dbQuery = "service_check('db.connection.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.sql.cpu_percent{*} > 90"
    New-DDMonitor -Name "Database Connectivity Issue (Hybrid v12.2)" -Query $dbQuery -Message "Database connection failure or high CPU." -Tags "env:prod,db:sql,hybrid:true"

    # AVD Broker
    $avdBrokerQuery = "service_check('avd.broker.status'){*}.over('last_5m') != 0"
    New-DDMonitor -Name "AVD Broker Down (Hybrid v12.2)" -Query $avdBrokerQuery -Message "AVD Broker is unavailable." -Tags "env:prod,avd:broker,hybrid:true"

    # Universal heartbeat
    $heartbeatQuery = "service_check('system.up'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{*} > 95"
    New-DDMonitor -Name "Universal Heartbeat Failure (Hybrid v12.2)" -Query $heartbeatQuery -Message "Heartbeat failure detected." -Tags "env:prod,hybrid:true,heartbeat:vm"

    Write-Host "`n=== Datadog Monitor Creation Completed ===`n" -ForegroundColor Green
}

# ===========================
# 9. REPORT GENERATION
# ===========================

Write-Host "`nGenerating deployment report..." -ForegroundColor Cyan

$ReportPath = ".\DatadogDeployReport_v12.2.csv"

try {
    $Global:DeployReport |
        Select-Object Timestamp, VM, OS, Status |
        Export-Csv -Path $ReportPath -NoTypeInformation -Force

    Write-Host ("Deployment report saved to: {0}" -f $ReportPath) -ForegroundColor Green
}
catch {
    Write-Host ("Failed to write CSV report: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# ===========================
# 10. SUMMARY
# ===========================

Write-Host "`n=== SUMMARY OF AGENT INSTALLATION ===" -ForegroundColor Yellow

$okCount   = ($Global:DeployReport | Where-Object { $_.Status -like "Installed*" }).Count
$failCount = ($Global:DeployReport | Where-Object { $_.Status -like "FAIL*" }).Count
$skipCount = ($Global:DeployReport | Where-Object { $_.Status -like "Skipped*" }).Count

Write-Host ("Agents Installed Successfully : {0}" -f $okCount) -ForegroundColor Green
Write-Host ("Agent Installation Failures  : {0}" -f $failCount) -ForegroundColor Red
Write-Host ("Skipped (Unknown OS)         : {0}" -f $skipCount) -ForegroundColor DarkYellow

Write-Host "`n=== SUMMARY OF MONITOR CREATION ===" -ForegroundColor Yellow
if ($DatadogConfigured) {
    Write-Host "Hybrid monitors (CPU / Mem / Disk / Network / App / DB / AVD / MOVEit) were attempted via US3 API." -ForegroundColor Cyan
    Write-Host "Login to Datadog and verify Monitors and data flow." -ForegroundColor Cyan
}
else {
    Write-Host "Datadog keys not set. No monitors were created." -ForegroundColor Yellow
}

Write-Host "`nDatadog Auto-Deploy v12.2 Completed (SAFE MODE)." -ForegroundColor Green
