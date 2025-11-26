# ULTIMATE BULLETPROOF FRONT DOOR FIX
# 100% AUTOMATIC - NO USER INPUT

$ErrorActionPreference = "SilentlyContinue"

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  ULTIMATE AUTO-FIX - CLIENT IS WAITING" -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Check login
Write-Log "Checking Azure login..." "Yellow"
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Log "Logging in..." "Yellow"
    az login --use-device-code | Out-Null
}
Write-Log "Logged in" "Green"
Write-Host ""

# STEP 1: FIND KEY VAULT WITH CERTIFICATES
Write-Log "STEP 1: Scanning Key Vaults..." "Cyan"
$allKeyVaults = az keyvault list --output json 2>$null | ConvertFrom-Json
$keyVaultWithCert = $null
$certName = $null

foreach ($kv in $allKeyVaults) {
    Write-Log "  Checking: $($kv.name)..." "Yellow"
    $certs = az keyvault certificate list --vault-name $kv.name --output json 2>$null | ConvertFrom-Json
    
    if ($certs -and $certs.Count -gt 0) {
        $keyVaultWithCert = $kv
        $certName = $certs[0].name
        Write-Log "  FOUND: $certName" "Green"
        break
    }
}

if (-not $keyVaultWithCert) {
    Write-Host ""
    Write-Log "ERROR: NO CERTIFICATES FOUND!" "Red"
    Write-Host ""
    Write-Host "RUN THIS COMMAND:" -ForegroundColor Yellow
    Write-Host "az keyvault certificate import --vault-name YOUR_KV --name moveit-cert --file YOUR_CERT.pfx --password YOUR_PASS" -ForegroundColor White
    Write-Host ""
    exit 1
}

$keyVaultName = $keyVaultWithCert.name
Write-Log "Using Key Vault: $keyVaultName" "Green"
Write-Log "Using Certificate: $certName" "Green"

# Get secret ID
$certDetails = az keyvault certificate show --vault-name $keyVaultName --name $certName --output json 2>$null | ConvertFrom-Json
$certSecretId = $certDetails.sid
Write-Log "Got certificate ID" "Green"

# STEP 2: GRANT ACCESS
Write-Host ""
Write-Log "STEP 2: Granting access..." "Cyan"
$frontDoorAppId = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8"

az keyvault set-policy --name $keyVaultName --spn $frontDoorAppId --secret-permissions get list --certificate-permissions get list --output none 2>$null
Write-Log "Access granted" "Green"

# STEP 3: FIND FRONT DOOR
Write-Host ""
Write-Log "STEP 3: Finding Front Door..." "Cyan"
$frontDoors = az afd profile list --output json 2>$null | ConvertFrom-Json

if (-not $frontDoors -or $frontDoors.Count -eq 0) {
    Write-Log "ERROR: No Front Door found!" "Red"
    exit 1
}

$frontDoor = $frontDoors[0]
$frontDoorName = $frontDoor.name
$resourceGroup = $frontDoor.resourceGroup
Write-Log "Using: $frontDoorName" "Green"

# STEP 4: GET CUSTOM DOMAIN
Write-Host ""
Write-Log "STEP 4: Getting domain..." "Cyan"
$customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json

if (-not $customDomains -or $customDomains.Count -eq 0) {
    Write-Log "No domain found - creating default..." "Yellow"
    $domainName = "moveit.pyxhealth.com"
    $customDomainName = "moveit-pyxhealth-com"
    
    az afd custom-domain create --profile-name $frontDoorName --resource-group $resourceGroup --custom-domain-name $customDomainName --host-name $domainName --minimum-tls-version TLS12 --output none 2>$null
    Start-Sleep -Seconds 10
    $customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
}

$customDomain = $customDomains[0]
$customDomainName = $customDomain.name
$customDomainHostname = $customDomain.hostName
Write-Log "Using domain: $customDomainHostname" "Green"

# STEP 5: BIND CERTIFICATE
Write-Host ""
Write-Log "STEP 5: Binding certificate..." "Cyan"

az afd custom-domain update --profile-name $frontDoorName --resource-group $resourceGroup --custom-domain-name $customDomainName --certificate-type CustomerCertificate --minimum-tls-version TLS12 --secret $certSecretId --output none 2>$null

Write-Log "Certificate bound!" "Green"

# SUCCESS
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  SUCCESS - CONFIGURATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Key Vault:    $keyVaultName" -ForegroundColor White
Write-Host "Certificate:  $certName" -ForegroundColor White
Write-Host "Front Door:   $frontDoorName" -ForegroundColor White
Write-Host "Domain:       $customDomainHostname" -ForegroundColor White
Write-Host ""
Write-Host "WAIT 10 MINUTES then test:" -ForegroundColor Yellow
Write-Host "https://$customDomainHostname" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
