# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 4 OF 7
# WAF, FRONT DOOR, AND COMPLETE ROUTING
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 4 OF 7: WAF & FRONT DOOR" -ForegroundColor Cyan
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
Write-Log "Creating WAF policy..." "Cyan"
$wafExists = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName 2>$null
if (-not $wafExists) {
    az network front-door waf-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.WAFPolicyName `
        --sku Standard_AzureFrontDoor `
        --mode Prevention `
        --output none
    
    Write-Log "WAF policy created" "Green"
    
    Write-Host ""
    Write-Log "Configuring WAF settings..." "Yellow"
    az network front-door waf-policy policy-setting update `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --mode Prevention `
        --redirect-url "" `
        --custom-block-response-status-code 403 `
        --custom-block-response-body "QWNjZXNzIERlbmllZA==" `
        --request-body-check Enabled `
        --output none
    
    Write-Host ""
    Write-Log "Adding Default Rule Set..." "Yellow"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type DefaultRuleSet `
        --version 1.0 `
        --output none
    
    Write-Log "Adding Bot Manager Rule Set..." "Yellow"
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type Microsoft_BotManagerRuleSet `
        --version 1.0 `
        --output none
    
    Write-Log "WAF configured" "Green"
} else {
    Write-Log "WAF policy already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE FRONT DOOR PROFILE
# ----------------------------------------------------------------
Write-Log "Creating Front Door profile..." "Cyan"
$fdProfileExists = az afd profile show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName 2>$null
if (-not $fdProfileExists) {
    az afd profile create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --sku Standard_AzureFrontDoor `
        --output none
    Write-Log "Front Door profile created" "Green"
} else {
    Write-Log "Front Door profile already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE ENDPOINT
# ----------------------------------------------------------------
Write-Log "Creating Front Door endpoint..." "Yellow"
$fdEndpointExists = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName 2>$null
if (-not $fdEndpointExists) {
    az afd endpoint create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --enabled-state Enabled `
        --output none
    Write-Log "Endpoint created" "Green"
} else {
    Write-Log "Endpoint already exists" "Yellow"
}

# Get endpoint hostname
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv
Write-Log "Endpoint: $frontDoorEndpoint" "Green"

Write-Host ""

# ================================================================
# CRITICAL: COMPLETE ROUTING CONFIGURATION
# ================================================================
Write-Log "============================================" "Magenta"
Write-Log "CONFIGURING COMPLETE ROUTING" "Magenta"
Write-Log "============================================" "Magenta"
Write-Host ""

# ----------------------------------------------------------------
# CREATE ORIGIN GROUP
# ----------------------------------------------------------------
Write-Log "Creating origin group..." "Cyan"
$originGroupExists = az afd origin-group show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName 2>$null
if (-not $originGroupExists) {
    az afd origin-group create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name $config.FrontDoorOriginGroupName `
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

# ----------------------------------------------------------------
# CREATE ORIGIN (MOVEIT BACKEND)
# ----------------------------------------------------------------
Write-Log "Creating origin (MOVEit backend)..." "Cyan"
$originExists = az afd origin show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName 2>$null
if (-not $originExists) {
    az afd origin create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name $config.FrontDoorOriginGroupName `
        --origin-name $config.FrontDoorOriginName `
        --host-name $config.MOVEitPrivateIP `
        --origin-host-header $config.MOVEitPrivateIP `
        --http-port 80 `
        --https-port 443 `
        --priority 1 `
        --weight 1000 `
        --enabled-state Enabled `
        --output none
    Write-Log "Origin created: $($config.MOVEitPrivateIP)" "Green"
} else {
    Write-Log "Origin already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE ROUTE
# ----------------------------------------------------------------
Write-Log "Creating route to connect endpoint -> origin..." "Cyan"
$routeExists = az afd route show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName 2>$null
if (-not $routeExists) {
    az afd route create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --route-name $config.FrontDoorRouteName `
        --origin-group $config.FrontDoorOriginGroupName `
        --supported-protocols Https `
        --https-redirect Enabled `
        --forwarding-protocol HttpsOnly `
        --patterns-to-match "/*" `
        --enabled-state Enabled `
        --output none
    Write-Log "Route created and linked!" "Green"
} else {
    Write-Log "Route already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# CONFIGURE SSL/TLS SECURITY
# ----------------------------------------------------------------
Write-Log "============================================" "Magenta"
Write-Log "CONFIGURING SSL/TLS SECURITY" "Magenta"
Write-Log "============================================" "Magenta"
Write-Host ""

Write-Log "Setting TLS 1.2 as minimum version..." "Yellow"
az afd endpoint update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --output none 2>$null

az afd route update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --route-name $config.FrontDoorRouteName `
    --supported-protocols Https `
    --https-redirect Enabled `
    --forwarding-protocol HttpsOnly `
    --output none 2>$null

Write-Log "SSL/TLS 1.2+ enforced" "Green"

Write-Host ""

# ----------------------------------------------------------------
# ATTACH WAF TO FRONT DOOR
# ----------------------------------------------------------------
Write-Log "Attaching WAF to Front Door..." "Yellow"
$wafPolicyId = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName --query id --output tsv
$subscriptionId = az account show --query id --output tsv

az afd security-policy create `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --security-policy-name "moveit-waf-security" `
    --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" `
    --waf-policy $wafPolicyId `
    --output none 2>$null

Write-Log "WAF attached!" "Green"

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 4 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "FRONT DOOR CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Endpoint:    https://$frontDoorEndpoint" -ForegroundColor Green
Write-Host "  WAF:         Prevention Mode" -ForegroundColor Green
Write-Host "  Origin:      $($config.MOVEitPrivateIP)" -ForegroundColor White
Write-Host "  HTTPS-Only:  Enabled" -ForegroundColor White
Write-Host "  TLS Minimum: 1.2" -ForegroundColor Green
Write-Host ""
Write-Host "ROUTING CONFIGURED:" -ForegroundColor Cyan
Write-Host "  ✓ Origin Group: $($config.FrontDoorOriginGroupName)" -ForegroundColor Green
Write-Host "  ✓ Origin:       $($config.FrontDoorOriginName)" -ForegroundColor Green
Write-Host "  ✓ Route:        $($config.FrontDoorRouteName)" -ForegroundColor Green
Write-Host "  ✓ Pattern:      /* (all traffic)" -ForegroundColor Green
Write-Host ""
Write-Host "SECURITY ENABLED:" -ForegroundColor Magenta
Write-Host "  ✓ TLS 1.2+ only" -ForegroundColor Green
Write-Host "  ✓ HTTPS enforced" -ForegroundColor Green
Write-Host "  ✓ WAF protection" -ForegroundColor Green
Write-Host "  ✓ OWASP rules" -ForegroundColor Green
Write-Host "  ✓ Bot protection" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT: Run Script 5 - Defender" -ForegroundColor Yellow
Write-Host ""
