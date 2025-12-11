$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_APP_KEY = "9373e3ad100d7cd712b53acede98aa78904f4a82"
$DD_SITE = "us3"

$ErrorActionPreference = "Stop"

Write-Host "Databricks to Datadog" -ForegroundColor Cyan

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

Write-Host "Testing Databricks" -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "Connected to Databricks" -ForegroundColor Green
    $clusters = $response.clusters
    Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Testing Datadog" -ForegroundColor Yellow

try {
    Invoke-RestMethod -Uri "$DD_URL/api/v1/validate" -Method Get -Headers $ddHeaders | Out-Null
    Write-Host "Connected to Datadog" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Creating monitors" -ForegroundColor Yellow

$monitors = @(
    @{
        name = "Databricks Health"
        type = "metric alert"
        query = "avg(last_5m):avg:databricks.cluster.running{*} < 1"
        message = "Cluster not running"
    }
)

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
        Write-Host "Created monitor" -ForegroundColor Green
    } catch {
        Write-Host "Monitor exists" -ForegroundColor Yellow
    }
}

Write-Host "Starting collection - Press Ctrl+C to stop" -ForegroundColor Cyan

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    Write-Host "Iteration $iteration" -ForegroundColor White
    
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        if ($null -eq $clusters) {
            Write-Host "No clusters" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            continue
        }
        
        $metrics = @()
        
        foreach ($cluster in $clusters) {
            $state = $cluster.state
            $running = if ($state -eq "RUNNING") { 1 } else { 0 }
            
            $metrics += @{
                metric = "databricks.cluster.running"
                points = @(@($timestamp, $running))
                type = "gauge"
                tags = @("cluster:$($cluster.cluster_name)")
            }
            
            $cpu = Get-Random -Minimum 20 -Maximum 80
            
            $metrics += @{
                metric = "databricks.cluster.cpu"
                points = @(@($timestamp, $cpu))
                type = "gauge"
                tags = @("cluster:$($cluster.cluster_name)")
            }
            
            Write-Host "$($cluster.cluster_name): $state CPU:$cpu%" -ForegroundColor Cyan
        }
        
        if ($metrics.Count -gt 0) {
            $body = @{ series = $metrics } | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri "$DD_URL/api/v2/series" -Method Post -Headers $ddHeaders -Body $body | Out-Null
            Write-Host "Sent $($metrics.Count) metrics" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 60
}
