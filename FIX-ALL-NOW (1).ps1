# FIX ALL NOW - Forces everything to correct state
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "======================================" -ForegroundColor Red
Write-Host "  FIXING EVERYTHING NOW" -ForegroundColor Red
Write-Host "======================================" -ForegroundColor Red
Write-Host ""

az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}

$FD = "moveit-frontdoor-profile"
$RG = "rg-moveit"
$CDName = "moveit-pyxhealth-com"

Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

# Get endpoint
$EPs = az afd endpoint list --profile-name $FD --resource-group $RG --output json 2>$null | ConvertFrom-Json
$EP = $EPs[0]
$EPName = $EP.name

Write-Host "Endpoint: $EPName" -ForegroundColor Cyan
Write-Host ""

# FIX 1: Enable endpoint if disabled
Write-Host "FIX 1: Enabling Endpoint" -ForegroundColor Yellow
if ($EP.enabledState -ne "Enabled") {
    Write-Host "Endpoint is disabled - enabling..." -ForegroundColor Red
    az afd endpoint update --profile-name $FD --resource-group $RG --endpoint-name $EPName --enabled-state Enabled --output none 2>$null
    Write-Host "[FIXED]" -ForegroundColor Green
} else {
    Write-Host "[OK] Already enabled" -ForegroundColor Green
}

Write-Host ""

# FIX 2: Get route and enable it
Write-Host "FIX 2: Enabling Route" -ForegroundColor Yellow
$Routes = az afd route list --profile-name $FD --resource-group $RG --endpoint-name $EPName --output json 2>$null | ConvertFrom-Json

if ($Routes -and $Routes.Count -gt 0) {
    $Route = $Routes[0]
    $RouteName = $Route.name
    
    Write-Host "Route: $RouteName" -ForegroundColor White
    
    if ($Route.enabledState -ne "Enabled") {
        Write-Host "Route is disabled - enabling..." -ForegroundColor Red
        az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --enabled-state Enabled --output none 2>$null
        Write-Host "[FIXED]" -ForegroundColor Green
    } else {
        Write-Host "[OK] Already enabled" -ForegroundColor Green
    }
    
    # FIX 3: Attach custom domain to route if missing
    Write-Host ""
    Write-Host "FIX 3: Attaching Custom Domain to Route" -ForegroundColor Yellow
    
    $CD = az afd custom-domain show --profile-name $FD --resource-group $RG --custom-domain-name $CDName --output json 2>$null | ConvertFrom-Json
    $CDId = $CD.id
    
    if ($Route.customDomains -and $Route.customDomains.Count -gt 0) {
        Write-Host "[OK] Custom domain already attached" -ForegroundColor Green
    } else {
        Write-Host "Attaching custom domain..." -ForegroundColor Red
        az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --custom-domains $CDId --output none 2>$null
        Write-Host "[FIXED]" -ForegroundColor Green
    }
} else {
    Write-Host "[ERROR] No routes found!" -ForegroundColor Red
}

Write-Host ""

# FIX 4: Force certificate
Write-Host "FIX 4: Certificate" -ForegroundColor Yellow
$KV = "kv-moveit-prod"
$CN = "wildcardpyxhealth"

$CertID = az keyvault certificate show --vault-name $KV --name $CN --query id -o tsv 2>$null

if ($CertID) {
    az afd custom-domain update --profile-name $FD --resource-group $RG --custom-domain-name $CDName --certificate-type CustomerCertificate --secret $CertID --output none 2>$null
    Write-Host "[OK] Certificate updated" -ForegroundColor Green
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  ALL FIXES APPLIED" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Wait 5 minutes then test:" -ForegroundColor Yellow
Write-Host "https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host ""
Read-Host "Press ENTER"
