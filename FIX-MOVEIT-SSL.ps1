# FIX MOVEIT SSL/TLS CERTIFICATE – AUTO-DETECT + CHAIN FIX
param(
    [string]$Domain = "moveit.pyxhealth.com",
    [string]$PfxPath = "C:\Users\SyedRizvi\Downloads\DMZ\moveit.pfx",
    [string]$PfxPassword = ""
)

Write-Host "=== MOVEIT SSL FIX STARTED ===" -ForegroundColor Cyan

# 1) Test DNS
Write-Host "`n1) Testing DNS..." -ForegroundColor Yellow
try {
    $dns = Resolve-DnsName $Domain -ErrorAction Stop
    Write-Host "DNS OK → $($dns.IPAddress)" -ForegroundColor Green
}
catch {
    Write-Host "DNS FAILED" -ForegroundColor Red
    exit
}

# 2) Test Port 443
Write-Host "`n2) Testing TCP Port 443..." -ForegroundColor Yellow
$tcp = Test-NetConnection -ComputerName $Domain -Port 443
if ($tcp.TcpTestSucceeded) {
    Write-Host "TCP 443 OK" -ForegroundColor Green
} else {
    Write-Host "TCP 443 BLOCKED" -ForegroundColor Red
    exit
}

# 3) DOWNLOAD SERVER CERTIFICATE
Write-Host "`n3) Pulling server certificate..." -ForegroundColor Yellow

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient($Domain,443)
    $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(),$false,{ $true })
    $sslStream.AuthenticateAsClient($Domain)
    $serverCert = $sslStream.RemoteCertificate
    $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $serverCert
    Write-Host "Server Certificate Retrieved Successfully" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Server certificate cannot be pulled. This confirms chain or hostname issue." -ForegroundColor Red
}

# 4) Install Missing Intermediate Certificates
Write-Host "`n4) Installing Intermediate Certificates..." -ForegroundColor Yellow

$IntermediateUrls = @(
    "http://certs.godaddy.com/repository/gdig2.crt",
    "http://certs.godaddy.com/repository/gd_intermediate.crt"
)

foreach ($url in $IntermediateUrls) {
    try {
        $crtPath = "$env:TEMP\intermediate.crt"
        Invoke-WebRequest -Uri $url -OutFile $crtPath -UseBasicParsing
        certutil -addstore -f "CA" $crtPath | Out-Null
        Write-Host "Installed Intermediate → $url" -ForegroundColor Green
    } catch {
    }
}

# 5) Install your MOVEIT PFX if provided
if (Test-Path $PfxPath) {
    Write-Host "`n5) Installing MOVEIT certificate PFX..." -ForegroundColor Yellow
    try {
        certutil -importpfx $PfxPath $PfxPassword | Out-Null
        Write-Host "PFX Installed Successfully" -ForegroundColor Green
    } catch {
        Write-Host "PFX INSTALL FAILED" -ForegroundColor Red
    }
} else {
    Write-Host "PFX NOT FOUND → $PfxPath" -ForegroundColor Yellow
}

# 6) Final SSL test
Write-Host "`n6) VALIDATING HTTPS..." -ForegroundColor Yellow
try {
    $result = Invoke-WebRequest "https://$Domain" -UseBasicParsing -TimeoutSec 10
    Write-Host "HTTPS SUCCESS → SSL OK" -ForegroundColor Green
}
catch {
    Write-Host "HTTPS STILL FAILING – SERVER STILL SERVING BAD CERT" -ForegroundColor Red
}

Write-Host "`n=== SSL FIX COMPLETE ===" -ForegroundColor Cyan
