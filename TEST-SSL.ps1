# SSL CERTIFICATE TEST SCRIPT
# Tests if MOVEit HTTPS is working

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SSL CERTIFICATE TEST - MOVEIT.PYXHEALTH.COM" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$domain = "moveit.pyxhealth.com"
$url = "https://$domain"

function Write-Test {
    param([string]$Test, [string]$Status, [string]$Color = "White")
    $padding = " " * (50 - $Test.Length)
    Write-Host "  $Test$padding" -NoNewline
    Write-Host "[$Status]" -ForegroundColor $Color
}

# TEST 1: DNS RESOLUTION
Write-Host "[TEST 1] DNS Resolution" -ForegroundColor Yellow
try {
    $dns = Resolve-DnsName $domain -ErrorAction Stop
    $ip = $dns[0].IPAddress
    Write-Test "DNS resolves to IP" "✓ PASS" "Green"
    Write-Host "    IP Address: $ip" -ForegroundColor Gray
} catch {
    Write-Test "DNS resolves to IP" "✗ FAIL" "Red"
    Write-Host "    Error: Cannot resolve domain" -ForegroundColor Red
    Write-Host ""
    Write-Host "FIX: Add DNS CNAME record pointing to Front Door" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# TEST 2: HTTPS CONNECTION
Write-Host "[TEST 2] HTTPS Connection" -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $statusCode = $response.StatusCode
    Write-Test "HTTPS responds" "✓ PASS" "Green"
    Write-Host "    Status Code: $statusCode" -ForegroundColor Gray
} catch {
    Write-Test "HTTPS responds" "✗ FAIL" "Red"
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Message -like "*SSL*" -or $_.Exception.Message -like "*certificate*") {
        Write-Host ""
        Write-Host "CERTIFICATE ISSUE DETECTED!" -ForegroundColor Red
        Write-Host "Certificate may still be provisioning. Wait 5 more minutes." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Trying alternative test..." -ForegroundColor Yellow
}

Write-Host ""

# TEST 3: SSL CERTIFICATE DETAILS
Write-Host "[TEST 3] SSL Certificate" -ForegroundColor Yellow
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($domain, 443)
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false)
    $sslStream.AuthenticateAsClient($domain)
    
    $cert = $sslStream.RemoteCertificate
    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
    
    Write-Test "Certificate found" "✓ PASS" "Green"
    Write-Host "    Subject: $($cert2.Subject)" -ForegroundColor Gray
    Write-Host "    Issuer: $($cert2.Issuer)" -ForegroundColor Gray
    Write-Host "    Valid From: $($cert2.NotBefore)" -ForegroundColor Gray
    Write-Host "    Valid Until: $($cert2.NotAfter)" -ForegroundColor Gray
    
    # Check if certificate is valid
    $now = Get-Date
    if ($now -gt $cert2.NotBefore -and $now -lt $cert2.NotAfter) {
        Write-Test "Certificate is valid" "✓ PASS" "Green"
    } else {
        Write-Test "Certificate is valid" "✗ FAIL" "Red"
        Write-Host "    Error: Certificate expired or not yet valid" -ForegroundColor Red
    }
    
    # Check if wildcard
    if ($cert2.Subject -like "*\*.pyxhealth.com*") {
        Write-Test "Wildcard certificate" "✓ YES" "Green"
        Write-Host "    Covers all *.pyxhealth.com subdomains" -ForegroundColor Gray
    }
    
    $sslStream.Close()
    $tcpClient.Close()
    
} catch {
    Write-Test "Certificate found" "✗ FAIL" "Red"
    Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "CERTIFICATE NOT READY YET!" -ForegroundColor Red
    Write-Host "Wait 5-10 more minutes for Azure to provision it." -ForegroundColor Yellow
}

Write-Host ""

# TEST 4: FRONT DOOR STATUS (if logged in)
Write-Host "[TEST 4] Azure Front Door Status" -ForegroundColor Yellow
$loginCheck = az account show 2>$null
if ($loginCheck) {
    try {
        $fdProfiles = az afd profile list --output json 2>$null | ConvertFrom-Json
        $fd = $fdProfiles | Where-Object { $_.name -like "*moveit*" -or $_.name -like "*frontdoor*" } | Select-Object -First 1
        
        if ($fd) {
            Write-Test "Front Door found" "✓ PASS" "Green"
            Write-Host "    Name: $($fd.name)" -ForegroundColor Gray
            
            $domains = az afd custom-domain list --profile-name $fd.name --resource-group $fd.resourceGroup --output json 2>$null | ConvertFrom-Json
            $customDomain = $domains | Where-Object { $_.hostName -eq $domain } | Select-Object -First 1
            
            if ($customDomain) {
                Write-Test "Custom domain configured" "✓ PASS" "Green"
                Write-Host "    Domain: $($customDomain.hostName)" -ForegroundColor Gray
                Write-Host "    Status: $($customDomain.deploymentStatus)" -ForegroundColor Gray
                
                if ($customDomain.tlsSettings) {
                    Write-Test "HTTPS enabled" "✓ PASS" "Green"
                    Write-Host "    Certificate Type: $($customDomain.tlsSettings.certificateType)" -ForegroundColor Gray
                    Write-Host "    TLS Version: $($customDomain.tlsSettings.minimumTlsVersion)" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Test "Front Door check" "⚠ SKIP" "Yellow"
        Write-Host "    Could not check (non-critical)" -ForegroundColor Gray
    }
} else {
    Write-Test "Azure login required" "⚠ SKIP" "Yellow"
    Write-Host "    Run 'az login' to check Front Door details" -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan

# FINAL RESULT
Write-Host ""
$testPassed = $true

if ($dns -and $response -and $cert2) {
    Write-Host "  ✓✓✓ SUCCESS - CERTIFICATE IS WORKING! ✓✓✓" -ForegroundColor Green
    Write-Host ""
    Write-Host "  YOUR SITE IS LIVE AND SECURE!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Test it in browser: $url" -ForegroundColor Cyan
    Write-Host "  You should see lock icon 🔒 with no warnings" -ForegroundColor White
    Write-Host ""
    Write-Host "  CALL YOUR CLIENT NOW! 📞" -ForegroundColor Yellow
    
} elseif ($dns -and $response) {
    Write-Host "  ⚠ PARTIAL SUCCESS - SITE WORKS, CHECKING CERT..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The site is accessible via HTTPS" -ForegroundColor White
    Write-Host "  Certificate details could not be verified via script" -ForegroundColor White
    Write-Host "  Test manually in browser: $url" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  If browser shows lock icon 🔒 = YOU'RE GOOD!" -ForegroundColor Green
    
} elseif ($dns) {
    Write-Host "  ✗ NOT READY YET - CERTIFICATE STILL PROVISIONING" -ForegroundColor Red
    Write-Host ""
    Write-Host "  DNS is working ✓" -ForegroundColor Green
    Write-Host "  But HTTPS/Certificate not ready yet ✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "  WAIT 5-10 MORE MINUTES" -ForegroundColor Yellow
    Write-Host "  Then run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "  Azure is still propagating your certificate globally" -ForegroundColor Gray
    
} else {
    Write-Host "  ✗ NOT WORKING - DNS ISSUE" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Domain does not resolve ✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "  FIX: Add DNS CNAME record" -ForegroundColor Yellow
    Write-Host "  Point: moveit.pyxhealth.com" -ForegroundColor White
    Write-Host "  To: [Your Front Door endpoint].azurefd.net" -ForegroundColor White
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
