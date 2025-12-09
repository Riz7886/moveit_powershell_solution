param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc"
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "DELETE ALL AND CREATE NEW MONITORS" -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.us3.datadoghq.com/api/v1/monitor"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

Write-Host "Step 1: Getting all monitors..." -ForegroundColor Yellow

try {
    $allMonitors = Invoke-RestMethod -Uri $monitorUrl -Method Get -Headers $headers
    Write-Host "Found $($allMonitors.Count) monitors" -ForegroundColor Green
}
catch {
    Write-Host "Failed to get monitors: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Continuing anyway..." -ForegroundColor Yellow
    $allMonitors = @()
}

Write-Host ""
Write-Host "Step 2: Deleting monitors..." -ForegroundColor Yellow

$deletedCount = 0
$failedCount = 0

foreach ($monitor in $allMonitors) {
    try {
        $deleteUrl = "$monitorUrl/$($monitor.id)?force=true"
        Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers -ErrorAction Stop | Out-Null
        Write-Host "[DELETED] $($monitor.name)" -ForegroundColor Red
        $deletedCount++
        Start-Sleep -Milliseconds 100
    }
    catch {
        Write-Host "[FAILED] $($monitor.name) - $($_.Exception.Message)" -ForegroundColor Yellow
        $failedCount++
    }
}

Write-Host ""
Write-Host "Deleted: $deletedCount monitors" -ForegroundColor Green
Write-Host "Failed: $failedCount monitors" -ForegroundColor Yellow
Write-Host ""

Start-Sleep -Seconds 2

Write-Host "Step 3: Creating NEW monitors..." -ForegroundColor Yellow
Write-Host ""

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
        return $true
    }
    catch {
        Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$created = 0

if (New-Monitor -Name "CPU Usage High" -Query "avg(last_5m):100 - avg:system.cpu.idle{*} > 85" -Message "CPU usage above 85 percent") { $created++ }
if (New-Monitor -Name "System CPU High" -Query "avg(last_5m):avg:system.cpu.system{*} > 50" -Message "System CPU above 50 percent") { $created++ }
if (New-Monitor -Name "User CPU High" -Query "avg(last_5m):avg:system.cpu.user{*} > 70" -Message "User CPU above 70 percent") { $created++ }
if (New-Monitor -Name "Load Average High" -Query "avg(last_5m):avg:system.load.1{*} > 10" -Message "Load average above 10") { $created++ }
if (New-Monitor -Name "Memory Free Low" -Query "avg(last_5m):avg:system.mem.free{*} < 500000000" -Message "Free memory below 500MB") { $created++ }
if (New-Monitor -Name "Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.90" -Message "Disk usage above 90 percent") { $created++ }
if (New-Monitor -Name "Network Packets In High" -Query "avg(last_5m):avg:system.net.packets_in.count{*} > 100000" -Message "Network packets in high") { $created++ }
if (New-Monitor -Name "Network Packets Out High" -Query "avg(last_5m):avg:system.net.packets_out.count{*} > 100000" -Message "Network packets out high") { $created++ }
if (New-Monitor -Name "Process Count High" -Query "avg(last_5m):avg:system.processes.number{*} > 1000" -Message "Process count above 1000") { $created++ }
if (New-Monitor -Name "Swap Free Low" -Query "avg(last_5m):avg:system.swap.free{*} < 100000000" -Message "Swap space below 100MB") { $created++ }

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Deleted old monitors: $deletedCount" -ForegroundColor Red
Write-Host "Created new monitors: $created" -ForegroundColor Green
Write-Host ""
Write-Host "GO TO DATADOG NOW AND CHECK" -ForegroundColor Yellow
Write-Host "Monitors will show GREEN" -ForegroundColor Yellow
Write-Host ""
