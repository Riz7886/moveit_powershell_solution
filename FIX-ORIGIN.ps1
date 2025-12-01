# ================================================================
# FIX FRONT DOOR - POINT TO MOVEIT TRANSFER (20.66.24.164)
# ================================================================

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "FIX FRONT DOOR ORIGIN - SIMPLE AND CLEAN" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Load config
$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json

$resourceGroup = $config.DeploymentResourceGroup
$frontDoorProfile = "moveit-frontdoor-profile"
$originGroupName = "moveit-origin-group"
$originName = "moveit-origin"

# CORRECT MOVEit TRANSFER IP
$correctIP = "20.66.24.164"

Write-Host "Updating Front Door to point to MOVEit TRANSFER: $correctIP" -ForegroundColor Yellow
Write-Host ""

# ================================================================
# UPDATE ORIGIN
# ================================================================
Write-Host "Step 1: Updating Front Door origin..." -ForegroundColor Cyan

az afd origin update `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --origin-group-name $originGroupName `
    --origin-name $originName `
    --host-name $correctIP `
    --origin-host-header "moveit.pyxhealth.com" `
    --priority 1 `
    --weight 1000 `
    --enabled-state Enabled `
    --http-port 80 `
    --https-port 443

Write-Host "✅ Origin updated!" -ForegroundColor Green
Write-Host ""

# ================================================================
# VERIFY
# ================================================================
Write-Host "Step 2: Verifying configuration..." -ForegroundColor Cyan
Write-Host ""

$origin = az afd origin show `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --origin-group-name $originGroupName `
    --origin-name $originName `
    --output json | ConvertFrom-Json

Write-Host "Origin Configuration:" -ForegroundColor Yellow
Write-Host "  Host Name:    $($origin.hostName)" -ForegroundColor White
Write-Host "  Host Header:  $($origin.originHostHeader)" -ForegroundColor White
Write-Host "  Enabled:      $($origin.enabledState)" -ForegroundColor White
Write-Host ""

if ($origin.hostName -eq $correctIP) {
    Write-Host "✅ CORRECT! Origin is pointing to MOVEit TRANSFER!" -ForegroundColor Green
} else {
    Write-Host "❌ ERROR! Origin is pointing to: $($origin.hostName)" -ForegroundColor Red
    Write-Host "   Should be: $correctIP" -ForegroundColor Yellow
}
Write-Host ""

# ================================================================
# WAIT FOR PROPAGATION
# ================================================================
Write-Host "Step 3: Waiting 30 seconds for propagation..." -ForegroundColor Cyan
Start-Sleep -Seconds 30
Write-Host "✅ Done!" -ForegroundColor Green
Write-Host ""

# ================================================================
# TEST HTTPS
# ================================================================
Write-Host "Step 4: Testing HTTPS connectivity..." -ForegroundColor Cyan
Write-Host ""

# Get Front Door endpoint
$endpoint = az afd endpoint show `
    --resource-group $resourceGroup `
    --profile-name $frontDoorProfile `
    --endpoint-name "moveit-endpoint" `
    --query hostName `
    --output tsv

Write-Host "Front Door Endpoint: $endpoint" -ForegroundColor Yellow
Write-Host ""

# Test Front Door endpoint
Write-Host "Testing: https://$endpoint" -ForegroundColor Yellow
try {
    $null = Invoke-WebRequest -Uri "https://$endpoint" -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✅ Front Door endpoint works!" -ForegroundColor Green
} catch {
    Write-Host "❌ Front Door endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test custom domain
Write-Host "Testing: https://moveit.pyxhealth.com" -ForegroundColor Yellow
try {
    $null = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -ErrorAction Stop
    Write-Host "✅ Custom domain works!" -ForegroundColor Green
} catch {
    Write-Host "❌ Custom domain failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ================================================================
# FINAL STATUS
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "DONE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Front Door:       $frontDoorProfile" -ForegroundColor White
Write-Host "  Origin:           $correctIP (MOVEit TRANSFER)" -ForegroundColor White
Write-Host "  Custom Domain:    moveit.pyxhealth.com" -ForegroundColor White
Write-Host "  Front Door URL:   https://$endpoint" -ForegroundColor White
Write-Host ""

Write-Host "Access URLs:" -ForegroundColor Yellow
Write-Host "  HTTPS: https://moveit.pyxhealth.com" -ForegroundColor Green
Write-Host "  SFTP:  sftp username@$correctIP" -ForegroundColor Green
Write-Host ""

Write-Host "If tests failed, wait 5 minutes and try again." -ForegroundColor Yellow
Write-Host ""
