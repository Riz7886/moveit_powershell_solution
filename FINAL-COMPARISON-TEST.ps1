$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "FINAL DIAGNOSTIC - COMPARING FORMATS" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# First, let's see if you can see working metrics
Write-Host "STEP 1: Check if you can see working metrics in UI" -ForegroundColor Yellow
Write-Host ""
Write-Host "Go to Datadog > Metrics > Explorer right now" -ForegroundColor White
Write-Host "Search for: system.cpu.user" -ForegroundColor White
Write-Host ""
Write-Host "Do you see a graph with data? (y/n): " -ForegroundColor Yellow -NoNewline
$canSeeSystem = Read-Host

if ($canSeeSystem -ne "y") {
    Write-Host ""
    Write-Host "ERROR: If you can't see system.cpu.user, something is very wrong!" -ForegroundColor Red
    Write-Host "Check that you're logged into the correct Datadog organization!" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "STEP 2: Sending test metrics in EXACT same format as system metrics" -ForegroundColor Yellow
Write-Host ""

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

# Get current time in seconds (Unix timestamp)
$now = [int][double]::Parse((Get-Date -UFormat %s))

Write-Host "Current timestamp: $now" -ForegroundColor White
Write-Host "Current time: $(Get-Date)" -ForegroundColor White
Write-Host ""

# Format 1: Exactly like system metrics (with host)
Write-Host "Sending: mytest.cpu.percent (with host)" -ForegroundColor Cyan

$body1 = @"
{
  "series": [
    {
      "metric": "mytest.cpu.percent",
      "points": [[$now, 75.5]],
      "type": "gauge",
      "host": "testserver",
      "tags": ["env:production"]
    }
  ]
}
"@

try {
    $response1 = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body1
    Write-Host "Response: $($response1 | ConvertTo-Json)" -ForegroundColor Green
    Write-Host "SUCCESS - Sent mytest.cpu.percent" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Start-Sleep -Seconds 3

# Format 2: Simple format without host
Write-Host "Sending: simpletest (no host, no tags)" -ForegroundColor Cyan

$body2 = @"
{
  "series": [
    {
      "metric": "simpletest",
      "points": [[$now, 99]],
      "type": "gauge"
    }
  ]
}
"@

try {
    $response2 = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body2
    Write-Host "Response: $($response2 | ConvertTo-Json)" -ForegroundColor Green
    Write-Host "SUCCESS - Sent simpletest" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Start-Sleep -Seconds 3

# Format 3: With databricks in name (like your monitors want)
Write-Host "Sending: databricks.simple.test" -ForegroundColor Cyan

$body3 = @"
{
  "series": [
    {
      "metric": "databricks.simple.test",
      "points": [[$now, 123]],
      "type": "gauge",
      "tags": ["service:databricks"]
    }
  ]
}
"@

try {
    $response3 = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body3
    Write-Host "Response: $($response3 | ConvertTo-Json)" -ForegroundColor Green
    Write-Host "SUCCESS - Sent databricks.simple.test" -ForegroundColor Green
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "ALL METRICS SENT!" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "CRITICAL: Wait exactly 3 minutes, then do this:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Go to Datadog > Metrics > Explorer" -ForegroundColor White
Write-Host "2. Change time range to 'Past 1 Hour'" -ForegroundColor White
Write-Host "3. Search for each of these:" -ForegroundColor White
Write-Host "   - mytest.cpu.percent" -ForegroundColor Cyan
Write-Host "   - simpletest" -ForegroundColor Cyan
Write-Host "   - databricks.simple.test" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Tell me which ones show data (value):" -ForegroundColor White
Write-Host "   - mytest.cpu.percent should show 75.5" -ForegroundColor Gray
Write-Host "   - simpletest should show 99" -ForegroundColor Gray
Write-Host "   - databricks.simple.test should show 123" -ForegroundColor Gray
Write-Host ""
Write-Host "IF NONE OF THEM SHOW DATA:" -ForegroundColor Red
Write-Host "Your account CANNOT store custom metrics (trial restriction or config issue)" -ForegroundColor Red
Write-Host ""
Write-Host "IF SOME WORK BUT NOT OTHERS:" -ForegroundColor Yellow
Write-Host "We'll know exactly what format works and fix it!" -ForegroundColor Yellow
Write-Host ""
Write-Host "SET A 3 MINUTE TIMER NOW!" -ForegroundColor Cyan
