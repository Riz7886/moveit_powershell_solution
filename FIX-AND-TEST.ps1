# ================================================================
# COMPREHENSIVE FIX AND TEST SCRIPT
# ================================================================
# Description: Diagnoses issues, fixes configuration, tests everything
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "COMPREHENSIVE FIX AND TEST SCRIPT" -ForegroundColor Cyan
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
    Write-Host "Please run Script 1 first!" -ForegroundColor Yellow
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json

Write-Log "Configuration loaded" "Green"
Write-Log "Resource Group: $($config.DeploymentResourceGroup)" "Yellow"
Write-Host ""

# ================================================================
# STEP 1: GET CURRENT LOAD BALANCER IP
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: CHECKING LOAD BALANCER IP" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Getting current Load Balancer public IP..." "Yellow"
$currentLoadBalancerIP = az network public-ip show `
    --resource-group $config.DeploymentResourceGroup `
    --name $config.PublicIPName `
    --query ipAddress `
    --output tsv

if (-not $currentLoadBalancerIP) {
    Write-Log "ERROR: Could not get Load Balancer IP!" "Red"
    exit 1
}

Write-Log "Current Load Balancer IP: $currentLoadBalancerIP" "Green"
Write-Host ""

# ================================================================
# STEP 2: CHECK FRONT DOOR ORIGIN CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: CHECKING FRONT DOOR ORIGIN" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$FrontDoorProfileName = "moveit-frontdoor-profile"
$FrontDoorOriginGroupName = "moveit-origin-group"
$FrontDoorOriginName = "moveit-origin"

Write-Log "Getting current Front Door origin configuration..." "Yellow"
$originHostName = az afd origin show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --origin-group-name $FrontDoorOriginGroupName `
    --origin-name $FrontDoorOriginName `
    --query hostName `
    --output tsv

Write-Log "Front Door origin points to: $originHostName" "Cyan"

if ($originHostName -ne $currentLoadBalancerIP) {
    Write-Log "MISMATCH DETECTED!" "Red"
    Write-Log "Origin IP ($originHostName) != Load Balancer IP ($currentLoadBalancerIP)" "Red"
    Write-Host ""
    
    Write-Log "FIXING: Updating Front Door origin to correct IP..." "Yellow"
    az afd origin update `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --origin-group-name $FrontDoorOriginGroupName `
        --origin-name $FrontDoorOriginName `
        --host-name $currentLoadBalancerIP `
        --origin-host-header $currentLoadBalancerIP `
        --output none

    Write-Log "Front Door origin updated to: $currentLoadBalancerIP" "Green"
} else {
    Write-Log "Front Door origin is correct!" "Green"
}
Write-Host ""

# ================================================================
# STEP 3: VERIFY NSG RULES
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: VERIFYING NSG RULES" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking NSG rules for ports 22 and 443..." "Yellow"

$nsgName = "nsg-moveit"
$nsgRules = az network nsg rule list `
    --resource-group $config.DeploymentResourceGroup `
    --nsg-name $nsgName `
    --query "[?destinationPortRange=='22' || destinationPortRange=='443'].{Name:name, Port:destinationPortRange, Access:access}" `
    --output json | ConvertFrom-Json

Write-Host "NSG Rules Found:" -ForegroundColor Cyan
foreach ($rule in $nsgRules) {
    $color = if ($rule.Access -eq "Allow") { "Green" } else { "Red" }
    Write-Host "  Port $($rule.Port): $($rule.Access)" -ForegroundColor $color
}
Write-Host ""

# ================================================================
# STEP 4: CHECK FRONT DOOR ENDPOINT
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 4: CHECKING FRONT DOOR ENDPOINT" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$FrontDoorEndpointName = "moveit-endpoint"
$endpointHostname = az afd endpoint show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --endpoint-name $FrontDoorEndpointName `
    --query hostName `
    --output tsv

Write-Log "Front Door Endpoint: https://$endpointHostname" "Cyan"
Write-Host ""

# ================================================================
# STEP 5: WAIT FOR FRONT DOOR PROPAGATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 5: WAITING FOR FRONT DOOR PROPAGATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Waiting 30 seconds for Front Door changes to propagate..." "Yellow"
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`r  Waiting: $i seconds..." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Log "Wait complete!" "Green"
Write-Host ""

# ================================================================
# STEP 6: TEST CONNECTIVITY
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 6: TESTING CONNECTIVITY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$testResults = @()
$passedTests = 0
$failedTests = 0

# Test 1: Front Door HTTPS Endpoint
Write-Log "Testing Front Door HTTPS endpoint..." "Yellow"
try {
    $response = Invoke-WebRequest -Uri "https://$endpointHostname" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Log "[PASS] Front Door HTTPS endpoint is accessible" "Green"
    $testResults += "[PASS] Front Door HTTPS Endpoint"
    $passedTests++
} catch {
    Write-Log "[FAIL] Front Door HTTPS endpoint connection failed" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Red"
    $testResults += "[FAIL] Front Door HTTPS Endpoint"
    $failedTests++
}
Write-Host ""

# Test 2: Custom Domain (if DNS propagated)
Write-Log "Testing custom domain..." "Yellow"
try {
    $response = Invoke-WebRequest -Uri "https://$($config.CustomDomain)" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Log "[PASS] Custom domain is accessible" "Green"
    $testResults += "[PASS] Custom Domain (https://$($config.CustomDomain))"
    $passedTests++
} catch {
    Write-Log "[FAIL] Custom domain not yet accessible (DNS may still be propagating)" "Yellow"
    Write-Log "       This is normal - DNS can take 5-30 minutes to propagate" "Yellow"
    $testResults += "[PENDING] Custom Domain (DNS propagation in progress)"
    $failedTests++
}
Write-Host ""

# Test 3: SFTP Port on Load Balancer
Write-Log "Testing SFTP port (22) on Load Balancer..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($currentLoadBalancerIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is accessible on $currentLoadBalancerIP" "Green"
    $testResults += "[PASS] SFTP Port Accessibility"
    $passedTests++
} catch {
    Write-Log "[FAIL] SFTP port 22 is not accessible on $currentLoadBalancerIP" "Red"
    Write-Log "       Check: NSG rules, Load Balancer backend pool, MOVEit server status" "Yellow"
    $testResults += "[FAIL] SFTP Port Accessibility"
    $failedTests++
}
Write-Host ""

# Test 4: Load Balancer Backend Health
Write-Log "Checking Load Balancer backend pool health..." "Yellow"
$backendHealth = az network lb show `
    --resource-group $config.DeploymentResourceGroup `
    --name "lb-moveit-sftp" `
    --query "backendAddressPools[0].backendIPConfigurations" `
    --output json | ConvertFrom-Json

if ($backendHealth) {
    Write-Log "[PASS] Load Balancer backend pool is configured" "Green"
    $testResults += "[PASS] Load Balancer Backend Pool"
    $passedTests++
} else {
    Write-Log "[FAIL] Load Balancer backend pool has no backends" "Red"
    $testResults += "[FAIL] Load Balancer Backend Pool"
    $failedTests++
}
Write-Host ""

# ================================================================
# STEP 7: DNS PROPAGATION CHECK
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 7: DNS PROPAGATION CHECK" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking DNS propagation for $($config.CustomDomain)..." "Yellow"
try {
    $dnsResult = Resolve-DnsName -Name $config.CustomDomain -Type CNAME -ErrorAction Stop
    Write-Log "DNS CNAME Record:" "Cyan"
    Write-Log "  Name:  $($dnsResult.Name)" "White"
    Write-Log "  Value: $($dnsResult.NameHost)" "White"
    
    if ($dnsResult.NameHost -like "*azurefd.net") {
        Write-Log "[PASS] DNS is correctly pointing to Front Door" "Green"
        $testResults += "[PASS] DNS Configuration"
        $passedTests++
    } else {
        Write-Log "[FAIL] DNS is not pointing to Front Door" "Red"
        $testResults += "[FAIL] DNS Configuration"
        $failedTests++
    }
} catch {
    Write-Log "[PENDING] DNS propagation still in progress" "Yellow"
    Write-Log "          Wait 5-30 minutes and try accessing https://$($config.CustomDomain)" "Yellow"
    $testResults += "[PENDING] DNS Propagation"
}
Write-Host ""

# ================================================================
# FINAL REPORT
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FIX AND TEST COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$totalTests = $passedTests + $failedTests
$successRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

Write-Host "TEST RESULTS SUMMARY:" -ForegroundColor Magenta
Write-Host "  Total Tests:  $totalTests" -ForegroundColor White
Write-Host "  Passed:       $passedTests" -ForegroundColor Green
Write-Host "  Failed:       $failedTests" -ForegroundColor Red
Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 75) { "Green" } else { "Yellow" })
Write-Host ""

Write-Host "DETAILED RESULTS:" -ForegroundColor Magenta
foreach ($result in $testResults) {
    if ($result -like "*PASS*") {
        Write-Host "  $result" -ForegroundColor Green
    } elseif ($result -like "*FAIL*") {
        Write-Host "  $result" -ForegroundColor Red
    } else {
        Write-Host "  $result" -ForegroundColor Yellow
    }
}
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  Load Balancer IP: $currentLoadBalancerIP" -ForegroundColor Cyan
Write-Host "  Front Door:       https://$endpointHostname" -ForegroundColor Cyan
Write-Host "  Custom Domain:    https://$($config.CustomDomain)" -ForegroundColor Cyan
Write-Host ""

Write-Host "QUICK ACCESS:" -ForegroundColor Magenta
Write-Host "  SFTP:   sftp username@$currentLoadBalancerIP" -ForegroundColor Green
Write-Host "  HTTPS:  https://$endpointHostname" -ForegroundColor Green
Write-Host "  Custom: https://$($config.CustomDomain)" -ForegroundColor Green
Write-Host ""

if ($failedTests -gt 0) {
    Write-Host "TROUBLESHOOTING:" -ForegroundColor Yellow
    Write-Host "  1. If SFTP fails: Check MOVEit server is running on 192.168.0.5" -ForegroundColor Yellow
    Write-Host "  2. If HTTPS fails: Wait 5 minutes and run this script again" -ForegroundColor Yellow
    Write-Host "  3. If DNS fails: Wait 10-30 minutes for DNS propagation" -ForegroundColor Yellow
    Write-Host "  4. Check Azure Portal > Front Door > Origins for configuration" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "NEXT STEPS:" -ForegroundColor Magenta
if ($failedTests -eq 0) {
    Write-Host "  All tests passed! Your deployment is LIVE!" -ForegroundColor Green
    Write-Host "  Users can connect via SFTP on port 22" -ForegroundColor Green
    Write-Host "  HTTPS access is available via Front Door" -ForegroundColor Green
} else {
    Write-Host "  1. Wait 10 minutes for DNS propagation" -ForegroundColor Yellow
    Write-Host "  2. Run this script again to retest" -ForegroundColor Yellow
    Write-Host "  3. If issues persist, check Azure Portal resources" -ForegroundColor Yellow
}
Write-Host ""

# Save results
$resultsFile = "$env:USERPROFILE\Desktop\MOVEit-Fix-Results.txt"
$testResults | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Log "Results saved to: $resultsFile" "Green"
Write-Host ""
