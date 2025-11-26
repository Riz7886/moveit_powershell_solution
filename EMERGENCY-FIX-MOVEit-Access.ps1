# ================================================================
# EMERGENCY FIX - MOVEIT EXTERNAL ACCESS
# Fix NSG to allow external users to access MOVEit
# ================================================================

Write-Host "================================================================" -ForegroundColor Red
Write-Host "  EMERGENCY FIX - MOVEIT EXTERNAL ACCESS" -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "ISSUE: Users cannot access MOVEit from home" -ForegroundColor Yellow
Write-Host "FIX: Update NSG rules to allow external access" -ForegroundColor Yellow
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

# Configuration
Write-Log "Looking for MOVEit resources..." "Yellow"

# Find the NSG
$nsgName = "nsg-moveit"
$nsgRG = "rg-moveit"

Write-Host ""
Write-Log "============================================" "Cyan"
Write-Log "FIXING NSG RULES" "Cyan"
Write-Log "============================================" "Cyan"
Write-Host ""

# Update NSG rule for HTTPS (port 443) - Allow from Internet
Write-Log "[1/3] Updating HTTPS rule to allow Internet access..." "Yellow"
az network nsg rule update `
    --resource-group $nsgRG `
    --nsg-name $nsgName `
    --name "Allow-HTTPS-443" `
    --source-address-prefixes "Internet" `
    --access Allow `
    --output none 2>$null

# If rule doesn't exist, create it
if ($LASTEXITCODE -ne 0) {
    Write-Log "Rule doesn't exist. Creating new HTTPS rule..." "Yellow"
    az network nsg rule create `
        --resource-group $nsgRG `
        --nsg-name $nsgName `
        --name "Allow-HTTPS-443" `
        --priority 110 `
        --source-address-prefixes "Internet" `
        --destination-address-prefixes "*" `
        --destination-port-ranges 443 `
        --protocol Tcp `
        --access Allow `
        --direction Inbound `
        --output none
}

Write-Log "HTTPS rule updated" "Green"

# Update NSG rule for SFTP (port 22) - Allow from Internet
Write-Log "[2/3] Updating SFTP rule to allow Internet access..." "Yellow"
az network nsg rule update `
    --resource-group $nsgRG `
    --nsg-name $nsgName `
    --name "Allow-SFTP-22" `
    --source-address-prefixes "Internet" `
    --access Allow `
    --output none 2>$null

# If rule doesn't exist, create it
if ($LASTEXITCODE -ne 0) {
    Write-Log "Rule doesn't exist. Creating new SFTP rule..." "Yellow"
    az network nsg rule create `
        --resource-group $nsgRG `
        --nsg-name $nsgName `
        --name "Allow-SFTP-22" `
        --priority 100 `
        --source-address-prefixes "Internet" `
        --destination-address-prefixes "*" `
        --destination-port-ranges 22 `
        --protocol Tcp `
        --access Allow `
        --direction Inbound `
        --output none
}

Write-Log "SFTP rule updated" "Green"

# Verify rules
Write-Log "[3/3] Verifying NSG rules..." "Yellow"
$rules = az network nsg rule list --resource-group $nsgRG --nsg-name $nsgName --output json | ConvertFrom-Json

Write-Host ""
Write-Log "Current NSG Rules:" "Cyan"
foreach ($rule in $rules) {
    if ($rule.name -like "Allow-*") {
        $source = if ($rule.sourceAddressPrefix -eq "Internet") { "Internet (ANY)" } else { $rule.sourceAddressPrefix }
        Write-Host "  ✓ $($rule.name): Port $($rule.destinationPortRange) from $source" -ForegroundColor Green
    }
}

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "NSG RULES FIXED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "WHAT WAS FIXED:" -ForegroundColor Cyan
Write-Host "  ✓ Port 443 (HTTPS) now allows Internet access" -ForegroundColor Green
Write-Host "  ✓ Port 22 (SFTP) now allows Internet access" -ForegroundColor Green
Write-Host "  ✓ External users can now access MOVEit" -ForegroundColor Green
Write-Host ""
Write-Host "TEST NOW:" -ForegroundColor Cyan
Write-Host "  1. Go to: https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host "  2. Should load MOVEit login page" -ForegroundColor White
Write-Host "  3. SFTP: sftp username@PUBLIC_IP" -ForegroundColor White
Write-Host ""
Write-Host "If still not working, check:" -ForegroundColor Yellow
Write-Host "  - Front Door origin health" -ForegroundColor Yellow
Write-Host "  - MOVEit service is running" -ForegroundColor Yellow
Write-Host "  - Windows Firewall on MOVEit server" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
