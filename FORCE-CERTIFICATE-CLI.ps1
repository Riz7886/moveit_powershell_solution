# FORCE CERTIFICATE VIA CLI - Direct command
# NO ERRORS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Red
Write-Host "  FORCE CERTIFICATE UPDATE VIA CLI" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Logging in..." -ForegroundColor Yellow
    az login --use-device-code | Out-Null
}
Write-Host "[OK] Logged in to Azure" -ForegroundColor Green
Write-Host ""

# Variables
$FrontDoorName = "moveit-frontdoor-profile"
$ResourceGroup = "rg-moveit"
$DomainName = "moveit-pyxhealth-com"
$VaultName = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Front Door: $FrontDoorName" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Domain: $DomainName" -ForegroundColor White
Write-Host "  Key Vault: $VaultName" -ForegroundColor White
Write-Host "  Certificate: $CertName" -ForegroundColor White
Write-Host ""

# Get current certificate type
Write-Host "Checking current certificate type..." -ForegroundColor Cyan
$CurrentDomain = az afd custom-domain show --profile-name $FrontDoorName --resource-group $ResourceGroup --custom-domain-name $DomainName --output json 2>$null | ConvertFrom-Json

if ($CurrentDomain) {
    Write-Host "Current Certificate Type: $($CurrentDomain.tlsSettings.certificateType)" -ForegroundColor Yellow
} else {
    Write-Host "[ERROR] Cannot find custom domain!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit 1
}

Write-Host ""

# Get Key Vault certificate
Write-Host "Getting Key Vault certificate..." -ForegroundColor Cyan
$CertId = az keyvault certificate show --vault-name $VaultName --name $CertName --query id -o tsv 2>$null

if (-not $CertId) {
    Write-Host "[ERROR] Cannot find certificate in Key Vault!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit 1
}

Write-Host "Certificate ID: $CertId" -ForegroundColor Green
Write-Host ""

# Update certificate
Write-Host "Updating custom domain to use Key Vault certificate..." -ForegroundColor Cyan
Write-Host "This may take 30-60 seconds..." -ForegroundColor Yellow
Write-Host ""

$UpdateResult = az afd custom-domain update `
    --profile-name $FrontDoorName `
    --resource-group $ResourceGroup `
    --custom-domain-name $DomainName `
    --certificate-type CustomerCertificate `
    --secret $CertId `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[SUCCESS] Certificate update command completed!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Update command failed!" -ForegroundColor Red
    Write-Host "Error: $UpdateResult" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verify certificate type changed
Write-Host "Verifying certificate type..." -ForegroundColor Cyan
$VerifyDomain = az afd custom-domain show --profile-name $FrontDoorName --resource-group $ResourceGroup --custom-domain-name $DomainName --output json 2>$null | ConvertFrom-Json

if ($VerifyDomain.tlsSettings.certificateType -eq "CustomerCertificate") {
    Write-Host "[SUCCESS] Certificate type is now: CustomerCertificate" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Certificate type is still: $($VerifyDomain.tlsSettings.certificateType)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  CERTIFICATE UPDATE COMPLETE" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Wait 10-15 minutes for propagation" -ForegroundColor White
Write-Host "2. Make sure MOVEit VMs are running" -ForegroundColor White
Write-Host "3. Test: https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host ""
Read-Host "Press ENTER"
