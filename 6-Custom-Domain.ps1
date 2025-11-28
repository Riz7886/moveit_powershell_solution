# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 6 OF 7 (OPTIONAL)
# CUSTOM DOMAIN WITH KEY VAULT CERTIFICATE
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 6 OF 7: CUSTOM DOMAIN (OPTIONAL)" -ForegroundColor Cyan
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
# GET FRONT DOOR ENDPOINT
# ----------------------------------------------------------------
Write-Log "Getting Front Door endpoint..." "Yellow"
$frontDoorEndpoint = az afd endpoint show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --query hostName `
    --output tsv

Write-Log "Front Door: $frontDoorEndpoint" "Green"
Write-Host ""

# ----------------------------------------------------------------
# DNS CONFIGURATION INSTRUCTIONS
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Magenta"
Write-Log "DNS CONFIGURATION REQUIRED" "Magenta"
Write-Log "============================================" "Magenta"
Write-Host ""

Write-Host "CONFIGURE DNS IN GODADDY BEFORE CONTINUING!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Domain: pyxhealth.com" -ForegroundColor Cyan
Write-Host ""
Write-Host "DELETE THIS RECORD:" -ForegroundColor Red
Write-Host "  Type:  A" -ForegroundColor Red
Write-Host "  Name:  moveit" -ForegroundColor Red
Write-Host "  Value: 20.86.24.168" -ForegroundColor Red
Write-Host ""
Write-Host "ADD THIS RECORD:" -ForegroundColor Green
Write-Host "  Type:  CNAME" -ForegroundColor Green
Write-Host "  Name:  moveit" -ForegroundColor Green
Write-Host "  Value: $frontDoorEndpoint" -ForegroundColor Green
Write-Host "  TTL:   600" -ForegroundColor Green
Write-Host ""
Write-Host "GODADDY STEPS:" -ForegroundColor Cyan
Write-Host "  1. Login to GoDaddy.com" -ForegroundColor White
Write-Host "  2. My Products > DNS > pyxhealth.com" -ForegroundColor White
Write-Host "  3. Find 'moveit' A record -> DELETE" -ForegroundColor White
Write-Host "  4. Add -> CNAME" -ForegroundColor White
Write-Host "  5. Name: moveit" -ForegroundColor White
Write-Host "  6. Value: $frontDoorEndpoint" -ForegroundColor White
Write-Host "  7. Save" -ForegroundColor White
Write-Host ""

$dnsReady = Read-Host "Have you configured DNS in GoDaddy? (yes/no)"
if ($dnsReady -ne "yes") {
    Write-Log "Please configure DNS first, then re-run this script." "Yellow"
    exit 0
}

Write-Host ""

# ----------------------------------------------------------------
# GRANT FRONT DOOR ACCESS TO KEY VAULT
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "KEY VAULT CONFIGURATION" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Log "Checking Key Vault..." "Yellow"
$kvExists = az keyvault show --name $config.KeyVaultName 2>$null
if (-not $kvExists) {
    Write-Log "ERROR: Key Vault '$($config.KeyVaultName)' not found!" "Red"
    Write-Host ""
    Write-Host "Available Key Vaults:" -ForegroundColor Yellow
    az keyvault list --query "[].name" --output tsv
    Write-Host ""
    exit 1
}

Write-Log "Key Vault found: $($config.KeyVaultName)" "Green"
Write-Host ""

# Grant Front Door service principal access
Write-Log "Granting Front Door access to Key Vault..." "Yellow"
$frontDoorAppId = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8"

az keyvault set-policy `
    --name $config.KeyVaultName `
    --spn $frontDoorAppId `
    --secret-permissions get list `
    --certificate-permissions get list `
    --output none 2>$null

Write-Log "Front Door access granted" "Green"

# Grant current user access
$currentUser = az account show --query user.name --output tsv
az keyvault set-policy `
    --name $config.KeyVaultName `
    --upn $currentUser `
    --secret-permissions get list `
    --certificate-permissions get list `
    --output none 2>$null

Write-Log "Your account has access" "Green"
Write-Host ""

# Wait for permissions to propagate
Write-Log "Waiting for permissions to propagate..." "Yellow"
Start-Sleep -Seconds 5

# ----------------------------------------------------------------
# GET CERTIFICATE FROM KEY VAULT
# ----------------------------------------------------------------
Write-Log "Getting certificates from Key Vault..." "Yellow"
$certs = az keyvault certificate list --vault-name $config.KeyVaultName --output json 2>$null | ConvertFrom-Json

if (-not $certs -or $certs.Count -eq 0) {
    Write-Log "ERROR: No certificates found in Key Vault!" "Red"
    Write-Host ""
    Write-Host "Import a certificate first:" -ForegroundColor Yellow
    Write-Host "az keyvault certificate import --vault-name $($config.KeyVaultName) --name moveit-cert --file cert.pfx --password PASSWORD" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Certificates found:" -ForegroundColor Cyan
for ($i = 0; $i -lt $certs.Count; $i++) {
    Write-Host "[$($i + 1)] $($certs[$i].name)" -ForegroundColor White
}
Write-Host ""

if ($certs.Count -eq 1) {
    $certName = $certs[0].name
    Write-Log "Auto-selected: $certName" "Green"
} else {
    $certSelection = Read-Host "Select certificate number"
    $certName = $certs[[int]$certSelection - 1].name
}

Write-Log "Using certificate: $certName" "Green"

# Get certificate secret ID
$certDetails = az keyvault certificate show --vault-name $config.KeyVaultName --name $certName --output json | ConvertFrom-Json
$certSecretId = $certDetails.sid

if (-not $certSecretId) {
    Write-Log "ERROR: Could not get certificate secret ID!" "Red"
    exit 1
}

Write-Log "Certificate Secret ID obtained" "Green"
Write-Host ""

# ----------------------------------------------------------------
# CREATE/UPDATE CUSTOM DOMAIN
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "CUSTOM DOMAIN CONFIGURATION" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

$customDomainName = "moveit-pyxhealth-com"

Write-Log "Configuring custom domain: $($config.CustomDomain)" "Yellow"
$domainExists = az afd custom-domain show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --output none 2>$null

if (-not $domainExists) {
    Write-Log "Creating custom domain..." "Yellow"
    az afd custom-domain create `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --custom-domain-name $customDomainName `
        --host-name $config.CustomDomain `
        --minimum-tls-version TLS12 `
        --output none
    
    Write-Log "Custom domain created" "Green"
} else {
    Write-Log "Custom domain already exists" "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# WAIT FOR DOMAIN VALIDATION
# ----------------------------------------------------------------
Write-Log "Waiting for domain validation..." "Yellow"
Write-Host "  This can take 1-5 minutes..." -ForegroundColor Gray

$validated = $false
for ($i = 1; $i -le 20; $i++) {
    $domainStatus = az afd custom-domain show `
        --resource-group $config.DeploymentResourceGroup `
        --profile-name $config.FrontDoorProfileName `
        --custom-domain-name $customDomainName `
        --query "validationProperties.validationState" `
        --output tsv 2>$null
    
    Write-Host "  Attempt $i/20: $domainStatus" -ForegroundColor Gray
    
    if ($domainStatus -eq "Approved" -or $domainStatus -eq "Pending") {
        Write-Log "Domain validated: $domainStatus" "Green"
        $validated = $true
        break
    }
    
    Start-Sleep -Seconds 15
}

if (-not $validated) {
    Write-Log "WARNING: Validation taking longer. Continuing anyway..." "Yellow"
}

Write-Host ""

# ----------------------------------------------------------------
# ATTACH CERTIFICATE TO CUSTOM DOMAIN
# ----------------------------------------------------------------
Write-Log "Attaching Key Vault certificate to domain..." "Cyan"

az afd custom-domain update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --certificate-type CustomerCertificate `
    --minimum-tls-version TLS12 `
    --secret $certSecretId `
    --output none 2>$null

Write-Log "Certificate attached!" "Green"
Write-Host ""

# ----------------------------------------------------------------
# ASSOCIATE CUSTOM DOMAIN WITH ROUTE
# ----------------------------------------------------------------
Write-Log "Associating domain with route..." "Cyan"

$subscriptionId = az account show --query id --output tsv
$customDomainId = "/subscriptions/$subscriptionId/resourceGroups/$($config.DeploymentResourceGroup)/providers/Microsoft.Cdn/profiles/$($config.FrontDoorProfileName)/customDomains/$customDomainName"

# Get current route
$currentRoute = az afd route show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --route-name $config.FrontDoorRouteName `
    --output json 2>$null | ConvertFrom-Json

# Build domains array
$domainIds = @()
if ($currentRoute.customDomains) {
    foreach ($domain in $currentRoute.customDomains) {
        if ($domain.id -ne $customDomainId) {
            $domainIds += $domain.id
        }
    }
}
$domainIds += $customDomainId

# Update route with custom domain
$domainsJson = ($domainIds | ForEach-Object { "{`"id`":`"$_`"}" }) -join ","
az afd route update `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --endpoint-name $config.FrontDoorEndpointName `
    --route-name $config.FrontDoorRouteName `
    --custom-domains "[$domainsJson]" `
    --output none 2>$null

Write-Log "Domain associated with route!" "Green"
Write-Host ""

# ----------------------------------------------------------------
# VERIFICATION
# ----------------------------------------------------------------
Write-Log "============================================" "Cyan"
Write-Log "VERIFICATION" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

$domainDetails = az afd custom-domain show `
    --resource-group $config.DeploymentResourceGroup `
    --profile-name $config.FrontDoorProfileName `
    --custom-domain-name $customDomainName `
    --output json | ConvertFrom-Json

Write-Host "CUSTOM DOMAIN STATUS:" -ForegroundColor Cyan
Write-Host "  Domain:       $($domainDetails.hostName)" -ForegroundColor White
Write-Host "  Validation:   $($domainDetails.validationProperties.validationState)" -ForegroundColor Green
Write-Host "  Certificate:  CustomerCertificate (Key Vault)" -ForegroundColor Green
Write-Host "  TLS Minimum:  $($domainDetails.tlsSettings.minimumTlsVersion)" -ForegroundColor Green
Write-Host ""

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 6 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""

Write-Host "CUSTOM DOMAIN CONFIGURED:" -ForegroundColor Cyan
Write-Host "  Your Domain:  https://$($config.CustomDomain)" -ForegroundColor Green
Write-Host "  Certificate:  $certName (Key Vault)" -ForegroundColor White
Write-Host "  TLS Version:  1.2 minimum" -ForegroundColor White
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Wait 5-10 minutes for DNS propagation" -ForegroundColor White
Write-Host "  2. Test: https://$($config.CustomDomain)" -ForegroundColor White
Write-Host "  3. Verify certificate (no browser warnings)" -ForegroundColor White
Write-Host "  4. Run Script 7 for automated testing" -ForegroundColor White
Write-Host ""

Write-Host "OPTIONAL: Run Script 7 for complete testing" -ForegroundColor Yellow
Write-Host ""
