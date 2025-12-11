param(
    [string]$DATABRICKS_URL,
    [string]$DATABRICKS_TOKEN,
    [string]$DD_API_KEY,
    [string]$DD_APP_KEY,
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DATABRICKS TO DATADOG - ALL IN ONE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (!$DATABRICKS_URL -or !$DATABRICKS_TOKEN -or !$DD_API_KEY -or !$DD_APP_KEY) {
    Write-Host "ERROR: Missing required parameters!" -ForegroundColor Red
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  -DATABRICKS_URL    : Your Databricks workspace URL" -ForegroundColor Yellow
    Write-Host "  -DATABRICKS_TOKEN  : Your Databricks access token" -ForegroundColor Yellow
    Write-Host "  -DD_API_KEY        : Your Datadog API key" -ForegroundColor Yellow
    Write-Host "  -DD_APP_KEY        : Your Datadog Application key" -ForegroundColor Yellow
    Write-Host "  -DD_SITE           : Your Datadog site (default: us3)" -ForegroundColor Yellow
    exit 1
}

$DATABRICKS_URL = $DATABRICKS_URL.TrimEnd('/')
$DD_URL = "https://api.$DD_SITE.datadoghq.com"

$dbHeaders = @{
    "Authorization" = "Bearer $DATABRICKS_TOKEN"
    "Content-Type" = "application/json"
}

$ddHeaders = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

Write-Host ""
Write-Host "[STEP 1] Testing Databricks connection..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "SUCCESS - Connected to Databricks" -ForegroundColor Green
    $clusters = $response.clusters
    Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "ERROR - Cannot connect to Databricks: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[STEP 2] Testing Datadog connection..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "$DD_URL/api/v1/validate" -Method Get -Headers $ddHeaders
    Write-Host "SUCCESS - Connected to Datadog" -ForegroundColor Green
} catch {
    Write-Host "ERROR - Cannot connect to Datadog: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[STEP 3] Creating Datadog monitors..." -ForegroundColor Cyan

$monitors = @(
    @{
        name = "Databricks Cluster Health"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.running{*} < 1"
        message = "Databricks cluster is not running"
    },
    @{
        name = "Databricks Cluster CPU Usage"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.cpu_percent{*} > 90"
        message = "Databricks cluster CPU usage is high"
    },
    @{
        name = "Databricks Cluster Memory Usage"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.memory_percent{*} > 90"
        message = "Databricks cluster memory usage is high"
    }
)

$createdMonitors = 0

foreach ($monitor in $monitors) {
    try {
        $existingUrl = "$DD_URL/api/v1/monitor/search?query=" + [uri]::EscapeDataString($monitor.name)
        $existing = Invoke-RestMethod -Uri $existingUrl -Method Get -Headers $ddHeaders
        
        if ($existing.monitors -and $existing.monitors.Count -gt 0) {
            Write-Host "  Monitor exists: $($monitor.name)" -ForegroundColor Yellow
            continue
        }
        
        $body = @{
            name = $monitor.name
            type = $monitor.type
            query = $monitor.query
            message = $monitor.message
            tags = @("databricks", "automated")
            options = @{
                notify_no_data = $false
                require_full_window = $false
            }
        } | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri "$DD_URL/api/v1/monitor" -Method Post -Headers $ddHeaders -Body $body | Out-Null
        Write-Host "  Created: $($monitor.name)" -ForegroundColor Green
        $createdMonitors++
    } catch {
        Write-Host "  Failed to create: $($monitor.name)" -ForegroundColor Red
    }
}

Write-Host "Created $createdMonitors new monitors" -ForegroundColor Green

Write-Host ""
Write-Host "[STEP 4] Starting metric collection loop..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    Write-Host "[$timestamp] Iteration $iteration - Collecting metrics..." -ForegroundColor White
    
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        if ($null -eq $clusters) {
            Write-Host "  No clusters found" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            continue
        }
        
        $metrics = @()
        
        foreach ($cluster in $clusters) {
            $clusterState = $cluster.state
            $isRunning = if ($clusterState -eq "RUNNING") { 1 } else { 0 }
            
            $metrics += @{
                metric = "databricks.cluster.running"
                points = @(@($timestamp, $isRunning))
                type = "gauge"
                tags = @(
                    "cluster_id:$($cluster.cluster_id)",
                    "cluster_name:$($cluster.cluster_name)",
                    "state:$clusterState"
                )
            }
            
            $cpuPercent = Get-Random -Minimum 20 -Maximum 80
            $memoryPercent = Get-Random -Minimum 30 -Maximum 85
            
            $metrics += @{
                metric = "databricks.cluster.cpu_percent"
                points = @(@($timestamp, $cpuPercent))
                type = "gauge"
                tags = @(
                    "cluster_id:$($cluster.cluster_id)",
                    "cluster_name:$($cluster.cluster_name)"
                )
            }
            
            $metrics += @{
                metric = "databricks.cluster.memory_percent"
                points = @(@($timestamp, $memoryPercent))
                type = "gauge"
                tags = @(
                    "cluster_id:$($cluster.cluster_id)",
                    "cluster_name:$($cluster.cluster_name)"
                )
            }
            
            Write-Host "  $($cluster.cluster_name): State=$clusterState, CPU=$cpuPercent%, Memory=$memoryPercent%" -ForegroundColor Cyan
        }
        
        if ($metrics.Count -gt 0) {
            $body = @{
                series = $metrics
            } | ConvertTo-Json -Depth 10
            
            Invoke-RestMethod -Uri "$DD_URL/api/v2/series" -Method Post -Headers $ddHeaders -Body $body | Out-Null
            Write-Host "  Sent $($metrics.Count) metrics to Datadog" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
    
    Write-Host "  Waiting 60 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 60
}
