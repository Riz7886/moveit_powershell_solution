# CHECK BACKEND SERVER NOW
# Quick test to see if MOVEit server is responding

$BackendIP = "20.86.24.168"
$Port = 443

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  BACKEND SERVER CHECK" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Testing: $BackendIP on port $Port" -ForegroundColor Yellow
Write-Host ""

# TCP Test
Write-Host "1) TCP Connection Test..." -ForegroundColor Yellow
try {
    $Tcp = New-Object System.Net.Sockets.TcpClient
    $Tcp.Connect($BackendIP, $Port)
    Write-Host "   [PASS] Port $Port is open" -ForegroundColor Green
    $Tcp.Close()
} catch {
    Write-Host "   [FAIL] Cannot connect to port $Port" -ForegroundColor Red
    Write-Host "   Server may be down or firewall blocking" -ForegroundColor Red
}

Write-Host ""

# HTTPS Test
Write-Host "2) HTTPS Response Test..." -ForegroundColor Yellow
try {
    $Response = Invoke-WebRequest -Uri "https://$BackendIP" -UseBasicParsing -TimeoutSec 10 -SkipCertificateCheck
    Write-Host "   [PASS] Server responding on HTTPS" -ForegroundColor Green
    Write-Host "   Status Code: $($Response.StatusCode)" -ForegroundColor White
    
    if ($Response.Content -match "MOVEit") {
        Write-Host "   [PASS] MOVEit detected!" -ForegroundColor Green
    }
} catch {
    Write-Host "   [FAIL] Server not responding on HTTPS" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Press ENTER"
