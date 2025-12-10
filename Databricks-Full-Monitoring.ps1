
<#
Databricks Full Monitoring Automation for Datadog
Syed Enterprise Pack – v1.0
#>

param(
    [string]$DD_API_KEY = "",
    [string]$DD_APP_KEY = "",
    [string]$DD_SITE    = "us3"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "   DATABRICKS → DATADOG FULL MONITORING PACK" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$baseUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/monitor"
$headers = @{
    "DD-API-KEY"        = $DD_API_KEY
    "DD-APPLICATION-KEY"= $DD_APP_KEY
    "Content-Type"      = "application/json"
}

function New-DDMonitor {
    param(
        [string]$Name,
        [string]$Query,
        [string]$Message
    )

    $body = @{
        name    = $Name
        type    = "metric alert"
        query   = $Query
        message = $Message
        tags    = @("env:prod","service:databricks","hybrid:true")
        options = @{
            notify_no_data = $true
            no_data_timeframe = 10
        }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $baseUrl -Headers $headers -Method Post -Body $body | Out-Null
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] $Name → $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Creating Databricks Monitoring Pack…" -ForegroundColor Cyan

### CLUSTER METRICS
New-DDMonitor -Name "DBX Cluster CPU High" `
    -Query "avg(last_5m):avg:databricks.cluster.cpu_percent{*} > 85" `
    -Message "Cluster CPU above 85%"

New-DDMonitor -Name "DBX Cluster Memory High" `
    -Query "avg(last_5m):avg:databricks.cluster.memory_percent{*} > 85" `
    -Message "Cluster memory above 85%"

New-DDMonitor -Name "DBX Cluster DBU Spike" `
    -Query "avg(last_5m):avg:databricks.cluster.dbus{*} > 100" `
    -Message "High DBU usage"

### SQL WAREHOUSE METRICS
New-DDMonitor -Name "DBX SQL Warehouse Queries Failing" `
    -Query "sum(last_5m):sum:databricks.sql.query_failures{*} > 5" `
    -Message "SQL warehouse queries failing"

New-DDMonitor -Name "DBX SQL Warehouse Latency High" `
    -Query "avg(last_5m):avg:databricks.sql.execution_time{*} > 5000" `
    -Message "SQL warehouse execution latency > 5 seconds"

### JOBS METRICS
New-DDMonitor -Name "DBX Jobs Failing" `
    -Query "sum(last_5m):sum:databricks.jobs.failed_runs{*} > 1" `
    -Message "Databricks jobs are failing"

New-DDMonitor -Name "DBX Jobs Queued" `
    -Query "avg(last_5m):avg:databricks.jobs.queued{*} > 10" `
    -Message "Jobs are stuck in queue"

### NETWORK/API METRICS
New-DDMonitor -Name "DBX API 5xx Errors" `
    -Query "sum(last_5m):sum:databricks.api.errors_5xx{*} > 1" `
    -Message "Databricks API is returning 5xx"

New-DDMonitor -Name "DBX API Latency High" `
    -Query "avg(last_5m):avg:databricks.api.latency_ms{*} > 2000" `
    -Message "Databricks API latency > 2s"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "    DATABRICKS MONITORING PACK CREATED SUCCESSFULLY"
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
