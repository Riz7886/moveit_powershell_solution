$DD_API_KEY = "YOUR_API_KEY_HERE"

Write-Host "DATADOG EXACT FORMAT TEST" -ForegroundColor Cyan
Write-Host ""

$currentTime = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

Write-Host "Current Unix timestamp: $currentTime" -ForegroundColor White
Write-Host "Current time: $(Get-Date)" -ForegroundColor White
Write-Host ""

# EXACT format from Datadog docs
$jsonBody = @{
    series = @(
        @{
            metric = "working.test.metric"
            type = 0
            points = @(
                @{
                    timestamp = $currentTime
                    value = 123.45
                }
            )
            resources = @(
                @{
                    name = "test-host"
                    type = "host"
                }
            )
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host "JSON Body:" -ForegroundColor Gray
Write-Host $jsonBody -ForegroundColor Gray
Write-Host ""

$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "Content-Type" = "application/json"
}

Write-Host "Sending to Datadog v2 API..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.us3.datadoghq.com/api/v2/series" `
        -Method Post `
        -Headers $headers `
        -Body $jsonBody `
        -Verbose
    
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "FAILED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response Body: $responseBody" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Now trying v1 API with simpler format..." -ForegroundColor Yellow

$v1Body = @{
    series = @(
        @{
            metric = "simple.working.test"
            points = @(
                @($currentTime, 777)
            )
            type = "gauge"
            host = "testhost"
            tags = @("env:test")
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

Write-Host "V1 JSON Body:" -ForegroundColor Gray
Write-Host $v1Body -ForegroundColor Gray
Write-Host ""

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.us3.datadoghq.com/api/v1/series" `
        -Method Post `
        -Headers $headers `
        -Body $v1Body `
        -Verbose
    
    Write-Host "V1 SUCCESS!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Green
} catch {
    Write-Host "V1 FAILED!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Wait 3 minutes then search for:" -ForegroundColor Yellow
Write-Host "  - working.test.metric" -ForegroundColor White
Write-Host "  - simple.working.test" -ForegroundColor White
Write-Host ""
Write-Host "In Datadog, make sure time range is: Past 1 Hour" -ForegroundColor Yellow
