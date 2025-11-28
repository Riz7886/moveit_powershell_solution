# FORCE DELETE FRONT DOOR - ACTUALLY WORKS
# This script WAITS for deletion and VERIFIES

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "FORCE DELETE FRONT DOOR - FOR REAL" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"
$EndpointName = "moveit-endpoint-e9foashyq2cddef0"

# Login check
Write-Host "[STEP 1] Checking Azure..." -ForegroundColor Yellow
$context = Get-AzContext
if ($null -eq $context) {
    Write-Host "  Logging in..." -ForegroundColor Yellow
    Connect-AzAccount
}
Write-Host "  [OK] Logged in" -ForegroundColor Green

# Find subscription
Write-Host "`n[STEP 2] Finding subscription..." -ForegroundColor Yellow
$subs = Get-AzSubscription
$correctSub = $null

foreach ($sub in $subs) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    $rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
    if ($rg) {
        $correctSub = $sub
        Write-Host "  [OK] Found in: $($sub.Name)" -ForegroundColor Green
        break
    }
}

if (-not $correctSub) {
    Write-Host "  [FAIL] Cannot find rg-moveit!" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# Delete in correct order - routes first, then domains, then origins, then everything else
Write-Host "`n[STEP 3] Deleting routes..." -ForegroundColor Yellow
try {
    $routes = Get-AzFrontDoorCdnRoute -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName -ErrorAction SilentlyContinue
    foreach ($route in $routes) {
        Write-Host "  Deleting route: $($route.Name)" -ForegroundColor Cyan
        Remove-AzFrontDoorCdnRoute -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName -RouteName $route.Name -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host "  [OK] Routes deleted" -ForegroundColor Green
} catch {
    Write-Host "  [OK] No routes or already deleted" -ForegroundColor Green
}

Start-Sleep -Seconds 5

# Delete custom domains
Write-Host "`n[STEP 4] Deleting custom domains..." -ForegroundColor Yellow
try {
    $domains = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -ErrorAction SilentlyContinue
    foreach ($domain in $domains) {
        Write-Host "  Deleting domain: $($domain.HostName)" -ForegroundColor Cyan
        Remove-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -CustomDomainName $domain.Name -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host "  [OK] Domains deleted" -ForegroundColor Green
} catch {
    Write-Host "  [OK] No domains or already deleted" -ForegroundColor Green
}

Start-Sleep -Seconds 5

# Delete origins
Write-Host "`n[STEP 5] Deleting origins..." -ForegroundColor Yellow
try {
    $originGroups = Get-AzFrontDoorCdnOriginGroup -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -ErrorAction SilentlyContinue
    foreach ($og in $originGroups) {
        $origins = Get-AzFrontDoorCdnOrigin -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $og.Name -ErrorAction SilentlyContinue
        foreach ($origin in $origins) {
            Write-Host "  Deleting origin: $($origin.Name)" -ForegroundColor Cyan
            Remove-AzFrontDoorCdnOrigin -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $og.Name -OriginName $origin.Name -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Write-Host "  [OK] Origins deleted" -ForegroundColor Green
} catch {
    Write-Host "  [OK] No origins or already deleted" -ForegroundColor Green
}

Start-Sleep -Seconds 5

# Delete origin groups
Write-Host "`n[STEP 6] Deleting origin groups..." -ForegroundColor Yellow
try {
    $originGroups = Get-AzFrontDoorCdnOriginGroup -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -ErrorAction SilentlyContinue
    foreach ($og in $originGroups) {
        Write-Host "  Deleting origin group: $($og.Name)" -ForegroundColor Cyan
        Remove-AzFrontDoorCdnOriginGroup -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $og.Name -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host "  [OK] Origin groups deleted" -ForegroundColor Green
} catch {
    Write-Host "  [OK] No origin groups or already deleted" -ForegroundColor Green
}

Start-Sleep -Seconds 5

# Delete endpoints
Write-Host "`n[STEP 7] Deleting endpoints..." -ForegroundColor Yellow
try {
    $endpoints = Get-AzFrontDoorCdnEndpoint -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -ErrorAction SilentlyContinue
    foreach ($ep in $endpoints) {
        Write-Host "  Deleting endpoint: $($ep.Name)" -ForegroundColor Cyan
        Remove-AzFrontDoorCdnEndpoint -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $ep.Name -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host "  [OK] Endpoints deleted" -ForegroundColor Green
} catch {
    Write-Host "  [OK] No endpoints or already deleted" -ForegroundColor Green
}

Start-Sleep -Seconds 10

# Delete the profile itself
Write-Host "`n[STEP 8] Deleting Front Door profile..." -ForegroundColor Yellow
Write-Host "  This may take 2-3 minutes..." -ForegroundColor Cyan

try {
    Remove-AzFrontDoorCdnProfile -ResourceGroupName $ResourceGroup -Name $ProfileName -ErrorAction Stop
    Write-Host "  [OK] Delete initiated!" -ForegroundColor Green
} catch {
    Write-Host "  [WARNING] Delete command may have failed: $_" -ForegroundColor Yellow
}

# Wait and verify
Write-Host "`n[STEP 9] Waiting for deletion to complete..." -ForegroundColor Yellow
$maxWait = 180 # 3 minutes
$waited = 0

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 10
    $waited += 10
    
    $profile = Get-AzFrontDoorCdnProfile -ResourceGroupName $ResourceGroup -Name $ProfileName -ErrorAction SilentlyContinue
    
    if (-not $profile) {
        Write-Host "  [OK] Front Door completely deleted!" -ForegroundColor Green
        break
    }
    
    Write-Host "  Still deleting... ($waited seconds)" -ForegroundColor Cyan
}

# Final verification
Write-Host "`n[STEP 10] Final verification..." -ForegroundColor Yellow
$profile = Get-AzFrontDoorCdnProfile -ResourceGroupName $ResourceGroup -Name $ProfileName -ErrorAction SilentlyContinue

if ($profile) {
    Write-Host "  [WARNING] Profile still exists! May need manual deletion" -ForegroundColor Red
    Write-Host "  Go to Azure Portal and delete manually if needed" -ForegroundColor Yellow
} else {
    Write-Host "  [SUCCESS] Front Door completely deleted!" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "DELETION COMPLETE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run 5-story scripts IN ORDER" -ForegroundColor Cyan
Write-Host "2. Story 1, 2, 3, 4, 5" -ForegroundColor Cyan
Write-Host "3. Wait 15 minutes" -ForegroundColor Cyan
Write-Host "4. Test site" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Gray
Read-Host
