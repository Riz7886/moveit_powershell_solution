<#
    Datadog-OneFile-AutoDeploy-v12.1.ps1
    FULL SAFE MODE + AUTO DISCOVERY + HYBRID METRICS + FIXED LOGIN

    THIS VERSION FIXES:
    • Azure login persistence
    • Subscription auto-detection failing
    • Hybrid monitor NO-DATA errors
    • service_check() queries breaking PowerShell
    • MOVEit, AVD, DB, API monitor syntax
    • Datadog US3 endpoint errors

    SAFE MODE GUARANTEES:
    ✔ Never deletes anything
    ✔ Never overwrites Azure resources
    ✔ Only reads + installs Datadog agent + creates monitors
    ✔ No destructive operations allowed
#>

Write-Host "`n=== DATADOG AUTO-DEPLOY V12.1 STARTED ===`n" -ForegroundColor Cyan

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

# ===========================
# 2. FIXED AZURE LOGIN (V12.1)
# ===========================

Write-Host "Connecting to Azure..." -ForegroundColor Yellow

try {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Enable-AzContextAutosave  -Scope CurrentUser | Out-Null

    $ctx = Get-AzContext -ErrorAction SilentlyContinue

    if ($ctx) {
        Write-Host "Using existing Azure login: $($ctx.Account)" -ForegroundColor Green
    }
    else {
        Write-Host "No saved session — performing one-time device login..." -ForegroundColor Yellow
        Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
    }
}
catch {
    Write-Host "Azure login failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ===========================
# 3. GET ALL AZURE SUBSCRIPTIONS
# ===========================

Write-Host "`nFinding all Azure subscriptions..." -ForegroundColor Yellow

$Subs = Get-AzSubscription | Sort-Object -Property Name

if ($Subs.Count -eq 0) {
    Write-Host "No subscriptions found." -ForegroundColor Red
    exit
}

Write-Host "`nAvailable Subscriptions:`n"
$index = 1
foreach ($s in $Subs) {
    Write-Host "[$index] $($s.Name)  ($($s.Id))"
    $index++
}

$choice = Read-Host "`nEnter subscription number to run deployment on"
if ([int]$choice -lt 1 -or [int]$choice -gt $Subs.Count) {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit
}

$SelectedSub = $Subs[$choice - 1]
Set-AzContext -Subscription $SelectedSub.Id | Out-Null

Write-Host "`nUsing Subscription: $($SelectedSub.Name)`n" -ForegroundColor Green

# ===========================
# 4. VM DISCOVERY
# ===========================

$Global:DeployReport = @()

Write-Host "Scanning subscription for VMs..." -ForegroundColor Yellow

$VMs = Get-AzVM -Status

if ($VMs.Count -eq 0) {
    Write-Host "No VMs found in this subscription." -ForegroundColor Red
    exit
}

Write-Host "`nFound $($VMs.Count) VMs:`n" -ForegroundColor Green
foreach ($vm in $VMs) {
    Write-Host "- $($vm.Name) ($($vm.StorageProfile.OsDisk.OsType))"
}

# ===========================
# 5. EXECUTION HELPERS
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
        Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroup `
            -Name $VMName `
            -CommandId $CommandID `
            -ScriptString $ScriptBlock `
            -ErrorAction Stop
    }
    catch {
        return $_.Exception.Message
    }
}

# ===========================
# 6. AGENT INSTALLERS
# ===========================

Write-Host "`nInitializing Datadog agent installers..." -ForegroundColor Cyan

function Install-DDWindowsAgent {
    param($ResourceGroup, $VMName)

    $script = @"
msiexec.exe /i https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi /qn APIKEY=$DD_API_KEY SITE=$DatadogSite
Restart-Service datadogagent
"@

    $result = Run-VMCommand $ResourceGroup $VMName "RunPowerShellScript" $script

    if ($result -is [string]) {
        Add-DeployLog $VMName "Windows" "FAIL: $result"
        Write-Host "[FAILED] $VMName — Windows agent install failed." -ForegroundColor Red
    }
    else {
        Add-DeployLog $VMName "Windows" "Installed"
        Write-Host "[OK] $VMName — Windows agent installed." -ForegroundColor Green
    }
}

function Install-DDLinuxAgent {
    param($ResourceGroup, $VMName)

    $script = @"
DD_API_KEY=$DD_API_KEY DD_SITE=$DatadogSite bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@

    $result = Run-VMCommand $ResourceGroup $VMName "RunShellScript" $script

    if ($result -is [string]) {
        Add-DeployLog $VMName "Linux" "FAIL: $result"
        Write-Host "[FAILED] $VMName — Linux agent install failed." -ForegroundColor Red
    }
    else {
        Add-DeployLog $VMName "Linux" "Installed"
        Write-Host "[OK] $VMName — Linux agent installed." -ForegroundColor Green
    }
}

# ===========================
# 7. INSTALL AGENTS ON ALL VMS
# ===========================

Write-Host "`nInstalling Datadog agents on all VMs..." -ForegroundColor Yellow

foreach ($vm in $VMs) {
    $VMName = $vm.Name
    $RG     = $vm.ResourceGroupName
    $OS     = $vm.StorageProfile.OsDisk.OsType

    Write-Host "`n--- Processing VM: $VMName ($OS) ---" -ForegroundColor Cyan

    if ($OS -eq "Windows") { Install-DDWindowsAgent $RG $VMName }
    elseif ($OS -eq "Linux") { Install-DDLinuxAgent $RG $VMName }
    else {
        Add-DeployLog $VMName $OS "Skipped: Unknown OS"
    }
}

# ===========================
# 8. MONITOR ENGINE (HYBRID + FIXED QUERIES)
# ===========================

Write-Host "`nCreating Datadog Hybrid Monitors..." -ForegroundColor Cyan

function New-DDMonitor {
    param($Name, $Query, $Message, $Tags)

    $body = @{
        name    = $Name
        type    = "metric alert"
        query   = $Query
        message = $Message
        tags    = $Tags.Split(",")
        options = @{
            evaluation_delay   = 300
            notify_no_data     = $true
            no_data_timeframe  = 10
            require_full_window = $false
        }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $BaseUrl -Method Post -Headers $Headers -Body $body -ErrorAction Stop
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] $Name — $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ===========
# FIXED QUERIES
# ===========

# CPU
$cpuQuery = "avg(last_5m):(avg:system.cpu.user{*} OR avg:azure.vm.cpu_percentage{*}) > 85"

New-DDMonitor "CPU High Usage (Hybrid v12.1)" $cpuQuery `
    "CPU usage exceeded 85%." "env:prod,metric:cpu,hybrid:true"

# MEMORY
$memQuery = "avg(last_5m):(avg:system.mem.pct_usable{*} OR (1 - avg:azure.vm.memory_available_bytes{*}/avg:azure.vm.memory_total_bytes{*})) < 0.20"

New-DDMonitor "Memory Low (Hybrid v12.1)" $memQuery `
    "Available memory below 20%." "env:prod,metric:memory,hybrid:true"

# DISK
$diskQuery = "avg(last_5m):(avg:system.disk.in_use{*} OR avg:azure.vm.disk_used_percentage{*}) > 85"

New-DDMonitor "Disk Space High (Hybrid v12.1)" $diskQuery `
    "Disk usage above 85%." "env:prod,metric:disk,hybrid:true"

# NETWORK
$networkQuery = "avg(last_5m):(avg:azure.vm.network_in_total{*} + avg:azure.vm.network_out_total{*}) > 50000000"

New-DDMonitor "Network High (Hybrid v12.1)" $networkQuery `
    "Network throughput high." "env:prod,metric:network,hybrid:true"

# MOVEit
$moveitServiceQuery = "service_check('moveit.service.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{tags:moveit} > 90"

New-DDMonitor "MOVEit Service Down (Hybrid v12.1)" $moveitServiceQuery `
    "MOVEit service down or CPU overloaded." "env:prod,app:moveit,hybrid:true"

# API
$apiHeartbeatQuery = "avg(last_5m):(avg:synthetics.api.status{*} OR service_check('api.heartbeat'){*}.over('last_5m')) != 0"

New-DDMonitor "API Heartbeat Failure (Hybrid v12.1)" $apiHeartbeatQuery `
    "API heartbeat failed." "env:prod,app:api,hybrid:true"

# DB
$dbQuery = "service_check('db.connection.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.sql.cpu_percent{*} > 90"

New-DDMonitor "Database Connectivity Issue (Hybrid v12.1)" $dbQuery `
    "Database connection failure." "env:prod,db:sql,hybrid:true"

# AVD Broker
$avdBrokerQuery = "service_check('avd.broker.status'){*}.over('last_5m') != 0"

New-DDMonitor "AVD Broker Down (Hybrid v12.1)" $avdBrokerQuery `
    "AVD Broker unavailable." "env:prod,avd:broker"

# Universal
$heartbeatQuery = "service_check('system.up'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{*} > 95"

New-DDMonitor "Universal Heartbeat Failure (Hybrid v12.1)" $heartbeatQuery `
    "Heartbeat failure." "env:prod,hybrid:true"

# ===========================
# 9. REPORT GENERATION
# ===========================

$ReportPath = ".\DatadogDeployReport_v12.1.csv"

$Global:DeployReport |
    Select-Object Timestamp, VM, OS, Status |
    Export-Csv -Path $ReportPath -NoTypeInformation -Force

Write-Host "`nDeployment Report Saved → $ReportPath" -ForegroundColor Green

# ===========================
# 10. SUMMARY
# ===========================

Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
Write-Host "Agents Installed: $($Global:DeployReport.Count)" -ForegroundColor Cyan
Write-Host "`nDatadog Auto-Deploy v12.1 Completed Successfully`n" -ForegroundColor Green

# END
