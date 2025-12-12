$DD_API_KEY = "PUT_YOUR_API_KEY"
$DD_APP_KEY = "PUT_YOUR_APP_KEY"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PAID ACCOUNT DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$headers_api = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

$headers_both = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

# TEST 1: Check account info
Write-Host "TEST 1: Checking account status..." -ForegroundColor Yellow

try {
    $usage = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/usage/summary?start_month=$(Get-Date -Format 'yyyy-MM')" -Method Get -Headers $headers_both
    Write-Host "SUCCESS - Account accessible" -ForegroundColor Green
    
    if ($usage.usage) {
        $customMetrics = $usage.usage | Where-Object { $_.hour } | Select-Object -First 1
        Write-Host "Custom metrics in use: Check your usage page" -ForegroundColor White
    }
} catch {
    Write-Host "WARNING - Cannot access usage API" -ForegroundColor Yellow
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# TEST 2: Send a test metric with verbose output
Write-Host "TEST 2: Sending test metric..." -ForegroundColor Yellow

$now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$testBody = @{
    series = @(
        @{
            metric = "test.paid.account"
            points = @(,@($now, 999))
            type = "gauge"
            host = "test-host"
            tags = @("environment:test")
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

Write-Host "Sending metric: test.paid.account with value 999" -ForegroundColor White
Write-Host "Timestamp: $now" -ForegroundColor White

try {
    $response = Invoke-WebRequest -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers_api -Body $testBody -UseBasicParsing
    Write-Host "HTTP Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response: $($response.Content)" -ForegroundColor Green
} catch {
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response Body: $responseBody" -ForegroundColor Red
    }
}

Write-Host ""

# TEST 3: Wait and try to query it back
Write-Host "TEST 3: Waiting 30 seconds then querying data back..." -ForegroundColor Yellow

for ($i = 30; $i -gt 0; $i--) {
    Write-Host "  $i seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 1
}

$from = $now - 600
$to = $now + 600

try {
    $queryUrl = "https://api.us3.datadoghq.com/api/v1/query?from=$from&to=$to&query=avg:test.paid.account{*}"
    $result = Invoke-RestMethod -Uri $queryUrl -Method Get -Headers $headers_both
    
    if ($result.series -and $result.series.Count -gt 0) {
        Write-Host "SUCCESS - Data was stored!" -ForegroundColor Green
        Write-Host "Found $($result.series[0].pointlist.Count) data points" -ForegroundColor Green
        Write-Host ""
        Write-Host "YOUR ACCOUNT CAN STORE CUSTOM METRICS!" -ForegroundColor Green
        Write-Host "The problem must be something else..." -ForegroundColor Yellow
    } else {
        Write-Host "PROBLEM - No data returned!" -ForegroundColor Red
        Write-Host "Datadog accepted the metric but isn't storing the data" -ForegroundColor Red
        Write-Host ""
        Write-Host "Response: $($result | ConvertTo-Json)" -ForegroundColor Red
    }
} catch {
    Write-Host "FAILED - Cannot query data" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# TEST 4: Check if metric appears in metrics list
Write-Host "TEST 4: Checking if metric appears in metrics list..." -ForegroundColor Yellow

try {
    $metrics = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/metrics" -Method Get -Headers $headers_both
    
    $found = $false
    foreach ($metric in $metrics.metrics) {
        if ($metric -like "*test.paid.account*") {
            Write-Host "FOUND: $metric" -ForegroundColor Green
            $found = $true
        }
    }
    
    if (-not $found) {
        Write-Host "NOT FOUND in metrics list" -ForegroundColor Red
    }
} catch {
    Write-Host "Cannot access metrics list" -ForegroundColor Red
}

Write-Host ""

# TEST 5: Send Databricks metric and check
Write-Host "TEST 5: Sending actual Databricks metric..." -ForegroundColor Yellow

$dbBody = @{
    series = @(
        @{
            metric = "custom.databricks.test.final"
            points = @(,@($now, 555))
            type = "gauge"
            tags = @("service:databricks", "env:prod")
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

try {
    $response = Invoke-WebRequest -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers_api -Body $dbBody -UseBasicParsing
    Write-Host "Sent custom.databricks.test.final - Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Failed to send" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now go to Datadog Metrics Explorer and search for:" -ForegroundColor Yellow
Write-Host "  1. test.paid.account" -ForegroundColor White
Write-Host "  2. custom.databricks.test.final" -ForegroundColor White
Write-Host ""
Write-Host "Wait 2-3 minutes then check if you see data!" -ForegroundColor Yellow
