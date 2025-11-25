# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 2 OF 5
# NETWORK SECURITY GROUP (NSG) - PORT 22 ONLY
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 2 OF 5: NETWORK SECURITY (NSG)" -ForegroundColor Cyan
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
# CREATE NSG WITH PORT 22 ONLY
# ----------------------------------------------------------------
$NSGName = "nsg-moveit"

Write-Log "Creating Network Security Group..." "Cyan"
$nsgExists = az network nsg show --resource-group $config.NetworkResourceGroup --name $NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create --resource-group $config.NetworkResourceGroup --name $NSGName --location $config.Location --output none
    Write-Log "NSG created: $NSGName" "Green"
} else {
    Write-Log "NSG already exists: $NSGName" "Yellow"
}

Write-Host ""
Write-Log "Configuring NSG rules..." "Cyan"

# Rule 1: SFTP Port 22
Write-Log "  Adding rule: Allow SFTP port 22" "Yellow"
az network nsg rule create `
    --resource-group $config.NetworkResourceGroup `
    --nsg-name $NSGName `
    --name "Allow-SFTP-22" `
    --priority 100 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes '*' `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 22 `
    --output none 2>$null

# Rule 2: HTTPS Port 443
Write-Log "  Adding rule: Allow HTTPS port 443" "Yellow"
az network nsg rule create `
    --resource-group $config.NetworkResourceGroup `
    --nsg-name $NSGName `
    --name "Allow-HTTPS-443" `
    --priority 110 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefixes '*' `
    --source-port-ranges '*' `
    --destination-address-prefixes '*' `
    --destination-port-ranges 443 `
    --output none 2>$null

# Attach NSG to Subnet
Write-Log "Attaching NSG to subnet..." "Yellow"
az network vnet subnet update `
    --resource-group $config.NetworkResourceGroup `
    --vnet-name $config.VNetName `
    --name $config.SubnetName `
    --network-security-group $NSGName `
    --output none

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 2 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "NSG CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Name: $NSGName" -ForegroundColor White
Write-Host "  Port 22 (SFTP): ALLOWED" -ForegroundColor Green
Write-Host "  Port 443 (HTTPS): ALLOWED" -ForegroundColor Green
Write-Host "  Attached to: $($config.VNetName)/$($config.SubnetName)" -ForegroundColor White
Write-Host ""
Write-Host "NEXT: Run Script 3 - Load Balancer" -ForegroundColor Yellow
Write-Host ""
