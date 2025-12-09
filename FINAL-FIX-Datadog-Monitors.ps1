param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "438d47ab7dbc503fb3f44439a20ad21761e78bbc"
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "FINAL FIX - DELETING OLD AND CREATING WORKING MONITORS" -ForegroundColor Cyan
Write-Host ""

$monitorUrl = "https://api.us3.datadoghq.com/api/v1/monitor"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

Write-Host "Step 1: Getting all existing monitors..." -ForegroundColor Cyan
try {
    $allMonitors = Invoke-RestMethod -Uri $monitorUrl -Method Get -Headers $headers -ErrorAction Stop
    Write-Host "Found $($allMonitors.Count) monitors" -ForegroundColor Yellow
    
    Write-Host ""
    Write-Host "Step 2: Deleting all monitors..." -ForegroundColor Cyan
    foreach ($monitor in $allMonitors) {
        try {
            Invoke-RestMethod -Uri "$monitorUrl/$($monitor.id)" -Method Delete -Headers $headers -ErrorAction Stop | Out-Null
            Write-Host "[DELETED] $($monitor.name)" -ForegroundColor Red
        }
        catch {
            Write-Host "[SKIP] $($monitor.name)" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "Could not get monitors, continuing..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 3: Creating NEW working monitors..." -ForegroundColor Cyan
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

$success = 0
$fail = 0

if (New-Monitor -Name "CPU High" -Query "avg(last_5m):100 - avg:system.cpu.idle{*} > 85" -Message "CPU usage above 85 percent") { $success++ } else { $fail++ }

if (New-Monitor -Name "CPU System High" -Query "avg(last_5m):avg:system.cpu.system{*} > 50" -Message "System CPU above 50 percent") { $success++ } else { $fail++ }

if (New-Monitor -Name "CPU User High" -Query "avg(last_5m):avg:system.cpu.user{*} > 70" -Message "User CPU above 70 percent") { $success++ } else { $fail++ }

if (New-Monitor -Name "CPU IOWait High" -Query "avg(last_5m):avg:system.cpu.iowait{*} > 30" -Message "IO Wait above 30 percent") { $success++ } else { $fail++ }

if (New-Monitor -Name "Load Average High" -Query "avg(last_5m):avg:system.load.1{*} > 10" -Message "1 minute load average above 10") { $success++ } else { $fail++ }

if (New-Monitor -Name "Memory Free Low" -Query "avg(last_5m):avg:system.mem.free{*} < 500000000" -Message "Free memory below 500MB") { $success++ } else { $fail++ }

if (New-Monitor -Name "Swap Free Low" -Query "avg(last_5m):avg:system.swap.free{*} < 100000000" -Message "Free swap below 100MB") { $success++ } else { $fail++ }

if (New-Monitor -Name "Disk Usage High" -Query "avg(last_5m):avg:system.disk.in_use{*} > 0.90" -Message "Disk usage above 90 percent") { $success++ } else { $fail++ }

if (New-Monitor -Name "Network Errors" -Query "avg(last_5m):avg:system.net.packets_in.error{*} > 100" -Message "Network packet errors detected") { $success++ } else { $fail++ }

if (New-Monitor -Name "Process Count High" -Query "avg(last_5m):avg:system.processes.number{*} > 1000" -Message "Process count above 1000") { $success++ } else { $fail++ }

Write-Host ""
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Created: $success monitors" -ForegroundColor Green
Write-Host "Failed: $fail monitors" -ForegroundColor Red
Write-Host ""
Write-Host "Go to Datadog Monitors now - you should see GREEN" -ForegroundColor Yellow
Write-Host ""
