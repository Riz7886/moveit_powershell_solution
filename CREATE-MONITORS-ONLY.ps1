param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "77f25dd4921f21d5f3bbc8be779ffc94f5573d75",
    [string]$DD_SITE = "us3"
)

Write-Host ""
Write-Host "CREATING DATADOG MONITORS ONLY" -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/monitor"

Write-Host "API URL: $monitorUrl" -ForegroundColor Yellow
Write-Host ""

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

function Create-Monitor {
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
        options = @{
            thresholds = @{
                critical = 1
            }
            notify_no_data = $false
            require_full_window = $false
        }
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "  [SUCCESS] Monitor ID: $($response.id)" -ForegroundColor Green
        return $true
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        Write-Host "  [FAILED] Status: $statusCode" -ForegroundColor Red
        Write-Host "  Error: $errorBody" -ForegroundColor Red
        return $false
    }
}

Write-Host "Creating 3 monitors..." -ForegroundColor Cyan
Write-Host ""

$created = 0

if (Create-Monitor -Name "CPU Usage High" -Query "avg(last_5m):100 - avg:system.cpu.idle{*} by {host} > 85" -Message "CPU above 85%") {
    $created++
}

Write-Host ""

if (Create-Monitor -Name "Memory Available Low" -Query "avg(last_5m):avg:system.mem.usable{*} by {host} < 500000000" -Message "Memory below 500MB") {
    $created++
}

Write-Host ""

if (Create-Monitor -Name "Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} by {host,device} > 0.90" -Message "Disk above 90%") {
    $created++
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "RESULT: Created $created monitors" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""

if ($created -eq 3) {
    Write-Host "SUCCESS - Go check: https://$DD_SITE.datadoghq.com/monitors/manage" -ForegroundColor Green
} else {
    Write-Host "SOME FAILED - Check errors above" -ForegroundColor Yellow
}

Write-Host ""
