# ================================================================
# FIX LOAD BALANCER BACKEND POOL
# ================================================================
# Description: Adds MOVEit VM to Load Balancer backend pool
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FIX LOAD BALANCER BACKEND POOL" -ForegroundColor Cyan
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

# ================================================================
# STEP 1: GET MOVEIT VM NETWORK INTERFACE
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 1: FINDING MOVEIT VM NETWORK INTERFACE" -ForegroundColor Magenta
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
    Write-Log "Make sure the MOVEit VM exists in resource group: $($config.DeploymentResourceGroup)" "Yellow"
    exit 1
}

$nicId = $nicInfo[0].id
$nicName = $nicInfo[0].name
$ipConfigName = $nicInfo[0].ipConfigurations[0].name

Write-Log "Found MOVEit VM network interface:" "Green"
Write-Log "  NIC Name: $nicName" "Cyan"
Write-Log "  IP Config: $ipConfigName" "Cyan"
Write-Log "  Private IP: $($config.MOVEitPrivateIP)" "Cyan"
Write-Host ""

# ================================================================
# STEP 2: ADD NIC TO LOAD BALANCER BACKEND POOL
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 2: ADDING NIC TO LOAD BALANCER BACKEND POOL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$loadBalancerName = "lb-moveit-sftp"
$backendPoolName = "moveit-backend-pool"

Write-Log "Getting Load Balancer backend pool ID..." "Yellow"
$backendPoolId = az network lb address-pool show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    --query id `
    --output tsv

if (-not $backendPoolId) {
    Write-Log "ERROR: Could not find backend pool '$backendPoolName'" "Red"
    exit 1
}

Write-Log "Backend Pool ID: $backendPoolId" "Cyan"
Write-Host ""

Write-Log "Adding MOVEit VM to Load Balancer backend pool..." "Yellow"

# Update NIC to add backend pool
az network nic ip-config address-pool add `
    --resource-group $config.DeploymentResourceGroup `
    --nic-name $nicName `
    --ip-config-name $ipConfigName `
    --lb-name $loadBalancerName `
    --address-pool $backendPoolName `
    --output none

Write-Log "MOVEit VM added to backend pool!" "Green"
Write-Host ""

# ================================================================
# STEP 3: VERIFY BACKEND POOL
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 3: VERIFYING BACKEND POOL CONFIGURATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Checking backend pool members..." "Yellow"

$backendMembers = az network lb address-pool show `
    --resource-group $config.DeploymentResourceGroup `
    --lb-name $loadBalancerName `
    --name $backendPoolName `
    --query "backendIPConfigurations[].{Name:id, PrivateIP:privateIPAddress}" `
    --output json | ConvertFrom-Json

if ($backendMembers -and $backendMembers.Count -gt 0) {
    Write-Log "Backend pool now has $($backendMembers.Count) member(s):" "Green"
    foreach ($member in $backendMembers) {
        Write-Log "  - Private IP: $($member.PrivateIP)" "Cyan"
    }
} else {
    Write-Log "WARNING: Backend pool still appears empty!" "Red"
}
Write-Host ""

# ================================================================
# STEP 4: TEST LOAD BALANCER
# ================================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "STEP 4: TESTING LOAD BALANCER" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

Write-Log "Getting Load Balancer public IP..." "Yellow"
$loadBalancerIP = az network public-ip show `
    --resource-group $config.DeploymentResourceGroup `
    --name $config.PublicIPName `
    --query ipAddress `
    --output tsv

Write-Log "Load Balancer IP: $loadBalancerIP" "Cyan"
Write-Host ""

Write-Log "Testing SFTP port (22)..." "Yellow"
$tcpClient = New-Object System.Net.Sockets.TcpClient
try {
    $tcpClient.Connect($loadBalancerIP, 22)
    $tcpClient.Close()
    Write-Log "[PASS] SFTP port 22 is now accessible!" "Green"
} catch {
    Write-Log "[FAIL] SFTP port 22 is still not accessible" "Red"
    Write-Log "       Wait 1-2 minutes for configuration to propagate" "Yellow"
}
Write-Host ""

# ================================================================
# FINAL SUMMARY
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "BACKEND FIX COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "WHAT WAS FIXED:" -ForegroundColor Magenta
Write-Host "  - Added MOVEit VM ($($config.MOVEitPrivateIP)) to Load Balancer backend pool" -ForegroundColor Green
Write-Host "  - Load Balancer can now forward traffic to MOVEit" -ForegroundColor Green
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Magenta
Write-Host "  Load Balancer:  $loadBalancerName" -ForegroundColor Cyan
Write-Host "  Backend Pool:   $backendPoolName" -ForegroundColor Cyan
Write-Host "  Backend VM:     MOVEit ($($config.MOVEitPrivateIP))" -ForegroundColor Cyan
Write-Host "  Public IP:      $loadBalancerIP" -ForegroundColor Cyan
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Magenta
Write-Host "  1. Wait 2 minutes for changes to propagate" -ForegroundColor Yellow
Write-Host "  2. Run FIX-AND-TEST.ps1 again to verify everything works" -ForegroundColor Yellow
Write-Host "  3. Test SFTP: sftp username@$loadBalancerIP" -ForegroundColor Yellow
Write-Host ""

Write-Host "RUN THIS COMMAND IN 2 MINUTES:" -ForegroundColor Cyan
Write-Host "  .\FIX-AND-TEST.ps1" -ForegroundColor White
Write-Host ""
