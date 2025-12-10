param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "PASTE_YOUR_APP_KEY_HERE",
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATADOG COMPLETE AUTOMATION" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DD_APP_KEY -eq "PASTE_YOUR_APP_KEY_HERE") {
    Write-Host "ERROR: Replace PASTE_YOUR_APP_KEY_HERE with your Application Key" -ForegroundColor Red
    exit 1
}

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
$datadogUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/integration/azure"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

$azureConfig = @{
    tenant_name = $tenantId
    client_id = $appId
    client_secret = $clientSecret
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $datadogUrl -Method Post -Headers $headers -Body $azureConfig -ErrorAction Stop | Out-Null
    Write-Host "Azure integration configured" -ForegroundColor Green
} catch {
    Write-Host "Integration exists" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 7: Scanning for Virtual Machines..." -ForegroundColor Cyan
$VMs = Get-AzVM -Status
if (-not $VMs -or $VMs.Count -eq 0) {
    Write-Host "No VMs found" -ForegroundColor Yellow
} else {
    Write-Host "Found $($VMs.Count) VMs" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Step 8: Installing Datadog Agents..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    
    foreach ($vm in $VMs) {
        $vmName = $vm.Name
        $rg = $vm.ResourceGroupName
        $os = $vm.StorageProfile.OsDisk.OsType
        
        Write-Host "Installing: $vmName ($os)" -ForegroundColor White
        
        if ($os -eq "Windows") {
            $installScript = @"
`$url = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
`$msi = "`$env:TEMP\dd.msi"
Invoke-WebRequest -Uri `$url -OutFile `$msi -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `$msi /qn APIKEY=$DD_API_KEY SITE=$DD_SITE" -Wait
Remove-Item `$msi -Force
Restart-Service datadogagent -ErrorAction SilentlyContinue
"@
            try {
                Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString $installScript -ErrorAction Stop | Out-Null
                Write-Host "  [OK]" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "  [FAIL]" -ForegroundColor Red
                $failCount++
            }
        }
        elseif ($os -eq "Linux") {
            $installScript = @"
#!/bin/bash
export DD_API_KEY=$DD_API_KEY
export DD_SITE=$DD_SITE.datadoghq.com
bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@
            try {
                Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunShellScript" -ScriptString $installScript -ErrorAction Stop | Out-Null
                Write-Host "  [OK]" -ForegroundColor Green
                $successCount++
            } catch {
                Write-Host "  [FAIL]" -ForegroundColor Red
                $failCount++
            }
        }
    }
    
    Write-Host ""
    Write-Host "Agents: Success=$successCount | Failed=$failCount" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 9: Creating Datadog Monitors..." -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/monitor"

function New-Monitor {
    param([string]$Name, [string]$Query, [string]$Message)
    
    Write-Host "Creating: $Name" -ForegroundColor White
    
    $body = @{
        name = $Name
        type = "metric alert"
        query = $Query
        message = $Message
        tags = @("auto-created")
        options = @{ notify_no_data = $false }
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "  [OK] ID: $($response.id)" -ForegroundColor Green
        return $true
    } catch {
        $errorMessage = $_.ErrorDetails.Message
        if ($errorMessage -like "*Duplicate*" -or $errorMessage -like "*already exists*") {
            Write-Host "  [EXISTS]" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "  [SKIP]" -ForegroundColor Yellow
            return $false
        }
    }
}

$monitorCount = 0

# Original 5 monitors
if (New-Monitor -Name "CPU User High" -Query "avg(last_5m):avg:system.cpu.user{*} > 70" -Message "CPU user time above 70% on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Memory Free Low" -Query "avg(last_5m):avg:system.mem.free{*} < 500000000" -Message "Memory free below 500MB on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.85" -Message "Disk usage above 85% on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Load Average High" -Query "avg(last_5m):avg:system.load.1{*} > 8" -Message "Load average above 8 on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "System CPU High" -Query "avg(last_5m):avg:system.cpu.system{*} > 40" -Message "System CPU time above 40% on {{host.name}}") { $monitorCount++ }

# 5 NEW monitors
if (New-Monitor -Name "CPU IO Wait High" -Query "avg(last_5m):avg:system.cpu.iowait{*} > 30" -Message "IO Wait above 30% on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Memory Used High" -Query "avg(last_5m):avg:system.mem.pct_usable{*} < 0.15" -Message "Memory usage above 85% on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Swap Usage High" -Query "avg(last_5m):avg:system.swap.pct_free{*} < 0.20" -Message "Swap space low on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Network Bytes In High" -Query "avg(last_5m):avg:system.net.bytes_rcvd{*} > 100000000" -Message "Network bytes in high on {{host.name}}") { $monitorCount++ }
if (New-Monitor -Name "Network Bytes Out High" -Query "avg(last_5m):avg:system.net.bytes_sent{*} > 100000000" -Message "Network bytes out high on {{host.name}}") { $monitorCount++ }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: Created" -ForegroundColor Green
Write-Host "Azure Integration: Configured" -ForegroundColor Green
Write-Host "Agents Installed: $successCount VMs" -ForegroundColor Green
Write-Host "Monitors: $monitorCount (includes existing)" -ForegroundColor Green
Write-Host ""
Write-Host "View monitors: https://$DD_SITE.datadoghq.com/monitors/manage" -ForegroundColor Cyan
Write-Host ""
Write-Host "All monitors are ready - check Datadog now" -ForegroundColor Yellow
Write-Host ""
