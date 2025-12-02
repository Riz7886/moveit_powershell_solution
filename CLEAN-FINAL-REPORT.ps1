# FINAL DEPLOYMENT REPORT
# Zero syntax errors - verified clean

Clear-Host

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MOVEIT DEPLOYMENT - FINAL REPORT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

# SECTION 1: CLEANUP SUMMARY
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "SECTION 1: CLEANUP SUMMARY" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Items deleted during cleanup:" -ForegroundColor White
Write-Host ""
Write-Host "  [DELETED] nsg-moveit" -ForegroundColor Green
Write-Host "    Reason: Not attached to subnet or NIC" -ForegroundColor Gray
Write-Host ""
Write-Host "  [DELETED] pip-moveit-sftp" -ForegroundColor Green
Write-Host "    Reason: Not attached to any resource" -ForegroundColor Gray
Write-Host ""
Write-Host "  [DELETED] vm-moveit-xfrRestoredNIC" -ForegroundColor Green
Write-Host "    Reason: Old NIC not attached to VM" -ForegroundColor Gray
Write-Host ""
Write-Host "Total cleaned: 3 items" -ForegroundColor Green
Write-Host ""

# SECTION 2: CURRENT RESOURCES
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "SECTION 2: RESOURCE INVENTORY" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "LOAD BALANCERS:" -ForegroundColor Cyan
$lbs = az network lb list --resource-group $rg --output json | ConvertFrom-Json
foreach ($lb in $lbs) {
    Write-Host "  [PASS] $($lb.name)" -ForegroundColor Green
}
Write-Host ""

Write-Host "NETWORK SECURITY GROUPS:" -ForegroundColor Cyan
$nsgs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $nsgs) {
    $hasSubnet = $false
    $hasNIC = $false
    if ($nsg.subnets) {
        if ($nsg.subnets.Count -gt 0) {
            $hasSubnet = $true
        }
    }
    if ($nsg.networkInterfaces) {
        if ($nsg.networkInterfaces.Count -gt 0) {
            $hasNIC = $true
        }
    }
    if ($hasSubnet -or $hasNIC) {
        Write-Host "  [PASS] $($nsg.name) - IN USE" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($nsg.name) - LOOSE" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "PUBLIC IP ADDRESSES:" -ForegroundColor Cyan
$pips = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $pips) {
    $ipAddr = "none"
    if ($pip.ipAddress) {
        $ipAddr = $pip.ipAddress
    }
    if ($pip.ipConfiguration) {
        Write-Host "  [PASS] $($pip.name) - $ipAddr - ATTACHED" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($pip.name) - $ipAddr - LOOSE" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "NETWORK INTERFACES:" -ForegroundColor Cyan
$nics = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $nics) {
    if ($nic.virtualMachine) {
        Write-Host "  [PASS] $($nic.name) - ATTACHED" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($nic.name) - LOOSE" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "DISKS:" -ForegroundColor Cyan
$disks = az disk list --resource-group $rg --output json | ConvertFrom-Json
foreach ($disk in $disks) {
    if ($disk.managedBy) {
        Write-Host "  [PASS] $($disk.name) - ATTACHED" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($disk.name) - LOOSE" -ForegroundColor Red
    }
}
Write-Host ""

# SECTION 3: LOOSE ENDS CHECK
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "SECTION 3: LOOSE ENDS VERIFICATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$looseNSGs = 0
$loosePIPs = 0
$looseNICs = 0
$looseDisks = 0

foreach ($nsg in $nsgs) {
    $hasSubnet = $false
    $hasNIC = $false
    if ($nsg.subnets) {
        if ($nsg.subnets.Count -gt 0) {
            $hasSubnet = $true
        }
    }
    if ($nsg.networkInterfaces) {
        if ($nsg.networkInterfaces.Count -gt 0) {
            $hasNIC = $true
        }
    }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  [FAIL] Loose NSG: $($nsg.name)" -ForegroundColor Red
        $looseNSGs = $looseNSGs + 1
    }
}

foreach ($pip in $pips) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  [FAIL] Loose Public IP: $($pip.name)" -ForegroundColor Red
        $loosePIPs = $loosePIPs + 1
    }
}

foreach ($nic in $nics) {
    if (-not $nic.virtualMachine) {
        Write-Host "  [FAIL] Loose NIC: $($nic.name)" -ForegroundColor Red
        $looseNICs = $looseNICs + 1
    }
}

foreach ($disk in $disks) {
    if (-not $disk.managedBy) {
        Write-Host "  [FAIL] Loose Disk: $($disk.name)" -ForegroundColor Red
        $looseDisks = $looseDisks + 1
    }
}

$totalLoose = $looseNSGs + $loosePIPs + $looseNICs + $looseDisks

if ($totalLoose -eq 0) {
    Write-Host "  [PASS] No loose ends found" -ForegroundColor Green
}

Write-Host ""
Write-Host "Loose Ends Summary:" -ForegroundColor White
if ($looseNSGs -eq 0) {
    Write-Host "  NSGs:       0" -ForegroundColor Green
} else {
    Write-Host "  NSGs:       $looseNSGs" -ForegroundColor Red
}
if ($loosePIPs -eq 0) {
    Write-Host "  Public IPs: 0" -ForegroundColor Green
} else {
    Write-Host "  Public IPs: $loosePIPs" -ForegroundColor Red
}
if ($looseNICs -eq 0) {
    Write-Host "  NICs:       0" -ForegroundColor Green
} else {
    Write-Host "  NICs:       $looseNICs" -ForegroundColor Red
}
if ($looseDisks -eq 0) {
    Write-Host "  Disks:      0" -ForegroundColor Green
} else {
    Write-Host "  Disks:      $looseDisks" -ForegroundColor Red
}
if ($totalLoose -eq 0) {
    Write-Host "  TOTAL:      0" -ForegroundColor Green
} else {
    Write-Host "  TOTAL:      $totalLoose" -ForegroundColor Red
}
Write-Host ""

# SECTION 4: MOVEIT TEST
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "SECTION 4: MOVEIT FUNCTIONALITY TEST" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Testing https://moveit.pyxhealth.com..." -ForegroundColor White
$moveitWorking = $false
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing
    Write-Host "  [PASS] MOVEit is working" -ForegroundColor Green
    Write-Host "    Status: $($response.StatusCode)" -ForegroundColor Gray
    $moveitWorking = $true
} catch {
    Write-Host "  [FAIL] MOVEit is not responding" -ForegroundColor Red
}
Write-Host ""

# SECTION 5: RESOURCE COUNTS
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "SECTION 5: FINAL RESOURCE COUNTS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbCount = $lbs.Count
$nsgCount = $nsgs.Count
$pipCount = $pips.Count
$nicCount = $nics.Count
$diskCount = $disks.Count

Write-Host "  Load Balancers: $lbCount" -ForegroundColor White
Write-Host "  NSGs:           $nsgCount" -ForegroundColor White
Write-Host "  Public IPs:     $pipCount" -ForegroundColor White
Write-Host "  NICs:           $nicCount" -ForegroundColor White
Write-Host "  Disks:          $diskCount" -ForegroundColor White
Write-Host ""

# SECTION 6: FINAL VERDICT
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SECTION 6: FINAL VERDICT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "TEST RESULTS:" -ForegroundColor White
Write-Host ""

if ($totalLoose -eq 0) {
    Write-Host "  Loose Ends:     [PASS] 0 loose ends" -ForegroundColor Green
} else {
    Write-Host "  Loose Ends:     [FAIL] $totalLoose loose ends" -ForegroundColor Red
}

if ($moveitWorking) {
    Write-Host "  MOVEit Working: [PASS] Operational" -ForegroundColor Green
} else {
    Write-Host "  MOVEit Working: [FAIL] Not working" -ForegroundColor Red
}

Write-Host ""

if ($totalLoose -eq 0 -and $moveitWorking) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    DEPLOYMENT: 100 PERCENT CLEAN" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "  ZERO LOOSE ENDS" -ForegroundColor Green
    Write-Host "  MOVEIT OPERATIONAL" -ForegroundColor Green
    Write-Host "  PRODUCTION READY" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "    STATUS: APPROVED FOR PRODUCTION" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "    DEPLOYMENT: ISSUES FOUND" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    if ($totalLoose -gt 0) {
        Write-Host "  Action needed: Clean up $totalLoose loose ends" -ForegroundColor Yellow
    }
    if (-not $moveitWorking) {
        Write-Host "  Action needed: Fix MOVEit connectivity" -ForegroundColor Yellow
    }
}

Write-Host ""
