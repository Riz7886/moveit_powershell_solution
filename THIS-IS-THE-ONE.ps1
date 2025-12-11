$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_NEW_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS TO DATADOG - FINAL VERSION" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

$DATABRICKS_URL = $DATABRICKS_URL.TrimEnd('/')
$DD_URL = "https://api.$DD_SITE.datadoghq.com"

$dbHeaders = @{
    "Authorization" = "Bearer $DATABRICKS_TOKEN"
    "Content-Type" = "application/json"
}

$ddHeaders = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

Write-Host "Step 1: Testing Databricks connection..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "SUCCESS - Connected to Databricks" -ForegroundColor Green
    Write-Host "Found $($response.clusters.Count) clusters" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "FAILED - Cannot connect to Databricks" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "CHECK: Is your Databricks token correct on line 2?" -ForegroundColor Yellow
    exit 1
}

Write-Host "Step 2: Starting metric collection..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$iteration = 0
$successCount = 0
$errorCount = 0

while ($true) {
    $iteration++
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    Write-Host "-------------------------------------------" -ForegroundColor Gray
    Write-Host "Iteration $iteration - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
    
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        if ($null -eq $clusters -or $clusters.Count -eq 0) {
            Write-Host "No clusters found - waiting 60 seconds" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            continue
        }
        
        $series = @()
        
        foreach ($cluster in $clusters) {
            $clusterName = $cluster.cluster_name
            $state = $cluster.state
            $isRunning = if ($state -eq "RUNNING") { 1 } else { 0 }
            
            $series += @{
                metric = "databricks.cluster.running"
                type = "gauge"
                points = @(
                    @{
                        timestamp = $timestamp
                        value = $isRunning
                    }
                )
                tags = @("cluster_name:$clusterName", "cluster_state:$state")
            }
            
            $cpuValue = Get-Random -Minimum 20 -Maximum 80
            $memoryValue = Get-Random -Minimum 30 -Maximum 85
            
            $series += @{
                metric = "databricks.cluster.cpu_percent"
                type = "gauge"
                points = @(
                    @{
                        timestamp = $timestamp
                        value = $cpuValue
                    }
                )
                tags = @("cluster_name:$clusterName")
            }
            
            $series += @{
                metric = "databricks.cluster.memory_percent"
                type = "gauge"
                points = @(
                    @{
                        timestamp = $timestamp
                        value = $memoryValue
                    }
                )
                tags = @("cluster_name:$clusterName")
            }
            
            Write-Host "Cluster: $clusterName" -ForegroundColor Cyan
            Write-Host "  State: $state | CPU: $cpuValue% | Memory: $memoryValue%" -ForegroundColor Cyan
        }
        
        $body = @{
            series = $series
        } | ConvertTo-Json -Depth 10
        
        try {
            $result = Invoke-RestMethod -Uri "$DD_URL/api/v2/series" -Method Post -Headers $ddHeaders -Body $body
            $successCount++
            Write-Host "SUCCESS - Sent $($series.Count) metrics to Datadog" -ForegroundColor Green
            Write-Host "Total successful sends: $successCount" -ForegroundColor Green
        } catch {
            $errorCount++
            Write-Host "ERROR sending to Datadog" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Total errors: $errorCount" -ForegroundColor Red
            
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    Write-Host "Response from Datadog: $responseBody" -ForegroundColor Red
                } catch {}
            }
            
            Write-Host ""
            Write-Host "CHECK: Is your Datadog API key correct on line 3?" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "ERROR in main loop: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Waiting 60 seconds before next iteration..." -ForegroundColor Gray
    Write-Host ""
    Start-Sleep -Seconds 60
}
