$DATABRICKS_URL = "https://adb-2758318924173706.6.azuredatabricks.net"
$DATABRICKS_TOKEN = "PUT_YOUR_TOKEN_HERE"
$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DATADOG CONNECTION DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing Datadog API connectivity..." -ForegroundColor Yellow
Write-Host ""

$DD_URL = "https://api.$DD_SITE.datadoghq.com"

Write-Host "API URL: $DD_URL" -ForegroundColor White
Write-Host "API Key: $($DD_API_KEY.Substring(0,10))..." -ForegroundColor White
Write-Host ""

$ddHeaders = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

Write-Host "Test 1: Validating API Key..." -ForegroundColor Yellow

try {
    $validateUrl = "$DD_URL/api/v1/validate"
    Write-Host "URL: $validateUrl" -ForegroundColor Gray
    
    $response = Invoke-RestMethod -Uri $validateUrl -Method Get -Headers $ddHeaders
    Write-Host "SUCCESS - API Key is valid!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "FAILED - API Key validation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        if ($statusCode -eq 403) {
            Write-Host ""
            Write-Host "403 = Wrong API key or expired!" -ForegroundColor Red
            Write-Host "Go to Datadog > Organization Settings > API Keys" -ForegroundColor Yellow
            Write-Host "Create a NEW API key and update line 3 of script" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

Write-Host "Test 2: Sending test metric..." -ForegroundColor Yellow

$now = [int][double]::Parse((Get-Date -UFormat %s))

$testMetric = @{
    series = @(
        @{
            metric = "test.databricks.connection"
            points = @(,@($now, 1))
            type = "gauge"
            tags = @("test:true")
        }
    )
}

$json = $testMetric | ConvertTo-Json -Depth 10

Write-Host "Metric JSON:" -ForegroundColor Gray
Write-Host $json -ForegroundColor Gray
Write-Host ""

try {
    $seriesUrl = "$DD_URL/api/v1/series"
    Write-Host "URL: $seriesUrl" -ForegroundColor Gray
    
    $response = Invoke-RestMethod -Uri $seriesUrl -Method Post -Headers $ddHeaders -Body $json
    Write-Host "SUCCESS - Test metric sent!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Go to Datadog > Metrics > Explorer" -ForegroundColor Yellow
    Write-Host "Search for: test.databricks.connection" -ForegroundColor Yellow
    Write-Host "You should see it in 2-3 minutes!" -ForegroundColor Yellow
    Write-Host ""
} catch {
    Write-Host "FAILED - Could not send metric" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response: $responseBody" -ForegroundColor Red
        } catch {}
    }
    Write-Host ""
}

Write-Host "Test 3: Checking Datadog site..." -ForegroundColor Yellow
Write-Host ""

$sites = @("us3", "datadoghq.com", "us5.datadoghq.com", "eu1.datadoghq.com")

Write-Host "Your current site: $DD_SITE" -ForegroundColor White
Write-Host ""
Write-Host "Testing all sites..." -ForegroundColor Gray

foreach ($site in $sites) {
    $testUrl = "https://api.$site.datadoghq.com/api/v1/validate"
    try {
        Invoke-RestMethod -Uri $testUrl -Method Get -Headers $ddHeaders -TimeoutSec 3 | Out-Null
        Write-Host "  $site - WORKS!" -ForegroundColor Green
    } catch {
        Write-Host "  $site - Failed" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
