$DD_API_KEY = "YOUR_API_KEY_HERE"
$DD_APP_KEY = "YOUR_APP_KEY_HERE"

Write-Host "ACCOUNT DIAGNOSTIC" -ForegroundColor Cyan
Write-Host ""

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
}

Write-Host "Checking your Datadog account..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Test 1: Can we access the API?" -ForegroundColor Yellow
try {
    $validate = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/validate" -Method Get -Headers $headers
    Write-Host "SUCCESS - API is accessible" -ForegroundColor Green
    Write-Host "Valid: $($validate.valid)" -ForegroundColor Green
} catch {
    Write-Host "FAILED - Cannot access API" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Test 2: What metrics exist in your account?" -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/metrics" -Method Get -Headers $headers
    
    Write-Host "Total metrics in account: $($response.metrics.Count)" -ForegroundColor Green
    Write-Host ""
    
    if ($response.metrics.Count -eq 0) {
        Write-Host "WARNING: NO METRICS IN YOUR ACCOUNT!" -ForegroundColor Red
        Write-Host "This might be a brand new account or trial account" -ForegroundColor Yellow
        Write-Host "Try installing Datadog Agent on a VM first to get some baseline metrics" -ForegroundColor Yellow
    } else {
        Write-Host "First 20 metrics:" -ForegroundColor White
        $response.metrics | Select-Object -First 20 | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "Searching for any 'test' or 'databricks' metrics:" -ForegroundColor Yellow
        $found = $false
        foreach ($metric in $response.metrics) {
            if ($metric -like "*test*" -or $metric -like "*databricks*" -or $metric -like "*dbx*") {
                Write-Host "  - $metric" -ForegroundColor Cyan
                $found = $true
            }
        }
        
        if (-not $found) {
            Write-Host "  None found" -ForegroundColor Gray
        }
    }
    
} catch {
    Write-Host "FAILED - Cannot list metrics" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    if ($_.Exception.Response.StatusCode.value__ -eq 403) {
        Write-Host ""
        Write-Host "403 Error = Application Key is wrong or missing permissions" -ForegroundColor Yellow
        Write-Host "Go to Datadog > Organization Settings > Application Keys" -ForegroundColor Yellow
        Write-Host "Create a new Application Key (NOT API Key)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Test 3: Can we query any existing metric?" -ForegroundColor Yellow

$now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$from = $now - 3600
$to = $now

try {
    $queryUrl = "https://api.us3.datadoghq.com/api/v1/query?from=$from&to=$to&query=avg:system.cpu.user{*}"
    $response = Invoke-RestMethod -Uri $queryUrl -Method Get -Headers $headers
    
    if ($response.series -and $response.series.Count -gt 0) {
        Write-Host "SUCCESS - Can query system.cpu.user" -ForegroundColor Green
        Write-Host "This proves your account can display metrics!" -ForegroundColor Green
    } else {
        Write-Host "No data for system.cpu.user" -ForegroundColor Yellow
        Write-Host "You might not have any hosts with Datadog Agent installed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Cannot query system.cpu.user" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
