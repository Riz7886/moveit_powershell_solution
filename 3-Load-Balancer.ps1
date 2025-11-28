# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 3 OF 7
# LOAD BALANCER (PORT 22)
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 3 OF 7: LOAD BALANCER (PORT 22)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# LOAD CONFIGURATION
# ----------------------------------------------------------------
$configFile = "$env:TEMP\moveit-config.json"
if (-not (Test-Path $configFile)) {
    Write-Log "ERROR: Configuration not found! Run Script 1 first." "Red"
    exit 1
}

$config = Get-Content $configFile | ConvertFrom-Json
Write-Log "Configuration loaded" "Green"
Write-Host ""

# ----------------------------------------------------------------
# CREATE PUBLIC IP
# ----------------------------------------------------------------
Write-Log "Creating public IP for Load Balancer..." "Cyan"
$pipExists = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName 2>$null
if (-not $pipExists) {
    az network public-ip create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.PublicIPName `
        --sku Standard `
        --allocation-method Static `
        --location $config.Location `
        --output none
    
    Write-Log "Public IP created" "Green"
} else {
    Write-Log "Public IP already exists" "Yellow"
}

$publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv
Write-Log "Public IP: $publicIP" "Green"
Write-Host ""

# ----------------------------------------------------------------
# CREATE LOAD BALANCER
# ----------------------------------------------------------------
Write-Log "Creating Load Balancer..." "Cyan"
$lbExists = az network lb show --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerName 2>$null
if (-not $lbExists) {
    az network lb create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.LoadBalancerName `
        --sku Standard `
        --public-ip-address $config.PublicIPName `
        --frontend-ip-name "frontend-sftp" `
        --backend-pool-name $config.BackendPoolName `
        --location $config.Location `
        --output none
    
    Write-Log "Load Balancer created" "Green"
} else {
    Write-Log "Load Balancer already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# ADD MOVEIT TO BACKEND POOL
# ----------------------------------------------------------------
Write-Log "Adding MOVEit server to backend pool..." "Yellow"

# Get NIC of MOVEit server
$moveitNIC = az network nic list --query "[?ipConfigurations[0].privateIPAddress=='$($config.MOVEitPrivateIP)'].id" --output tsv

if ($moveitNIC) {
    az network nic ip-config address-pool add `
        --resource-group $config.NetworkResourceGroup `
        --nic-name (Split-Path $moveitNIC -Leaf) `
        --ip-config-name "ipconfig1" `
        --lb-name $config.LoadBalancerName `
        --address-pool $config.BackendPoolName `
        --output none 2>$null
    
    Write-Log "MOVEit added to backend pool" "Green"
} else {
    Write-Log "WARNING: Could not find MOVEit NIC. Add manually later." "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE HEALTH PROBE
# ----------------------------------------------------------------
Write-Log "Creating health probe for port 22..." "Yellow"
$probeExists = az network lb probe show --resource-group $config.DeploymentResourceGroup --lb-name $config.LoadBalancerName --name $config.HealthProbeName 2>$null
if (-not $probeExists) {
    az network lb probe create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name $config.HealthProbeName `
        --protocol Tcp `
        --port 22 `
        --interval 5 `
        --threshold 2 `
        --output none
    
    Write-Log "Health probe created" "Green"
} else {
    Write-Log "Health probe already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE LOAD BALANCING RULE
# ----------------------------------------------------------------
Write-Log "Creating load balancing rule for port 22..." "Yellow"
$ruleExists = az network lb rule show --resource-group $config.DeploymentResourceGroup --lb-name $config.LoadBalancerName --name $config.LoadBalancingRuleName 2>$null
if (-not $ruleExists) {
    az network lb rule create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $config.LoadBalancerName `
        --name $config.LoadBalancingRuleName `
        --protocol Tcp `
        --frontend-port 22 `
        --backend-port 22 `
        --frontend-ip-name "frontend-sftp" `
        --backend-pool-name $config.BackendPoolName `
        --probe-name $config.HealthProbeName `
        --disable-outbound-snat true `
        --idle-timeout 15 `
        --enable-tcp-reset true `
        --output none
    
    Write-Log "Load balancing rule created" "Green"
} else {
    Write-Log "Load balancing rule already exists" "Yellow"
}

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 3 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "LOAD BALANCER CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Name:         $($config.LoadBalancerName)" -ForegroundColor White
Write-Host "  Public IP:    $publicIP" -ForegroundColor Green
Write-Host "  Port:         22 (SFTP/SSH)" -ForegroundColor White
Write-Host "  Backend:      $($config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host "  Health Probe: TCP port 22" -ForegroundColor White
Write-Host ""
Write-Host "SFTP ACCESS:" -ForegroundColor Cyan
Write-Host "  sftp username@$publicIP" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT: Run Script 4 - WAF & Front Door" -ForegroundColor Yellow
Write-Host ""
