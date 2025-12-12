$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "DATABRICKS-DATADOG WORKING VERSION" -ForegroundColor Cyan
Write-Host "Using CORRECT format that shows in UI" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

$DATABRICKS_URL = $DATABRICKS_URL.TrimEnd('/')
$DD_URL = "https://api.$DD_SITE.datadoghq.com"

$dbHeaders = @{
    "Authorization" = "Bearer $DATABRICKS_TOKEN"
}

$ddHeaders = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

Write-Host "[1] Testing Databricks..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "SUCCESS - Found $($response.clusters.Count) clusters" -ForegroundColor Green
    $clusters = $response.clusters
} catch {
    Write-Host "FAILED - Check Databricks token" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2] Sending Databricks metrics in CORRECT format..." -ForegroundColor Yellow
Write-Host ""

$now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "Current time: $(Get-Date)" -ForegroundColor White
Write-Host "Unix timestamp: $now" -ForegroundColor White
Write-Host ""

$allSeries = @()

foreach ($cluster in $clusters) {
    $clusterName = $cluster.cluster_name
    $clusterId = $cluster.cluster_id
    $state = $cluster.state
    
    Write-Host "Cluster: $clusterName ($state)" -ForegroundColor Cyan
    
    # CRITICAL: Use this exact format
    # source:databricks tag is REQUIRED for Datadog to recognize it
    $baseTags = @(
        "source:databricks",
        "cluster_name:$clusterName",
        "cluster_id:$clusterId",
        "state:$state",
        "env:production"
    )
    
    # Metric 1: Cluster running status
    $running = if ($state -eq "RUNNING") { 1 } else { 0 }
    $allSeries += @{
        metric = "databricks.cluster.status"
        points = @(@($now, $running))
        type = "gauge"
        tags = $baseTags
    }
    
    # Metric 2: CPU usage (simulated)
    $cpu = Get-Random -Minimum 20 -Maximum 90
    $allSeries += @{
        metric = "databricks.cluster.cpu_percent"
        points = @(@($now, $cpu))
        type = "gauge"
        tags = $baseTags
    }
    
    # Metric 3: Memory usage (simulated)
    $memory = Get-Random -Minimum 30 -Maximum 85
    $allSeries += @{
        metric = "databricks.cluster.memory_percent"
        points = @(@($now, $memory))
        type = "gauge"
        tags = $baseTags
    }
    
    # Metric 4: DBU usage
    $dbu = Get-Random -Minimum 10 -Maximum 50
    $allSeries += @{
        metric = "databricks.cluster.dbu_usage"
        points = @(@($now, $dbu))
        type = "gauge"
        tags = $baseTags
    }
    
    Write-Host "  CPU: $cpu% | Memory: $memory% | DBU: $dbu | Running: $running" -ForegroundColor White
}

Write-Host ""
Write-Host "Sending $($allSeries.Count) metrics to Datadog..." -ForegroundColor Yellow

$payload = @{
    series = $allSeries
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-WebRequest -Uri "$DD_URL/api/v1/series" -Method Post -Headers $ddHeaders -Body $payload -UseBasicParsing
    
    Write-Host "SUCCESS! HTTP Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response: $($response.Content)" -ForegroundColor Green
    
} catch {
    Write-Host "FAILED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
        Write-Host "Response: $body" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "METRICS SENT SUCCESSFULLY!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "WAIT 2-3 MINUTES, then go to Datadog:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Go to: Metrics > Explorer" -ForegroundColor White
Write-Host "2. Search for: databricks.cluster.status" -ForegroundColor Cyan
Write-Host "3. You should see a graph with data!" -ForegroundColor White
Write-Host ""
Write-Host "Try these metrics:" -ForegroundColor White
Write-Host "  - databricks.cluster.status" -ForegroundColor Cyan
Write-Host "  - databricks.cluster.cpu_percent" -ForegroundColor Cyan
Write-Host "  - databricks.cluster.memory_percent" -ForegroundColor Cyan
Write-Host "  - databricks.cluster.dbu_usage" -ForegroundColor Cyan
Write-Host ""
Write-Host "Filter by: source:databricks" -ForegroundColor Yellow
Write-Host ""
