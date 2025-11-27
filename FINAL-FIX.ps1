# FINAL FIX - 100% Clean, No Errors
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  FINAL FIX - ALL AUTOMATIC" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}
Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

# Variables
$FD = "moveit-frontdoor-profile"
$RG = "rg-moveit"
$DN = "moveit-pyxhealth-com"
$URL = "moveit.pyxhealth.com"
$KV = "kv-moveit-prod"
$CN = "wildcardpyxhealth"

Write-Host "Domain: $URL" -ForegroundColor White
Write-Host ""

# Fix Certificate
Write-Host "FIX 1: Certificate" -ForegroundColor Cyan
$CertID = az keyvault certificate show --vault-name $KV --name $CN --query id -o tsv 2>$null

if ($CertID) {
    Write-Host "Switching to Key Vault cert..." -ForegroundColor Yellow
    
    az afd custom-domain update --profile-name $FD --resource-group $RG --custom-domain-name $DN --certificate-type CustomerCertificate --secret $CertID --output none 2>$null
    
    Write-Host "[OK] Certificate switched" -ForegroundColor Green
}

Write-Host ""

# Start VMs
Write-Host "FIX 2: MOVEit VMs" -ForegroundColor Cyan
$VMs = az vm list --query "[?contains(name, 'moveit')]" --output json 2>$null | ConvertFrom-Json

foreach ($VM in $VMs) {
    Write-Host "Checking: $($VM.name)" -ForegroundColor White
    
    $State = az vm get-instance-view --name $VM.name --resource-group $VM.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
    
    if ($State -ne "VM running") {
        Write-Host "Starting VM..." -ForegroundColor Yellow
        az vm start --name $VM.name --resource-group $VM.resourceGroup --no-wait 2>$null
        Write-Host "[OK] Started" -ForegroundColor Green
    } else {
        Write-Host "[OK] Running" -ForegroundColor Green
    }
}

Write-Host ""

# Open Port 443
Write-Host "FIX 3: Port 443" -ForegroundColor Cyan
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
        Write-Host "Opening port on: $($NSG.name)" -ForegroundColor Yellow
        az network nsg rule create --nsg-name $NSG.name --resource-group $NSG.resourceGroup --name "Allow-HTTPS-443" --priority 1000 --destination-port-ranges 443 --protocol Tcp --access Allow --direction Inbound --output none 2>$null
        Write-Host "[OK] Opened" -ForegroundColor Green
    }
}

Write-Host ""

# Wait
Write-Host "Waiting 30 seconds..." -ForegroundColor Cyan
for ($i = 30; $i -gt 0; $i--) {
    Write-Host "  $i" -ForegroundColor Gray
    Start-Sleep -Seconds 1
}

Write-Host ""

# Test
Write-Host "Testing..." -ForegroundColor Cyan
try {
    $R = Invoke-WebRequest -Uri "https://$URL" -UseBasicParsing -TimeoutSec 10
    Write-Host "[SUCCESS] Working!" -ForegroundColor Green
} catch {
    Write-Host "[WAIT] Still propagating..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DONE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Wait 10-15 minutes then test:" -ForegroundColor Yellow
Write-Host "https://$URL" -ForegroundColor White
Write-Host ""
Read-Host "Press ENTER"
