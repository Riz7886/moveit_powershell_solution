param(
    [string]$Domain = "moveit.pyxhealth.com",
    [int]$Port = 443,
    [string]$ExpectedText = "MOVEit"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " SSL CERTIFICATE TEST - $Domain" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

function Write-Result {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# 1. DNS LOOKUP
Write-Host "1) Testing DNS resolution..." -ForegroundColor Yellow
try {
    $dns = Resolve-DnsName -Name $Domain -ErrorAction Stop | Where-Object { $_.IPAddress }
    if ($dns) {
        $ips = ($dns | Select-Object -ExpandProperty IPAddress) -join ", "
        Write-Result "   DNS OK -> $ips" "Green"
    } else {
        Write-Result "   DNS returned no IP addresses!" "Red"
    }
}
catch {
    Write-Result "   DNS lookup FAILED: $($_.Exception.Message)" "Red"
}

Write-Host ""

# 2. TCP 443 CONNECTIVITY
Write-Host "2) Testing TCP connectivity on port $Port..." -ForegroundColor Yellow
try {
    $conn = Test-NetConnection -ComputerName $Domain -Port $Port -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Result "   TCP port $Port is reachable." "Green"
    }
    else {
        Write-Result "   TCP port $Port is NOT reachable." "Red"
    }
}
catch {
    Write-Result "   TCP connectivity test FAILED: $($_.Exception.Message)" "Red"
}

Write-Host ""

# 3. HTTPS + PAGE CONTENT
Write-Host "3) Testing HTTPS response and page content..." -ForegroundColor Yellow
try {
    $url = "https://$Domain"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
    Write-Result ("   HTTPS status code: {0}" -f $response.StatusCode) "Green"

    if ($ExpectedText -and ($response.Content -match $ExpectedText)) {
        Write-Result "   Page content looks like MOVEit login page (found '$ExpectedText')." "Green"
    }
    else {
        Write-Result "   HTTPS works, but expected text '$ExpectedText' was NOT found in the page." "Yellow"
    }
}
catch {
    Write-Result "   HTTPS request FAILED: $($_.Exception.Message)" "Red"
}

Write-Host ""

# 4. CERTIFICATE DETAILS
Write-Host "4) Checking TLS certificate details..." -ForegroundColor Yellow
try {
    $tcpClient  = New-Object System.Net.Sockets.TcpClient($Domain, $Port)
    $sslStream  = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, { $true })
    $sslStream.AuthenticateAsClient($Domain)

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)

    Write-Result "   Subject : $($cert.Subject)" "Cyan"
    Write-Result "   Issuer  : $($cert.Issuer)" "Cyan"
    Write-Result "   NotBefore : $($cert.NotBefore)" "Cyan"
    Write-Result "   NotAfter  : $($cert.NotAfter)" "Cyan"

    $now = Get-Date
    if ($cert.NotAfter -lt $now) {
        Write-Result "   CERTIFICATE IS EXPIRED!" "Red"
    }
    elseif ($cert.NotBefore -gt $now) {
        Write-Result "   CERTIFICATE NOT YET VALID (check system time and cert dates)." "Red"
    }
    else {
        Write-Result "   Certificate validity dates look OK." "Green"
    }

    $sslStream.Close()
    $tcpClient.Close()
}
catch {
    Write-Result "   Could not inspect certificate: $($_.Exception.Message)" "Red"
}

Write-Host ""
Write-Host "If browser shows lock icon on DMZ and you see GREEN above, YOU ARE GOOD!" -ForegroundColor Green
Write-Host ""
Read-Host "Press ENTER to exit"
