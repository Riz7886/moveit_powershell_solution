# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 4 OF 5
# WAF AND FRONT DOOR
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 4 OF 5: WAF AND FRONT DOOR" -ForegroundColor Cyan
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
# CREATE WAF POLICY
# ----------------------------------------------------------------
$WAFPolicyName = "moveitWAFPolicy"

Write-Log "Creating WAF policy..." "Cyan"
$wafExists = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $WAFPolicyName 2>$null
if (-not $wafExists) {
    az network front-door waf-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --name $WAFPolicyName `
        --sku Standard_AzureFrontDoor `
        --mode Prevention `
        --output none
    
    Write-Log "WAF policy created" "Green"
    
    # Configure WAF settings
    Write-Host ""
    Write-Log "Configuring WAF policy settings..." "Yellow"
    az network front-door waf-policy policy-setting update `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $WAFPolicyName `
        --mode Prevention `
        --redirect-url "" `
        --custom-block-response-status-code 403 `
        --custom-block-response-body "QWNjZXNzIERlbmllZA==" `
        --request-body-check Enabled `
        --max-request-body-size-in-kb 524288 `
        --file-upload-enforcement true `
        --file-upload-limit-in-mb 500 `
        --output none
    
    # Add managed rule sets
    Write-Host ""
    Write-Log "Adding Default Rule Set..." "Yellow"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $WAFPolicyName `
        --type DefaultRuleSet `
        --version 1.0 `
        --output none
    
    Write-Log "Adding Bot Manager Rule Set..." "Yellow"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $WAFPolicyName `
        --type Microsoft_BotManagerRuleSet `
        --version 1.0 `
        --output none
    
    Write-Log "WAF configured" "Green"
} else {
    Write-Log "WAF policy already exists" "Yellow"
}

# ----------------------------------------------------------------
# CREATE FRONT DOOR
# ----------------------------------------------------------------
$FrontDoorProfileName = "moveit-frontdoor-profile"
$FrontDoorEndpointName = "moveit-endpoint"
$FrontDoorOriginGroupName = "moveit-origin-group"
$FrontDoorOriginName = "moveit-origin"
$FrontDoorRouteName = "moveit-route"

Write-Host ""
Write-Log "Creating Front Door profile..." "Cyan"
$fdProfileExists = az afd profile show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName 2>$null
if (-not $fdProfileExists) {
    az afd profile create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --sku Standard_AzureFrontDoor `
        --output none
    Write-Log "Front Door profile created" "Green"
} else {
    Write-Log "Front Door profile already exists" "Yellow"
}

Write-Host ""
Write-Log "Creating Front Door endpoint..." "Yellow"
$fdEndpointExists = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --endpoint-name $FrontDoorEndpointName 2>$null
if (-not $fdEndpointExists) {
    az afd endpoint create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --endpoint-name $FrontDoorEndpointName `
        --enabled-state Enabled `
        --output none
    Write-Log "Front Door endpoint created" "Green"
} else {
    Write-Log "Front Door endpoint already exists" "Yellow"
}

Write-Host ""
Write-Log "Creating origin group..." "Yellow"
$originGroupExists = az afd origin-group show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --origin-group-name $FrontDoorOriginGroupName 2>$null
if (-not $originGroupExists) {
    az afd origin-group create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --origin-group-name $FrontDoorOriginGroupName `
        --probe-request-type GET `
        --probe-protocol Https `
        --probe-interval-in-seconds 30 `
        --probe-path "/" `
        --sample-size 4 `
        --successful-samples-required 2 `
        --additional-latency-in-milliseconds 0 `
        --output none
    Write-Log "Origin group created" "Green"
} else {
    Write-Log "Origin group already exists" "Yellow"
}

Write-Host ""
Write-Log "Creating origin..." "Yellow"
$originExists = az afd origin show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --origin-group-name $FrontDoorOriginGroupName --origin-name $FrontDoorOriginName 2>$null
if (-not $originExists) {
    az afd origin create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --origin-group-name $FrontDoorOriginGroupName `
        --origin-name $FrontDoorOriginName `
        --host-name $config.MOVEitPrivateIP `
        --origin-host-header $config.MOVEitPrivateIP `
        --http-port 80 `
        --https-port 443 `
        --priority 1 `
        --weight 1000 `
        --enabled-state Enabled `
        --output none
    Write-Log "Origin created" "Green"
} else {
    Write-Log "Origin already exists" "Yellow"
}

Write-Host ""
Write-Log "Creating route..." "Yellow"
$routeExists = az afd route show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --endpoint-name $FrontDoorEndpointName --route-name $FrontDoorRouteName 2>$null
if (-not $routeExists) {
    az afd route create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --endpoint-name $FrontDoorEndpointName `
        --route-name $FrontDoorRouteName `
        --origin-group $FrontDoorOriginGroupName `
        --supported-protocols Https `
        --https-redirect Enabled `
        --forwarding-protocol HttpsOnly `
        --patterns-to-match "/*" `
        --enabled-state Enabled `
        --output none
    Write-Log "Route created" "Green"
} else {
    Write-Log "Route already exists" "Yellow"
}

Write-Host ""
Write-Log "Attaching WAF to Front Door..." "Yellow"
$wafPolicyId = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $WAFPolicyName --query id --output tsv
$subscriptionId = az account show --query id --output tsv

az afd security-policy create `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --security-policy-name "moveit-waf-security" `
    --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$FrontDoorProfileName/afdEndpoints/$FrontDoorEndpointName" `
    --waf-policy $wafPolicyId `
    --output none 2>$null

Write-Log "WAF attached to Front Door" "Green"

# Get Front Door endpoint
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --endpoint-name $FrontDoorEndpointName --query hostName --output tsv

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 4 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "FRONT DOOR CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Endpoint: https://$frontDoorEndpoint" -ForegroundColor Green
Write-Host "  WAF: Prevention Mode" -ForegroundColor Green
Write-Host "  Origin: $($config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host "  HTTPS-Only: Enabled" -ForegroundColor White
Write-Host ""
Write-Host "USERS CAN NOW ACCESS:" -ForegroundColor Yellow
Write-Host "  https://$frontDoorEndpoint" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT: Run Script 5 - Defender" -ForegroundColor Yellow
Write-Host ""
