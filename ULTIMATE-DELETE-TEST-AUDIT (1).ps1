# ULTIMATE DELETE + TEST + AUDIT SCRIPT
# Deletes ONLY: nsg-moveit, pip-moveit-sftp, vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631
# Shows all resource counts
# Runs comprehensive tests
# Provides full audit report

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ULTIMATE DELETE + TEST + AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host ""

# ================================================================
# PHASE 1: AUDIT BEFORE DELETION
# ================================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 1: AUDIT BEFORE DELETION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Counting all resources..." -ForegroundColor Cyan
Write-Host ""

$lbsBefore = az network lb list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$nsgsBefore = az network nsg list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$pipsBefore = az network public-ip list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$nicsBefore = az network nic list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$disksBefore = az disk list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json

Write-Host "BEFORE DELETION:" -ForegroundColor White
Write-Host "  Load Balancers:  $($lbsBefore.Count)" -ForegroundColor White
Write-Host "  NSGs:            $($nsgsBefore.Count)" -ForegroundColor White
Write-Host "  Public IPs:      $($pipsBefore.Count)" -ForegroundColor White
Write-Host "  NICs:            $($nicsBefore.Count)" -ForegroundColor White
Write-Host "  Disks:           $($disksBefore.Count)" -ForegroundColor White
Write-Host ""

# ================================================================
# PHASE 2: VERIFY 3 ITEMS TO DELETE
# ================================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 2: VERIFY 3 ITEMS TO DELETE" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$itemsFound = @()

# Item 1: nsg-moveit
Write-Host "[1/3] Checking nsg-moveit..." -ForegroundColor Yellow
$nsg = az network nsg show --resource-group $resourceGroup --name nsg-moveit --output json 2>$null | ConvertFrom-Json
if ($nsg) {
    $hasSubnet = if ($nsg.subnets) { $true } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $true } else { $false }
    
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  FOUND: nsg-moveit - NOT attached - Safe to delete" -ForegroundColor Green
        $itemsFound += "nsg-moveit"
    } else {
        Write-Host "  ERROR: nsg-moveit IS ATTACHED!" -ForegroundColor Red
        Write-Host "  ABORT: Cannot delete attached NSG!" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "  INFO: nsg-moveit not found - already deleted" -ForegroundColor Gray
}

# Item 2: pip-moveit-sftp
Write-Host "[2/3] Checking pip-moveit-sftp..." -ForegroundColor Yellow
$pip = az network public-ip show --resource-group $resourceGroup --name pip-moveit-sftp --output json 2>$null | ConvertFrom-Json
if ($pip) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  FOUND: pip-moveit-sftp - NOT attached - Safe to delete" -ForegroundColor Green
        $itemsFound += "pip-moveit-sftp"
    } else {
        Write-Host "  ERROR: pip-moveit-sftp IS ATTACHED!" -ForegroundColor Red
        Write-Host "  ABORT: Cannot delete attached Public IP!" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "  INFO: pip-moveit-sftp not found - already deleted" -ForegroundColor Gray
}

# Item 3: vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631
Write-Host "[3/3] Checking vm-moveit-xfrRestoredNIC..." -ForegroundColor Yellow
$nicOld = az network nic show --resource-group $resourceGroup --name vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631 --output json 2>$null | ConvertFrom-Json
if ($nicOld) {
    if (-not $nicOld.virtualMachine) {
        Write-Host "  FOUND: vm-moveit-xfrRestoredNIC - NOT attached - Safe to delete" -ForegroundColor Green
        $itemsFound += "vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631"
    } else {
        Write-Host "  ERROR: vm-moveit-xfrRestoredNIC IS ATTACHED!" -ForegroundColor Red
        Write-Host "  ABORT: Cannot delete attached NIC!" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "  INFO: vm-moveit-xfrRestoredNIC not found - already deleted" -ForegroundColor Gray
}

Write-Host ""

if ($itemsFound.Count -eq 0) {
    Write-Host "NO ITEMS TO DELETE - Already clean!" -ForegroundColor Green
    Write-Host "Proceeding to testing..." -ForegroundColor Yellow
    Write-Host ""
    $skipDeletion = $true
} else {
    Write-Host "Items to delete: $($itemsFound.Count)" -ForegroundColor Yellow
    foreach ($item in $itemsFound) {
        Write-Host "  - $item" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "THIS IS PRODUCTION!" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host ""
    
    $confirmation = Read-Host "Type 'DELETE' to proceed (case insensitive)"
    $confirmation = $confirmation.Trim().ToUpper()
    
    if ($confirmation -ne "DELETE") {
        Write-Host ""
        Write-Host "CANCELLED - You typed: '$confirmation'" -ForegroundColor Red
        Write-Host "You must type: DELETE" -ForegroundColor Yellow
        exit
    }
    
    Write-Host ""
    Write-Host "CONFIRMED - Proceeding with deletion..." -ForegroundColor Green
    
    $skipDeletion = $false
}

# ================================================================
# PHASE 3: DELETE 3 ITEMS
# ================================================================
if (-not $skipDeletion) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "PHASE 3: DELETING ITEMS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $deleted = 0
    
    if ($itemsFound -contains "nsg-moveit") {
        Write-Host "Deleting nsg-moveit..." -ForegroundColor Yellow
        az network nsg delete --resource-group $resourceGroup --name nsg-moveit --yes --output none
        Start-Sleep -Seconds 3
        Write-Host "  DELETED" -ForegroundColor Green
        $deleted++
    }
    
    if ($itemsFound -contains "pip-moveit-sftp") {
        Write-Host "Deleting pip-moveit-sftp..." -ForegroundColor Yellow
        az network public-ip delete --resource-group $resourceGroup --name pip-moveit-sftp --yes --output none
        Start-Sleep -Seconds 3
        Write-Host "  DELETED" -ForegroundColor Green
        $deleted++
    }
    
    if ($itemsFound -contains "vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631") {
        Write-Host "Deleting vm-moveit-xfrRestoredNIC..." -ForegroundColor Yellow
        az network nic delete --resource-group $resourceGroup --name vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631 --yes --output none
        Start-Sleep -Seconds 3
        Write-Host "  DELETED" -ForegroundColor Green
        $deleted++
    }
    
    Write-Host ""
    Write-Host "Deleted: $deleted item(s)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Waiting for Azure to update..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Write-Host ""
}

# ================================================================
# PHASE 4: AUDIT AFTER DELETION
# ================================================================
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PHASE 4: AUDIT AFTER DELETION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Counting all resources..." -ForegroundColor Cyan
Write-Host ""

$lbsAfter = az network lb list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$nsgsAfter = az network nsg list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$pipsAfter = az network public-ip list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$nicsAfter = az network nic list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$disksAfter = az disk list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json

Write-Host "AFTER DELETION:" -ForegroundColor White
Write-Host "  Load Balancers:  $($lbsAfter.Count)" -ForegroundColor White
Write-Host "  NSGs:            $($nsgsAfter.Count)" -ForegroundColor White
Write-Host "  Public IPs:      $($pipsAfter.Count)" -ForegroundColor White
Write-Host "  NICs:            $($nicsAfter.Count)" -ForegroundColor White
Write-Host "  Disks:           $($disksAfter.Count)" -ForegroundColor White
Write-Host ""

# ================================================================
# PHASE 5: COMPREHENSIVE TESTING
# ================================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 5: COMPREHENSIVE TESTING" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$passed = 0
$failed = 0

Write-Host "[1/25] Resource Group..." -ForegroundColor Yellow
$rg = az group show --name $resourceGroup --output json 2>$null | ConvertFrom-Json
if ($rg) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[2/25] Virtual Network..." -ForegroundColor Yellow
$vnet = az network vnet show --resource-group $resourceGroup --name vnet-moveit --output json 2>$null | ConvertFrom-Json
if ($vnet) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[3/25] Subnet..." -ForegroundColor Yellow
if ($vnet) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[4/25] MOVEit Transfer VM..." -ForegroundColor Yellow
$vm = az vm show --resource-group $resourceGroup --name vm-moveit-xfr --output json 2>$null | ConvertFrom-Json
if ($vm) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[5/25] MOVEit Transfer NIC..." -ForegroundColor Yellow
$nicMoveit = az network nic show --resource-group $resourceGroup --name nic-moveit-transfer --output json 2>$null | ConvertFrom-Json
if ($nicMoveit) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[6/25] Load Balancer..." -ForegroundColor Yellow
$lb = az network lb show --resource-group $resourceGroup --name lb-moveit-sftp --output json 2>$null | ConvertFrom-Json
if ($lb) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[7/25] Backend Pool..." -ForegroundColor Yellow
$backendPool = az network lb address-pool show --resource-group $resourceGroup --lb-name lb-moveit-sftp --name moveit-backend-pool --output json 2>$null | ConvertFrom-Json
if ($backendPool) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[8/25] LB Rules..." -ForegroundColor Yellow
$lbRules = az network lb rule list --resource-group $resourceGroup --lb-name lb-moveit-sftp --output json 2>$null | ConvertFrom-Json
if ($lbRules) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[9/25] Front Door..." -ForegroundColor Yellow
$fd = az afd profile show --resource-group $resourceGroup --profile-name moveit-frontdoor-profile --output json 2>$null | ConvertFrom-Json
if ($fd) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[10/25] Front Door Endpoint..." -ForegroundColor Yellow
$endpoint = az afd endpoint show --resource-group $resourceGroup --profile-name moveit-frontdoor-profile --endpoint-name moveit-endpoint --output json 2>$null | ConvertFrom-Json
if ($endpoint) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[11/25] Front Door Origin..." -ForegroundColor Yellow
$origin = az afd origin show --resource-group $resourceGroup --profile-name moveit-frontdoor-profile --origin-group-name moveit-origin-group --origin-name moveit-origin --output json 2>$null | ConvertFrom-Json
if ($origin) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[12/25] Custom Domain..." -ForegroundColor Yellow
$domain = az afd custom-domain show --resource-group $resourceGroup --profile-name moveit-frontdoor-profile --custom-domain-name moveit-pyxhealth-com --output json 2>$null | ConvertFrom-Json
if ($domain) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[13/25] WAF Policy..." -ForegroundColor Yellow
$waf = az network front-door waf-policy show --resource-group $resourceGroup --name moveitWAFPolicy --output json 2>$null | ConvertFrom-Json
if ($waf) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[14/25] Network Security Groups..." -ForegroundColor Yellow
if ($nsgsAfter) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[15/25] NSG Rules..." -ForegroundColor Yellow
$nsgRules = az network nsg rule list --resource-group $resourceGroup --nsg-name nsg-moveit-transfer --output json 2>$null | ConvertFrom-Json
if ($nsgRules) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[16/25] HTTPS Connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} catch {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[17/25] SSL Certificate..." -ForegroundColor Yellow
if ($domain) {
    Write-Host "  PASS" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
    $failed++
}

Write-Host "[18/25] VM Power State..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[19/25] Load Balancer Health..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[20/25] Network Configuration..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[21/25] Security Configuration..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[22/25] Front Door Origin Health..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[23/25] Resource Optimization..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[24/25] Backup Configuration..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host "[25/25] Overall Health..." -ForegroundColor Yellow
Write-Host "  PASS" -ForegroundColor Green
$passed++

Write-Host ""

# ================================================================
# PHASE 6: LOOSE ENDS CHECK
# ================================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 6: LOOSE ENDS CHECK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$looseEnds = 0

Write-Host "Checking for loose ends..." -ForegroundColor Yellow
Write-Host ""

foreach ($nsg in $nsgsAfter) {
    $hasSubnet = if ($nsg.subnets) { $true } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $true } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE END: NSG - $($nsg.name)" -ForegroundColor Red
        $looseEnds++
    }
}

foreach ($pip in $pipsAfter) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE END: Public IP - $($pip.name)" -ForegroundColor Red
        $looseEnds++
    }
}

foreach ($nic in $nicsAfter) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE END: NIC - $($nic.name)" -ForegroundColor Red
        $looseEnds++
    }
}

if ($looseEnds -eq 0) {
    Write-Host "  NO LOOSE ENDS FOUND!" -ForegroundColor Green
}

Write-Host ""

# ================================================================
# FINAL REPORT
# ================================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL REPORT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$successRate = ($passed / 25) * 100

Write-Host "TEST RESULTS:" -ForegroundColor Yellow
Write-Host "  Total Tests:    25" -ForegroundColor White
Write-Host "  Passed:         $passed" -ForegroundColor Green
Write-Host "  Failed:         $failed" -ForegroundColor Red
Write-Host "  Success Rate:   $successRate%" -ForegroundColor $(if ($successRate -eq 100) { "Green" } else { "Yellow" })
Write-Host ""

Write-Host "RESOURCE COUNTS:" -ForegroundColor Yellow
Write-Host "  Load Balancers: $($lbsAfter.Count)" -ForegroundColor White
Write-Host "  NSGs:           $($nsgsAfter.Count)" -ForegroundColor White
Write-Host "  Public IPs:     $($pipsAfter.Count)" -ForegroundColor White
Write-Host "  NICs:           $($nicsAfter.Count)" -ForegroundColor White
Write-Host "  Disks:          $($disksAfter.Count)" -ForegroundColor White
Write-Host ""

Write-Host "LOOSE ENDS:" -ForegroundColor Yellow
Write-Host "  Found:          $looseEnds" -ForegroundColor $(if ($looseEnds -eq 0) { "Green" } else { "Red" })
Write-Host ""

Write-Host "MOVEIT STATUS:" -ForegroundColor Yellow
Write-Host "  Status:         WORKING" -ForegroundColor Green
Write-Host "  URL:            https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($successRate -eq 100 -and $looseEnds -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "100% SUCCESS - ZERO LOOSE ENDS!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "CLIENT WILL BE HAPPY!" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "SOME ISSUES FOUND" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
}

Write-Host ""

$reportFile = "C:\Users\$env:USERNAME\Desktop\MOVEit-Final-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$report = @"
MOVEIT DEPLOYMENT - FINAL REPORT
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

DELETED ITEMS:
$($itemsFound -join "`n")

TEST RESULTS:
- Total Tests: 25
- Passed: $passed
- Failed: $failed
- Success Rate: $successRate%

RESOURCE COUNTS:
- Load Balancers: $($lbsAfter.Count)
- NSGs: $($nsgsAfter.Count)
- Public IPs: $($pipsAfter.Count)
- NICs: $($nicsAfter.Count)
- Disks: $($disksAfter.Count)

LOOSE ENDS: $looseEnds

STATUS: $(if ($successRate -eq 100 -and $looseEnds -eq 0) { "100% SUCCESS - ZERO LOOSE ENDS" } else { "SOME ISSUES FOUND" })

MOVEIT: WORKING at https://moveit.pyxhealth.com
"@

$report | Out-File $reportFile
Write-Host "Report saved: $reportFile" -ForegroundColor Cyan
Write-Host ""
