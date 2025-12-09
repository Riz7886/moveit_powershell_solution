<#
    Datadog-OneFile-AutoDeploy-v12.ps1
    FULL SAFE MODE + AUTO DISCOVERY + HYBRID METRICS
#>

Write-Host "`n=== DATADOG AUTO-DEPLOY V12 STARTED ===`n" -ForegroundColor Cyan

# ===========================
# 1. CONFIGURATION BLOCK
# ===========================

# INSERT YOUR REAL KEYS
$DD_API_KEY     = "PUT_YOUR_API_KEY_HERE"
$DD_APP_KEY     = "PUT_YOUR_APP_KEY_HERE"

# Datadog US3 Endpoint (CORRECT)
$DatadogSite = "us3"
$BaseUrl = "https://api.us3.datadoghq.com/api/v1/monitor"

$Headers = @{
    "DD-API-KEY"        = $DD_API_KEY
    "DD-APPLICATION-KEY"= $DD_APP_KEY
    "Content-Type"      = "application/json"
}

$ErrorActionPreference = "Stop"

# ===========================
# 2. LOGIN TO AZURE
# ===========================

Write-Host "Connecting to Azure..." -ForegroundColor Yellow

try {
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) { Connect-AzAccount -UseDeviceAuthentication | Out-Null }
}
catch {
    Write-Host "Azure login failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ===========================
# 3. GET ALL SUBSCRIPTIONS
# ===========================

Write-Host "`nFinding all Azure subscriptions..." -ForegroundColor Yellow

$Subs = Get-AzSubscription | Sort-Object -Property Name
if ($Subs.Count -eq 0) { Write-Host "No subscriptions found."; exit }

Write-Host "`nAvailable Subscriptions:`n"
$idx = 1
foreach ($s in $Subs) {
    Write-Host "[$idx] $($s.Name) ($($s.Id))"
    $idx++
}

$choice = Read-Host "`nEnter subscription number"
$SelectedSub = $Subs[[int]$choice - 1]

Write-Host "`nUsing Subscription: $($SelectedSub.Name)`n" -ForegroundColor Green
Set-AzContext -Subscription $SelectedSub.Id | Out-Null

# ===========================
# 4. LOGGING
# ===========================

$Global:DeployReport = @()
Write-Host "Logging initialized.`n" -ForegroundColor Cyan

# ===========================
# 5. DISCOVER VMS
# ===========================

Write-Host "Scanning VM inventory..." -ForegroundColor Yellow

$VMs = Get-AzVM -Status
if ($VMs.Count -eq 0) { Write-Host "No VMs found."; exit }

Write-Host "`nFound $($VMs.Count) VMs:`n"
foreach ($vm in $VMs) {
    Write-Host "- $($vm.Name) ($($vm.StorageProfile.OsDisk.OsType))"
}

# ===========================
# 6. HELPER FUNCTIONS
# ===========================

function Add-DeployLog {
    param($VM,$OS,$Result)
    $Global:DeployReport += [pscustomobject]@{
        Timestamp = (Get-Date)
        VM = $VM
        OS = $OS
        Status = $Result
    }
}

function Run-VMCommand {
    param($ResourceGroup,$VMName,$CommandID,$ScriptBlock)
    try {
        return Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroup `
            -Name $VMName `
            -CommandId $CommandID `
            -ScriptString $ScriptBlock `
            -ErrorAction Stop
    }
    catch { return $_.Exception.Message }
}

# ===========================
# 7. AGENT INSTALL (WINDOWS)
# ===========================

function Install-DDWindowsAgent {
    param($ResourceGroup,$VMName)

    $script = @"
msiexec.exe /i https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi /qn APIKEY=$DD_API_KEY SITE=$DatadogSite
Restart-Service datadogagent
"@

    $result = Run-VMCommand $ResourceGroup $VMName "RunPowerShellScript" $script

    if ($result -is [string]) {
        Add-DeployLog $VMName "Windows" "FAIL: $result"
        Write-Host "[FAILED] $VMName" -ForegroundColor Red
    }
    else {
        Add-DeployLog $VMName "Windows" "Installed"
        Write-Host "[OK] $VMName" -ForegroundColor Green
    }
}

# ===========================
# 8. AGENT INSTALL (LINUX)
# ===========================

function Install-DDLinuxAgent {
    param($ResourceGroup,$VMName)

    $script = @"
DD_API_KEY=$DD_API_KEY DD_SITE=$DatadogSite bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@

    $result = Run-VMCommand $ResourceGroup $VMName "RunShellScript" $script

    if ($result -is [string]) {
        Add-DeployLog $VMName "Linux" "FAIL: $result"
        Write-Host "[FAILED] $VMName" -ForegroundColor Red
    }
    else {
        Add-DeployLog $VMName "Linux" "Installed"
        Write-Host "[OK] $VMName" -ForegroundColor Green
    }
}

# ===========================
# 9. INSTALL AGENTS ON ALL VMS
# ===========================

Write-Host "`nInstalling Datadog Agents...`n" -ForegroundColor Yellow

foreach ($vm in $VMs) {
    $name = $vm.Name
    $rg   = $vm.ResourceGroupName
    $os   = $vm.StorageProfile.OsDisk.OsType

    Write-Host "`n--- $name ($os) ---" -ForegroundColor Cyan

    if ($os -eq "Windows") { Install-DDWindowsAgent $rg $name }
    elseif ($os -eq "Linux") { Install-DDLinuxAgent $rg $name }
    else {
        Add-DeployLog $name $os "Skipped - Unknown OS"
    }
}

# ===========================
# 10. MONITOR CREATION ENGINE
# ===========================

function New-DDMonitor {
    param($Name,$Query,$Message,$Tags)

    $body = @{
        name    = $Name
        type    = "metric alert"
        query   = $Query
        message = $Message
        tags    = $Tags.Split(",")
        options = @{
            evaluation_delay = 300
            notify_no_data   = $true
            no_data_timeframe= 10
            require_full_window = $false
        }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $BaseUrl -Method Post -Headers $Headers -Body $body
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] $Name — $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ===========================
# HYBRID ALERTS (CORRECTED)
# ===========================

$cpuQuery = @"
avg(last_5m):(avg:system.cpu.user{*} OR avg:azure.vm.cpu_percentage{*}) > 85
"@

$memQuery = @"
avg(last_5m):(avg:system.mem.pct_usable{*} OR (1 - avg:azure.vm.memory_available_bytes{*}/avg:azure.vm.memory_total_bytes{*})) < 0.20
"@

$diskQuery = @"
avg(last_5m):(avg:system.disk.in_use{*} OR avg:azure.vm.disk_used_percentage{*}) > 85
"@

$networkQuery = @"
avg(last_5m):(avg:azure.vm.network_in_total{*} + avg:azure.vm.network_out_total{*}) > 50000000
"@

New-DDMonitor "CPU High Usage (Hybrid v12)"     $cpuQuery     "CPU overload detected."     "env:prod,metric:cpu"
New-DDMonitor "Memory Low (Hybrid v12)"         $memQuery     "Memory critically low."     "env:prod,metric:memory"
New-DDMonitor "Disk Space High (Hybrid v12)"    $diskQuery    "Disk space high."           "env:prod,metric:disk"
New-DDMonitor "Network High (Hybrid v12)"       $networkQuery "Network throughput high."   "env:prod,metric:network"

# ===========================
# APPLICATION MONITORS (CORRECTED)
# ===========================

$moveitServiceQuery = @"
service_check('moveit.service.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{tags:moveit} > 90
"@

New-DDMonitor "MOVEit Service Down (Hybrid v12)" $moveitServiceQuery "MOVEit appears down." "env:prod,app:moveit"

$moveitHttpQuery = @"
avg(last_5m):avg:synthetics.http.response_time{app:moveit} > 2000
"@

New-DDMonitor "MOVEit HTTPS Slow (Hybrid v12)" $moveitHttpQuery "MOVEit HTTPS slow." "env:prod,app:moveit"

$apiHeartbeatQuery = @"
avg(last_5m):(avg:synthetics.api.status{*} OR service_check('api.heartbeat'){*}.over('last_5m')) != 0
"@

New-DDMonitor "API Heartbeat Failure" $apiHeartbeatQuery "API heartbeat failing." "env:prod,app:api"

$dbQuery = @"
service_check('db.connection.status'){*}.over('last_5m') != 0 OR avg(last_5m):azure.sql.cpu_percent{*} > 90
"@

New-DDMonitor "DB Connectivity Issue" $dbQuery "Database connectivity issue." "env:prod,db:sql"

$heartbeatQuery = @"
service_check('system.up'){*}.over('last_5m') != 0 OR avg(last_5m):azure.vm.cpu_percentage{*} > 95
"@

New-DDMonitor "Universal Heartbeat Failure" $heartbeatQuery "Heartbeat failure." "env:prod"

# ===========================
# 11. CSV REPORT
# ===========================

$ReportPath = ".\DatadogDeployReport_v12.csv"
$Global:DeployReport | Export-Csv -Path $ReportPath -NoTypeInformation -Force
Write-Host "`nReport saved: $ReportPath`n" -ForegroundColor Green

Write-Host "`n=== DATADOG AUTODEPLOY v12 COMPLETE ===`n" -ForegroundColor Cyan
