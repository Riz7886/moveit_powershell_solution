$DD_API_KEY = "38ff811dd7d44e5387063786c3bd60e94"

Write-Host "ULTRA SIMPLE TEST" -ForegroundColor Cyan

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

$now = [int][double]::Parse((Get-Date -UFormat %s))

Write-Host "Sending to Datadog..." -ForegroundColor Yellow

for ($i = 1; $i -le 5; $i++) {
    Write-Host "Attempt $i..." -ForegroundColor White
    
    $body = @"
{
    "series": [
        {
            "metric": "my.simple.test",
            "points": [[$now, $i]],
            "type": "gauge"
        }
    ]
}
"@
    
    try {
        # Try us3
        $response = Invoke-RestMethod -Uri "https://api.us3.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body
        Write-Host "  us3 - SUCCESS!" -ForegroundColor Green
    } catch {
        Write-Host "  us3 - FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    try {
        # Try default
        $response = Invoke-RestMethod -Uri "https://api.datadoghq.com/api/v1/series" -Method Post -Headers $headers -Body $body
        Write-Host "  datadoghq.com - SUCCESS!" -ForegroundColor Green
    } catch {
        Write-Host "  datadoghq.com - FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 10
}

Write-Host ""
Write-Host "Done! Wait 3 minutes then search for: my.simple.test" -ForegroundColor Yellow
