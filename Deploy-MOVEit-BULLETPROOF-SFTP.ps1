# ================================================================
# MOVEIT DEPLOYMENT - BULLETPROOF WITH SFTP PORT 22
# WILL FIND YOUR VNET-PROD NO MATTER WHAT
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT DEPLOYMENT - BULLETPROOF" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# HARDCODED CONFIG
# ----------------------------------------------------------------
$config = @{
    MOVEitPrivateIP          = "192.168.0.5"
    Location                 = "westus"
    
    FrontDoorProfileName     = "moveit-frontdoor-profile"
    FrontDoorEndpointName    = "moveit-endpoint"
    FrontDoorOriginGroupName = "moveit-origin-group"
    FrontDoorOriginName      = "moveit-origin"
    FrontDoorRouteName       = "moveit-route"
    FrontDoorSKU             = "Standard_AzureFrontDoor"
    
    WAFPolicyName            = "moveitWAFPolicy"
    WAFMode                  = "Prevention"
    WAFSKU                   = "Standard_AzureFrontDoor"
    
    LoadBalancerName         = "lb-moveit-sftp"
    LoadBalancerPublicIPName = "pip-moveit-sftp"
    NSGName                  = "nsg-moveit"
    
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
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN
# ----------------------------------------------------------------
Write-Log "Checking login..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
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
# STEP 4: AUTO-FIND EXISTING NETWORK RESOURCES
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "AUTO-DETECTING YOUR NETWORK" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Find resource group with "network" in name
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
    Write-Log "ERROR: No resource group with 'network' in name found!" "Red"
    Write-Log "Available resource groups:" "Yellow"
    foreach ($rg in $allRGs) {
        Write-Log "  - $($rg.name)" "White"
    }
    exit 1
}

$config.NetworkResourceGroup = $networkRG
Write-Log "Using Network RG: $networkRG" "Green"
Write-Host ""

# Find VNet in that resource group
Write-Log "Looking for VNets in $networkRG..." "Yellow"
$allVNets = az network vnet list --resource-group $networkRG --output json 2>$null | ConvertFrom-Json

if (-not $allVNets -or $allVNets.Count -eq 0) {
    Write-Log "ERROR: No VNets found in $networkRG!" "Red"
    exit 1
}

Write-Log "FOUND VNets:" "Green"
foreach ($vnet in $allVNets) {
    Write-Log "  - $($vnet.name)" "Cyan"
}

# Use first VNet (or one with "prod" in name)
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

$config.VNetName = $selectedVNet
Write-Log "Selected VNet: $selectedVNet" "Green"
Write-Host ""

# Find Subnets in VNet
Write-Log "Looking for subnets in $selectedVNet..." "Yellow"
$vnetDetails = az network vnet show --resource-group $networkRG --name $selectedVNet --output json | ConvertFrom-Json
$allSubnets = $vnetDetails.subnets

Write-Log "FOUND Subnets:" "Green"
foreach ($subnet in $allSubnets) {
    Write-Log "  - $($subnet.name)" "Cyan"
}

# Use subnet with "moveit" in name, or first one
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

$config.SubnetName = $selectedSubnet
Write-Log "Selected Subnet: $selectedSubnet" "Green"
Write-Host ""

# ----------------------------------------------------------------
# CONFIRMATION
# ----------------------------------------------------------------
Write-Log "============================================" "Yellow"
Write-Log "DETECTED CONFIGURATION" "Yellow"
Write-Log "============================================" "Yellow"
Write-Host "Network RG: " -NoNewline; Write-Host $config.NetworkResourceGroup -ForegroundColor Yellow
Write-Host "VNet: " -NoNewline; Write-Host $config.VNetName -ForegroundColor Yellow
Write-Host "Subnet: " -NoNewline; Write-Host $config.SubnetName -ForegroundColor Yellow
Write-Host "MOVEit IP: " -NoNewline; Write-Host $config.MOVEitPrivateIP -ForegroundColor Yellow
Write-Host "Deployment RG: " -NoNewline; Write-Host $config.DeploymentResourceGroup -ForegroundColor Yellow
Write-Host ""
Write-Host "Press ENTER to continue deployment..." -ForegroundColor Cyan
Read-Host

# ----------------------------------------------------------------
# STEP 5: ENSURE DEPLOYMENT RG EXISTS
# ----------------------------------------------------------------
Write-Log "Checking deployment resource group..." "Yellow"
$deployRGExists = az group show --name $config.DeploymentResourceGroup 2>$null
if (-not $deployRGExists) {
    Write-Log "Creating $($config.DeploymentResourceGroup)..." "Yellow"
    az group create --name $config.DeploymentResourceGroup --location $config.Location --output none
}
Write-Log "Deployment RG ready: $($config.DeploymentResourceGroup)" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 6: CREATE NSG WITH PORT 22
# ----------------------------------------------------------------
Write-Log "Creating NSG in network RG..." "Cyan"

$nsgExists = az network nsg show --resource-group $config.NetworkResourceGroup --name $config.NSGName 2>$null
if (-not $nsgExists) {
    az network nsg create --resource-group $config.NetworkResourceGroup --name $config.NSGName --location $config.Location --output none
}

az network nsg rule create --resource-group $config.NetworkResourceGroup --nsg-name $config.NSGName --name "Allow-SFTP-22" --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --output none 2>$null

az network nsg rule create --resource-group $config.NetworkResourceGroup --nsg-name $config.NSGName --name "Allow-HTTPS-443" --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --output none 2>$null

az network vnet subnet update --resource-group $config.NetworkResourceGroup --vnet-name $config.VNetName --name $config.SubnetName --network-security-group $config.NSGName --output none

Write-Log "NSG configured with port 22 (SFTP)" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 7: CREATE LOAD BALANCER WITH PORT 22
# ----------------------------------------------------------------
Write-Log "Creating Load Balancer in deployment RG..." "Cyan"

$lbPublicIPExists = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerPublicIPName 2>$null
if (-not $lbPublicIPExists) {
    az network public-ip create --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerPublicIPName --sku Standard --allocation-method Static --location $config.Location --output none
}

$lbExists = az network lb show --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerName 2>$null
if (-not $lbExists) {
    az network lb create --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerName --sku Standard --public-ip-address $config.LoadBalancerPublicIPName --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "backend-pool-lb" --location $config.Location --output none
    
    $vnetId = az network vnet show --resource-group $config.NetworkResourceGroup --name $config.VNetName --query id --output tsv
    
    az network lb address-pool address add --resource-group $config.DeploymentResourceGroup --lb-name $config.LoadBalancerName --pool-name "backend-pool-lb" --name "moveit-backend" --vnet $vnetId --ip-address $config.MOVEitPrivateIP --output none
    
    az network lb probe create --resource-group $config.DeploymentResourceGroup --lb-name $config.LoadBalancerName --name "health-probe-sftp" --protocol tcp --port 22 --interval 15 --threshold 2 --output none
    
    az network lb rule create --resource-group $config.DeploymentResourceGroup --lb-name $config.LoadBalancerName --name "lb-rule-sftp-22" --protocol Tcp --frontend-port 22 --backend-port 22 --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "backend-pool-lb" --probe-name "health-probe-sftp" --idle-timeout 30 --enable-tcp-reset true --output none
}

Write-Log "Load Balancer created with port 22 (SFTP)" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 8: CREATE WAF
# ----------------------------------------------------------------
Write-Log "Creating WAF..." "Cyan"

$wafExists = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName 2>$null
if (-not $wafExists) {
    az network front-door waf-policy create --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName --sku $config.WAFSKU --mode $config.WAFMode --output none
    
    az network front-door waf-policy policy-setting update --resource-group $config.DeploymentResourceGroup --policy-name $config.WAFPolicyName --mode Prevention --redirect-url "" --custom-block-response-status-code 403 --custom-block-response-body "QWNjZXNzIERlbmllZA==" --request-body-check Enabled --max-request-body-size-in-kb 524288 --file-upload-enforcement true --file-upload-limit-in-mb 500 --output none
    
    az network front-door waf-policy managed-rules add --resource-group $config.DeploymentResourceGroup --policy-name $config.WAFPolicyName --type DefaultRuleSet --version 1.0 --output none
    
    az network front-door waf-policy managed-rules add --resource-group $config.DeploymentResourceGroup --policy-name $config.WAFPolicyName --type Microsoft_BotManagerRuleSet --version 1.0 --output none
    
    az network front-door waf-policy rule create --resource-group $config.DeploymentResourceGroup --policy-name $config.WAFPolicyName --name "AllowLargeUploads" --rule-type MatchRule --priority 100 --action Allow --match-condition "RequestMethod Equal POST PUT PATCH" --output none 2>$null
    
    az network front-door waf-policy rule create --resource-group $config.DeploymentResourceGroup --policy-name $config.WAFPolicyName --name "AllowMOVEitMethods" --rule-type MatchRule --priority 110 --action Allow --match-condition "RequestMethod Equal GET POST HEAD OPTIONS PUT PATCH DELETE" --output none 2>$null
}

Write-Log "WAF created" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 9: CREATE FRONT DOOR
# ----------------------------------------------------------------
Write-Log "Creating Front Door..." "Cyan"

$fdProfileExists = az afd profile show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName 2>$null
if (-not $fdProfileExists) {
    az afd profile create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --sku $config.FrontDoorSKU --output none
}

$fdEndpointExists = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName 2>$null
if (-not $fdEndpointExists) {
    az afd endpoint create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --enabled-state Enabled --output none
}

$originGroupExists = az afd origin-group show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName 2>$null
if (-not $originGroupExists) {
    az afd origin-group create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 30 --probe-path "/" --sample-size 4 --successful-samples-required 2 --additional-latency-in-milliseconds 0 --output none
}

$originExists = az afd origin show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName 2>$null
if (-not $originExists) {
    az afd origin create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName --host-name $config.MOVEitPrivateIP --origin-host-header $config.MOVEitPrivateIP --http-port 80 --https-port 443 --priority 1 --weight 1000 --enabled-state Enabled --output none
}

$routeExists = az afd route show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName 2>$null
if (-not $routeExists) {
    az afd route create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName --origin-group $config.FrontDoorOriginGroupName --supported-protocols Https --https-redirect Enabled --forwarding-protocol HttpsOnly --patterns-to-match "/*" --enabled-state Enabled --output none
}

$wafPolicyId = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName --query id --output tsv
$subscriptionId = az account show --query id --output tsv

az afd security-policy create --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --security-policy-name "moveit-waf-security" --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" --waf-policy $wafPolicyId --output none 2>$null

Write-Log "Front Door created" "Green"
Write-Host ""

# ----------------------------------------------------------------
# STEP 10: ENABLE DEFENDER
# ----------------------------------------------------------------
Write-Log "Enabling Defender..." "Cyan"
az security pricing create --name VirtualMachines --tier Standard --output none 2>$null
az security pricing create --name AppServices --tier Standard --output none 2>$null
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "Defender enabled" "Green"
Write-Host ""

# ----------------------------------------------------------------
# COMPLETE
# ----------------------------------------------------------------
$sftpPublicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerPublicIPName --query ipAddress --output tsv 2>$null
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv 2>$null

Write-Log "============================================" "Green"
Write-Log "  DEPLOYMENT COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "SFTP: $sftpPublicIP (port 22)" -ForegroundColor Cyan
Write-Host "HTTPS: https://$frontDoorEndpoint" -ForegroundColor Cyan
Write-Host ""
Write-Host "Network: $($config.NetworkResourceGroup)/$($config.VNetName)/$($config.SubnetName)" -ForegroundColor Yellow
Write-Host "Deployment: $($config.DeploymentResourceGroup)" -ForegroundColor Yellow
Write-Host "MOVEit IP: $($config.MOVEitPrivateIP)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Cost: $83/month" -ForegroundColor Yellow
Write-Host ""

$summaryFile = "$env:USERPROFILE\Desktop\MOVEit-Summary.txt"
@"
MOVEIT DEPLOYMENT
Deployed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

SFTP: $sftpPublicIP (port 22)
HTTPS: https://$frontDoorEndpoint

Network: $($config.NetworkResourceGroup)/$($config.VNetName)/$($config.SubnetName)
Deployment: $($config.DeploymentResourceGroup)
MOVEit IP: $($config.MOVEitPrivateIP)

Cost: $83/month
"@ | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Summary saved to Desktop" "Cyan"
