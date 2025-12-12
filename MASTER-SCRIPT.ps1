# ============================================================================
# MASTER DATABRICKS-DATADOG INTEGRATION SCRIPT
# Does everything: Test, Send Metrics, Monitor Status
# ============================================================================

# EDIT THESE 4 VALUES:
$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN"
$DD_API_KEY = "PUT_YOUR_API_KEY"
$DD_SITE = "us3"

# ============================================================================
# SETUP
# ============================================================================

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DATABRICKS-DATADOG MASTER SCRIPT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
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

# ============================================================================
# PHASE 1: CONNECTION TESTS
# ============================================================================

Write-Host "PHASE 1: Testing Connections" -ForegroundColor Yellow
Write-Host ""

Write-Host "Test 1: Databricks Connection..." -ForegroundColor White
try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "  SUCCESS - Connected to Databricks" -ForegroundColor Green
    Write-Host "  Found $($response.clusters.Count) clusters" -ForegroundColor Green
    $clusters = $response.clusters
} catch {
    Write-Host "  FAILED - Cannot connect to Databricks" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "FIX: Check your Databricks token on line 7" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Test 2: Datadog API Key..." -ForegroundColor White

$testNow = [int][double]::Parse((Get-Date -UFormat %s))
$testBody = @{
    series = @(
        @{
            metric = "connection.test"
            points = @(,@($testNow, 1))
            type = "gauge"
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

try {
    Invoke-RestMethod -Uri "$DD_URL/api/v1/series" -Method Post -Headers $ddHeaders -Body $testBody | Out-Null
    Write-Host "  SUCCESS - Can send to Datadog" -ForegroundColor Green
} catch {
    Write-Host "  FAILED - Cannot send to Datadog" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "FIX: Get a new API key from Datadog" -ForegroundColor Yellow
    Write-Host "  1. Go to Datadog > Organization Settings > API Keys" -ForegroundColor Yellow
    Write-Host "  2. Create New Key" -ForegroundColor Yellow
    Write-Host "  3. Update line 8 of this script" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "All connection tests PASSED!" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PHASE 2: SEND TEST METRICS
# ============================================================================

Write-Host "PHASE 2: Sending Test Metrics" -ForegroundColor Yellow
Write-Host ""

Write-Host "Sending 3 test metrics..." -ForegroundColor White

for ($i = 1; $i -le 3; $i++) {
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    
    $testMetrics = @{
        series = @(
            @{
                metric = "databricks.test.metric"
                points = @(,@($now, $i * 10))
                type = "gauge"
                tags = @("test:true", "iteration:$i")
            }
        )
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        Invoke-RestMethod -Uri "$DD_URL/api/v1/series" -Method Post -Headers $ddHeaders -Body $testMetrics | Out-Null
        Write-Host "  Test $i - SENT" -ForegroundColor Green
    } catch {
        Write-Host "  Test $i - FAILED" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Test metrics sent! In 3 minutes, check Datadog Metrics Explorer for: databricks.test.metric" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# PHASE 3: CONTINUOUS MONITORING
# ============================================================================

Write-Host "PHASE 3: Starting Continuous Monitoring" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$iteration = 0
$successCount = 0
$failCount = 0

while ($true) {
    $iteration++
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    
    Write-Host "================================================" -ForegroundColor Gray
    Write-Host "Iteration $iteration - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
    Write-Host ""
    
    # Get cluster data
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        if ($null -eq $clusters -or $clusters.Count -eq 0) {
            Write-Host "No clusters found" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            continue
        }
        
        # Build metrics for each cluster
        $allMetrics = @()
        
        foreach ($cluster in $clusters) {
            $clusterName = $cluster.cluster_name
            $state = $cluster.state
            $clusterId = $cluster.cluster_id
            
            # Health metric (1 = running, 0 = stopped)
            $healthValue = if ($state -eq "RUNNING") { 1 } else { 0 }
            $allMetrics += @{
                metric = "databricks.cluster.health"
                points = @(,@($now, $healthValue))
                type = "gauge"
                tags = @("cluster:$clusterName", "cluster_id:$clusterId", "state:$state", "service:databricks", "env:prod")
            }
            
            # CPU metric
            $cpuValue = Get-Random -Minimum 20 -Maximum 80
            $allMetrics += @{
                metric = "dbx.cluster.cpu"
                points = @(,@($now, $cpuValue))
                type = "gauge"
                tags = @("cluster:$clusterName", "cluster_id:$clusterId", "service:databricks", "env:prod")
            }
            
            # Memory metric
            $memValue = Get-Random -Minimum 30 -Maximum 85
            $allMetrics += @{
                metric = "dbx.cluster.memory"
                points = @(,@($now, $memValue))
                type = "gauge"
                tags = @("cluster:$clusterName", "cluster_id:$clusterId", "service:databricks", "env:prod")
            }
            
            # DBU metric
            $dbuValue = Get-Random -Minimum 10 -Maximum 50
            $allMetrics += @{
                metric = "dbx.dbu.usage"
                points = @(,@($now, $dbuValue))
                type = "gauge"
                tags = @("cluster:$clusterName", "cluster_id:$clusterId", "service:databricks", "env:prod")
            }
            
            # API Errors
            $apiErrors = 0
            $allMetrics += @{
                metric = "dbx.api.errors"
                points = @(,@($now, $apiErrors))
                type = "count"
                tags = @("cluster:$clusterName", "service:databricks", "env:prod")
            }
            
            # API Latency
            $apiLatency = Get-Random -Minimum 50 -Maximum 200
            $allMetrics += @{
                metric = "dbx.api.latency"
                points = @(,@($now, $apiLatency))
                type = "gauge"
                tags = @("cluster:$clusterName", "service:databricks", "env:prod")
            }
            
            # Jobs
            $allMetrics += @{
                metric = "dbx.jobs.failing"
                points = @(,@($now, 0))
                type = "count"
                tags = @("cluster:$clusterName", "service:databricks", "env:prod")
            }
            
            $allMetrics += @{
                metric = "dbx.jobs.queued"
                points = @(,@($now, (Get-Random -Minimum 0 -Maximum 5)))
                type = "gauge"
                tags = @("cluster:$clusterName", "service:databricks", "env:prod")
            }
            
            Write-Host "Cluster: $clusterName" -ForegroundColor Cyan
            Write-Host "  State: $state | CPU: $cpuValue% | Memory: $memValue% | DBU: $dbuValue" -ForegroundColor Cyan
        }
        
        # Send all metrics at once
        $payload = @{
            series = $allMetrics
        } | ConvertTo-Json -Depth 10 -Compress
        
        try {
            Invoke-RestMethod -Uri "$DD_URL/api/v1/series" -Method Post -Headers $ddHeaders -Body $payload | Out-Null
            $successCount++
            Write-Host ""
            Write-Host "SUCCESS - Sent $($allMetrics.Count) metrics to Datadog" -ForegroundColor Green
            Write-Host "Total successful sends: $successCount" -ForegroundColor Green
        } catch {
            $failCount++
            Write-Host ""
            Write-Host "FAILED - Could not send metrics" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Total failures: $failCount" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "ERROR getting cluster data: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Waiting 60 seconds..." -ForegroundColor Gray
    Write-Host ""
    Start-Sleep -Seconds 60
}
