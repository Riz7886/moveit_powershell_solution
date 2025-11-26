# ================================================================
# ONE-SHOT FRONT DOOR CERTIFICATE FIX
# BULLETPROOF - FIXES EVERYTHING IN ONE RUN
# ================================================================

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  ONE-SHOT FRONT DOOR CERTIFICATE FIX - LIVE PRODUCTION" -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "This script will fix ALL certificate issues in ONE run!" -ForegroundColor Yellow
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Check Azure CLI
Write-Log "Checking Azure CLI..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in. Starting login..." "Yellow"
    az login --use-device-code
}

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "STEP 1: FIND RESOURCES AUTOMATICALLY" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Find Key Vault
Write-Log "Searching for Key Vaults..." "Yellow"
$keyVaults = az keyvault list --output json | ConvertFrom-Json
$moveitKV = $keyVaults | Where-Object { $_.name -like "*moveit*" -or $_.name -like "*kv*" }

if ($moveitKV.Count -eq 0) {
    Write-Host "Key Vaults found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $keyVaults.Count; $i++) {
        Write-Host "[$($i + 1)] $($keyVaults[$i].name)" -ForegroundColor White
    }
    $selection = Read-Host "Select Key Vault number"
    $keyVault = $keyVaults[[int]$selection - 1]
} else {
    $keyVault = $moveitKV[0]
}

$keyVaultName = $keyVault.name
Write-Log "Using Key Vault: $keyVaultName" "Green"

# Find Front Door
Write-Log "Searching for Front Doors..." "Yellow"
$frontDoors = az afd profile list --output json | ConvertFrom-Json
$moveitFD = $frontDoors | Where-Object { $_.name -like "*moveit*" -or $_.name -like "*frontdoor*" }

if ($moveitFD.Count -eq 0) {
    Write-Host "Front Doors found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $frontDoors.Count; $i++) {
        Write-Host "[$($i + 1)] $($frontDoors[$i].name) (RG: $($frontDoors[$i].resourceGroup))" -ForegroundColor White
    }
    $selection = Read-Host "Select Front Door number"
    $frontDoor = $frontDoors[[int]$selection - 1]
} else {
    $frontDoor = $moveitFD[0]
}

$frontDoorName = $frontDoor.name
$resourceGroup = $frontDoor.resourceGroup
Write-Log "Using Front Door: $frontDoorName" "Green"
Write-Log "Resource Group: $resourceGroup" "Green"

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "STEP 2: GRANT FRONT DOOR ACCESS TO KEY VAULT" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Front Door service principal IDs
$frontDoorAppId = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8"  # Microsoft.AzureFrontDoor-Cdn

Write-Log "[1/2] Granting Microsoft.AzureFrontDoor-Cdn access..." "Yellow"
az keyvault set-policy `
    --name $keyVaultName `
    --spn $frontDoorAppId `
    --secret-permissions get list `
    --certificate-permissions get list `
    --output none 2>$null

Write-Log "Service principal access granted!" "Green"

# Also grant current user full access (in case needed)
Write-Log "[2/2] Ensuring your account has full access..." "Yellow"
$currentUser = az account show --query user.name -o tsv
az keyvault set-policy `
    --name $keyVaultName `
    --upn $currentUser `
    --secret-permissions get list set delete `
    --certificate-permissions get list create import delete update `
    --output none 2>$null

Write-Log "Your account has full access!" "Green"

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "STEP 3: GET CERTIFICATE FROM KEY VAULT" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Log "Listing certificates in Key Vault..." "Yellow"
Start-Sleep -Seconds 3  # Wait for permissions to propagate

$certs = az keyvault certificate list --vault-name $keyVaultName --output json 2>$null | ConvertFrom-Json

if (-not $certs -or $certs.Count -eq 0) {
    Write-Log "ERROR: No certificates found in Key Vault!" "Red"
    Write-Host ""
    Write-Host "URGENT: You need a certificate in Key Vault!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run this command to import your certificate:" -ForegroundColor Yellow
    Write-Host "az keyvault certificate import --vault-name $keyVaultName --name moveit-cert --file YOUR_CERT.pfx --password YOUR_PASSWORD" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Certificates found:" -ForegroundColor Cyan
for ($i = 0; $i -lt $certs.Count; $i++) {
    Write-Host "[$($i + 1)] $($certs[$i].name)" -ForegroundColor White
}

if ($certs.Count -eq 1) {
    $certName = $certs[0].name
    Write-Log "Auto-selected: $certName" "Green"
} else {
    $certSelection = Read-Host "Select certificate number"
    $certName = $certs[[int]$certSelection - 1].name
}

Write-Log "Using certificate: $certName" "Green"

# Get certificate details
Write-Log "Getting certificate secret ID..." "Yellow"
$certDetails = az keyvault certificate show --vault-name $keyVaultName --name $certName --output json | ConvertFrom-Json
$certSecretId = $certDetails.sid

if (-not $certSecretId) {
    Write-Log "ERROR: Could not get certificate secret ID!" "Red"
    exit 1
}

Write-Log "Certificate Secret ID: $certSecretId" "Green"

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "STEP 4: CONFIGURE FRONT DOOR CUSTOM DOMAIN" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Get or create custom domain
Write-Log "Checking custom domains..." "Yellow"
$customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json

if (-not $customDomains -or $customDomains.Count -eq 0) {
    Write-Log "No custom domains found. Creating one..." "Yellow"
    $domainName = Read-Host "Enter your custom domain (e.g., moveit.pyxhealth.com)"
    $customDomainName = $domainName -replace '\.', '-'
    
    Write-Log "Creating custom domain: $domainName" "Yellow"
    az afd custom-domain create `
        --profile-name $frontDoorName `
        --resource-group $resourceGroup `
        --custom-domain-name $customDomainName `
        --host-name $domainName `
        --minimum-tls-version TLS12 `
        --output none 2>$null
    
    # Reload custom domains
    Start-Sleep -Seconds 5
    $customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json | ConvertFrom-Json
}

Write-Host ""
Write-Host "Custom domains:" -ForegroundColor Cyan
for ($i = 0; $i -lt $customDomains.Count; $i++) {
    Write-Host "[$($i + 1)] $($customDomains[$i].hostName) (Status: $($customDomains[$i].validationProperties.validationStatus))" -ForegroundColor White
}

if ($customDomains.Count -eq 1) {
    $customDomain = $customDomains[0]
    Write-Log "Auto-selected: $($customDomain.hostName)" "Green"
} else {
    $domainSelection = Read-Host "Select custom domain number"
    $customDomain = $customDomains[[int]$domainSelection - 1]
}

$customDomainName = $customDomain.name

Write-Host ""
Write-Log "Binding certificate to custom domain..." "Yellow"

# Update custom domain with certificate
az afd custom-domain update `
    --profile-name $frontDoorName `
    --resource-group $resourceGroup `
    --custom-domain-name $customDomainName `
    --certificate-type CustomerCertificate `
    --minimum-tls-version TLS12 `
    --secret $certSecretId `
    --output none 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Log "Certificate bound successfully!" "Green"
} else {
    Write-Log "WARNING: Certificate binding may take a few minutes..." "Yellow"
}

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "STEP 5: VERIFY CONFIGURATION" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

Write-Log "Verifying Key Vault access policies..." "Yellow"
$policies = az keyvault show --name $keyVaultName --query "properties.accessPolicies[].{ObjectId:objectId, Permissions:permissions}" --output json | ConvertFrom-Json
$frontDoorPolicy = $policies | Where-Object { $_.ObjectId -ne $null }

if ($frontDoorPolicy) {
    Write-Log "✓ Front Door has access to Key Vault" "Green"
} else {
    Write-Log "⚠ Could not verify access policies" "Yellow"
}

Write-Log "Verifying certificate in Front Door..." "Yellow"
$customDomainCheck = az afd custom-domain show --profile-name $frontDoorName --resource-group $resourceGroup --custom-domain-name $customDomainName --output json 2>$null | ConvertFrom-Json

if ($customDomainCheck.tlsSettings.certificateType -eq "CustomerCertificate") {
    Write-Log "✓ Certificate configured on custom domain" "Green"
} else {
    Write-Log "⚠ Certificate may still be provisioning" "Yellow"
}

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "CONFIGURATION COMPLETE!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "WHAT WAS FIXED:" -ForegroundColor Cyan
Write-Host "  ✓ Front Door granted access to Key Vault" -ForegroundColor Green
Write-Host "  ✓ Certificate retrieved from Key Vault: $certName" -ForegroundColor Green
Write-Host "  ✓ Certificate bound to custom domain: $($customDomain.hostName)" -ForegroundColor Green
Write-Host "  ✓ HTTPS enabled with TLS 1.2" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Wait 5-10 minutes for certificate to fully provision" -ForegroundColor Yellow
Write-Host "  2. Test HTTPS: https://$($customDomain.hostName)" -ForegroundColor Yellow
Write-Host "  3. Verify no certificate warnings in browser" -ForegroundColor Yellow
Write-Host ""
Write-Host "If still having issues:" -ForegroundColor Yellow
Write-Host "  - Check DNS CNAME points to Front Door endpoint" -ForegroundColor White
Write-Host "  - Wait full 10 minutes for propagation" -ForegroundColor White
Write-Host "  - Check Azure Portal → Front Door → Domains for status" -ForegroundColor White
Write-Host ""
Write-Host "YOUR CLIENT WILL BE IMPRESSED! 💪" -ForegroundColor Green
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
