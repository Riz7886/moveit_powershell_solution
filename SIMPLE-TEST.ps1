$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"
$DD_SITE = "us3"

Write-Host "SIMPLE TEST - Sending 1 metric" -ForegroundColor Cyan

$DD_URL = "https://api.$DD_SITE.datadoghq.com"

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

$now = [int][double]::Parse((Get-Date -UFormat %s))

Write-Host "Timestamp: $now" -ForegroundColor White
Write-Host "Current time: $(Get-Date)" -ForegroundColor White

$body = @"
{
    "series": [
        {
            "metric": "simple.test.metric",
            "points": [[$now, 100]],
            "type": "gauge",
            "tags": ["test:simple"]
        }
    ]
}
"@

Write-Host "Sending to: $DD_URL/api/v1/series" -ForegroundColor Yellow
Write-Host "Body: $body" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod -Uri "$DD_URL/api/v1/series" -Method Post -Headers $headers -Body $body
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Wait 2 minutes, then search in Datadog for: simple.test.metric" -ForegroundColor Yellow
} catch {
    Write-Host "FAILED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}
