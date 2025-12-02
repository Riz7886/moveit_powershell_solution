# BULLETPROOF CLEANUP - PROTECTS PRODUCTION NICS
# This script will NOT delete NICs attached to VMs

Clear-Host
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "BULLETPROOF CLEANUP - SAFE VERSION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

# ==================================================
# STEP 1: LIST ALL NICS WITH DETAILS
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "STEP 1: LIST ALL NICS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$allNICsJson = az network nic list --resource-group $rg --output json
$allNICs = $allNICsJson | ConvertFrom-Json

Write-Host "Total NICs found: $($allNICs.Count)" -ForegroundColor White
Write-Host ""

$safeNICs = @()
$unsafeNICs = @()

foreach ($nic in $allNICs) {
    $nicName = $nic.name
    $isAttached = $null -ne $nic.virtualMachine
    
    Write-Host "NIC: $nicName" -ForegroundColor Cyan
    
    if ($isAttached) {
        Write-Host "  Status: ATTACHED TO VM" -ForegroundColor Green
        Write-Host "  VM: $($nic.virtualMachine.id)" -ForegroundColor Green
        Write-Host "  ACTION: PROTECTED - WILL NOT DELETE" -ForegroundColor Green
        $safeNICs += $nicName
    } else {
        Write-Host "  Status: NOT ATTACHED" -ForegroundColor Red
        Write-Host "  ACTION: CANDIDATE FOR DELETION" -ForegroundColor Yellow
        $unsafeNICs += $nicName
    }
    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor White
Write-Host "  Protected NICs (attached to VMs): $($safeNICs.Count)" -ForegroundColor Green
Write-Host "  Unattached NICs (can be deleted): $($unsafeNICs.Count)" -ForegroundColor Yellow
Write-Host ""

if ($unsafeNICs.Count -eq 0) {
    Write-Host "NO UNATTACHED NICS FOUND!" -ForegroundColor Green
    Write-Host "All NICs are properly attached to VMs." -ForegroundColor Green
    Write-Host ""
    Write-Host "Jumping to final audit..." -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "Found $($unsafeNICs.Count) unattached NIC(s) to delete:" -ForegroundColor Yellow
    foreach ($nicName in $unsafeNICs) {
        Write-Host "  - $nicName" -ForegroundColor Red
    }
    Write-Host ""
    
    # ==================================================
    # STEP 2: CONFIRMATION
    # ==================================================
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "STEP 2: CONFIRMATION" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "PRODUCTION ENVIRONMENT!" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host "Protected NICs will NOT be deleted!" -ForegroundColor Green
    Write-Host ""
    
    $confirmation = Read-Host "Type DELETE to delete $($unsafeNICs.Count) unattached NIC(s)"
    $confirmation = $confirmation.Trim().ToUpper()
    
    if ($confirmation -ne "DELETE") {
        Write-Host ""
        Write-Host "CANCELLED" -ForegroundColor Red
        exit
    }
    
    # ==================================================
    # STEP 3: DELETE UNATTACHED NICS
    # ==================================================
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "STEP 3: DELETING UNATTACHED NICS" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    
    foreach ($nicName in $unsafeNICs) {
        Write-Host "Deleting: $nicName..." -ForegroundColor Yellow
        
        $output = az network nic delete --resource-group $rg --name $nicName 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  SUCCESS" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  FAILED" -ForegroundColor Red
            Write-Host "  Error: $output" -ForegroundColor Red
            $failCount++
        }
        Write-Host ""
    }
    
    Write-Host "Deletion Summary:" -ForegroundColor White
    Write-Host "  Succeeded: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "White" })
    Write-Host ""
    
    Write-Host "Waiting 15 seconds for Azure to propagate changes..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    Write-Host ""
}

# ==================================================
# STEP 4: VERIFY - LIST ALL NICS AGAIN
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "STEP 4: VERIFY - LIST ALL NICS AGAIN" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$allNICsAfterJson = az network nic list --resource-group $rg --output json
$allNICsAfter = $allNICsAfterJson | ConvertFrom-Json

Write-Host "Total NICs now: $($allNICsAfter.Count)" -ForegroundColor White
Write-Host ""

$looseNICsAfter = @()

foreach ($nic in $allNICsAfter) {
    $nicName = $nic.name
    $isAttached = $null -ne $nic.virtualMachine
    
    Write-Host "NIC: $nicName" -ForegroundColor Cyan
    
    if ($isAttached) {
        Write-Host "  Status: ATTACHED TO VM" -ForegroundColor Green
    } else {
        Write-Host "  Status: UNATTACHED (LOOSE END)" -ForegroundColor Red
        $looseNICsAfter += $nicName
    }
    Write-Host ""
}

# ==================================================
# STEP 5: CHECK ALL OTHER LOOSE ENDS
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "STEP 5: CHECK ALL LOOSE ENDS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$looseNSGs = @()
$loosePIPs = @()

Write-Host "Checking NSGs..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE NSG: $($nsg.name)" -ForegroundColor Red
        $looseNSGs += $nsg.name
    }
}

Write-Host "Checking Public IPs..." -ForegroundColor Yellow
$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE PIP: $($pip.name)" -ForegroundColor Red
        $loosePIPs += $pip.name
    }
}

Write-Host ""
$totalLooseEnds = $looseNSGs.Count + $loosePIPs.Count + $looseNICsAfter.Count

Write-Host "LOOSE ENDS SUMMARY:" -ForegroundColor White
Write-Host "  NSGs:       $($looseNSGs.Count)" -ForegroundColor $(if ($looseNSGs.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Public IPs: $($loosePIPs.Count)" -ForegroundColor $(if ($loosePIPs.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  NICs:       $($looseNICsAfter.Count)" -ForegroundColor $(if ($looseNICsAfter.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  TOTAL:      $totalLooseEnds" -ForegroundColor $(if ($totalLooseEnds -gt 0) { "Red" } else { "Green" })
Write-Host ""

# ==================================================
# STEP 6: TEST MOVEIT
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "STEP 6: TEST MOVEIT" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Testing https://moveit.pyxhealth.com..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "  WORKING - Status $($response.StatusCode)" -ForegroundColor Green
    $moveitWorking = $true
} catch {
    Write-Host "  FAILED" -ForegroundColor Red
    $moveitWorking = $false
}

Write-Host ""

# ==================================================
# STEP 7: RESOURCE COUNTS
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "STEP 7: RESOURCE COUNTS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbs = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgs = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pips = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nics = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$disks = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbs" -ForegroundColor White
Write-Host "  NSGs:           $nsgs" -ForegroundColor White
Write-Host "  Public IPs:     $pips" -ForegroundColor White
Write-Host "  NICs:           $nics" -ForegroundColor White
Write-Host "  Disks:          $disks" -ForegroundColor White
Write-Host ""

# ==================================================
# STEP 8: FINAL SUMMARY
# ==================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "RESOURCES:" -ForegroundColor White
Write-Host "  Load Balancers: $lbs" -ForegroundColor White
Write-Host "  NSGs:           $nsgs" -ForegroundColor White
Write-Host "  Public IPs:     $pips" -ForegroundColor White
Write-Host "  NICs:           $nics" -ForegroundColor White
Write-Host "  Disks:          $disks" -ForegroundColor White
Write-Host ""

Write-Host "LOOSE ENDS:     $totalLooseEnds" -ForegroundColor $(if ($totalLooseEnds -eq 0) { "Green" } else { "Red" })
Write-Host "MOVEIT:         $(if ($moveitWorking) { 'WORKING' } else { 'FAILED' })" -ForegroundColor $(if ($moveitWorking) { "Green" } else { "Red" })
Write-Host "URL:            https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($totalLooseEnds -eq 0 -and $moveitWorking) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "ZERO LOOSE ENDS - 100% CLEAN!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "ENVIRONMENT IS PRODUCTION READY!" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Red
    if ($totalLooseEnds -gt 0) {
        Write-Host "STILL HAVE $totalLooseEnds LOOSE END(S)" -ForegroundColor Red
        Write-Host ""
        Write-Host "If NICs still show as loose ends after deletion," -ForegroundColor Yellow
        Write-Host "they may be in 'Deleting' state in Azure." -ForegroundColor Yellow
        Write-Host "Wait 5 minutes and run this script again." -ForegroundColor Yellow
    }
    if (-not $moveitWorking) {
        Write-Host "MOVEIT IS NOT WORKING!" -ForegroundColor Red
    }
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host ""
