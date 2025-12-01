# ================================================================
# FIX BACKEND POOL - CORRECT MOVEit SERVER
# ================================================================
# Client confirmed: MOVEit is vm-moveit-xfr at 192.168.0.5
# NIC: nic-moveit-transfer
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FIX BACKEND POOL - CORRECT MOVEit SERVER" -ForegroundColor Cyan
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
$loadBalancerName = "lb-moveit-sftp"
$backendPoolName = "moveit-backend-pool"
$correctNicName = "nic-moveit-transfer"
$wrongNicName = "nic-moveit-automation"
$correctIP = "192.168.0.5"
$wrongIP = "192.168.0.4"
$correctVmName = "vm-moveit-xfr"

Write-Host "CORRECT MOVEit SERVER:" -ForegroundColor Magenta
Write-Host "  VM Name:  $correctVmName" -ForegroundColor Cyan
Write-Host "  NIC:      $correctNicName" -ForegroundColor Cyan
Write-Host "  IP:       $correctIP" -ForegroundColor Cyan
Write-Host ""

# ================================================================
# STEP 1: REMOVE WRONG NIC FROM BACKEND POOL (if present)
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: CHECKING FOR WRONG NIC (192.168.0.4)" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking if wrong NIC ($wrongNicName) is in backend pool..." "Yellow"

$wrongNic = az network nic show `
    --resource-group $resourceGroup `
    --name $wrongNicName `
    2>$null | ConvertFrom-Json

if ($wrongNic) {
    $wrongNicIpConfig = $wrongNic.ipConfigurations[0].name
    
    # Check if in backend pool
    $inPool = $false
    if ($wrongNic.ipConfigurations[0].loadBalancerBackendAddressPools) {
        $pools = $wrongNic.ipConfigurations[0].loadBalancerBackendAddressPools
        foreach ($pool in $pools) {
            if ($pool.id -like "*$backendPoolName*") {
                $inPool = $true
                break
            }
        }
    }
    
    if ($inPool) {
        Write-Log "Removing wrong NIC from backend pool..." "Yellow"
        
        az network nic ip-config address-pool remove `
            --resource-group $resourceGroup `
            --nic-name $wrongNicName `
            --ip-config-name $wrongNicIpConfig `
            --lb-name $loadBalancerName `
            --address-pool $backendPoolName `
            --output none `
            2>$null
        
        Write-Log "Wrong NIC removed!" "Green"
    } else {
        Write-Log "Wrong NIC is not in backend pool (OK)" "Yellow"
    }
} else {
    Write-Log "Wrong NIC not found (OK)" "Yellow"
}
Write-Host ""

# ================================================================
# STEP 2: ADD CORRECT NIC TO BACKEND POOL
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: ADDING CORRECT NIC (192.168.0.5)" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Getting correct MOVEit NIC: $correctNicName" "Yellow"

$correctNic = az network nic show `
    --resource-group $resourceGroup `
    --name $correctNicName `
    2>$null | ConvertFrom-Json

if (-not $correctNic) {
    Write-Host "ERROR: Cannot find correct NIC: $correctNicName" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available NICs:" -ForegroundColor Yellow
    az network nic list --resource-group $resourceGroup --query "[].{Name:name, IP:ipConfigurations[0].privateIPAddress}" -o table
    exit 1
}

Write-Log "Found correct MOVEit NIC!" "Green"
Write-Log "  NIC Name:     $correctNicName" "Cyan"
Write-Log "  IP Address:   $($correctNic.ipConfigurations[0].privateIPAddress)" "Cyan"
if ($correctNic.virtualMachine) {
    Write-Log "  Attached to:  $($correctNic.virtualMachine.id.Split('/')[-1])" "Cyan"
}
Write-Host ""

# Get IP config name
$correctNicIpConfig = $correctNic.ipConfigurations[0].name

# Check if already in backend pool
$alreadyInPool = $false
if ($correctNic.ipConfigurations[0].loadBalancerBackendAddressPools) {
    $pools = $correctNic.ipConfigurations[0].loadBalancerBackendAddressPools
    foreach ($pool in $pools) {
        if ($pool.id -like "*$backendPoolName*") {
            $alreadyInPool = $true
            break
        }
    }
}

if ($alreadyInPool) {
    Write-Log "Correct MOVEit NIC is already in backend pool!" "Green"
} else {
    Write-Log "Adding correct MOVEit NIC to backend pool..." "Yellow"
    
    az network nic ip-config address-pool add `
        --resource-group $resourceGroup `
        --nic-name $correctNicName `
        --ip-config-name $correctNicIpConfig `
        --lb-name $loadBalancerName `
        --address-pool $backendPoolName `
        --output none
    
    Write-Log "Correct MOVEit NIC added to backend pool!" "Green"
}
Write-Host ""

# ================================================================
# STEP 3: VERIFY CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: VERIFYING CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking backend pool members..." "Yellow"

$backendMembers = az network lb address-pool show `
    --resource-group $resourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    --query "backendIPConfigurations[].{NIC:id.split('/')[-3], IP:privateIPAddress}" `
    --output json | ConvertFrom-Json

if ($backendMembers -and $backendMembers.Count -gt 0) {
    Write-Host "Backend Pool Members:" -ForegroundColor Cyan
    foreach ($member in $backendMembers) {
        $nicName = $member.NIC
        $ip = $member.IP
        
        if ($ip -eq $correctIP) {
            Write-Host "  ✅ $nicName (IP: $ip) ← CORRECT MOVEit!" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $nicName (IP: $ip) ← WRONG!" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  No members in backend pool! (ERROR)" -ForegroundColor Red
}
Write-Host ""

# ================================================================
# STEP 4: WAIT FOR CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 4: WAITING FOR CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Waiting 30 seconds for backend pool configuration to propagate..." "Yellow"
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "`r  Waiting: $i seconds..." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host ""
Write-Log "Wait complete!" "Green"
Write-Host ""

# ================================================================
# STEP 5: TEST SFTP CONNECTIVITY
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 5: TESTING SFTP CONNECTIVITY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

# Get Load Balancer public IP
$loadBalancerIP = az network public-ip show `
    --resource-group $resourceGroup `
    --name $config.PublicIPName `
    --query ipAddress `
    --output tsv

Write-Log "Load Balancer Public IP: $loadBalancerIP" "Cyan"
Write-Host ""

# Test SFTP port
Write-Log "Testing SFTP port (22) on $loadBalancerIP..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($loadBalancerIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is NOW ACCESSIBLE!" "Green"
    $sftpWorks = $true
} catch {
    Write-Log "[FAIL] SFTP port 22 is still not accessible" "Red"
    Write-Log "       Error: $($_.Exception.Message)" "Yellow"
    $sftpWorks = $false
}
Write-Host ""

# ================================================================
# FINAL SUMMARY
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "BACKEND POOL FIX COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "CORRECT CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  MOVEit VM:        $correctVmName" -ForegroundColor Cyan
Write-Host "  MOVEit NIC:       $correctNicName" -ForegroundColor Cyan
Write-Host "  MOVEit IP:        $correctIP" -ForegroundColor Cyan
Write-Host "  Load Balancer:    $loadBalancerName" -ForegroundColor Cyan
Write-Host "  Backend Pool:     $backendPoolName" -ForegroundColor Cyan
Write-Host "  LB Public IP:     $loadBalancerIP" -ForegroundColor Cyan
Write-Host ""

Write-Host "STATUS:" -ForegroundColor Magenta
if ($sftpWorks) {
    Write-Host "  SFTP Access:      ✅ WORKING!" -ForegroundColor Green
    Write-Host ""
    Write-Host "QUICK ACCESS:" -ForegroundColor Magenta
    Write-Host "  SFTP:  sftp username@$loadBalancerIP" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Magenta
    Write-Host "  1. Wait for DNS/certificate (check after 30 min)" -ForegroundColor Yellow
    Write-Host "  2. Run .\FIX-AND-TEST.ps1 to verify everything" -ForegroundColor Yellow
    Write-Host "  3. Test: https://moveit.pyxhealth.com" -ForegroundColor Yellow
    Write-Host "  4. YOUR DEPLOYMENT IS LIVE! 🎉" -ForegroundColor Green
} else {
    Write-Host "  SFTP Access:      ❌ STILL NOT WORKING" -ForegroundColor Red
    Write-Host ""
    Write-Host "TROUBLESHOOTING:" -ForegroundColor Yellow
    Write-Host "  Backend pool is now correctly configured with:" -ForegroundColor Yellow
    Write-Host "    - MOVEit VM: $correctVmName" -ForegroundColor White
    Write-Host "    - IP: $correctIP" -ForegroundColor White
    Write-Host ""
    Write-Host "  If SFTP still fails, check:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. RDP to MOVEit VM: $correctVmName" -ForegroundColor White
    Write-Host "     - Is MOVEit Transfer service running?" -ForegroundColor Gray
    Write-Host "     - Run: netstat -an | findstr :22" -ForegroundColor Gray
    Write-Host "     - Should show: TCP 0.0.0.0:22 LISTENING" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Check Windows Firewall on MOVEit VM:" -ForegroundColor White
    Write-Host "     - Is port 22 allowed inbound?" -ForegroundColor Gray
    Write-Host "     - Run: Get-NetFirewallRule -DisplayName '*SSH*' | Select DisplayName, Enabled" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Verify MOVEit SSH/SFTP is configured:" -ForegroundColor White
    Write-Host "     - Open MOVEit Admin interface" -ForegroundColor Gray
    Write-Host "     - Check Settings > SSH/SFTP Settings" -ForegroundColor Gray
    Write-Host "     - Ensure SFTP is enabled on port 22" -ForegroundColor Gray
    Write-Host ""
}
Write-Host ""
