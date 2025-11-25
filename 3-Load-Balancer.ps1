# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 3 OF 5
# LOAD BALANCER - PORT 22 ONLY
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 3 OF 5: LOAD BALANCER (PORT 22)" -ForegroundColor Cyan
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
# CREATE LOAD BALANCER WITH PORT 22
# ----------------------------------------------------------------
$LBName = "lb-moveit-sftp"
$PublicIPName = "pip-moveit-sftp"

Write-Log "Creating public IP for Load Balancer..." "Cyan"
$ipExists = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $PublicIPName 2>$null
if (-not $ipExists) {
    az network public-ip create `
        --resource-group $config.DeploymentResourceGroup `
        --name $PublicIPName `
        --sku Standard `
        --allocation-method Static `
        --location $config.Location `
        --output none
    Write-Log "Public IP created" "Green"
} else {
    Write-Log "Public IP already exists" "Yellow"
}

Write-Host ""
Write-Log "Creating Load Balancer..." "Cyan"
$lbExists = az network lb show --resource-group $config.DeploymentResourceGroup --name $LBName 2>$null
if (-not $lbExists) {
    az network lb create `
        --resource-group $config.DeploymentResourceGroup `
        --name $LBName `
        --sku Standard `
        --public-ip-address $PublicIPName `
        --frontend-ip-name "LoadBalancerFrontEnd" `
        --backend-pool-name "backend-pool-lb" `
        --location $config.Location `
        --output none
    
    Write-Log "Load Balancer created" "Green"
    
    # Add backend pool address
    Write-Host ""
    Write-Log "Adding MOVEit server to backend pool..." "Yellow"
    $vnetId = az network vnet show --resource-group $config.NetworkResourceGroup --name $config.VNetName --query id --output tsv
    
    az network lb address-pool address add `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $LBName `
        --pool-name "backend-pool-lb" `
        --name "moveit-backend" `
        --vnet $vnetId `
        --ip-address $config.MOVEitPrivateIP `
        --output none
    
    Write-Log "Backend pool configured" "Green"
    
    # Create health probe
    Write-Host ""
    Write-Log "Creating health probe for port 22..." "Yellow"
    az network lb probe create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $LBName `
        --name "health-probe-sftp" `
        --protocol tcp `
        --port 22 `
        --interval 15 `
        --threshold 2 `
        --output none
    
    Write-Log "Health probe created" "Green"
    
    # Create load balancing rule for port 22
    Write-Host ""
    Write-Log "Creating load balancing rule for port 22..." "Yellow"
    az network lb rule create `
        --resource-group $config.DeploymentResourceGroup `
        --lb-name $LBName `
        --name "lb-rule-sftp-22" `
        --protocol Tcp `
        --frontend-port 22 `
        --backend-port 22 `
        --frontend-ip-name "LoadBalancerFrontEnd" `
        --backend-pool-name "backend-pool-lb" `
        --probe-name "health-probe-sftp" `
        --idle-timeout 30 `
        --enable-tcp-reset true `
        --output none
    
    Write-Log "Load balancing rule created" "Green"
} else {
    Write-Log "Load Balancer already exists" "Yellow"
}

# Get public IP
$publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $PublicIPName --query ipAddress --output tsv

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 3 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "LOAD BALANCER CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Name: $LBName" -ForegroundColor White
Write-Host "  Public IP: $publicIP" -ForegroundColor Green
Write-Host "  Port 22 (SFTP): CONFIGURED" -ForegroundColor Green
Write-Host "  Backend: $($config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host "  Health Probe: Active on port 22" -ForegroundColor White
Write-Host ""
Write-Host "USERS CAN NOW CONNECT:" -ForegroundColor Yellow
Write-Host "  sftp username@$publicIP" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT: Run Script 4 - WAF and Front Door" -ForegroundColor Yellow
Write-Host ""
