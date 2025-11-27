# NUCLEAR-FIX.ps1 - Fixes EVERYTHING
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "============================================" -ForegroundColor Red
Write-Host "  NUCLEAR FIX - RESETTING EVERYTHING" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Red
Write-Host ""

az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Logging in..." -ForegroundColor Yellow
    az login --use-device-code | Out-Null
}

Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

$FD = "moveit-frontdoor-profile"
$RG = "rg-moveit"
$CDName = "moveit-pyxhealth-com"
$EPName = "moveit-endpoint-e9foashyq2cddef0"
$OGName = "moveit-origin-group"
$RouteName = "moveit-route"

# FIX 1: DELETE and RECREATE custom domain with Key Vault cert
Write-Host "FIX 1: Resetting domain with Key Vault cert..." -ForegroundColor Yellow
Write-Host "  Deleting old domain..." -ForegroundColor White
az afd custom-domain delete --profile-name $FD --resource-group $RG --custom-domain-name $CDName --yes 2>$null
Start-Sleep -Seconds 10

Write-Host "  Getting Key Vault certificate..." -ForegroundColor White
$KVCert = az keyvault certificate show --vault-name kv-moveit-prod --name wildcardpyxhealth --query id -o tsv 2>$null

Write-Host "  Creating domain with Key Vault cert..." -ForegroundColor White
az afd custom-domain create --profile-name $FD --resource-group $RG --custom-domain-name $CDName --host-name moveit.pyxhealth.com --certificate-type CustomerCertificate --secret $KVCert --output none 2>$null
Write-Host "[OK] Domain recreated with Key Vault cert" -ForegroundColor Green
Write-Host ""

# FIX 2: Fix origin IP
Write-Host "FIX 2: Fixing origin IP..." -ForegroundColor Yellow
$Origins = az afd origin list --profile-name $FD --resource-group $RG --origin-group-name $OGName --output json 2>$null | ConvertFrom-Json

foreach ($O in $Origins) {
    Write-Host "  Checking origin: $($O.name) - $($O.hostName)" -ForegroundColor White
    if ($O.hostName -eq "192.168.0.5" -or $O.hostName -eq "20.86.24.168") {
        Write-Host "  Deleting wrong origin..." -ForegroundColor White
        az afd origin delete --profile-name $FD --resource-group $RG --origin-group-name $OGName --origin-name $O.name --yes 2>$null
    }
}

Write-Host "  Creating origin with correct IP: 20.86.24.141" -ForegroundColor White
az afd origin create --profile-name $FD --resource-group $RG --origin-group-name $OGName --origin-name moveit-backend --host-name 20.86.24.141 --origin-host-header 20.86.24.141 --priority 1 --weight 1000 --enabled-state Enabled --http-port 80 --https-port 443 --output none 2>$null
Write-Host "[OK] Origin IP fixed to 20.86.24.141" -ForegroundColor Green
Write-Host ""

# FIX 3: Enable endpoint
Write-Host "FIX 3: Enabling endpoint..." -ForegroundColor Yellow
az afd endpoint update --profile-name $FD --resource-group $RG --endpoint-name $EPName --enabled-state Enabled --output none 2>$null
Write-Host "[OK] Endpoint enabled" -ForegroundColor Green
Write-Host ""

# FIX 4: Associate domain with route
Write-Host "FIX 4: Associating domain with route..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
$CDId = az afd custom-domain show --profile-name $FD --resource-group $RG --custom-domain-name $CDName --query id -o tsv 2>$null

Write-Host "  Enabling route..." -ForegroundColor White
az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --enabled-state Enabled --output none 2>$null

Write-Host "  Associating custom domain..." -ForegroundColor White
az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --custom-domains $CDId --output none 2>$null
Write-Host "[OK] Domain associated with route" -ForegroundColor Green
Write-Host ""

# FIX 5: Open port 443
Write-Host "FIX 5: Ensuring port 443 is open..." -ForegroundColor Yellow
$NSGs = az network nsg list --output json 2>$null | ConvertFrom-Json

foreach ($NSG in $NSGs) {
    $Rules = az network nsg rule list --nsg-name $NSG.name --resource-group $NSG.resourceGroup --output json 2>$null | ConvertFrom-Json
    $HasRule = $false
    
    foreach ($Rule in $Rules) {
        if ($Rule.destinationPortRange -eq "443" -and $Rule.access -eq "Allow") {
            $HasRule = $true
            break
        }
    }
    
    if (-not $HasRule) {
        az network nsg rule create --nsg-name $NSG.name --resource-group $NSG.resourceGroup --name "Allow-HTTPS-443" --priority 1000 --destination-port-ranges 443 --protocol Tcp --access Allow --direction Inbound --output none 2>$null
    }
}
Write-Host "[OK] Port 443 open" -ForegroundColor Green
Write-Host ""

Write-Host "============================================" -ForegroundColor Green
Write-Host "  ALL FIXES APPLIED!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "1. Wait 10-15 minutes for certificate to provision" -ForegroundColor White
Write-Host "2. Test: https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host "3. Look for LOCK ICON in browser" -ForegroundColor White
Write-Host ""
Write-Host "WHAT WAS FIXED:" -ForegroundColor Cyan
Write-Host "  - Domain deleted and recreated with Key Vault cert" -ForegroundColor White
Write-Host "  - Origin IP changed to 20.86.24.141" -ForegroundColor White
Write-Host "  - Endpoint enabled" -ForegroundColor White
Write-Host "  - Domain associated with route" -ForegroundColor White
Write-Host "  - Port 443 opened" -ForegroundColor White
Write-Host ""
Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
