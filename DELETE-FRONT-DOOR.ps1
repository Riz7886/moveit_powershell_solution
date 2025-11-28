# DELETE FRONT DOOR - COMPLETE CLEANUP
# Run this BEFORE redeploying with 5-story script

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "DELETE FRONT DOOR - NUCLEAR CLEANUP" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"

Write-Host "[WARNING] This will DELETE the entire Front Door profile!" -ForegroundColor Yellow
Write-Host "You will need to redeploy with the 5-story script after this." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Type YES to continue"

if ($confirm -ne "YES") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# Check Azure CLI
Write-Host "`n[STEP 1] Checking Azure CLI..." -ForegroundColor Yellow
try {
    az version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Azure CLI not installed!" -ForegroundColor Red
        exit
    }
    Write-Host "  [OK] Azure CLI ready" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Azure CLI not found!" -ForegroundColor Red
    exit
}

# Login check
Write-Host "`n[STEP 2] Checking login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Logging in..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "  [OK] Logged in: $($account.user.name)" -ForegroundColor Green

# Find correct subscription
Write-Host "`n[STEP 3] Finding subscription with rg-moveit..." -ForegroundColor Yellow
$subs = az account list | ConvertFrom-Json
$correctSub = $null

foreach ($sub in $subs) {
    az account set --subscription $sub.id 2>$null
    $testRg = az group show --name $ResourceGroup 2>$null
    if ($LASTEXITCODE -eq 0) {
        $correctSub = $sub
        Write-Host "  [OK] Found in: $($sub.name)" -ForegroundColor Green
        break
    }
}

if (-not $correctSub) {
    Write-Host "  [FAIL] Could not find rg-moveit!" -ForegroundColor Red
    exit
}

# Delete Front Door Profile
Write-Host "`n[STEP 4] Deleting Front Door profile..." -ForegroundColor Yellow
Write-Host "  This may take 5-10 minutes..." -ForegroundColor Cyan

az afd profile delete `
    --profile-name $ProfileName `
    --resource-group $ResourceGroup `
    --yes 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Front Door deleted!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Delete may have failed or profile doesn't exist" -ForegroundColor Yellow
}

# Verify deletion
Write-Host "`n[STEP 5] Verifying deletion..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$profiles = az afd profile list --resource-group $ResourceGroup 2>$null | ConvertFrom-Json

if (-not $profiles -or $profiles.Count -eq 0) {
    Write-Host "  [OK] Front Door completely deleted!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Some profiles may still exist" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "CLEANUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run the 5-story deployment scripts IN ORDER" -ForegroundColor Cyan
Write-Host "2. Start with Story 1 (Prerequisites)" -ForegroundColor Cyan
Write-Host "3. Then Story 2, 3, 4, 5" -ForegroundColor Cyan
Write-Host "4. Wait 15 minutes after Story 5 completes" -ForegroundColor Cyan
Write-Host "5. Test: https://moveit.pyxhealth.com" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Gray
Read-Host
