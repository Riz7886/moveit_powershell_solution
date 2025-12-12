$DD_API_KEY = "YOUR_API_KEY_HERE"

Write-Host "USING CURL TO SEND DATA" -ForegroundColor Cyan
Write-Host ""

$currentTime = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "Timestamp: $currentTime" -ForegroundColor White
Write-Host ""

# Create JSON file
$json = @"
{
  "series": [
    {
      "metric": "curl.test.metric",
      "points": [
        [$currentTime, 555]
      ],
      "type": "gauge",
      "host": "myhost",
      "tags": ["test:curl"]
    }
  ]
}
"@

$json | Out-File -FilePath "test-metric.json" -Encoding UTF8

Write-Host "Created test-metric.json" -ForegroundColor Green
Write-Host "Contents:" -ForegroundColor Gray
Write-Host $json -ForegroundColor Gray
Write-Host ""

Write-Host "Sending with curl..." -ForegroundColor Yellow

$curlCommand = "curl -X POST 'https://api.us3.datadoghq.com/api/v1/series' -H 'Content-Type: application/json' -H 'DD-API-KEY: $DD_API_KEY' -d '@test-metric.json'"

Write-Host "Command: $curlCommand" -ForegroundColor Gray
Write-Host ""

try {
    $result = Invoke-Expression $curlCommand
    Write-Host "Result: $result" -ForegroundColor Green
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Gray
Remove-Item "test-metric.json" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Wait 2 minutes then search for: curl.test.metric" -ForegroundColor Yellow
