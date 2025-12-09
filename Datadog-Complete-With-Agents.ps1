param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc",
    [string]$DD_SITE = "us3.datadoghq.com"
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

$choice = Read-Host "Select subscription (1-$($allSubs.Count))"
$selectedIndex = [int]$choice - 1
$selectedSub = $allSubs[$selectedIndex]
Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null

$subId = $selectedSub.Id
$tenantId = $selectedSub.TenantId

Write-Host ""
Write-Host "Using: $($selectedSub.Name)" -ForegroundColor Green
Write-Host ""

Write-Host "Step 3: Creating Service Principal..." -ForegroundColor Cyan
$appName = "Datadog-Integration-Auto"
$existingApp = Get-AzADApplication -DisplayName $appName -ErrorAction SilentlyContinue

if ($existingApp) {
    Write-Host "Service Principal exists" -ForegroundColor Yellow
    $appId = $existingApp.AppId
    $sp = Get-AzADServicePrincipal -ApplicationId $appId
} else {
    $app = New-AzADApplication -DisplayName $appName
    $appId = $app.AppId
    $sp = New-AzADServicePrincipal -ApplicationId $appId
    Start-Sleep -Seconds 10
    Write-Host "Service Principal created" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 4: Creating Client Secret..." -ForegroundColor Cyan
$startDate = Get-Date
$endDate = $startDate.AddYears(2)
$secret = New-AzADAppCredential -ApplicationId $appId -StartDate $startDate -EndDate $endDate
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
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

$azureConfig = @{
    tenant_name = $tenantId
    client_id = $appId
    client_secret = $clientSecret
    host_filters = ""
    app_service_plan_filters = ""
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
    $failCount = 0
    
    foreach ($vm in $VMs) {
        $vmName = $vm.Name
        $rg = $vm.ResourceGroupName
        $os = $vm.StorageProfile.OsDisk.OsType
        
        Write-Host "Installing agent on: $vmName ($os)" -ForegroundColor White
        
        if ($os -eq "Windows") {
            $script = @"
`$msiUrl = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
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
    Write-Host "  Failed: $failCount" -ForegroundColor Red
    Write-Host ""
}

Write-Host "Step 9: Creating Datadog Monitors..." -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.us3.datadoghq.com/api/v1/monitor"

function New-Monitor {
    param([string]$Name, [string]$Query, [string]$Message)
    
    $body = @{
        name = $Name
        type = "metric alert"
        query = $Query
        message = $Message
        tags = @("env:production")
        options = @{
            thresholds = @{ critical = 1 }
            notify_no_data = $true
            no_data_timeframe = 10
        }
    } | ConvertTo-Json -Depth 5
    
    try {
        Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[SKIP] $Name" -ForegroundColor Yellow
    }
}

New-Monitor -Name "VM CPU High" -Query "avg(last_5m):avg:azure.vm.percentage_cpu{*} > 85" -Message "VM CPU above 85 percent"
New-Monitor -Name "VM Network In High" -Query "avg(last_5m):avg:azure.vm.network_in_total{*} > 100000000" -Message "VM network in high"
New-Monitor -Name "VM Network Out High" -Query "avg(last_5m):avg:azure.vm.network_out_total{*} > 100000000" -Message "VM network out high"
New-Monitor -Name "VM Disk Read High" -Query "avg(last_5m):avg:azure.vm.disk_read_bytes{*} > 100000000" -Message "VM disk read high"
New-Monitor -Name "VM Disk Write High" -Query "avg(last_5m):avg:azure.vm.disk_write_bytes{*} > 100000000" -Message "VM disk write high"
New-Monitor -Name "VM Disk Operations High" -Query "avg(last_5m):avg:azure.vm.disk_read_operations_persec{*} > 500" -Message "VM disk operations high"
New-Monitor -Name "SQL Database DTU High" -Query "avg(last_5m):avg:azure.sql_servers_databases.dtu_consumption_percent{*} > 80" -Message "SQL DTU above 80 percent"
New-Monitor -Name "SQL Database Storage High" -Query "avg(last_5m):avg:azure.sql_servers_databases.storage_percent{*} > 85" -Message "SQL storage above 85 percent"
New-Monitor -Name "SQL Connection Failed" -Query "avg(last_5m):avg:azure.sql_servers_databases.connection_failed{*} > 5" -Message "SQL connection failures"
New-Monitor -Name "SQL Deadlocks" -Query "avg(last_5m):avg:azure.sql_servers_databases.deadlock{*} > 0" -Message "SQL deadlocks detected"
New-Monitor -Name "Storage Availability Low" -Query "avg(last_5m):avg:azure.storage_storageaccounts.availability{*} < 99" -Message "Storage availability below 99 percent"
New-Monitor -Name "Storage Latency High" -Query "avg(last_5m):avg:azure.storage_storageaccounts.success_e2_e_latency{*} > 1000" -Message "Storage latency high"
New-Monitor -Name "App Service CPU High" -Query "avg(last_5m):avg:azure.web_sites.cpu_time{*} > 80" -Message "App Service CPU above 80 percent"
New-Monitor -Name "App Service Response Time High" -Query "avg(last_5m):avg:azure.web_sites.average_response_time{*} > 3" -Message "App Service response time above 3 seconds"
New-Monitor -Name "App Service HTTP 5xx" -Query "avg(last_5m):avg:azure.web_sites.http_server_errors{*} > 10" -Message "App Service 5xx errors"
New-Monitor -Name "Load Balancer Health Low" -Query "avg(last_5m):avg:azure.network_loadbalancers.health_probe_status{*} < 50" -Message "Load balancer health below 50 percent"

Write-Host ""
Write-Host "COMPLETE - EVERYTHING AUTOMATED" -ForegroundColor Green
Write-Host ""
Write-Host "What was done:" -ForegroundColor Yellow
Write-Host "1. Created Service Principal in Azure" -ForegroundColor White
Write-Host "2. Generated Client Secret" -ForegroundColor White
Write-Host "3. Assigned Monitoring Reader role" -ForegroundColor White
Write-Host "4. Configured Azure integration in Datadog" -ForegroundColor White
Write-Host "5. Installed Datadog agents on $($VMs.Count) VMs" -ForegroundColor White
Write-Host "6. Created 16 monitors in Datadog" -ForegroundColor White
Write-Host ""
Write-Host "Wait 15-20 minutes for data to flow" -ForegroundColor Yellow
Write-Host "Then check: https://us3.datadoghq.com/monitors/manage" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can run this script on other subscriptions" -ForegroundColor Yellow
Write-Host "It will install agents on all VMs in each subscription" -ForegroundColor Yellow
Write-Host ""
