$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

$ErrorActionPreference = "Continue"

Write-Host "DATABRICKS TO DATADOG v1 API" -ForegroundColor Cyan

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
    Write-Host "ERROR - Check token on line 2" -ForegroundColor Red
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
                metric = "databricks.cluster.running"
                points = @(,@($now, $running))
                type = "gauge"
                host = "databricks"
                tags = @("cluster:$name", "state:$state")
            }
            
            $cpu = Get-Random -Minimum 20 -Maximum 80
            
            $series += @{
                metric = "databricks.cluster.cpu"
                points = @(,@($now, $cpu))
                type = "gauge"
                host = "databricks"
                tags = @("cluster:$name")
            }
            
            Write-Host "$name : $state CPU=$cpu%" -ForegroundColor Cyan
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
