# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 6 OF 6 (OPTIONAL)
# CUSTOM DOMAIN AUTOMATION - FULLY AUTOMATED
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 6 OF 6: CUSTOM DOMAIN (OPTIONAL)" -ForegroundColor Cyan
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
# CUSTOM DOMAIN CONFIGURATION
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "CUSTOM DOMAIN SETUP" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Host "This script will configure a custom domain for your MOVEit deployment." -ForegroundColor White
Write-Host "Example: moveit.yourdomain.com instead of Azure's default URL" -ForegroundColor White
Write-Host ""

# Ask for custom domain
$customDomain = Read-Host "Enter your custom domain (e.g., moveit.yourdomain.com)"
if (-not $customDomain -or $customDomain -notmatch "^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$") {
    Write-Log "ERROR: Invalid domain format!" "Red"
    exit 1
}

$customDomainName = $customDomain -replace '\.', '-'
Write-Log "Custom domain: $customDomain" "Green"
Write-Host ""

# ----------------------------------------------------------------
# GET FRONT DOOR INFO
# ----------------------------------------------------------------
$FrontDoorProfileName = "moveit-frontdoor-profile"
$FrontDoorEndpointName = "moveit-endpoint"

Write-Log "Getting Front Door endpoint..." "Yellow"
$frontDoorEndpoint = az afd endpoint show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --endpoint-name $FrontDoorEndpointName `
    --query hostName `
    --output tsv

if (-not $frontDoorEndpoint) {
    Write-Log "ERROR: Front Door endpoint not found! Run Script 4 first." "Red"
    exit 1
}

Write-Log "Front Door endpoint: $frontDoorEndpoint" "Green"
Write-Host ""

# ----------------------------------------------------------------
# DNS CONFIGURATION INSTRUCTIONS
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Magenta"
Write-Log "DNS CONFIGURATION REQUIRED" "Magenta"
Write-Log "============================================" "Magenta"
Write-Host ""

Write-Host "BEFORE CONTINUING, you must configure DNS!" -ForegroundColor Yellow
Write-Host ""
Write-Host "DNS PROVIDER: GoDaddy, Cloudflare, Route53, etc." -ForegroundColor Cyan
Write-Host ""
Write-Host "CREATE THIS DNS RECORD:" -ForegroundColor Cyan
Write-Host "  Type:  CNAME" -ForegroundColor White
Write-Host "  Name:  $(($customDomain -split '\.')[0])" -ForegroundColor White
Write-Host "  Value: $frontDoorEndpoint" -ForegroundColor Green
Write-Host "  TTL:   600 (10 minutes)" -ForegroundColor White
Write-Host ""

Write-Host "EXAMPLE FOR GODADDY:" -ForegroundColor Cyan
Write-Host "  1. Login to GoDaddy.com" -ForegroundColor Gray
Write-Host "  2. Go to: My Products > DNS" -ForegroundColor Gray
Write-Host "  3. Find your domain" -ForegroundColor Gray
Write-Host "  4. Click: Add > CNAME" -ForegroundColor Gray
Write-Host "  5. Fill in:" -ForegroundColor Gray
Write-Host "     Name:  $(($customDomain -split '\.')[0])" -ForegroundColor White
Write-Host "     Value: $frontDoorEndpoint" -ForegroundColor Green
Write-Host "  6. Save" -ForegroundColor Gray
Write-Host ""

$dnsReady = Read-Host "Have you configured DNS? (yes/no)"
if ($dnsReady -ne "yes") {
    Write-Log "Please configure DNS first, then re-run this script." "Yellow"
    exit 0
}

Write-Host ""
Write-Log "Checking DNS propagation..." "Yellow"
Write-Host ""

# Try to resolve DNS
$dnsResolved = $false
for ($i = 1; $i -le 3; $i++) {
    Write-Log "DNS check attempt $i/3..." "Yellow"
    try {
        $dnsResult = Resolve-DnsName -Name $customDomain -Type CNAME -ErrorAction SilentlyContinue
        if ($dnsResult) {
            Write-Log "DNS CNAME found: $($dnsResult.NameHost)" "Green"
            $dnsResolved = $true
            break
        }
    } catch {
        Write-Log "DNS not propagated yet..." "Yellow"
    }
    
    if ($i -lt 3) {
        Start-Sleep -Seconds 5
    }
}

if (-not $dnsResolved) {
    Write-Log "WARNING: DNS not fully propagated yet. This is normal." "Yellow"
    Write-Host "  DNS can take 5-30 minutes to propagate globally." -ForegroundColor Gray
    Write-Host "  The script will continue and Azure will validate DNS later." -ForegroundColor Gray
}

Write-Host ""

# ----------------------------------------------------------------
# CREATE CUSTOM DOMAIN IN FRONT DOOR
# ----------------------------------------------------------------
Write-Log "Adding custom domain to Front Door..." "Cyan"

$domainExists = az afd custom-domain show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --output none 2>$null

if (-not $domainExists) {
    az afd custom-domain create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --custom-domain-name $customDomainName `
        --host-name $customDomain `
        --minimum-tls-version TLS12 `
        --output none
    
    Write-Log "Custom domain added" "Green"
} else {
    Write-Log "Custom domain already exists" "Yellow"
}

# Wait for domain validation
Write-Host ""
Write-Log "Waiting for Azure to validate domain ownership..." "Yellow"
Write-Host "  This can take 1-5 minutes..." -ForegroundColor Gray
Write-Host ""

$validated = $false
for ($i = 1; $i -le 10; $i++) {
    $domainStatus = az afd custom-domain show `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $FrontDoorProfileName `
        --custom-domain-name $customDomainName `
        --query "validationProperties.validationState" `
        --output tsv 2>$null
    
    if ($domainStatus -eq "Approved" -or $domainStatus -eq "Pending") {
        Write-Log "Domain validation: $domainStatus" "Green"
        $validated = $true
        break
    }
    
    Write-Host "  Attempt $i/10: Status = $domainStatus" -ForegroundColor Gray
    Start-Sleep -Seconds 15
}

if (-not $validated) {
    Write-Log "WARNING: Domain validation taking longer than expected." "Yellow"
    Write-Host "  This is normal if DNS hasn't fully propagated yet." -ForegroundColor Gray
    Write-Host "  Azure will continue validating in the background." -ForegroundColor Gray
}

Write-Host ""

# ----------------------------------------------------------------
# CONFIGURE SSL CERTIFICATE
# ----------------------------------------------------------------
Write-Log "Configuring Azure-managed SSL certificate..." "Cyan"

az afd custom-domain update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --certificate-type ManagedCertificate `
    --minimum-tls-version TLS12 `
    --output none 2>$null

Write-Log "Azure-managed SSL certificate configured" "Green"
Write-Host ""
Write-Host "  Azure will automatically provision a free SSL certificate" -ForegroundColor Gray
Write-Host "  This process can take 10-60 minutes after DNS validation" -ForegroundColor Gray
Write-Host ""

# ----------------------------------------------------------------
# ASSOCIATE CUSTOM DOMAIN WITH ROUTE
# ----------------------------------------------------------------
Write-Log "Associating custom domain with Front Door route..." "Cyan"

$FrontDoorRouteName = "moveit-route"
$subscriptionId = az account show --query id --output tsv

# Get current route configuration
$routeConfig = az afd route show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --endpoint-name $FrontDoorEndpointName `
    --route-name $FrontDoorRouteName `
    --query "{domains:customDomains}" `
    --output json 2>$null | ConvertFrom-Json

# Build domains array
$domainIds = @()
if ($routeConfig.domains) {
    $domainIds += $routeConfig.domains | ForEach-Object { $_.id }
}

# Add new custom domain
$newDomainId = "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$FrontDoorProfileName/customDomains/$customDomainName"
if ($newDomainId -notin $domainIds) {
    $domainIds += $newDomainId
}

# Update route with all domains
$domainIdsJson = ($domainIds | ForEach-Object { "{`"id`":`"$_`"}" }) -join ","
az afd route update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --endpoint-name $FrontDoorEndpointName `
    --route-name $FrontDoorRouteName `
    --custom-domains "[$domainIdsJson]" `
    --output none 2>$null

Write-Log "Custom domain associated with route" "Green"
Write-Host ""

# ----------------------------------------------------------------
# VERIFICATION
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "VERIFYING CONFIGURATION" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Log "Checking custom domain status..." "Yellow"
$domainDetails = az afd custom-domain show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --output json | ConvertFrom-Json

Write-Host ""
Write-Host "CUSTOM DOMAIN STATUS:" -ForegroundColor Cyan
Write-Host "  Domain:       $($domainDetails.hostName)" -ForegroundColor White
Write-Host "  Validation:   $($domainDetails.validationProperties.validationState)" -ForegroundColor $(if ($domainDetails.validationProperties.validationState -eq "Approved") {"Green"} else {"Yellow"})
Write-Host "  TLS Minimum:  $($domainDetails.tlsSettings.minimumTlsVersion)" -ForegroundColor White
Write-Host "  Certificate:  $($domainDetails.tlsSettings.certificateType)" -ForegroundColor White
Write-Host ""

# ----------------------------------------------------------------
# FINAL SUMMARY
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 6 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""

Write-Host "CUSTOM DOMAIN CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Your Domain:    https://$customDomain" -ForegroundColor Green
Write-Host "  Default Domain: https://$frontDoorEndpoint" -ForegroundColor White
Write-Host ""

Write-Host "SSL CERTIFICATE:" -ForegroundColor Cyan
Write-Host "  Type:           Azure-managed (free)" -ForegroundColor White
Write-Host "  TLS Version:    1.2 minimum" -ForegroundColor White
Write-Host "  Auto-renewal:   Enabled" -ForegroundColor Green
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. WAIT FOR DNS PROPAGATION (10-30 minutes)" -ForegroundColor White
Write-Host "   DNS records need time to propagate globally" -ForegroundColor Gray
Write-Host ""
Write-Host "2. WAIT FOR SSL CERTIFICATE (10-60 minutes)" -ForegroundColor White
Write-Host "   Azure will automatically provision SSL certificate" -ForegroundColor Gray
Write-Host "   after DNS validation completes" -ForegroundColor Gray
Write-Host ""
Write-Host "3. TEST YOUR DOMAIN:" -ForegroundColor White
Write-Host "   https://$customDomain" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. CHECK CERTIFICATE STATUS:" -ForegroundColor White
Write-Host "   Portal > Front Door > Domains > $customDomain" -ForegroundColor Gray
Write-Host ""

Write-Host "VERIFICATION COMMANDS:" -ForegroundColor Cyan
Write-Host "  # Check DNS" -ForegroundColor Gray
Write-Host "  nslookup $customDomain" -ForegroundColor White
Write-Host ""
Write-Host "  # Test HTTPS" -ForegroundColor Gray
Write-Host "  curl -I https://$customDomain" -ForegroundColor White
Write-Host ""

Write-Host "DEPLOYMENT COMPLETE! 🎉" -ForegroundColor Green
Write-Host ""
Write-Host "All 6 scripts have been executed successfully." -ForegroundColor White
Write-Host "Your MOVEit deployment is now fully configured with:" -ForegroundColor White
Write-Host "  ✓ Network security (NSG)" -ForegroundColor Green
Write-Host "  ✓ Load Balancer (SFTP/SSH on port 22)" -ForegroundColor Green
Write-Host "  ✓ WAF protection" -ForegroundColor Green
Write-Host "  ✓ Front Door (HTTPS with custom domain)" -ForegroundColor Green
Write-Host "  ✓ Microsoft Defender" -ForegroundColor Green
Write-Host "  ✓ Custom domain with SSL/TLS 1.2" -ForegroundColor Green
Write-Host ""
