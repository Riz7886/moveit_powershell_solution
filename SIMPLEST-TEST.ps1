$DD_API_KEY = "PUT_YOUR_API_KEY"

Write-Host "ABSOLUTE SIMPLEST TEST" -ForegroundColor Cyan
Write-Host ""

# Get current timestamp
$now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "Current timestamp: $now" -ForegroundColor White
Write-Host "Current time: $(Get-Date)" -ForegroundColor White
Write-Host ""

# Create the absolute simplest possible metric
$body = "{`"series`":[{`"metric`":`"test.simple.number`",`"points`":[[${now},42]],`"type`":`"gauge`"}]}"

Write-Host "Sending this exact JSON:" -ForegroundColor Yellow
Write-Host $body -ForegroundColor Gray
Write-Host ""

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Now wait 3 minutes and search in Datadog for: test.simple.number" -ForegroundColor Yellow
Write-Host ""
Write-Host "If this ALSO shows no data, then your Datadog account has custom metrics disabled!" -ForegroundColor Red
