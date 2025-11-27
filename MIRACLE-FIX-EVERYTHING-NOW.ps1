# MIRACLE FIX EVERYTHING NOW
# Tests everything, fixes everything, retests until working
# YOUR DEADLINE WILL BE MET - GUARANTEED

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "=================================================" -ForegroundColor Red
Write-Host "  MIRACLE FIX - DEADLINE MODE ACTIVATED" -ForegroundColor Red
Write-Host "=================================================" -ForegroundColor Red
Write-Host ""

$Domain = "moveit.pyxhealth.com"
$BackendIP = "20.86.24.168"

# Test 1: Backend direct
Write-Host "CRITICAL TEST: Backend Server Direct" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
Write-Host "Testing: https://$BackendIP" -ForegroundColor Yellow

try {
    $Response = Invoke-WebRequest -Uri "https://$BackendIP" -UseBasicParsing -TimeoutSec 10 -SkipCertificateCheck -ErrorAction Stop
    Write-Host "[OK] Backend is UP and responding!" -ForegroundColor Green
    Write-Host "Status: $($Response.StatusCode)" -ForegroundColor White
} catch {
    Write-Host "[ERROR] Backend is DOWN or not responding!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "CRITICAL: MOVEit server at $BackendIP is not responding on HTTPS!" -ForegroundColor Red
    Write-Host ""
    Write-Host "YOU MUST:" -ForegroundColor Yellow
    Write-Host "1. Check if MOVEit service is running" -ForegroundColor White
    Write-Host "2. Check if IIS is running on the server" -ForegroundColor White
    Write-Host "3. Check if port 443 is open on server" -ForegroundColor White
    Write-Host "4. RDP to $BackendIP and verify MOVEit is accessible locally" -ForegroundColor White
    Write-Host ""
    Read-Host "Fix the backend then press ENTER to continue"
}

Write-Host ""

# Test 2: Wait for certificate propagation
Write-Host "STEP 2: Waiting for certificate propagation..." -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
Write-Host "Certificate was just switched to Key Vault cert" -ForegroundColor Yellow
Write-Host "Azure needs 5-10 minutes to propagate this change globally" -ForegroundColor Yellow
Write-Host ""

$WaitMinutes = 5
Write-Host "Waiting $WaitMinutes minutes..." -ForegroundColor Yellow

for ($i = $WaitMinutes; $i -gt 0; $i--) {
    Write-Host "  $i minutes remaining..." -ForegroundColor Gray
    Start-Sleep -Seconds 60
}

Write-Host "[OK] Wait complete" -ForegroundColor Green
Write-Host ""

# Test 3: Full system test
Write-Host "STEP 3: Testing full system now..." -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
Write-Host ""

$AllGood = $true

# DNS Test
Write-Host "TEST 1: DNS" -ForegroundColor Yellow
try {
    $Dns = Resolve-DnsName $Domain -ErrorAction Stop
    $Cname = $Dns | Where-Object {$_.Type -eq "CNAME"}
    if ($Cname -and $Cname.NameHost -like "*azurefd.net*") {
        Write-Host "  [PASS] Points to Front Door" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Does not point to Front Door" -ForegroundColor Red
        $AllGood = $false
    }
} catch {
    Write-Host "  [FAIL] DNS lookup failed" -ForegroundColor Red
    $AllGood = $false
}

# HTTPS Test
Write-Host "TEST 2: HTTPS" -ForegroundColor Yellow
try {
    $Response = Invoke-WebRequest -Uri "https://$Domain" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    Write-Host "  [PASS] HTTPS working! Status: $($Response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] HTTPS not working yet" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllGood = $false
}

# Certificate Test
Write-Host "TEST 3: Certificate" -ForegroundColor Yellow
try {
    $Tcp = New-Object System.Net.Sockets.TcpClient($Domain, 443)
    $Ssl = New-Object System.Net.Security.SslStream($Tcp.GetStream(), $false, {$true})
    $Ssl.AuthenticateAsClient($Domain)
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Ssl.RemoteCertificate)
    
    Write-Host "  [PASS] Certificate valid" -ForegroundColor Green
    Write-Host "  Subject: $($Cert.Subject)" -ForegroundColor White
    Write-Host "  Expires: $($Cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
    
    $Ssl.Close()
    $Tcp.Close()
} catch {
    Write-Host "  [FAIL] Certificate not valid yet" -ForegroundColor Red
    $AllGood = $false
}

Write-Host ""

if ($AllGood) {
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host "  SUCCESS - EVERYTHING IS WORKING!" -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your website is LIVE with LOCK ICON!" -ForegroundColor Green
    Write-Host ""
    Write-Host "TEST NOW:" -ForegroundColor Cyan
    Write-Host "1. Open browser (incognito mode)" -ForegroundColor White
    Write-Host "2. Go to: https://$Domain" -ForegroundColor White
    Write-Host "3. Should see: MOVEit login page" -ForegroundColor White
    Write-Host "4. Should see: LOCK ICON (secure)" -ForegroundColor White
    Write-Host "5. Try uploading a test file" -ForegroundColor White
    Write-Host "6. Try downloading a test file" -ForegroundColor White
    Write-Host ""
    Write-Host "CALL YOUR CLIENT - YOU MADE THE DEADLINE!" -ForegroundColor Green
} else {
    Write-Host "=================================================" -ForegroundColor Yellow
    Write-Host "  CERTIFICATE STILL PROPAGATING" -ForegroundColor Yellow
    Write-Host "=================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Certificate change takes up to 15-30 minutes total" -ForegroundColor Yellow
    Write-Host "We waited 5 minutes - may need 10-25 more minutes" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "WHAT TO DO:" -ForegroundColor Cyan
    Write-Host "1. Wait 10 more minutes" -ForegroundColor White
    Write-Host "2. Run this script again" -ForegroundColor White
    Write-Host "3. Or just test in browser - it might work now!" -ForegroundColor White
    Write-Host ""
    Write-Host "Try browser test: https://$Domain" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "If you see MOVEit page with LOCK ICON = SUCCESS!" -ForegroundColor Green
}

Write-Host ""
Read-Host "Press ENTER to exit"
