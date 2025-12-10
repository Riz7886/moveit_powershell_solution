param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "PASTE_YOUR_NEW_APP_KEY_HERE",
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATADOG MONITOR CREATION SCRIPT" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DD_APP_KEY -eq "PASTE_YOUR_NEW_APP_KEY_HERE") {
    Write-Host "ERROR: Please replace PASTE_YOUR_NEW_APP_KEY_HERE with your actual Application Key" -ForegroundColor Red
    Write-Host ""
    Write-Host "Get your new key from: https://us3.datadoghq.com/organization-settings/application-keys" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  API Key: $($DD_API_KEY.Substring(0,8))..." -ForegroundColor Gray
Write-Host "  App Key: $($DD_APP_KEY.Substring(0,8))..." -ForegroundColor Gray
Write-Host "  Site: $DD_SITE.datadoghq.com" -ForegroundColor Gray
Write-Host ""

$monitorUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/monitor"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

Write-Host "Testing API connection..." -ForegroundColor Cyan
try {
    $testMonitors = Invoke-RestMethod -Uri $monitorUrl -Method Get -Headers $headers -ErrorAction Stop
    Write-Host "  [SUCCESS] Connected to Datadog - Found $($testMonitors.Count) existing monitors" -ForegroundColor Green
} catch {
    Write-Host "  [FAILED] Cannot connect to Datadog API" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check your Application Key has these permissions:" -ForegroundColor Yellow
    Write-Host "  - monitors_read" -ForegroundColor White
    Write-Host "  - monitors_write" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Creating monitors..." -ForegroundColor Cyan
Write-Host ""

function New-DatadogMonitor {
    param(
        [string]$Name,
        [string]$Query,
        [string]$Message
    )
    
    Write-Host "Creating: $Name" -ForegroundColor White
    
    $body = @{
        name = $Name
        type = "metric alert"
        query = $Query
        message = $Message
        tags = @("auto-created")
        options = @{
            notify_no_data = $false
            require_full_window = $false
            thresholds = @{
                critical = 1
            }
        }
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "  [OK] Monitor ID: $($response.id)" -ForegroundColor Green
        return $true
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 409) {
            Write-Host "  [EXISTS] Monitor already exists" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "  [FAIL] Status: $statusCode" -ForegroundColor Red
            if ($_.ErrorDetails.Message) {
                Write-Host "  Error: $($_.ErrorDetails.Message)" -ForegroundColor Red
            }
            return $false
        }
    }
}

$created = 0

# Monitor 1: CPU Usage High
if (New-DatadogMonitor -Name "CPU User Time High" `
    -Query "avg(last_5m):avg:system.cpu.user{*} > 70" `
    -Message "CPU user time above 70% on {{host.name}}") {
    $created++
}

Write-Host ""

# Monitor 2: Memory Free Low
if (New-DatadogMonitor -Name "Memory Free Low" `
    -Query "avg(last_5m):avg:system.mem.free{*} < 500000000" `
    -Message "Memory free below 500MB on {{host.name}}") {
    $created++
}

Write-Host ""

# Monitor 3: Disk Usage High
if (New-DatadogMonitor -Name "Disk Usage High" `
    -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.85" `
    -Message "Disk usage above 85% on {{host.name}}") {
    $created++
}

Write-Host ""

# Monitor 4: Load Average High
if (New-DatadogMonitor -Name "System Load High" `
    -Query "avg(last_5m):avg:system.load.1{*} > 8" `
    -Message "Load average above 8 on {{host.name}}") {
    $created++
}

Write-Host ""

# Monitor 5: System CPU High
if (New-DatadogMonitor -Name "System CPU Time High" `
    -Query "avg(last_5m):avg:system.cpu.system{*} > 40" `
    -Message "System CPU time above 40% on {{host.name}}") {
    $created++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully created/verified: $created monitors" -ForegroundColor Green
Write-Host ""
Write-Host "View monitors at: https://$DD_SITE.datadoghq.com/monitors/manage" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitors will show data in 5-10 minutes" -ForegroundColor Yellow
Write-Host ""
