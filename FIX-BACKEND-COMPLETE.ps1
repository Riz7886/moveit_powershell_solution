# ================================================================
# COMPREHENSIVE BACKEND POOL FIX
# ================================================================
# Description: Creates backend pool and adds MOVEit VM to it
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "COMPREHENSIVE BACKEND POOL FIX" -ForegroundColor Cyan
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
Write-Log "MOVEit Private IP: $($config.MOVEitPrivateIP)" "Yellow"
Write-Host ""

$loadBalancerName = "lb-moveit-sftp"
$backendPoolName = "moveit-backend-pool"

# ================================================================
# STEP 1: CHECK IF BACKEND POOL EXISTS
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: CHECKING BACKEND POOL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking if backend pool exists..." "Yellow"

$poolExists = az network lb address-pool show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    2>$null

if ($poolExists) {
    Write-Log "Backend pool '$backendPoolName' already exists" "Green"
} else {
    Write-Log "Backend pool '$backendPoolName' does NOT exist" "Yellow"
    Write-Log "Creating backend pool..." "Yellow"
    
    az network lb address-pool create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $loadBalancerName `
        --name $backendPoolName `
        --output none
    
    Write-Log "Backend pool created!" "Green"
}
Write-Host ""

# ================================================================
# STEP 2: GET MOVEIT VM NETWORK INTERFACE
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: FINDING MOVEIT VM NETWORK INTERFACE" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Searching for MOVEit VM network interface..." "Yellow"

# Find the NIC with IP 192.168.0.5
$nicInfo = az network nic list `
    --resource-group $config.DeploymentResourceGroup `
    --query "[?ipConfigurations[0].privateIPAddress=='$($config.MOVEitPrivateIP)']" `
    --output json | ConvertFrom-Json

if (-not $nicInfo -or $nicInfo.Count -eq 0) {
    Write-Log "ERROR: Could not find network interface with IP $($config.MOVEitPrivateIP)" "Red"
    Write-Log "Searching for ANY MOVEit VM..." "Yellow"
    
    # Try to find any VM with "moveit" in the name
    $allNics = az network nic list `
        --resource-group $config.DeploymentResourceGroup `
        --output json | ConvertFrom-Json
    
    Write-Host ""
    Write-Host "AVAILABLE NETWORK INTERFACES:" -ForegroundColor Cyan
    foreach ($nic in $allNics) {
        $ip = $nic.ipConfigurations[0].privateIPAddress
        Write-Host "  NIC: $($nic.name) - IP: $ip" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Log "ERROR: Could not find MOVEit VM!" "Red"
    Write-Log "Please verify the MOVEit VM exists and is in this resource group" "Yellow"
    exit 1
}

$nicName = $nicInfo[0].name
$ipConfigName = $nicInfo[0].ipConfigurations[0].name

Write-Log "Found MOVEit VM network interface:" "Green"
Write-Log "  NIC Name: $nicName" "Cyan"
Write-Log "  IP Config: $ipConfigName" "Cyan"
Write-Log "  Private IP: $($config.MOVEitPrivateIP)" "Cyan"
Write-Host ""

# ================================================================
# STEP 3: CHECK IF NIC IS ALREADY IN BACKEND POOL
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: CHECKING IF NIC IS ALREADY IN BACKEND POOL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking current NIC configuration..." "Yellow"

$nicDetails = az network nic show `
    --resource-group $config.DeploymentResourceGroup `
    --name $nicName `
    --output json | ConvertFrom-Json

$currentPools = $nicDetails.ipConfigurations[0].loadBalancerBackendAddressPools

if ($currentPools -and $currentPools.Count -gt 0) {
    Write-Log "NIC is already in backend pool(s):" "Yellow"
    foreach ($pool in $currentPools) {
        Write-Log "  - $($pool.id)" "Cyan"
    }
    
    # Check if it's our specific pool
    $inCorrectPool = $currentPools | Where-Object { $_.id -like "*$backendPoolName*" }
    if ($inCorrectPool) {
        Write-Log "NIC is already in the correct backend pool!" "Green"
        $needsToAdd = $false
    } else {
        Write-Log "NIC is in a different pool, will add to correct pool..." "Yellow"
        $needsToAdd = $true
    }
} else {
    Write-Log "NIC is not in any backend pool yet" "Yellow"
    $needsToAdd = $true
}
Write-Host ""

# ================================================================
# STEP 4: ADD NIC TO BACKEND POOL (IF NEEDED)
# ================================================================
if ($needsToAdd) {
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host "STEP 4: ADDING NIC TO BACKEND POOL" -ForegroundColor Magenta
    Write-Host "================================================================" -ForegroundColor Magenta
    Write-Host ""

    Write-Log "Adding MOVEit VM to backend pool..." "Yellow"

    az network nic ip-config address-pool add `
        --resource-group $config.DeploymentResourceGroup `
        --nic-name $nicName `
        --ip-config-name $ipConfigName `
        --lb-name $loadBalancerName `
        --address-pool $backendPoolName `
        --output none

    Write-Log "MOVEit VM added to backend pool!" "Green"
    Write-Host ""
} else {
    Write-Log "Skipping NIC addition - already configured" "Green"
    Write-Host ""
}

# ================================================================
# STEP 5: VERIFY CONFIGURATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 5: VERIFYING CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking Load Balancer configuration..." "Yellow"

# Get backend pool members
$backendMembers = az network lb address-pool show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    --query "backendIPConfigurations[]" `
    --output json | ConvertFrom-Json

if ($backendMembers -and $backendMembers.Count -gt 0) {
    Write-Log "Backend pool has $($backendMembers.Count) member(s):" "Green"
    foreach ($member in $backendMembers) {
        # Extract NIC name from ID
        $nicNameFromId = ($member.id -split '/')[-3]
        Write-Log "  - NIC: $nicNameFromId" "Cyan"
    }
} else {
    Write-Log "WARNING: Backend pool appears empty!" "Red"
}
Write-Host ""

# Get Load Balancer public IP
$loadBalancerIP = az network public-ip show `
    --resource-group $config.DeploymentResourceGroup `
    --name $config.PublicIPName `
    --query ipAddress `
    --output tsv

Write-Log "Load Balancer Public IP: $loadBalancerIP" "Cyan"
Write-Host ""

# ================================================================
# STEP 6: TEST CONNECTIVITY
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 6: TESTING CONNECTIVITY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Waiting 10 seconds for configuration to propagate..." "Yellow"
Start-Sleep -Seconds 10
Write-Host ""

Write-Log "Testing SFTP port (22)..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($loadBalancerIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is accessible!" "Green"
    $sftpWorks = $true
} catch {
    Write-Log "[FAIL] SFTP port 22 is not yet accessible" "Red"
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

Write-Host "CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  Load Balancer:    $loadBalancerName" -ForegroundColor Cyan
Write-Host "  Backend Pool:     $backendPoolName" -ForegroundColor Cyan
Write-Host "  Backend VM:       MOVEit ($($config.MOVEitPrivateIP))" -ForegroundColor Cyan
Write-Host "  Public IP:        $loadBalancerIP" -ForegroundColor Cyan
Write-Host ""

Write-Host "STATUS:" -ForegroundColor Magenta
if ($sftpWorks) {
    Write-Host "  SFTP Access:      WORKING! ✅" -ForegroundColor Green
} else {
    Write-Host "  SFTP Access:      NOT YET (wait 2 minutes) ⏳" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "QUICK ACCESS:" -ForegroundColor Magenta
Write-Host "  SFTP:  sftp username@$loadBalancerIP" -ForegroundColor Green
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Magenta
if ($sftpWorks) {
    Write-Host "  1. Run .\FIX-AND-TEST.ps1 to verify Front Door" -ForegroundColor Yellow
    Write-Host "  2. Everything should now work!" -ForegroundColor Green
} else {
    Write-Host "  1. Wait 2 minutes for changes to propagate" -ForegroundColor Yellow
    Write-Host "  2. Check MOVEit VM is running: 192.168.0.5" -ForegroundColor Yellow
    Write-Host "  3. Run .\FIX-AND-TEST.ps1 to test again" -ForegroundColor Yellow
}
Write-Host ""
