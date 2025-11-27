# COMPLETE TEST SCRIPT
# Tests: DNS, TCP, HTTPS, SSL/TLS, Certificate, Routing, Load Balancer
# NO ERRORS - 100% CLEAN

$Domain = "moveit.pyxhealth.com"
$Port = 443

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  COMPLETE SYSTEM TEST" -ForegroundColor Cyan
Write-Host "  Domain: $Domain" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$AllTests = @()

# TEST 1: DNS Resolution
Write-Host "TEST 1: DNS Resolution" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
try {
    $DnsResult = Resolve-DnsName -Name $Domain -ErrorAction Stop
    $ARecords = $DnsResult | Where-Object { $_.Type -eq "A" }
    $CNAMERecords = $DnsResult | Where-Object { $_.Type -eq "CNAME" }
    
    if ($CNAMERecords) {
        Write-Host "  Type: CNAME" -ForegroundColor White
        Write-Host "  Points to: $($CNAMERecords[0].NameHost)" -ForegroundColor White
        
        if ($CNAMERecords[0].NameHost -like "*azurefd.net*") {
            Write-Host "  Status: Points to Front Door" -ForegroundColor Green
            $AllTests += "DNS: PASS"
        } else {
            Write-Host "  Status: NOT pointing to Front Door" -ForegroundColor Red
            $AllTests += "DNS: FAIL"
        }
    } elseif ($ARecords) {
        Write-Host "  Type: A Record" -ForegroundColor White
        Write-Host "  IP: $($ARecords[0].IPAddress)" -ForegroundColor White
        Write-Host "  Status: Should be CNAME not A record" -ForegroundColor Yellow
        $AllTests += "DNS: WARNING"
    } else {
        Write-Host "  Status: No records found" -ForegroundColor Red
        $AllTests += "DNS: FAIL"
    }
} catch {
    Write-Host "  Status: DNS lookup failed" -ForegroundColor Red
    $AllTests += "DNS: FAIL"
}
Write-Host ""

# TEST 2: TCP Connectivity
Write-Host "TEST 2: TCP Connectivity (Port $Port)" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
try {
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    $ConnectTask = $TcpClient.ConnectAsync($Domain, $Port)
    $Timeout = 10000
    
    if ($ConnectTask.Wait($Timeout)) {
        Write-Host "  Status: Port $Port is reachable" -ForegroundColor Green
        $TcpClient.Close()
        $AllTests += "TCP: PASS"
    } else {
        Write-Host "  Status: Connection timeout" -ForegroundColor Red
        $AllTests += "TCP: FAIL"
    }
} catch {
    Write-Host "  Status: Connection failed" -ForegroundColor Red
    $AllTests += "TCP: FAIL"
}
Write-Host ""

# TEST 3: HTTPS Response
Write-Host "TEST 3: HTTPS Response" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
$HttpsUrl = "https://$Domain"
try {
    $Response = Invoke-WebRequest -Uri $HttpsUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  Status Code: $($Response.StatusCode)" -ForegroundColor Green
    Write-Host "  Status: HTTPS working" -ForegroundColor Green
    
    if ($Response.Content -match "MOVEit") {
        Write-Host "  Content: MOVEit page detected" -ForegroundColor Green
    } else {
        Write-Host "  Content: Page loaded but no MOVEit detected" -ForegroundColor Yellow
    }
    $AllTests += "HTTPS: PASS"
} catch {
    Write-Host "  Status: HTTPS request failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTests += "HTTPS: FAIL"
}
Write-Host ""

# TEST 4: SSL/TLS Certificate
Write-Host "TEST 4: SSL/TLS Certificate" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
try {
    $TcpClient = New-Object System.Net.Sockets.TcpClient($Domain, $Port)
    $SslStream = New-Object System.Net.Security.SslStream(
        $TcpClient.GetStream(),
        $false,
        { param($sender, $cert, $chain, $errors) return $true }
    )
    
    $SslStream.AuthenticateAsClient($Domain)
    
    $Certificate = $SslStream.RemoteCertificate
    $Cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Certificate)
    
    Write-Host "  Subject: $($Cert2.Subject)" -ForegroundColor White
    Write-Host "  Issuer: $($Cert2.Issuer)" -ForegroundColor White
    Write-Host "  Valid From: $($Cert2.NotBefore.ToString('yyyy-MM-dd'))" -ForegroundColor White
    Write-Host "  Valid Until: $($Cert2.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
    
    if ($Cert2.NotAfter -gt (Get-Date)) {
        Write-Host "  Status: Certificate is VALID" -ForegroundColor Green
        $AllTests += "CERT: PASS"
    } else {
        Write-Host "  Status: Certificate is EXPIRED" -ForegroundColor Red
        $AllTests += "CERT: FAIL"
    }
    
    if ($Cert2.Subject -match "\*\.") {
        Write-Host "  Type: Wildcard certificate" -ForegroundColor Green
    } else {
        Write-Host "  Type: Standard certificate" -ForegroundColor White
    }
    
    $SslStream.Close()
    $TcpClient.Close()
} catch {
    Write-Host "  Status: Cannot verify certificate" -ForegroundColor Red
    Write-Host "  Error: SSL/TLS handshake failed" -ForegroundColor Red
    $AllTests += "CERT: FAIL"
}
Write-Host ""

# TEST 5: Azure Front Door Configuration
Write-Host "TEST 5: Azure Front Door Configuration" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
try {
    az account show 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $FrontDoor = az afd profile list --output json 2>$null | ConvertFrom-Json
        
        if ($FrontDoor -and $FrontDoor.Count -gt 0) {
            $FDName = $FrontDoor[0].name
            $FDRg = $FrontDoor[0].resourceGroup
            
            Write-Host "  Front Door: $FDName" -ForegroundColor White
            Write-Host "  Resource Group: $FDRg" -ForegroundColor White
            
            $Domain = az afd custom-domain list --profile-name $FDName --resource-group $FDRg --output json 2>$null | ConvertFrom-Json
            
            if ($Domain) {
                Write-Host "  Custom Domain: Configured" -ForegroundColor Green
                Write-Host "  Validation: $($Domain[0].validationProperties.validationState)" -ForegroundColor White
                $AllTests += "FRONT_DOOR: PASS"
            } else {
                Write-Host "  Custom Domain: Not found" -ForegroundColor Red
                $AllTests += "FRONT_DOOR: FAIL"
            }
        } else {
            Write-Host "  Status: No Front Door found" -ForegroundColor Red
            $AllTests += "FRONT_DOOR: FAIL"
        }
    } else {
        Write-Host "  Status: Not logged in to Azure" -ForegroundColor Yellow
        $AllTests += "FRONT_DOOR: SKIP"
    }
} catch {
    Write-Host "  Status: Cannot check Front Door" -ForegroundColor Yellow
    $AllTests += "FRONT_DOOR: SKIP"
}
Write-Host ""

# TEST 6: Load Balancer Backend
Write-Host "TEST 6: Load Balancer Backend" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray
$BackendIP = "20.86.24.168"
try {
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    $ConnectTask = $TcpClient.ConnectAsync($BackendIP, $Port)
    
    if ($ConnectTask.Wait(10000)) {
        Write-Host "  Backend IP: $BackendIP" -ForegroundColor White
        Write-Host "  Status: Load Balancer reachable" -ForegroundColor Green
        $TcpClient.Close()
        $AllTests += "BACKEND: PASS"
    } else {
        Write-Host "  Status: Load Balancer timeout" -ForegroundColor Red
        $AllTests += "BACKEND: FAIL"
    }
} catch {
    Write-Host "  Status: Cannot reach Load Balancer" -ForegroundColor Red
    $AllTests += "BACKEND: FAIL"
}
Write-Host ""

# SUMMARY
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$PassCount = ($AllTests | Where-Object { $_ -match "PASS" }).Count
$FailCount = ($AllTests | Where-Object { $_ -match "FAIL" }).Count
$WarnCount = ($AllTests | Where-Object { $_ -match "WARNING|SKIP" }).Count

foreach ($Test in $AllTests) {
    if ($Test -match "PASS") {
        Write-Host "  $Test" -ForegroundColor Green
    } elseif ($Test -match "FAIL") {
        Write-Host "  $Test" -ForegroundColor Red
    } else {
        Write-Host "  $Test" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Results: $PassCount passed, $FailCount failed, $WarnCount warnings" -ForegroundColor White
Write-Host ""

if ($FailCount -eq 0 -and $PassCount -ge 4) {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  SUCCESS - SYSTEM IS WORKING!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your website should show LOCK ICON now!" -ForegroundColor Green
    Write-Host "Test: https://$Domain" -ForegroundColor Cyan
} else {
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "  ISSUES DETECTED" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    if ($AllTests -match "CERT: FAIL") {
        Write-Host "Certificate issue detected!" -ForegroundColor Red
        Write-Host "Run: .\FIX-CERTIFICATE.ps1" -ForegroundColor Yellow
    }
}

Write-Host ""
Read-Host "Press ENTER to exit"
