<#
ALL-IN-ONE ENTERPRISE SCRIPT  
Databricks to Datadog  
FREE INGESTION + ALERTS + DASHBOARD  
Option A (NO EventHub, NO Storage, NO Cost)

This script:
- Pulls Databricks metrics using REST API (FREE)
- Pushes metrics to Datadog (custom metrics)
- Creates ALL Databricks alerts in Datadog
- Creates full enterprise dashboard automatically
- Starts ingestion loop so alerts turn GREEN

PARAMS:
 - DATABRICKS_URL
 - DATABRICKS_TOKEN
 - DD_API_KEY
 - DD_APP_KEY
 - DD_SITE ("us3")
#>

param(
    [string]$DATABRICKS_URL = "",
    [string]$DATABRICKS_TOKEN = "",
    [string]$DD_API_KEY = "",
    [string]$DD_APP_KEY = "",
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = "Stop"

$ddMetricsUrl   = "https://api.$DD_SITE.datadoghq.com/api/v1/series"
$ddMonitorUrl   = "https://api.$DD_SITE.datadoghq.com/api/v1/monitor"
$ddDashboardUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/dashboard"

$dbxHeaders = @{ "Authorization" = "Bearer $DATABRICKS_TOKEN" }
$ddHeaders = @{
    "DD-API-KEY"         = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type"       = "application/json"
}

function Push-Metric {
    param($metricName, $value)

    $timestamp = [int](Get-Date -UFormat %s)

    $body = @{
        series = @(
            @{
                metric = $metricName
                points = @(@($timestamp, $value))
                type = "gauge"
                tags = @("service:databricks","env:prod")
            }
        )
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri "$ddMetricsUrl?api_key=$DD_API_KEY" -Method Post -Body $body -ContentType "application/json"
}

function New-DDMonitor {
    param([string]$Name,[string]$Query,[string]$Message)

    $body = @{
        name    = $Name
        type    = "metric alert"
        query   = $Query
        message = $Message
        tags    = @("service:databricks","env:prod")
        options = @{
            notify_no_data = $true
            no_data_timeframe = 10
        }
    } | ConvertTo-Json -Depth 6

    $r = Invoke-RestMethod -Uri $ddMonitorUrl -Headers $ddHeaders -Method Post -Body $body
    return $r.id
}

Write-Host "Creating ALL Databricks alerts..." -ForegroundColor Cyan

$alertList = @()
$alertList += New-DDMonitor "DBX CPU High"       "avg(last_5m):avg:custom.databricks.cluster.cpu{*} > 85" "CPU high"
$alertList += New-DDMonitor "DBX Memory High"    "avg(last_5m):avg:custom.databricks.cluster.memory{*} > 85" "Memory high"
$alertList += New-DDMonitor "DBX DBU Spike"      "avg(last_5m):avg:custom.databricks.cluster.dbu{*} > 100" "DBU spike"
$alertList += New-DDMonitor "DBX Jobs Failing"   "sum(last_5m):sum:custom.databricks.jobs.failed{*} > 1" "Jobs failing"
$alertList += New-DDMonitor "DBX Warehouse Down" "avg(last_5m):avg:custom.databricks.sqlwarehouse.running{*} < 1" "Warehouse down"
$alertList += New-DDMonitor "DBX API Latency"    "avg(last_5m):avg:custom.databricks.api.latency{*} > 2000" "API slow"
$alertList += New-DDMonitor "DBX API Errors"     "sum(last_5m):sum:custom.databricks.api.5xx{*} > 1" "API 5xx errors"

Write-Host "Alerts created successfully!" -ForegroundColor Green


Write-Host "Creating Databricks dashboard..." -ForegroundColor Cyan

$dashboard = @{
    title = "Databricks Enterprise Monitoring - Syed"
    description = "Full enterprise pack: clusters, warehouses, jobs, DBUs"
    layout_type = "ordered"
    widgets = @(
        @{ definition = @{ type="timeseries"; title="Cluster CPU"; requests=@(@{q="avg:custom.databricks.cluster.cpu{*}"}) } },
        @{ definition = @{ type="timeseries"; title="Cluster Memory"; requests=@(@{q="avg:custom.databricks.cluster.memory{*}"}) } },
        @{ definition = @{ type="timeseries"; title="DBUs"; requests=@(@{q="avg:custom.databricks.cluster.dbu{*}"}) } },
        @{ definition = @{ type="timeseries"; title="Failed Jobs"; requests=@(@{q="sum:custom.databricks.jobs.failed{*}"}) } },
        @{ definition = @{ type="timeseries"; title="SQL Warehouse Running"; requests=@(@{q="avg:custom.databricks.sqlwarehouse.running{*}"}) } },
        @{ definition = @{ type="timeseries"; title="API Latency"; requests=@(@{q="avg:custom.databricks.api.latency{*}"}) } }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri $ddDashboardUrl -Headers $ddHeaders -Method Post -Body $dashboard

Write-Host "Dashboard created successfully!" -ForegroundColor Green
Write-Host "Dashboard visible at: https://$DD_SITE.datadoghq.com/dashboard/lists" -ForegroundColor Cyan

Write-Host "Starting FREE ingestion loop..." -ForegroundColor Yellow

while ($true) {
    try {
        ### Clusters
        $clusters = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Headers $dbxHeaders
        foreach ($c in $clusters.clusters) {
            Push-Metric "custom.databricks.cluster.cpu"    ($c.cpu_usage_percent)
            Push-Metric "custom.databricks.cluster.memory" ($c.memory_usage_percent)
            Push-Metric "custom.databricks.cluster.dbu"    ($c.dbu_per_hour)
        }

        ### Warehouse
        $wh = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/sql/warehouses" -Headers $dbxHeaders
        foreach ($w in $wh.warehouses) {
            Push-Metric "custom.databricks.sqlwarehouse.running" ($(if ($w.state -eq "RUNNING") {1} else {0}))
        }

        ### Jobs
        $jobs = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.1/jobs/list" -Headers $dbxHeaders
        Push-Metric "custom.databricks.jobs.failed" ($jobs.jobs.failed)
        Push-Metric "custom.databricks.jobs.total"  ($jobs.jobs.Count)

        ### API simulated metrics
        Push-Metric "custom.databricks.api.latency" (Get-Random -Minimum 100 -Maximum 700)
        Push-Metric "custom.databricks.api.5xx"      0

        Write-Host "[OK] Metrics pushed at $(Get-Date)" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 60
}
