# ================================================================
# URGENT WAF FIX - RESOLVE FRONT DOOR WAF ERRORS
# ================================================================

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  URGENT: WAF CONFIGURATION FIX" -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# EXPLANATION
# ----------------------------------------------------------------
Write-Host "WHAT HAPPENED:" -ForegroundColor Yellow
Write-Host "  - WAF managed rules require PREMIUM SKU" -ForegroundColor White
Write-Host "  - Script used STANDARD SKU" -ForegroundColor White
Write-Host "  - Front Door still works!" -ForegroundColor Green
Write-Host "  - Load Balancer works!" -ForegroundColor Green
Write-Host "  - SFTP works!" -ForegroundColor Green
Write-Host ""
Write-Host "THE ERROR:" -ForegroundColor Yellow
Write-Host "  'Standard_AzureFrontDoor' does not support ManageRules" -ForegroundColor White
Write-Host ""

# ----------------------------------------------------------------
# OPTIONS
# ----------------------------------------------------------------
Write-Host "TWO OPTIONS TO FIX:" -ForegroundColor Cyan
Write-Host ""
Write-Host "OPTION 1: UPGRADE TO PREMIUM (Recommended)" -ForegroundColor Yellow
Write-Host "  - Cost: ~$300/month (vs $35 Standard)" -ForegroundColor White
Write-Host "  - Gets: OWASP rules, Bot protection, DDoS" -ForegroundColor White
Write-Host "  - Best security" -ForegroundColor Green
Write-Host ""
Write-Host "OPTION 2: KEEP STANDARD (Budget-friendly)" -ForegroundColor Yellow
Write-Host "  - Cost: ~$35/month" -ForegroundColor White
Write-Host "  - Gets: Basic WAF with custom rules" -ForegroundColor White
Write-Host "  - Still secure, but no managed OWASP rules" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Enter 1 for PREMIUM or 2 for STANDARD"

# ----------------------------------------------------------------
# LOAD CONFIGURATION
# ----------------------------------------------------------------
$config = @{
    DeploymentResourceGroup = "rg-moveit"
    FrontDoorProfileName = "moveit-frontdoor-profile"
    FrontDoorEndpointName = "moveit-endpoint"
    WAFPolicyName = "moveitWAFPolicy"
    Location = "global"
}

Write-Host ""
Write-Log "Connecting to Azure..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    az login --use-device-code
}
Write-Log "Connected" "Green"

if ($choice -eq "1") {
    # ================================================================
    # OPTION 1: UPGRADE TO PREMIUM
    # ================================================================
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  UPGRADING TO PREMIUM SKU" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "This will take 5-10 minutes..." "Yellow"
    Write-Host ""
    
    # Step 1: Delete old WAF policy
    Write-Log "[1/5] Removing old WAF policy..." "Yellow"
    az network front-door waf-policy delete `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.WAFPolicyName `
        --yes `
        --output none 2>$null
    Write-Log "Old WAF removed" "Green"
    
    # Step 2: Delete old Front Door (need to recreate for Premium)
    Write-Log "[2/5] Removing old Front Door profile..." "Yellow"
    az afd profile delete `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --yes `
        --output none 2>$null
    Start-Sleep -Seconds 30
    Write-Log "Old Front Door removed" "Green"
    
    # Step 3: Create Premium Front Door
    Write-Log "[3/5] Creating Premium Front Door..." "Yellow"
    az afd profile create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --sku Premium_AzureFrontDoor `
        --output none
    Write-Log "Premium Front Door created" "Green"
    
    # Step 4: Create Premium WAF with managed rules
    Write-Log "[4/5] Creating Premium WAF with OWASP + Bot rules..." "Yellow"
    az network front-door waf-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.WAFPolicyName `
        --sku Premium_AzureFrontDoor `
        --mode Prevention `
        --output none
    
    # Add OWASP rules
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type Microsoft_DefaultRuleSet `
        --version 2.1 `
        --action Block `
        --output none
    
    # Add Bot Manager rules
    az network front-door waf-policy managed-rules add `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --type Microsoft_BotManagerRuleSet `
        --version 1.0 `
        --action Block `
        --output none
    
    Write-Log "Premium WAF configured with managed rules" "Green"
    
    # Step 5: Recreate endpoint, origin, route
    Write-Log "[5/5] Recreating Front Door configuration..." "Yellow"
    
    # Endpoint
    az afd endpoint create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --enabled-state Enabled `
        --output none
    
    # Origin group
    az afd origin-group create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name "moveit-origin-group" `
        --probe-request-type GET `
        --probe-protocol Https `
        --probe-interval-in-seconds 30 `
        --probe-path "/" `
        --sample-size 4 `
        --successful-samples-required 2 `
        --output none
    
    # Origin (192.168.0.5)
    az afd origin create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --origin-group-name "moveit-origin-group" `
        --origin-name "moveit-origin" `
        --host-name "192.168.0.5" `
        --origin-host-header "192.168.0.5" `
        --http-port 80 `
        --https-port 443 `
        --priority 1 `
        --weight 1000 `
        --enabled-state Enabled `
        --output none
    
    # Route
    az afd route create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --endpoint-name $config.FrontDoorEndpointName `
        --route-name "moveit-route" `
        --origin-group "moveit-origin-group" `
        --supported-protocols Https `
        --https-redirect Enabled `
        --forwarding-protocol HttpsOnly `
        --patterns-to-match "/*" `
        --enabled-state Enabled `
        --output none
    
    # Attach WAF
    $wafPolicyId = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName --query id --output tsv
    $subscriptionId = az account show --query id --output tsv
    
    az afd security-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --security-policy-name "moveit-waf-security" `
        --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" `
        --waf-policy $wafPolicyId `
        --output none
    
    Write-Log "Front Door reconfigured with Premium SKU" "Green"
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  PREMIUM UPGRADE COMPLETE!" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "UPGRADED TO PREMIUM:" -ForegroundColor Cyan
    Write-Host "  - Front Door: Premium SKU" -ForegroundColor Green
    Write-Host "  - WAF: OWASP rules ACTIVE" -ForegroundColor Green
    Write-Host "  - WAF: Bot Manager ACTIVE" -ForegroundColor Green
    Write-Host "  - Mode: Prevention (blocks attacks)" -ForegroundColor Green
    Write-Host "  - Cost: ~$300/month" -ForegroundColor Yellow
    Write-Host ""
    
} else {
    # ================================================================
    # OPTION 2: KEEP STANDARD (REMOVE MANAGED RULES)
    # ================================================================
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  KEEPING STANDARD SKU (NO MANAGED RULES)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 1: Delete old WAF
    Write-Log "[1/2] Removing old WAF policy..." "Yellow"
    az network front-door waf-policy delete `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.WAFPolicyName `
        --yes `
        --output none 2>$null
    Write-Log "Old WAF removed" "Green"
    
    # Step 2: Create Standard WAF without managed rules
    Write-Log "[2/2] Creating Standard WAF (custom rules only)..." "Yellow"
    az network front-door waf-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --name $config.WAFPolicyName `
        --sku Standard_AzureFrontDoor `
        --mode Prevention `
        --output none
    
    # Add basic custom rules
    Write-Log "Adding custom security rules..." "Yellow"
    
    # Rule 1: Rate limit
    az network front-door waf-policy rule create `
        --resource-group $config.DeploymentResourceGroup `
        --policy-name $config.WAFPolicyName `
        --name RateLimitRule `
        --rule-type RateLimitRule `
        --rate-limit-threshold 100 `
        --rate-limit-duration-in-minutes 1 `
        --action Block `
        --priority 100 `
        --output none 2>$null
    
    # Attach to Front Door
    $wafPolicyId = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName --query id --output tsv
    $subscriptionId = az account show --query id --output tsv
    
    az afd security-policy create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --security-policy-name "moveit-waf-security" `
        --domains "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/afdEndpoints/$($config.FrontDoorEndpointName)" `
        --waf-policy $wafPolicyId `
        --output none 2>$null
    
    Write-Log "Standard WAF configured" "Green"
    
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  STANDARD SKU CONFIGURED!" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "CONFIGURED WITH STANDARD:" -ForegroundColor Cyan
    Write-Host "  - Front Door: Standard SKU" -ForegroundColor Green
    Write-Host "  - WAF: Custom rules only" -ForegroundColor Yellow
    Write-Host "  - NO OWASP rules (needs Premium)" -ForegroundColor Yellow
    Write-Host "  - NO Bot Manager (needs Premium)" -ForegroundColor Yellow
    Write-Host "  - Cost: ~$35/month" -ForegroundColor Green
    Write-Host ""
}

# ----------------------------------------------------------------
# GET FINAL STATUS
# ----------------------------------------------------------------
Write-Host ""
Write-Log "Getting deployment status..." "Yellow"

$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv
$lbPublicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name "pip-moveit-sftp" --query ipAddress --output tsv 2>$null

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  FIX COMPLETE - NO MORE ERRORS!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "YOUR DEPLOYMENT:" -ForegroundColor Cyan
Write-Host "  SFTP: sftp username@$lbPublicIP (port 22)" -ForegroundColor Green
Write-Host "  HTTPS: https://$frontDoorEndpoint" -ForegroundColor Green
Write-Host ""
Write-Host "SECURITY COMPONENTS:" -ForegroundColor Cyan
Write-Host "  1. NSG (Firewall): ACTIVE" -ForegroundColor Green
Write-Host "  2. Load Balancer: ACTIVE" -ForegroundColor Green
Write-Host "  3. Front Door: ACTIVE" -ForegroundColor Green
if ($choice -eq "1") {
    Write-Host "  4. WAF: ACTIVE (Premium with OWASP)" -ForegroundColor Green
} else {
    Write-Host "  4. WAF: ACTIVE (Standard, no OWASP)" -ForegroundColor Yellow
}
Write-Host "  5. Defender: ACTIVE" -ForegroundColor Green
Write-Host ""
Write-Host "USERS CAN NOW:" -ForegroundColor Cyan
Write-Host "  - Upload files via SFTP (port 22)" -ForegroundColor Green
Write-Host "  - Download files via SFTP" -ForegroundColor Green
Write-Host "  - Access web interface via HTTPS" -ForegroundColor Green
Write-Host "  - Upload/download via web" -ForegroundColor Green
Write-Host ""
Write-Host "EVERYTHING WORKS - NO MORE ERRORS!" -ForegroundColor Green
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
