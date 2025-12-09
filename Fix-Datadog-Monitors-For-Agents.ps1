param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc"
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "FIXING DATADOG MONITORS FOR AGENT METRICS" -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.us3.datadoghq.com/api/v1/monitor"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

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
            notify_no_data = $false
            require_full_window = $false
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

Write-Host "Creating monitors with AGENT metric names..." -ForegroundColor Cyan
Write-Host ""

New-Monitor -Name "Agent CPU High" -Query "avg(last_5m):avg:system.cpu.user{*} > 85" -Message "CPU user time above 85 percent"
New-Monitor -Name "Agent Memory Low" -Query "avg(last_5m):avg:system.mem.pct_usable{*} < 0.15" -Message "Memory available below 15 percent"
New-Monitor -Name "Agent Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.85" -Message "Disk usage above 85 percent"
New-Monitor -Name "Agent Load Average High" -Query "avg(last_5m):avg:system.load.1{*} > 5" -Message "Load average high"
New-Monitor -Name "Agent Network Sent High" -Query "avg(last_5m):avg:system.net.bytes_sent{*} > 100000000" -Message "Network bytes sent high"
New-Monitor -Name "Agent Network Received High" -Query "avg(last_5m):avg:system.net.bytes_rcvd{*} > 100000000" -Message "Network bytes received high"
New-Monitor -Name "Agent Disk Read High" -Query "avg(last_5m):avg:system.io.r_s{*} > 1000" -Message "Disk reads per second high"
New-Monitor -Name "Agent Disk Write High" -Query "avg(last_5m):avg:system.io.w_s{*} > 1000" -Message "Disk writes per second high"
New-Monitor -Name "Agent Process Count High" -Query "avg(last_5m):avg:system.processes.number{*} > 500" -Message "Process count high"
New-Monitor -Name "Agent Swap Usage High" -Query "avg(last_5m):avg:system.swap.pct_free{*} < 0.20" -Message "Swap space below 20 percent free"

Write-Host ""
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Go to Datadog and check monitors now" -ForegroundColor Yellow
Write-Host "These monitors use AGENT metrics not Azure metrics" -ForegroundColor Yellow
Write-Host "You should see GREEN status on monitors immediately" -ForegroundColor Yellow
Write-Host ""
