# ================================================================
# MOVEIT FRONT DOOR CERT + KEYVAULT AUTOMATION
# - Detects subscription
# - Ensures Resource Group + Key Vault
# - Imports MOVEit PFX cert into Key Vault
# - Enables HTTPS on Azure Front Door custom domains using KV cert
# Version: 1.0
# ================================================================

param(
    [string]$ResourceGroup = "rg-networking",        # RG that holds Front Door (or will be created)
    [string]$Location      = "westus",               # Azure region
    [string]$KeyVaultName  = "kv-moveit-cert-prod",  # Must be globally unique
    [string]$FrontDoorProfileName = "moveit-frontdoor-profile",
    [string]$CustomDomain1 = "moveit.pyxhealth.com",
    [string]$CustomDomain2 = "moveitauto.pyxhealth.com",
    [string]$CertificateName = "moveit-public-cert", # Name inside Key Vault
    [string]$PfxPath = "C:\\Certs\\moveit.pfx"       # LOCAL path to PFX file on this machine
)

# ----------------------------------------------------------------
# FUNCTION: Write Log
# ----------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

Write-Log "============================================" "Cyan"
Write-Log " MOVEIT FRONT DOOR CERT + KEYVAULT SETUP" "Cyan"
Write-Log " Auto-detects subscription like BULLETPROOF script" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# ----------------------------------------------------------------
# STEP 1: CHECK AZURE CLI
# ----------------------------------------------------------------
Write-Log "Checking Azure CLI..." "Yellow"
try {
    $azVersionJson = az version --output json 2>$null
    if (-not $azVersionJson) { throw "az version returned no data" }
    $azVersion = $azVersionJson | ConvertFrom-Json
    Write-Log "Azure CLI version: $($azVersion.'azure-cli')" "Green"
}
catch {
    Write-Log "ERROR: Azure CLI not found or not working." "Red"
    Write-Log "Install from: https://aka.ms/installazurecliwindows" "Yellow"
    exit 1
}

# ----------------------------------------------------------------
# STEP 2: LOGIN TO AZURE (DEVICE CODE IF NEEDED)
# ----------------------------------------------------------------
Write-Log "Checking Azure login status..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Not logged in - starting device code login..." "Yellow"
    az login --use-device-code | Out-Null
}
else {
    Write-Log "Already logged in." "Green"
}

# ----------------------------------------------------------------
# STEP 3: SELECT SUBSCRIPTION (LIKE BULLETPROOF SCRIPT)
# ----------------------------------------------------------------
Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Log "============================================" "Cyan"

$subscriptions = az account list --output json | ConvertFrom-Json
if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Log "ERROR: No subscriptions visible for this account." "Red"
    exit 1
}

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $stateColor = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host ("[{0}] " -f ($i + 1)) -NoNewline -ForegroundColor Cyan
    Write-Host ($sub.name + " ") -NoNewline -ForegroundColor White
    Write-Host ("({0})" -f $sub.state) -ForegroundColor $stateColor
}

Write-Host ""
Write-Host -NoNewline (Get-Date -Format "yyyy-MM-dd HH:mm:ss")" Select subscription number: "
$selection = Read-Host

try {
    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count) {
        throw "Index out of range"
    }
    $selectedSubscription = $subscriptions[$selectedIndex]
    Write-Log "Setting subscription to: $($selectedSubscription.name)" "Cyan"
    az account set --subscription $selectedSubscription.id
    $currentSub = az account show --query name -o tsv
    Write-Log "Active subscription: $currentSub" "Green"
}
catch {
    Write-Log "ERROR: Invalid subscription selection." "Red"
    exit 1
}

Write-Host ""

# ----------------------------------------------------------------
# STEP 4: ENSURE RESOURCE GROUP & KEY VAULT
# ----------------------------------------------------------------
Write-Log "Ensuring Resource Group exists: $ResourceGroup" "Yellow"
$rgExists = az group show --name $ResourceGroup 2>$null
if (-not $rgExists) {
    Write-Log "Resource Group not found. Creating RG $ResourceGroup in $Location..." "Yellow"
    az group create --name $ResourceGroup --location $Location --output none
    Write-Log "Resource Group created." "Green"
}
else {
    Write-Log "Resource Group already exists." "Green"
}

Write-Log "Ensuring Key Vault exists: $KeyVaultName" "Yellow"
$kvExists = az keyvault show --name $KeyVaultName 2>$null
if (-not $kvExists) {
    Write-Log "Key Vault not found. Creating Key Vault $KeyVaultName..." "Yellow"
    az keyvault create `
        --name $KeyVaultName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku standard `
        --enable-soft-delete true `
        --enable-purge-protection true `
        --public-network-access enabled `
        --output none
    Write-Log "Key Vault created." "Green"
}
else {
    Write-Log "Key Vault already exists." "Green"
}

# ----------------------------------------------------------------
# STEP 5: IMPORT PFX CERT INTO KEY VAULT
# ----------------------------------------------------------------
if (-not (Test-Path $PfxPath)) {
    Write-Log "ERROR: PFX file not found at path: $PfxPath" "Red"
    Write-Log "Update -PfxPath parameter to the correct local PFX file." "Yellow"
    exit 1
}

Write-Log "Enter password for the PFX certificate (will not be echoed):" "Yellow"
$certPasswordSecure = Read-Host -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPasswordSecure)
$certPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)

Write-Log "Importing certificate into Key Vault as '$CertificateName'..." "Cyan"
az keyvault certificate import `
    --vault-name $KeyVaultName `
    --name $CertificateName `
    --file $PfxPath `
    --password $certPasswordPlain `
    --output none

Write-Log "Certificate imported into Key Vault." "Green"

# Clear plaintext password from memory
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
$certPasswordPlain = $null

# Get Key Vault ID (needed for Front Door)
$kvId = az keyvault show --name $KeyVaultName --query id -o tsv

# ----------------------------------------------------------------
# STEP 6: ENSURE FRONT DOOR PROFILE & CUSTOM DOMAINS
# ----------------------------------------------------------------
Write-Log "Checking Front Door profile: $FrontDoorProfileName" "Yellow"
$fdProfile = az afd profile show `
    --resource-group $ResourceGroup `
    --profile-name $FrontDoorProfileName 2>$null

if (-not $fdProfile) {
    Write-Log "ERROR: Front Door profile '$FrontDoorProfileName' was not found in RG '$ResourceGroup'." "Red"
    Write-Log "Run the BULLETPROOF MOVEit script first to create Front Door." "Yellow"
    exit 1
}
else {
    Write-Log "Front Door profile exists." "Green"
}

# Helper to ensure a custom domain exists in Front Door
function Ensure-CustomDomain {
    param(
        [string]$HostName
    )
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $null }

    # Name inside Front Door = host name with dots replaced
    $safeName = $HostName.Replace(".","-")
    Write-Log "Ensuring AFD custom domain for host: $HostName  (name: $safeName)" "Cyan"

    $existing = az afd custom-domain show `
        --resource-group $ResourceGroup `
        --profile-name $FrontDoorProfileName `
        --custom-domain-name $safeName 2>$null

    if (-not $existing) {
        Write-Log "Custom domain not found. Creating..." "Yellow"
        az afd custom-domain create `
            --resource-group $ResourceGroup `
            --profile-name $FrontDoorProfileName `
            --custom-domain-name $safeName `
            --host-name $HostName `
            --output none
        Write-Log "Custom domain created: $HostName" "Green"
    }
    else {
        Write-Log "Custom domain already exists: $HostName" "Green"
    }

    return $safeName
}

$cd1Name = Ensure-CustomDomain -HostName $CustomDomain1
$cd2Name = Ensure-CustomDomain -HostName $CustomDomain2

# ----------------------------------------------------------------
# STEP 7: ENABLE HTTPS USING KEY VAULT CERT ON EACH CUSTOM DOMAIN
# ----------------------------------------------------------------
function Enable-HttpsForCustomDomain {
    param(
        [string]$CustomDomainName
    )
    if ([string]::IsNullOrWhiteSpace($CustomDomainName)) { return }

    Write-Log "Enabling HTTPS on AFD custom domain '$CustomDomainName' using Key Vault cert..." "Cyan"

    az afd custom-domain https update `
        --resource-group $ResourceGroup `
        --profile-name $FrontDoorProfileName `
        --custom-domain-name $CustomDomainName `
        --certificate-type CustomerCertificate `
        --secret-source AzureKeyVault `
        --secret-name $CertificateName `
        --secret-version "latest" `
        --vault-id $kvId `
        --output none

    Write-Log "HTTPS enabled via Key Vault certificate for custom domain: $CustomDomainName" "Green"
}

if ($cd1Name) { Enable-HttpsForCustomDomain -CustomDomainName $cd1Name }
if ($cd2Name) { Enable-HttpsForCustomDomain -CustomDomainName $cd2Name }

# ----------------------------------------------------------------
# STEP 8: SUMMARY
# ----------------------------------------------------------------
Write-Log "============================================" "Green"
Write-Log " FRONT DOOR + KEY VAULT CERT CONFIG COMPLETE" "Green"
Write-Log "============================================" "Green"
Write-Host ""

$subName = az account show --query name -o tsv
$fdEndpoints = az afd endpoint list `
    --resource-group $ResourceGroup `
    --profile-name $FrontDoorProfileName `
    --query "[].hostName" -o tsv

Write-Log "Subscription: $subName" "White"
Write-Log "Key Vault:   $KeyVaultName" "White"
Write-Log "Cert Name:   $CertificateName" "White"
Write-Log "Custom FQDNs secured:" "Yellow"
if ($CustomDomain1) { Write-Log " - https://$CustomDomain1" "Green" }
if ($CustomDomain2) { Write-Log " - https://$CustomDomain2" "Green" }
Write-Host ""
Write-Log "Front Door endpoints (CNAME targets):" "Yellow"
$fdEndpoints | ForEach-Object { Write-Log " - $_" "White" }

Write-Host ""
Write-Log "DONE. Update public DNS CNAMEs to point to the Front Door endpoint hostnames above." "Cyan"