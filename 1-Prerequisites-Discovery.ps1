# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 1 OF 5
# PREREQUISITES AND NETWORK DISCOVERY
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 1 OF 5: PREREQUISITES & DISCOVERY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------------
$global:config = @{
    MOVEitPrivateIP          = "192.168.0.5"
    Location                 = "westus"
    DeploymentResourceGroup  = "rg-moveit"
}

# ----------------------------------------------------------------
# STEP 1: CHECK AZURE CLI
# ----------------------------------------------------------------
Write-Log "Checking Azure CLI..." "Yellow"
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-Log "Azure CLI version: $($azVersion.'azure-cli')" "Green"
} catch {
    Write-Log "ERROR: Azure CLI not found!" "Red"
    Write-Log "Install from: https://aka.ms/installazurecliwindows" "Yellow"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN
# ----------------------------------------------------------------
Write-Log "Checking Azure login..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in. Starting login..." "Yellow"
    az login --use-device-code
} else {
    Write-Log "Already logged in" "Green"
}

# ----------------------------------------------------------------
# STEP 3: SELECT SUBSCRIPTION
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Log "============================================" "Cyan"

$subscriptions = az account list --output json | ConvertFrom-Json

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $stateColor = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($sub.name) " -NoNewline -ForegroundColor White
    Write-Host "($($sub.state))" -ForegroundColor $stateColor
}

Write-Host ""
$selection = Read-Host "Select subscription number"
$selectedSubscription = $subscriptions[[int]$selection - 1]
az account set --subscription $selectedSubscription.id
Write-Log "Active subscription: $($selectedSubscription.name)" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 4: AUTO-FIND NETWORK RESOURCES
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "DISCOVERING YOUR NETWORK" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Find network resource group
Write-Log "Looking for resource group with 'network' in name..." "Yellow"
$allRGs = az group list --output json | ConvertFrom-Json
$networkRG = $null

foreach ($rg in $allRGs) {
    if ($rg.name -like "*network*") {
        $networkRG = $rg.name
        Write-Log "FOUND: $networkRG" "Green"
        break
    }
}

if (-not $networkRG) {
    Write-Log "ERROR: No resource group with 'network' found!" "Red"
    Write-Log "Available resource groups:" "Yellow"
    foreach ($rg in $allRGs) {
        Write-Log "  - $($rg.name)" "White"
    }
    exit 1
}

$global:config.NetworkResourceGroup = $networkRG
Write-Log "Network RG: $networkRG" "Green"
Write-Host ""

# Find VNet
Write-Log "Looking for VNets..." "Yellow"
$allVNets = az network vnet list --resource-group $networkRG --output json 2>$null | ConvertFrom-Json

if (-not $allVNets -or $allVNets.Count -eq 0) {
    Write-Log "ERROR: No VNets found!" "Red"
    exit 1
}

Write-Log "FOUND VNets:" "Green"
foreach ($vnet in $allVNets) {
    Write-Log "  - $($vnet.name)" "Cyan"
}

# Select VNet
$selectedVNet = $null
foreach ($vnet in $allVNets) {
    if ($vnet.name -like "*prod*") {
        $selectedVNet = $vnet.name
        break
    }
}

if (-not $selectedVNet) {
    $selectedVNet = $allVNets[0].name
}

$global:config.VNetName = $selectedVNet
Write-Log "Selected VNet: $selectedVNet" "Green"
Write-Host ""

# Find Subnets
Write-Log "Looking for subnets..." "Yellow"
$vnetDetails = az network vnet show --resource-group $networkRG --name $selectedVNet --output json | ConvertFrom-Json
$allSubnets = $vnetDetails.subnets

Write-Log "FOUND Subnets:" "Green"
foreach ($subnet in $allSubnets) {
    Write-Log "  - $($subnet.name)" "Cyan"
}

# Select Subnet
$selectedSubnet = $null
foreach ($subnet in $allSubnets) {
    if ($subnet.name -like "*moveit*") {
        $selectedSubnet = $subnet.name
        break
    }
}

if (-not $selectedSubnet) {
    $selectedSubnet = $allSubnets[0].name
}

$global:config.SubnetName = $selectedSubnet
Write-Log "Selected Subnet: $selectedSubnet" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 5: CREATE DEPLOYMENT RG
# ----------------------------------------------------------------
Write-Log "Creating deployment resource group..." "Yellow"
$rgExists = az group show --name $global:config.DeploymentResourceGroup 2>$null
if (-not $rgExists) {
    az group create --name $global:config.DeploymentResourceGroup --location $global:config.Location --output none
    Write-Log "Created: $($global:config.DeploymentResourceGroup)" "Green"
} else {
    Write-Log "Already exists: $($global:config.DeploymentResourceGroup)" "Yellow"
}

# ----------------------------------------------------------------
# SAVE CONFIGURATION
# ----------------------------------------------------------------
$configFile = "$env:TEMP\moveit-config.json"
$global:config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 1 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "DISCOVERED CONFIGURATION:" -ForegroundColor Cyan
Write-Host "  Network RG: $($global:config.NetworkResourceGroup)" -ForegroundColor White
Write-Host "  VNet: $($global:config.VNetName)" -ForegroundColor White
Write-Host "  Subnet: $($global:config.SubnetName)" -ForegroundColor White
Write-Host "  MOVEit IP: $($global:config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host "  Deployment RG: $($global:config.DeploymentResourceGroup)" -ForegroundColor White
Write-Host ""
Write-Host "Configuration saved to: $configFile" -ForegroundColor Gray
Write-Host ""
Write-Host "NEXT: Run Script 2 - Network Security (NSG)" -ForegroundColor Yellow
Write-Host ""
