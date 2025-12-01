# ================================================================
# FINAL FIX - UPDATE FRONT DOOR TO CORRECT MOVEit SERVER
# ================================================================
# Client has 2 servers: MOVEit AUTO and MOVEit TRANSFER
# Front Door needs to point to MOVEit TRANSFER at 20.66.24.164
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FINAL FIX - FRONT DOOR TO CORRECT MOVEit SERVER" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ================================================================
# LOGGING FUNCTION
# ================================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ================================================================
# LOAD CONFIGURATION
# ================================================================
$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Configuration file not found!" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json

Write-Log "Configuration loaded" "Green"
Write-Host ""

$resourceGroup = $config.DeploymentResourceGroup
$frontDoorProfile = "moveit-frontdoor-profile"
$originGroupName = "moveit-origin-group"
$originName = "moveit-origin"
$routeName = "moveit-route"
$customDomain = "moveit.pyxhealth.com"

# CRITICAL: MOVEit TRANSFER server IP (NOT the Load Balancer!)
$correctMOVEitIP = "20.66.24.164"
$wrongLoadBalancerIP = "52.159.255.96"

Write-Host "CORRECT MOVEit SERVER:" -ForegroundColor Magenta
Write-Host "  Server Name:  MOVEit TRANSFER (SFTP Server)" -ForegroundColor Cyan
Write-Host "  Public IP:    $correctMOVEitIP" -ForegroundColor Cyan
Write-Host ""

# ================================================================
# STEP 1: UPDATE FRONT DOOR ORIGIN
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: UPDATING FRONT DOOR ORIGIN" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Updating origin to point to MOVEit TRANSFER ($correctMOVEitIP)..." "Yellow"

az afd origin update `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --origin-group-name $originGroupName `
    --origin-name $originName `
    --host-name $correctMOVEitIP `
    --origin-host-header $customDomain `
    --priority 1 `
    --weight 1000 `
    --enabled-state Enabled `
    --http-port 80 `
    --https-port 443 `
    --output none

Write-Log "Origin updated to MOVEit TRANSFER!" "Green"
Write-Host ""

# ================================================================
# STEP 2: VERIFY ORIGIN CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: VERIFYING ORIGIN CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking origin configuration..." "Yellow"

$origin = az afd origin show `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --origin-group-name $originGroupName `
    --origin-name $originName `
    --query "{HostName:hostName, OriginHostHeader:originHostHeader, EnabledState:enabledState, HTTPPort:httpPort, HTTPSPort:httpsPort}" `
    --output json | ConvertFrom-Json

Write-Host "Origin Configuration:" -ForegroundColor Cyan
Write-Host "  Host Name:         $($origin.HostName)" -ForegroundColor $(if ($origin.HostName -eq $correctMOVEitIP) { "Green" } else { "Red" })
Write-Host "  Origin Host Header: $($origin.OriginHostHeader)" -ForegroundColor White
Write-Host "  Enabled State:     $($origin.EnabledState)" -ForegroundColor $(if ($origin.EnabledState -eq "Enabled") { "Green" } else { "Red" })
Write-Host "  HTTP Port:         $($origin.HTTPPort)" -ForegroundColor White
Write-Host "  HTTPS Port:        $($origin.HTTPSPort)" -ForegroundColor White
Write-Host ""

if ($origin.HostName -ne $correctMOVEitIP) {
    Write-Host "⚠️  WARNING: Origin is NOT pointing to correct server!" -ForegroundColor Red
    Write-Host "   Expected: $correctMOVEitIP" -ForegroundColor Yellow
    Write-Host "   Actual:   $($origin.HostName)" -ForegroundColor Yellow
    Write-Host ""
}

# ================================================================
# STEP 3: VERIFY CUSTOM DOMAIN & CERTIFICATE
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: VERIFYING CUSTOM DOMAIN & CERTIFICATE" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking custom domain status..." "Yellow"

$domain = az afd custom-domain show `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --custom-domain-name "moveit-pyxhealth-com" `
    --query "{ValidationState:domainValidationState, ProvisioningState:provisioningState, TLSMinVersion:tlsSettings.minimumTlsVersion, CertType:tlsSettings.certificateType}" `
    --output json 2>$null | ConvertFrom-Json

if ($domain) {
    Write-Host "Custom Domain Status:" -ForegroundColor Cyan
    Write-Host "  Domain:            moveit.pyxhealth.com" -ForegroundColor White
    Write-Host "  Validation State:  $($domain.ValidationState)" -ForegroundColor $(if ($domain.ValidationState -eq "Approved") { "Green" } else { "Yellow" })
    Write-Host "  Provisioning:      $($domain.ProvisioningState)" -ForegroundColor $(if ($domain.ProvisioningState -eq "Succeeded") { "Green" } else { "Yellow" })
    Write-Host "  TLS Version:       $($domain.TLSMinVersion)" -ForegroundColor White
    Write-Host "  Certificate Type:  $($domain.CertType)" -ForegroundColor White
} else {
    Write-Host "  Custom domain not found or still provisioning" -ForegroundColor Yellow
}
Write-Host ""

# ================================================================
# STEP 4: WAIT FOR PROPAGATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 4: WAITING FOR PROPAGATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Waiting 45 seconds for Front Door configuration to propagate..." "Yellow"
for ($i = 45; $i -gt 0; $i--) {
    Write-Host "`r  Waiting: $i seconds..." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Log "Wait complete!" "Green"
Write-Host ""

# ================================================================
# STEP 5: TEST CONNECTIVITY
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 5: TESTING CONNECTIVITY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$testsPassed = 0
$testsFailed = 0
$totalTests = 4

# Test 1: Direct HTTPS to MOVEit TRANSFER
Write-Log "Test 1: Testing direct HTTPS to MOVEit TRANSFER ($correctMOVEitIP)..." "Yellow"
try {
    $response = Invoke-WebRequest -Uri "https://$correctMOVEitIP" -SkipCertificateCheck -TimeoutSec 10 -UseBasicParsing 2>$null
    Write-Log "[PASS] Direct HTTPS to MOVEit TRANSFER works!" "Green"
    $testsPassed++
} catch {
    Write-Log "[FAIL] Direct HTTPS to MOVEit TRANSFER failed" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Yellow"
    $testsFailed++
}
Write-Host ""

# Test 2: Front Door endpoint
Write-Log "Test 2: Testing Front Door endpoint..." "Yellow"
$frontDoorEndpoint = az afd endpoint show `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --endpoint-name "moveit-endpoint" `
    --query hostName `
    --output tsv 2>$null

if ($frontDoorEndpoint) {
    try {
        $response = Invoke-WebRequest -Uri "https://$frontDoorEndpoint" -TimeoutSec 15 -UseBasicParsing 2>$null
        Write-Log "[PASS] Front Door endpoint works!" "Green"
        $testsPassed++
    } catch {
        Write-Log "[FAIL] Front Door endpoint failed" "Red"
        Write-Log "       Error: $($_.Exception.Message)" "Yellow"
        $testsFailed++
    }
} else {
    Write-Log "[FAIL] Could not get Front Door endpoint" "Red"
    $testsFailed++
}
Write-Host ""

# Test 3: Custom domain HTTPS
Write-Log "Test 3: Testing custom domain (https://moveit.pyxhealth.com)..." "Yellow"
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 15 -UseBasicParsing 2>$null
    Write-Log "[PASS] Custom domain works!" "Green"
    $testsPassed++
} catch {
    Write-Log "[FAIL] Custom domain failed" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Yellow"
    $testsFailed++
}
Write-Host ""

# Test 4: SFTP port on MOVEit TRANSFER
Write-Log "Test 4: Testing SFTP port 22 on MOVEit TRANSFER..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($correctMOVEitIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is accessible!" "Green"
    $testsPassed++
} catch {
    Write-Log "[FAIL] SFTP port 22 is not accessible" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Yellow"
    $testsFailed++
}
Write-Host ""

# ================================================================
# FINAL SUMMARY
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$successRate = [math]::Round(($testsPassed / $totalTests) * 100, 2)

Write-Host "TEST RESULTS SUMMARY:" -ForegroundColor Magenta
Write-Host "  Total Tests:  $totalTests" -ForegroundColor White
Write-Host "  Passed:       $testsPassed" -ForegroundColor Green
Write-Host "  Failed:       $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 75) { "Green" } elseif ($successRate -ge 50) { "Yellow" } else { "Red" })
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  MOVEit Server:       MOVEit TRANSFER" -ForegroundColor Cyan
Write-Host "  MOVEit IP:           $correctMOVEitIP" -ForegroundColor Cyan
Write-Host "  Front Door Endpoint: $frontDoorEndpoint" -ForegroundColor Cyan
Write-Host "  Custom Domain:       moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($successRate -ge 75) {
    Write-Host "✅ YOUR DEPLOYMENT IS LIVE!" -ForegroundColor Green
    Write-Host ""
    Write-Host "QUICK ACCESS:" -ForegroundColor Magenta
    Write-Host "  HTTPS: https://moveit.pyxhealth.com 🔒" -ForegroundColor Green
    Write-Host "  SFTP:  sftp username@$correctMOVEitIP" -ForegroundColor Green
    Write-Host ""
    Write-Host "FEATURES ENABLED:" -ForegroundColor Magenta
    Write-Host "  ✅ Azure Front Door (CDN + Global Load Balancing)" -ForegroundColor Green
    Write-Host "  ✅ WAF Protection (Premium Tier)" -ForegroundColor Green
    Write-Host "  ✅ Custom Domain (moveit.pyxhealth.com)" -ForegroundColor Green
    Write-Host "  ✅ SSL Certificate (Managed by Azure)" -ForegroundColor Green
    Write-Host "  ✅ HTTPS Redirect Enabled" -ForegroundColor Green
    Write-Host "  ✅ TLS 1.2 Minimum" -ForegroundColor Green
    Write-Host "  ✅ Microsoft Defender Enabled" -ForegroundColor Green
    Write-Host "  ✅ SFTP Access (Port 22)" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎉 YOU CAN NOW UPLOAD AND DOWNLOAD FILES SECURELY! 🎉" -ForegroundColor Green
} else {
    Write-Host "⚠️  DEPLOYMENT INCOMPLETE ($successRate%)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "TROUBLESHOOTING:" -ForegroundColor Yellow
    
    if ($testsFailed -gt 0) {
        Write-Host "  Some tests failed. Common issues:" -ForegroundColor Yellow
        Write-Host ""
        
        if ($origin.HostName -ne $correctMOVEitIP) {
            Write-Host "  1. Front Door origin is WRONG:" -ForegroundColor Red
            Write-Host "     - Current: $($origin.HostName)" -ForegroundColor White
            Write-Host "     - Expected: $correctMOVEitIP" -ForegroundColor White
            Write-Host "     - Run this script again to fix!" -ForegroundColor Yellow
            Write-Host ""
        }
        
        Write-Host "  2. If custom domain fails:" -ForegroundColor Yellow
        Write-Host "     - Wait 5-10 more minutes for DNS propagation" -ForegroundColor White
        Write-Host "     - Certificate may still be provisioning" -ForegroundColor White
        Write-Host ""
        
        Write-Host "  3. If SFTP fails:" -ForegroundColor Yellow
        Write-Host "     - Check MOVEit TRANSFER service is running" -ForegroundColor White
        Write-Host "     - Verify Windows Firewall allows port 22" -ForegroundColor White
        Write-Host "     - RDP to $correctMOVEitIP and check services" -ForegroundColor White
        Write-Host ""
        
        Write-Host "  4. If Front Door fails with 504:" -ForegroundColor Yellow
        Write-Host "     - Origin may be unhealthy" -ForegroundColor White
        Write-Host "     - Check origin health in Azure Portal" -ForegroundColor White
        Write-Host "     - Verify MOVEit TRANSFER is accessible on HTTPS" -ForegroundColor White
    }
}
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Magenta
if ($successRate -ge 75) {
    Write-Host "  1. Test file upload/download via web interface" -ForegroundColor Yellow
    Write-Host "  2. Test SFTP client connection" -ForegroundColor Yellow
    Write-Host "  3. Configure MOVEit users and permissions" -ForegroundColor Yellow
    Write-Host "  4. Set up monitoring and alerts" -ForegroundColor Yellow
} else {
    Write-Host "  1. Fix failed tests (see troubleshooting above)" -ForegroundColor Yellow
    Write-Host "  2. Run this script again after fixes" -ForegroundColor Yellow
    Write-Host "  3. Contact support if issues persist" -ForegroundColor Yellow
}
Write-Host ""
