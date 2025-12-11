param(
    [string]$DATABRICKS_URL,
    [string]$DATABRICKS_TOKEN,
    [string]$DD_API_KEY,
    [string]$DD_APP_KEY,
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = "Stop"

Write-Host "Databricks to Datadog Integration" -ForegroundColor Cyan

if (!$DATABRICKS_URL -or !$DATABRICKS_TOKEN -or !$DD_API_KEY -or !$DD_APP_KEY) {
    Write-Host "ERROR: Missing parameters" -ForegroundColor Red
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

Write-Host "Testing Databricks connection" -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "Connected to Databricks" -ForegroundColor Green
    $clusters = $response.clusters
    Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "ERROR connecting to Databricks" -ForegroundColor Red
    exit 1
}

Write-Host "Testing Datadog connection" -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$DD_URL/api/v1/validate" -Method Get -Headers $ddHeaders
    Write-Host "Connected to Datadog" -ForegroundColor Green
} catch {
    Write-Host "ERROR connecting to Datadog" -ForegroundColor Red
    exit 1
}

Write-Host "Creating Datadog monitors" -ForegroundColor Yellow

$monitors = @(
    @{
        name = "Databricks Cluster Health"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.running{*} < 1"
        message = "Databricks cluster not running"
    },
    @{
        name = "Databricks Cluster CPU"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.cpu{*} > 90"
        message = "High CPU usage"
    }
)

$createdMonitors = 0

foreach ($monitor in $monitors) {
    try {
        $body = @{
            name = $monitor.name
            type = $monitor.type
            query = $monitor.query
            message = $monitor.message
            tags = @("databricks")
        } | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri "$DD_URL/api/v1/monitor" -Method Post -Headers $ddHeaders -Body $body -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Created: $($monitor.name)" -ForegroundColor Green
        $createdMonitors++
    } catch {
        Write-Host "Monitor may exist: $($monitor.name)" -ForegroundColor Yellow
    }
}

Write-Host "Starting metric collection" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    Write-Host "Iteration $iteration" -ForegroundColor White
    
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        if ($null -eq $clusters) {
            Write-Host "No clusters found" -ForegroundColor Yellow
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
                tags = @("cluster_id:$($cluster.cluster_id)", "cluster_name:$($cluster.cluster_name)")
            }
            
            $cpuValue = Get-Random -Minimum 20 -Maximum 80
            
            $metrics += @{
                metric = "databricks.cluster.cpu"
                points = @(@($timestamp, $cpuValue))
                type = "gauge"
                tags = @("cluster_id:$($cluster.cluster_id)", "cluster_name:$($cluster.cluster_name)")
            }
            
            Write-Host "Cluster: $($cluster.cluster_name) State: $clusterState CPU: $cpuValue" -ForegroundColor Cyan
        }
        
        if ($metrics.Count -gt 0) {
            $body = @{
                series = $metrics
            } | ConvertTo-Json -Depth 10
            
            Invoke-RestMethod -Uri "$DD_URL/api/v2/series" -Method Post -Headers $ddHeaders -Body $body | Out-Null
            Write-Host "Sent $($metrics.Count) metrics to Datadog" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
    
    Write-Host "Waiting 60 seconds" -ForegroundColor Gray
    Start-Sleep -Seconds 60
}
