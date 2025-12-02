# ULTIMATE CLEANUP AND AUDIT - NO BULLSHIT VERSION
# This script finds ALL loose ends dynamically and deletes them

Clear-Host
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ULTIMATE CLEANUP AND AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

# ==================================================
# PHASE 1: COUNT RESOURCES BEFORE
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 1: COUNT RESOURCES BEFORE" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbsBefore = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgsBefore = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pipsBefore = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nicsBefore = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$disksBefore = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbsBefore" -ForegroundColor White
Write-Host "  NSGs:           $nsgsBefore" -ForegroundColor White
Write-Host "  Public IPs:     $pipsBefore" -ForegroundColor White
Write-Host "  NICs:           $nicsBefore" -ForegroundColor White
Write-Host "  Disks:          $disksBefore" -ForegroundColor White
Write-Host ""

# ==================================================
# PHASE 2: FIND ALL LOOSE ENDS
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 2: FIND ALL LOOSE ENDS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$looseNSGs = @()
$loosePIPs = @()
$looseNICs = @()

Write-Host "Scanning NSGs..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE NSG: $($nsg.name)" -ForegroundColor Red
        $looseNSGs += $nsg.name
    }
}

Write-Host "Scanning Public IPs..." -ForegroundColor Yellow
$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE PIP: $($pip.name)" -ForegroundColor Red
        $loosePIPs += $pip.name
    }
}

Write-Host "Scanning NICs..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE NIC: $($nic.name)" -ForegroundColor Red
        $looseNICs += $nic.name
    }
}

Write-Host ""
$totalLooseEnds = $looseNSGs.Count + $loosePIPs.Count + $looseNICs.Count

if ($totalLooseEnds -eq 0) {
    Write-Host "NO LOOSE ENDS FOUND!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Jumping to testing..." -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "FOUND $totalLooseEnds LOOSE END(S):" -ForegroundColor Red
    Write-Host "  NSGs:       $($looseNSGs.Count)" -ForegroundColor Red
    Write-Host "  Public IPs: $($loosePIPs.Count)" -ForegroundColor Red
    Write-Host "  NICs:       $($looseNICs.Count)" -ForegroundColor Red
    Write-Host ""
    
    # ==================================================
    # PHASE 3: CONFIRMATION
    # ==================================================
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "PHASE 3: CONFIRMATION" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "THIS IS PRODUCTION!" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host ""
    
    $confirmation = Read-Host "Type DELETE to delete all $totalLooseEnds loose end(s)"
    $confirmation = $confirmation.Trim().ToUpper()
    
    if ($confirmation -ne "DELETE") {
        Write-Host ""
        Write-Host "CANCELLED" -ForegroundColor Red
        exit
    }
    
    # ==================================================
    # PHASE 4: DELETE ALL LOOSE ENDS
    # ==================================================
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "PHASE 4: DELETING LOOSE ENDS" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    $deletedCount = 0
    $failedCount = 0
    
    # Delete NSGs
    foreach ($nsgName in $looseNSGs) {
        Write-Host "Deleting NSG: $nsgName..." -ForegroundColor Yellow
        az network nsg delete --resource-group $rg --name $nsgName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  DELETED!" -ForegroundColor Green
            $deletedCount++
        } else {
            Write-Host "  FAILED!" -ForegroundColor Red
            $failedCount++
        }
    }
    
    # Delete Public IPs
    foreach ($pipName in $loosePIPs) {
        Write-Host "Deleting Public IP: $pipName..." -ForegroundColor Yellow
        az network public-ip delete --resource-group $rg --name $pipName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  DELETED!" -ForegroundColor Green
            $deletedCount++
        } else {
            Write-Host "  FAILED!" -ForegroundColor Red
            $failedCount++
        }
    }
    
    # Delete NICs
    foreach ($nicName in $looseNICs) {
        Write-Host "Deleting NIC: $nicName..." -ForegroundColor Yellow
        az network nic delete --resource-group $rg --name $nicName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  DELETED!" -ForegroundColor Green
            $deletedCount++
        } else {
            Write-Host "  FAILED!" -ForegroundColor Red
            $failedCount++
        }
    }
    
    Write-Host ""
    Write-Host "Deleted: $deletedCount, Failed: $failedCount" -ForegroundColor White
    Write-Host ""
    Write-Host "Waiting 10 seconds for Azure to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Write-Host ""
}

# ==================================================
# PHASE 5: COUNT RESOURCES AFTER
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 5: COUNT RESOURCES AFTER" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbsAfter = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgsAfter = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pipsAfter = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nicsAfter = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$disksAfter = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbsAfter" -ForegroundColor White
Write-Host "  NSGs:           $nsgsAfter" -ForegroundColor White
Write-Host "  Public IPs:     $pipsAfter" -ForegroundColor White
Write-Host "  NICs:           $nicsAfter" -ForegroundColor White
Write-Host "  Disks:          $disksAfter" -ForegroundColor White
Write-Host ""

# ==================================================
# PHASE 6: VERIFY NO LOOSE ENDS REMAIN
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 6: VERIFY NO LOOSE ENDS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$remainingLooseEnds = 0

Write-Host "Re-scanning for loose ends..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Checking NSGs..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  STILL LOOSE: $($nsg.name)" -ForegroundColor Red
        $remainingLooseEnds++
    }
}

Write-Host "Checking Public IPs..." -ForegroundColor Yellow
$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  STILL LOOSE: $($pip.name)" -ForegroundColor Red
        $remainingLooseEnds++
    }
}

Write-Host "Checking NICs..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  STILL LOOSE: $($nic.name)" -ForegroundColor Red
        $remainingLooseEnds++
    }
}

Write-Host ""

if ($remainingLooseEnds -eq 0) {
    Write-Host "ZERO LOOSE ENDS!" -ForegroundColor Green -BackgroundColor DarkGreen
} else {
    Write-Host "STILL HAVE $remainingLooseEnds LOOSE END(S)!" -ForegroundColor Red -BackgroundColor DarkRed
}

Write-Host ""

# ==================================================
# PHASE 7: TEST MOVEIT
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 7: TEST MOVEIT" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Testing https://moveit.pyxhealth.com..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "  WORKING - Status $($response.StatusCode)" -ForegroundColor Green
    $moveitWorking = $true
} catch {
    Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
    $moveitWorking = $false
}

Write-Host ""

# ==================================================
# PHASE 8: LIST ALL RESOURCES
# ==================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 8: LIST ALL RESOURCES" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Load Balancers:" -ForegroundColor Cyan
$lbs = az network lb list --resource-group $rg --output json | ConvertFrom-Json
foreach ($lb in $lbs) {
    Write-Host "  - $($lb.name)" -ForegroundColor White
}
Write-Host ""

Write-Host "NSGs:" -ForegroundColor Cyan
$nsgs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $nsgs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    $status = if ($hasSubnet -or $hasNIC) { "IN USE" } else { "LOOSE" }
    $color = if ($hasSubnet -or $hasNIC) { "Green" } else { "Red" }
    Write-Host "  - $($nsg.name) [$status]" -ForegroundColor $color
}
Write-Host ""

Write-Host "Public IPs:" -ForegroundColor Cyan
$pips = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $pips) {
    $attached = if ($pip.ipConfiguration) { "ATTACHED" } else { "LOOSE" }
    $color = if ($pip.ipConfiguration) { "Green" } else { "Red" }
    $ipAddr = if ($pip.ipAddress) { $pip.ipAddress } else { "none" }
    Write-Host "  - $($pip.name) [$attached] - $ipAddr" -ForegroundColor $color
}
Write-Host ""

Write-Host "NICs:" -ForegroundColor Cyan
$nics = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $nics) {
    $attached = if ($nic.virtualMachine) { "ATTACHED" } else { "LOOSE" }
    $color = if ($nic.virtualMachine) { "Green" } else { "Red" }
    Write-Host "  - $($nic.name) [$attached]" -ForegroundColor $color
}
Write-Host ""

Write-Host "Disks:" -ForegroundColor Cyan
$disks = az disk list --resource-group $rg --output json | ConvertFrom-Json
foreach ($disk in $disks) {
    $attached = if ($disk.managedBy) { "ATTACHED" } else { "UNATTACHED" }
    $color = if ($disk.managedBy) { "Green" } else { "Yellow" }
    Write-Host "  - $($disk.name) [$attached]" -ForegroundColor $color
}
Write-Host ""

# ==================================================
# PHASE 9: FINAL SUMMARY
# ==================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "RESOURCES:" -ForegroundColor White
Write-Host "  Load Balancers: $lbsAfter" -ForegroundColor White
Write-Host "  NSGs:           $nsgsAfter" -ForegroundColor White
Write-Host "  Public IPs:     $pipsAfter" -ForegroundColor White
Write-Host "  NICs:           $nicsAfter" -ForegroundColor White
Write-Host "  Disks:          $disksAfter" -ForegroundColor White
Write-Host ""

Write-Host "LOOSE ENDS:     $remainingLooseEnds" -ForegroundColor $(if ($remainingLooseEnds -eq 0) { "Green" } else { "Red" })
Write-Host "MOVEIT:         $(if ($moveitWorking) { 'WORKING' } else { 'FAILED' })" -ForegroundColor $(if ($moveitWorking) { "Green" } else { "Red" })
Write-Host "URL:            https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($remainingLooseEnds -eq 0 -and $moveitWorking) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "100% CLEAN - READY FOR PRODUCTION!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Red
    if ($remainingLooseEnds -gt 0) {
        Write-Host "STILL HAVE $remainingLooseEnds LOOSE END(S)" -ForegroundColor Red
    }
    if (-not $moveitWorking) {
        Write-Host "MOVEIT IS NOT WORKING!" -ForegroundColor Red
    }
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host ""
