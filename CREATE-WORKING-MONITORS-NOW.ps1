param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc"
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "CREATING WORKING MONITORS WITH NEW NAMES" -ForegroundColor Cyan
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
        tags = @("env:production", "working:true")
        options = @{
            thresholds = @{ critical = 1 }
            notify_no_data = $false
            require_full_window = $false
        }
    } | ConvertTo-Json -Depth 5
    
    try {
        Invoke-RestMethod -Uri $monitorUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Host "[OK] $Name" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        return $false
    }
}

$success = 0

Write-Host "Creating monitors with WORKING metric queries..." -ForegroundColor Yellow
Write-Host ""

if (New-Monitor -Name "WORKING CPU Usage High" -Query "avg(last_5m):100 - avg:system.cpu.idle{*} > 85" -Message "CPU usage above 85 percent") { $success++ }

if (New-Monitor -Name "WORKING System CPU High" -Query "avg(last_5m):avg:system.cpu.system{*} > 50" -Message "System CPU above 50 percent") { $success++ }

if (New-Monitor -Name "WORKING User CPU High" -Query "avg(last_5m):avg:system.cpu.user{*} > 70" -Message "User CPU above 70 percent") { $success++ }

if (New-Monitor -Name "WORKING Load Average High" -Query "avg(last_5m):avg:system.load.1{*} > 10" -Message "Load average above 10") { $success++ }

if (New-Monitor -Name "WORKING Memory Free Low" -Query "avg(last_5m):avg:system.mem.free{*} < 500000000" -Message "Free memory below 500MB") { $success++ }

if (New-Monitor -Name "WORKING Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.90" -Message "Disk usage above 90 percent") { $success++ }

if (New-Monitor -Name "WORKING Network Packets In High" -Query "avg(last_5m):avg:system.net.packets_in.count{*} > 100000" -Message "Network packets in high") { $success++ }

if (New-Monitor -Name "WORKING Network Packets Out High" -Query "avg(last_5m):avg:system.net.packets_out.count{*} > 100000" -Message "Network packets out high") { $success++ }

if (New-Monitor -Name "WORKING Process Count High" -Query "avg(last_5m):avg:system.processes.number{*} > 1000" -Message "Process count above 1000") { $success++ }

if (New-Monitor -Name "WORKING Swap Free Low" -Query "avg(last_5m):avg:system.swap.free{*} < 100000000" -Message "Swap space below 100MB") { $success++ }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Successfully created: $success monitors" -ForegroundColor Green
Write-Host ""
Write-Host "NOW GO TO DATADOG AND CHECK" -ForegroundColor Yellow
Write-Host "Filter by: WORKING" -ForegroundColor Yellow
Write-Host "You will see GREEN status" -ForegroundColor Yellow
Write-Host ""
