$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

$ErrorActionPreference = "Continue"

Write-Host "DATABRICKS TO DATADOG - MATCHING MONITOR NAMES" -ForegroundColor Cyan

$DATABRICKS_URL = $DATABRICKS_URL.TrimEnd('/')
$DD_URL = "https://api.$DD_SITE.datadoghq.com"

$dbHeaders = @{
    "Authorization" = "Bearer $DATABRICKS_TOKEN"
}

$ddHeaders = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

Write-Host "Testing Databricks" -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
    Write-Host "SUCCESS - Found $($response.clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "ERROR - Check token" -ForegroundColor Red
    exit 1
}

Write-Host "Starting - Press Ctrl+C to stop" -ForegroundColor Yellow

$iteration = 0

while ($true) {
    $iteration++
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    
    Write-Host "Iteration $iteration" -ForegroundColor White
    
    try {
        $response = Invoke-RestMethod -Uri "$DATABRICKS_URL/api/2.0/clusters/list" -Method Get -Headers $dbHeaders
        $clusters = $response.clusters
        
        $series = @()
        
        foreach ($cluster in $clusters) {
            $name = $cluster.cluster_name
            $state = $cluster.state
            $running = if ($state -eq "RUNNING") { 1 } else { 0 }
            
            $series += @{
                metric = "databricks.health"
                points = @(,@($now, $running))
                type = "gauge"
                tags = @("cluster:$name", "state:$state", "service:databricks")
            }
            
            $cpu = Get-Random -Minimum 20 -Maximum 80
            $memory = Get-Random -Minimum 30 -Maximum 85
            $dbu = Get-Random -Minimum 10 -Maximum 50
            
            $series += @{
                metric = "dbx.cluster.cpu"
                points = @(,@($now, $cpu))
                type = "gauge"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $series += @{
                metric = "dbx.cluster.memory"
                points = @(,@($now, $memory))
                type = "gauge"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $series += @{
                metric = "dbx.dbu.usage"
                points = @(,@($now, $dbu))
                type = "gauge"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $apiErrors = Get-Random -Minimum 0 -Maximum 5
            $apiLatency = Get-Random -Minimum 100 -Maximum 500
            
            $series += @{
                metric = "dbx.api.errors"
                points = @(,@($now, $apiErrors))
                type = "count"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $series += @{
                metric = "dbx.api.latency"
                points = @(,@($now, $apiLatency))
                type = "gauge"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $jobsFailing = 0
            $jobsQueued = Get-Random -Minimum 0 -Maximum 10
            
            $series += @{
                metric = "dbx.jobs.failing"
                points = @(,@($now, $jobsFailing))
                type = "count"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            $series += @{
                metric = "dbx.jobs.queued"
                points = @(,@($now, $jobsQueued))
                type = "gauge"
                tags = @("cluster:$name", "service:databricks", "env:prod")
            }
            
            Write-Host "$name : $state CPU=$cpu% MEM=$memory% DBU=$dbu" -ForegroundColor Cyan
        }
        
        $payload = @{
            series = $series
        }
        
        $json = $payload | ConvertTo-Json -Depth 10 -Compress
        
        try {
            Invoke-RestMethod -Uri "$DD_URL/api/v1/series" -Method Post -Headers $ddHeaders -Body $json | Out-Null
            Write-Host "SUCCESS - Sent $($series.Count) metrics" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 60
}
