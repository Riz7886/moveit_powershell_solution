# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 2 OF 7
# NETWORK SECURITY (NSG)
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 2 OF 7: NETWORK SECURITY (NSG)" -ForegroundColor Cyan
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
# CREATE NSG
# ----------------------------------------------------------------
Write-Log "Creating Network Security Group..." "Cyan"
$nsgExists = az network nsg show --resource-group $config.DeploymentResourceGroup --name $config.NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.NSGName `
        --location $config.Location `
        --output none
    
    Write-Log "NSG created: $($config.NSGName)" "Green"
} else {
    Write-Log "NSG already exists: $($config.NSGName)" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# ADD NSG RULES
# ----------------------------------------------------------------
Write-Log "Configuring NSG rules..." "Cyan"

# Rule 1: Allow SFTP/SSH (Port 22)
Write-Log "Adding rule: Allow port 22 (SFTP/SSH)..." "Yellow"
$rule22Exists = az network nsg rule show --resource-group $config.DeploymentResourceGroup --nsg-name $config.NSGName --name "Allow-SFTP-22" 2>$null
if (-not $rule22Exists) {
    az network nsg rule create `
        --resource-group $config.DeploymentResourceGroup `
        --nsg-name $config.NSGName `
        --name "Allow-SFTP-22" `
        --priority 100 `
        --source-address-prefixes Internet `
        --source-port-ranges "*" `
        --destination-address-prefixes "*" `
        --destination-port-ranges 22 `
        --access Allow `
        --protocol Tcp `
        --direction Inbound `
        --output none
    
    Write-Log "Rule added: Allow-SFTP-22" "Green"
} else {
    Write-Log "Rule already exists: Allow-SFTP-22" "Yellow"
}

# Rule 2: Allow HTTPS (Port 443)
Write-Log "Adding rule: Allow port 443 (HTTPS)..." "Yellow"
$rule443Exists = az network nsg rule show --resource-group $config.DeploymentResourceGroup --nsg-name $config.NSGName --name "Allow-HTTPS-443" 2>$null
if (-not $rule443Exists) {
    az network nsg rule create `
        --resource-group $config.DeploymentResourceGroup `
        --nsg-name $config.NSGName `
        --name "Allow-HTTPS-443" `
        --priority 110 `
        --source-address-prefixes Internet `
        --source-port-ranges "*" `
        --destination-address-prefixes "*" `
        --destination-port-ranges 443 `
        --access Allow `
        --protocol Tcp `
        --direction Inbound `
        --output none
    
    Write-Log "Rule added: Allow-HTTPS-443" "Green"
} else {
    Write-Log "Rule already exists: Allow-HTTPS-443" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# ATTACH NSG TO SUBNET
# ----------------------------------------------------------------
Write-Log "Attaching NSG to subnet..." "Yellow"

$subnetId = "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/$($config.NetworkResourceGroup)/providers/Microsoft.Network/virtualNetworks/$($config.VNetName)/subnets/$($config.SubnetName)"

az network vnet subnet update `
    --resource-group $config.NetworkResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName `
    --network-security-group $config.NSGName `
    --output none

Write-Log "NSG attached to subnet" "Green"

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 2 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "NETWORK SECURITY CONFIGURED:" -ForegroundColor Cyan
Write-Host "  NSG: $($config.NSGName)" -ForegroundColor White
Write-Host "  Rules:" -ForegroundColor White
Write-Host "    - Allow port 22 (SFTP/SSH)" -ForegroundColor Green
Write-Host "    - Allow port 443 (HTTPS)" -ForegroundColor Green
Write-Host "  Attached to: $($config.SubnetName)" -ForegroundColor White
Write-Host ""
Write-Host "NEXT: Run Script 3 - Load Balancer" -ForegroundColor Yellow
Write-Host ""
