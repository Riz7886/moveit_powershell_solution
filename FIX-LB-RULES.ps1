# ================================================================
# FIX LOAD BALANCER RULES AND HEALTH PROBE
# ================================================================
# Description: Adds port 22 forwarding rules to Load Balancer
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FIX LOAD BALANCER RULES AND HEALTH PROBE" -ForegroundColor Cyan
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

$loadBalancerName = "lb-moveit-sftp"
$backendPoolName = "moveit-backend-pool"
$healthProbeName = "moveit-health-probe"
$lbRuleName = "moveit-sftp-rule"

# ================================================================
# STEP 1: CREATE HEALTH PROBE
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: CREATING HEALTH PROBE" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking if health probe exists..." "Yellow"

$probeExists = az network lb probe show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $healthProbeName `
    2>$null

if ($probeExists) {
    Write-Log "Health probe already exists" "Green"
} else {
    Write-Log "Creating health probe on port 22..." "Yellow"
    
    az network lb probe create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $loadBalancerName `
        --name $healthProbeName `
        --protocol tcp `
        --port 22 `
        --interval 15 `
        --threshold 2 `
        --output none
    
    Write-Log "Health probe created!" "Green"
}
Write-Host ""

# ================================================================
# STEP 2: CREATE LOAD BALANCING RULE FOR PORT 22
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: CREATING LOAD BALANCING RULE" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking if load balancing rule exists..." "Yellow"

$ruleExists = az network lb rule show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $lbRuleName `
    2>$null

if ($ruleExists) {
    Write-Log "Load balancing rule already exists" "Green"
} else {
    Write-Log "Creating load balancing rule for port 22..." "Yellow"
    
    # Get frontend IP configuration name
    $frontendIPName = az network lb frontend-ip list `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $loadBalancerName `
        --query "[0].name" `
        --output tsv
    
    Write-Log "Frontend IP: $frontendIPName" "Cyan"
    
    az network lb rule create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $loadBalancerName `
        --name $lbRuleName `
        --protocol tcp `
        --frontend-port 22 `
        --backend-port 22 `
        --frontend-ip-name $frontendIPName `
        --backend-pool-name $backendPoolName `
        --probe-name $healthProbeName `
        --idle-timeout 4 `
        --output none
    
    Write-Log "Load balancing rule created!" "Green"
}
Write-Host ""

# ================================================================
# STEP 3: VERIFY CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: VERIFYING CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking Load Balancer configuration..." "Yellow"

# Check health probe
Write-Host "Health Probe:" -ForegroundColor Cyan
$probe = az network lb probe show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $healthProbeName `
    --query "{Protocol:protocol, Port:port, Interval:intervalInSeconds, Threshold:numberOfProbes}" `
    --output json | ConvertFrom-Json

Write-Host "  Protocol: $($probe.Protocol)" -ForegroundColor White
Write-Host "  Port: $($probe.Port)" -ForegroundColor White
Write-Host "  Interval: $($probe.Interval) seconds" -ForegroundColor White
Write-Host "  Threshold: $($probe.Threshold) failed probes" -ForegroundColor White
Write-Host ""

# Check load balancing rule
Write-Host "Load Balancing Rule:" -ForegroundColor Cyan
$rule = az network lb rule show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $lbRuleName `
    --query "{Protocol:protocol, FrontendPort:frontendPort, BackendPort:backendPort, IdleTimeout:idleTimeoutInMinutes}" `
    --output json | ConvertFrom-Json

Write-Host "  Protocol: $($rule.Protocol)" -ForegroundColor White
Write-Host "  Frontend Port: $($rule.FrontendPort)" -ForegroundColor White
Write-Host "  Backend Port: $($rule.BackendPort)" -ForegroundColor White
Write-Host "  Idle Timeout: $($rule.IdleTimeout) minutes" -ForegroundColor White
Write-Host ""

# Check backend pool
Write-Host "Backend Pool:" -ForegroundColor Cyan
$backendMembers = az network lb address-pool show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    --query "backendIPConfigurations[].{PrivateIP:privateIPAddress}" `
    --output json | ConvertFrom-Json

if ($backendMembers -and $backendMembers.Count -gt 0) {
    Write-Host "  Members: $($backendMembers.Count)" -ForegroundColor White
    foreach ($member in $backendMembers) {
        Write-Host "    - $($member.PrivateIP)" -ForegroundColor White
    }
} else {
    Write-Host "  Members: 0 (ERROR!)" -ForegroundColor Red
}
Write-Host ""

# ================================================================
# STEP 4: WAIT FOR CONFIGURATION TO PROPAGATE
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 4: WAITING FOR CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Waiting 30 seconds for Load Balancer configuration to propagate..." "Yellow"
for ($i = 30; $i -gt 0; $i--) {
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
Write-Host "STEP 5: TESTING SFTP CONNECTIVITY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

# Get Load Balancer public IP
$loadBalancerIP = az network public-ip show `
    --resource-group $config.DeploymentResourceGroup `
    --name $config.PublicIPName `
    --query ipAddress `
    --output tsv

Write-Log "Load Balancer IP: $loadBalancerIP" "Cyan"
Write-Host ""

# Test SFTP port
Write-Log "Testing SFTP port (22)..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($loadBalancerIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is NOW ACCESSIBLE!" "Green"
    $sftpWorks = $true
} catch {
    Write-Log "[FAIL] SFTP port 22 is still not accessible" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Yellow"
    Write-Log "       This might mean MOVEit service is not running on 192.168.0.5" "Yellow"
    $sftpWorks = $false
}
Write-Host ""

# ================================================================
# FINAL SUMMARY
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "LOAD BALANCER FIX COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  Load Balancer:    $loadBalancerName" -ForegroundColor Cyan
Write-Host "  Backend Pool:     $backendPoolName" -ForegroundColor Cyan
Write-Host "  Health Probe:     $healthProbeName (TCP port 22)" -ForegroundColor Cyan
Write-Host "  LB Rule:          $lbRuleName (22 -> 22)" -ForegroundColor Cyan
Write-Host "  Public IP:        $loadBalancerIP" -ForegroundColor Cyan
Write-Host ""

Write-Host "STATUS:" -ForegroundColor Magenta
if ($sftpWorks) {
    Write-Host "  SFTP Access:      ✅ WORKING!" -ForegroundColor Green
} else {
    Write-Host "  SFTP Access:      ❌ NOT YET" -ForegroundColor Red
}
Write-Host ""

Write-Host "QUICK ACCESS:" -ForegroundColor Magenta
Write-Host "  SFTP:  sftp username@$loadBalancerIP" -ForegroundColor Green
Write-Host ""

if ($sftpWorks) {
    Write-Host "NEXT STEPS:" -ForegroundColor Magenta
    Write-Host "  1. Run .\FIX-AND-TEST.ps1 to test Front Door and custom domain" -ForegroundColor Yellow
    Write-Host "  2. Your deployment is READY TO GO LIVE! 🎉" -ForegroundColor Green
} else {
    Write-Host "TROUBLESHOOTING:" -ForegroundColor Yellow
    Write-Host "  The Load Balancer is now fully configured, but SFTP still fails." -ForegroundColor Yellow
    Write-Host "  This means the issue is with the MOVEit VM (192.168.0.5):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Check these things:" -ForegroundColor Cyan
    Write-Host "    1. Is MOVEit VM running?" -ForegroundColor White
    Write-Host "       az vm list --resource-group rg-moveit --query '[].{Name:name, Status:powerState}' -o table" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    2. RDP to MOVEit VM (192.168.0.5) and check:" -ForegroundColor White
    Write-Host "       - Is MOVEit Transfer service running?" -ForegroundColor Gray
    Write-Host "       - Run: netstat -an | findstr :22" -ForegroundColor Gray
    Write-Host "       - Should show: TCP 0.0.0.0:22 LISTENING" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    3. Check Windows Firewall on MOVEit VM:" -ForegroundColor White
    Write-Host "       - Is port 22 allowed inbound?" -ForegroundColor Gray
    Write-Host ""
}
Write-Host ""
