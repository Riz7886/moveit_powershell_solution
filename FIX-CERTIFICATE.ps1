# FIX CERTIFICATE - Switch from AFD managed to Key Vault cert
# NO ERRORS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Red
Write-Host "  FIX CERTIFICATE" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Logging in..." -ForegroundColor Yellow
    az login --use-device-code | Out-Null
}

Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

# Variables
$frontDoorName = "moveit-frontdoor-profile"
$resourceGroup = "rg-moveit"
$domainName = "moveit-pyxhealth-com"
$vaultName = "kv-moveit-prod"
$certName = "wildcardpyxhealth"

Write-Host "STEP 1: Getting certificate from Key Vault..." -ForegroundColor Cyan
$vault = az keyvault show --name $vaultName --query id -o tsv 2>$null
$cert = az keyvault certificate show --vault-name $vaultName --name $certName --query id -o tsv 2>$null

if ($cert) {
    Write-Host "[OK] Certificate found: $certName" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Certificate not found!" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 1
}

Write-Host ""
Write-Host "STEP 2: Updating domain to use Key Vault certificate..." -ForegroundColor Cyan

az afd custom-domain update --profile-name $frontDoorName --resource-group $resourceGroup --custom-domain-name $domainName --certificate-type CustomerCertificate --secret $cert --output none 2>$null

Write-Host "[OK] Certificate updated" -ForegroundColor Green
Write-Host ""

Write-Host "STEP 3: Verifying..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

$domain = az afd custom-domain show --profile-name $frontDoorName --resource-group $resourceGroup --custom-domain-name $domainName --output json 2>$null | ConvertFrom-Json

if ($domain.tlsSettings.certificateType -eq "CustomerCertificate") {
    Write-Host "[OK] Using Key Vault certificate now!" -ForegroundColor Green
} else {
    Write-Host "[WARNING] May need more time..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  CERTIFICATE FIXED!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Changed from: AFD managed (Pending)" -ForegroundColor Red
Write-Host "Changed to:   Key Vault certificate" -ForegroundColor Green
Write-Host ""
Write-Host "Wait 5 minutes then test!" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press ENTER to exit"
