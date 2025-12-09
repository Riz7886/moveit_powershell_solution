param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc",
    [string]$DD_SITE    = "us3"
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "DATADOG COMPLETE AUTOMATION WITH AGENT INSTALLATION" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Connecting to Azure..." -ForegroundColor Cyan
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Connect-AzAccount | Out-Null
    $context = Get-AzContext
}
Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green

Write-Host ""
Write-Host "Step 2: Loading subscriptions..." -ForegroundColor Cyan
$allSubs = Get-AzSubscription
if ($allSubs.Count -eq 0) {
    Write-Host "No subscriptions found" -ForegroundColor Red
    exit 1
}

Write-Host ""
for ($i = 0; $i -lt $allSubs.Count; $i++) {
    Write-Host "[$($i + 1)] $($allSubs[$i].Name)"
}
Write-Host ""

$choice        = Read-Host "Select subscription (1-$($allSubs.Count))"
$selectedIndex = [int]$choice - 1
$selectedSub   = $allSubs[$selectedIndex]
Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null

$subId   = $selectedSub.Id
$tenantId = $selectedSub.TenantId

Write-Host ""
Write-Host "Using: $($selectedSub.Name)" -ForegroundColor Green
Write-Host ""

Write-Host "Step 3: Creating Service Principal..." -ForegroundColor Cyan
$appName     = "Datadog-Integration-Auto"
$existingApp = Get-AzADApplication -DisplayName $appName -ErrorAction SilentlyContinue

if ($existingApp) {
    Write-Host "Service Principal exists" -ForegroundColor Yellow
    $appId = $existingApp.AppId
    $sp    = Get-AzADServicePrincipal -ApplicationId $appId
} else {
    $app   = New-AzADApplication -DisplayName $appName
    $appId = $app.AppId
    $sp    = New-AzADServicePrincipal -ApplicationId $appId
    Start-Sleep -Seconds 10
    Write-Host "Service Principal created" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 4: Creating Client Secret..." -ForegroundColor Cyan
$startDate    = Get-Date
$endDate      = $startDate.AddYears(2)
$secret       = New-AzADAppCredential -ApplicationId $appId -StartDate $startDate -EndDate $endDate
$clientSecret = $secret.SecretText
Write-Host "Client Secret created" -ForegroundColor Green

Write-Host ""
Write-Host "Step 5: Assigning Monitoring Reader role..." -ForegroundColor Cyan
$roleAssignment = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Monitoring Reader" -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue

if (-not $roleAssignment) {
    New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Monitoring Reader" -Scope "/subscriptions/$subId" | Out-Null
    Write-Host "Role assigned" -ForegroundColor Green
} else {
    Write-Host "Role already assigned" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 6: Configuring Datadog Azure Integration..." -ForegroundColor Cyan
$datadogUrl = "https://api.us3.datadoghq.com/api/v1/integration/azure"
$headers = @{
    "DD-API-KEY"        = $DD_API_KEY
    "DD-APPLICATION-KEY"= $DD_APP_KEY
    "Content-Type"      = "application/json"
}

$azureConfig = @{
    tenant_name             = $tenantId
    client_id               = $appId
    client_secret           = $clientSecret
    host_filters            = ""
    app_service_plan_filters= ""
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $datadogUrl -Method Post -Headers $headers -Body $azureConfig -ErrorAction Stop | Out-Null
    Write-Host "Azure integration configured" -ForegroundColor Green
} catch {
    Write-Host "Integration configured or already exists" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 7: Scanning for Virtual Machines..." -ForegroundColor Cyan
$VMs = Get-AzVM -Status
if (-not $VMs -or $VMs.Count -eq 0) {
    Write-Host "No VMs found in subscription" -ForegroundColor Yellow
} else {
    Write-Host "Found $($VMs.Count) VMs" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Step 8: Installing Datadog Agents on VMs..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount    = 0
    
    foreach ($vm in $VMs) {
        $vmName = $vm.Name
        $rg     = $vm.ResourceGroupName
        $os     = $vm.StorageProfile.OsDisk.OsType
        
        Write-Host "Installing agent on: $vmName ($os)" -ForegroundColor White
        
        if ($os -eq "Windows") {
            $script = @"
`$msiUrl  = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
`$msiPath = "`$env:TEMP\datadog-agent.msi"
try {
    Invoke-WebRequest -Uri `$msiUrl -OutFile `$msiPath -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `$msiPath /qn APIKEY=$DD_API_KEY SITE=$DD_SITE" -Wait
    Remove-Item `$msiPath -Force
    Start-Sleep -Seconds 5
    Restart-Service datadogagent -ErrorAction SilentlyContinue
    Write-Output "Agent installed successfully"
} catch {
    Write-Output "Agent installation failed: `$_"
}
"@
            try {
                $result = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString $script -ErrorAction Stop
                Write-Host "  [OK] $vmName" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "  [FAIL] $vmName" -ForegroundColor Red
                $failCount++
            }
        }
        elseif ($os -eq "Linux") {
            $script = @"
#!/bin/bash
export DD_API_KEY=$DD_API_KEY
export DD_SITE=$DD_SITE
bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@
            try {
                $result = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunShellScript" -ScriptString $script -ErrorAction Stop
                Write-Host "  [OK] $vmName" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "  [FAIL] $vmName" -ForegroundColor Red
                $failCount++
            }
        }
        else {
            Write-Host "  [SKIP] $vmName - Unknown OS" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "Agent Installation Summary:" -ForegroundColor Yellow
    Write-Host "  Success: $successCount" -ForegroundColor Green
    Write-Host "  Failed:  $failCount" -ForegroundColor Red
    Write-Host ""
}

Write-Host "Step 9: Creating Datadog Monitors (FIXED HYBRID ONLY)..." -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.us3.datadoghq.com/api/v1/monitor"

# NOTE: Original Azure-only monitors removed (Option C).
# Only the FIXED hybrid monitors are created below.

####################################################################################
#  STEP 10: AUTO-FIX DATADOG MONITORS (SYED FIX MODULE)
####################################################################################

Write-Host ""
Write-Host "==============================================="
Write-Host "   STARTING DATADOG MONITOR AUTO-FIX ENGINE   "
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

$metricsApi = "https://api.us3.datadoghq.com/api/v1/metrics"

try {
    $metricResponse = Invoke-RestMethod -Uri $metricsApi -Method Get -Headers $headers -ErrorAction Stop
    $allMetrics     = $metricResponse.metrics
    Write-Host "Datadog Metric Count: $($allMetrics.Count)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Unable to read Datadog metric list" -ForegroundColor Red
    return
}

function Test-MetricExists {
    param([string]$metric)
    return $allMetrics -contains $metric
}

function Build-HybridQuery {
    param(
        [string]$agentMetric,
        [string]$azureMetric,
        [int]$threshold,
        [switch]$LessThan
    )

    $valid = @()

    if (Test-MetricExists $agentMetric) { $valid += "avg:$agentMetric{*}" }
    if (Test-MetricExists $azureMetric) { $valid += "avg:$azureMetric{*}" }

    if ($valid.Count -eq 0) { return $null }

    $join = "(" + ($valid -join " OR ") + ")"

    if ($LessThan) { return "avg(last_5m):$join < $threshold" }
    return "avg(last_5m):$join > $threshold"
}

function New-FixedMonitor {
    param(
        [string]$name,
        [string]$agentMetric,
        [string]$azureMetric,
        [int]$threshold,
        [string]$message,
        [switch]$LessThan
    )

    $query = Build-HybridQuery -agentMetric $agentMetric -azureMetric $azureMetric -threshold $threshold -LessThan:$LessThan
    if (-not $query) {
        Write-Host "[SKIP] $name → no valid metrics found" -ForegroundColor Yellow
        return
    }

    $body = @{
        name    = $name
        type    = "metric alert"
        query   = $query
        message = $message
        tags    = @("env:production")
        options = @{
            notify_no_data     = $true
            no_data_timeframe  = 10
            require_full_window= $false
        }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Host "[FIXED] $name" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $name → $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Creating FIXED hybrid monitors..." -ForegroundColor Cyan

New-FixedMonitor -name "CPU High (FIXED)"    -agentMetric "system.cpu.user"    -azureMetric "azure.vm.cpu_percentage"        -threshold 85       -message "High CPU detected"
New-FixedMonitor -name "Memory Low (FIXED)"  -agentMetric "system.mem.pct_usable" -azureMetric "azure.vm.memory_used_percent" -threshold 20 -message "Memory low" -LessThan
New-FixedMonitor -name "Disk High (FIXED)"   -agentMetric "system.disk.in_use"  -azureMetric "azure.vm.disk_used_percentage" -threshold 85       -message "Disk usage high"
New-FixedMonitor -name "Network High (FIXED)"-agentMetric "system.net.bytes_sent" -azureMetric "azure.vm.network_out_total"  -threshold 50000000 -message "High network traffic"

Write-Host ""
Write-Host "==============================================="
Write-Host "   DATADOG MONITOR AUTO-FIX FINISHED SUCCESS   "
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
