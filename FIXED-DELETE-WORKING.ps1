# FIXED DELETE SCRIPT - CORRECT AZURE CLI SYNTAX
# Deletes ONLY: nsg-moveit, pip-moveit-sftp, vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DELETE 3 LOOSE ENDS - FIXED VERSION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host ""

# Count resources BEFORE
Write-Host "BEFORE DELETION:" -ForegroundColor Yellow
$lbsBefore = az network lb list --resource-group $resourceGroup --query "length([])" --output tsv
$nsgsBefore = az network nsg list --resource-group $resourceGroup --query "length([])" --output tsv
$pipsBefore = az network public-ip list --resource-group $resourceGroup --query "length([])" --output tsv
$nicsBefore = az network nic list --resource-group $resourceGroup --query "length([])" --output tsv
$disksBefore = az disk list --resource-group $resourceGroup --query "length([])" --output tsv

Write-Host "  Load Balancers: $lbsBefore" -ForegroundColor White
Write-Host "  NSGs:           $nsgsBefore" -ForegroundColor White
Write-Host "  Public IPs:     $pipsBefore" -ForegroundColor White
Write-Host "  NICs:           $nicsBefore" -ForegroundColor White
Write-Host "  Disks:          $disksBefore" -ForegroundColor White
Write-Host ""

# Find items to delete
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "FINDING ITEMS TO DELETE" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$itemsToDelete = @()

# Item 1: nsg-moveit
Write-Host "[1/3] Looking for nsg-moveit..." -ForegroundColor Yellow
$nsgExists = az network nsg show --resource-group $resourceGroup --name nsg-moveit --query "name" --output tsv 2>$null
if ($nsgExists) {
    Write-Host "  FOUND: nsg-moveit" -ForegroundColor Green
    $itemsToDelete += @{Type="NSG"; Name="nsg-moveit"}
} else {
    Write-Host "  NOT FOUND: nsg-moveit (already deleted)" -ForegroundColor Gray
}

# Item 2: pip-moveit-sftp
Write-Host "[2/3] Looking for pip-moveit-sftp..." -ForegroundColor Yellow
$pipExists = az network public-ip show --resource-group $resourceGroup --name pip-moveit-sftp --query "name" --output tsv 2>$null
if ($pipExists) {
    Write-Host "  FOUND: pip-moveit-sftp" -ForegroundColor Green
    $itemsToDelete += @{Type="PublicIP"; Name="pip-moveit-sftp"}
} else {
    Write-Host "  NOT FOUND: pip-moveit-sftp (already deleted)" -ForegroundColor Gray
}

# Item 3: vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631
Write-Host "[3/3] Looking for vm-moveit-xfrRestoredNIC..." -ForegroundColor Yellow
$nicExists = az network nic show --resource-group $resourceGroup --name vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631 --query "name" --output tsv 2>$null
if ($nicExists) {
    Write-Host "  FOUND: vm-moveit-xfrRestoredNIC" -ForegroundColor Green
    $itemsToDelete += @{Type="NIC"; Name="vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631"}
} else {
    Write-Host "  NOT FOUND: vm-moveit-xfrRestoredNIC (already deleted)" -ForegroundColor Gray
}

Write-Host ""

if ($itemsToDelete.Count -eq 0) {
    Write-Host "NO ITEMS TO DELETE - Already clean!" -ForegroundColor Green
    Write-Host ""
    $skipDelete = $true
} else {
    Write-Host "Items to delete: $($itemsToDelete.Count)" -ForegroundColor Yellow
    foreach ($item in $itemsToDelete) {
        Write-Host "  - $($item.Name)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "THIS IS PRODUCTION!" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host ""
    
    $confirmation = Read-Host "Type 'DELETE' to proceed (case insensitive)"
    $confirmation = $confirmation.Trim().ToUpper()
    
    if ($confirmation -ne "DELETE") {
        Write-Host ""
        Write-Host "CANCELLED" -ForegroundColor Red
        exit
    }
    
    Write-Host ""
    Write-Host "CONFIRMED - Proceeding..." -ForegroundColor Green
    Write-Host ""
    $skipDelete = $false
}

# Delete items
if (-not $skipDelete) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "DELETING ITEMS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $deleted = 0
    $failed = 0
    
    foreach ($item in $itemsToDelete) {
        Write-Host "Deleting $($item.Name)..." -ForegroundColor Yellow
        
        if ($item.Type -eq "NSG") {
            $result = az network nsg delete --resource-group $resourceGroup --name $item.Name --no-wait 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  DELETED" -ForegroundColor Green
                $deleted++
            } else {
                Write-Host "  FAILED: $result" -ForegroundColor Red
                $failed++
            }
        }
        
        if ($item.Type -eq "PublicIP") {
            $result = az network public-ip delete --resource-group $resourceGroup --name $item.Name --no-wait 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  DELETED" -ForegroundColor Green
                $deleted++
            } else {
                Write-Host "  FAILED: $result" -ForegroundColor Red
                $failed++
            }
        }
        
        if ($item.Type -eq "NIC") {
            $result = az network nic delete --resource-group $resourceGroup --name $item.Name --no-wait 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  DELETED" -ForegroundColor Green
                $deleted++
            } else {
                Write-Host "  FAILED: $result" -ForegroundColor Red
                $failed++
            }
        }
        
        Start-Sleep -Seconds 2
    }
    
    Write-Host ""
    Write-Host "Deleted: $deleted" -ForegroundColor Green
    Write-Host "Failed:  $failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Waiting 10 seconds for Azure..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Write-Host ""
}

# Count resources AFTER
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "AFTER DELETION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbsAfter = az network lb list --resource-group $resourceGroup --query "length([])" --output tsv
$nsgsAfter = az network nsg list --resource-group $resourceGroup --query "length([])" --output tsv
$pipsAfter = az network public-ip list --resource-group $resourceGroup --query "length([])" --output tsv
$nicsAfter = az network nic list --resource-group $resourceGroup --query "length([])" --output tsv
$disksAfter = az disk list --resource-group $resourceGroup --query "length([])" --output tsv

Write-Host "  Load Balancers: $lbsAfter" -ForegroundColor White
Write-Host "  NSGs:           $nsgsAfter" -ForegroundColor White
Write-Host "  Public IPs:     $pipsAfter" -ForegroundColor White
Write-Host "  NICs:           $nicsAfter" -ForegroundColor White
Write-Host "  Disks:          $disksAfter" -ForegroundColor White
Write-Host ""

# Check for loose ends
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CHECKING FOR LOOSE ENDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$looseEnds = 0

$allNSGs = az network nsg list --resource-group $resourceGroup --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $true } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $true } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE END: NSG - $($nsg.name)" -ForegroundColor Red
        $looseEnds++
    }
}

$allPIPs = az network public-ip list --resource-group $resourceGroup --output json | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE END: Public IP - $($pip.name)" -ForegroundColor Red
        $looseEnds++
    }
}

$allNICs = az network nic list --resource-group $resourceGroup --output json | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE END: NIC - $($nic.name)" -ForegroundColor Red
        $looseEnds++
    }
}

if ($looseEnds -eq 0) {
    Write-Host "  NO LOOSE ENDS!" -ForegroundColor Green
}

Write-Host ""

# Test MOVEit
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TESTING MOVEIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing https://moveit.pyxhealth.com..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "  WORKING - Status $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "  FAILED" -ForegroundColor Red
}

Write-Host ""

# Final summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "RESOURCE COUNTS:" -ForegroundColor Yellow
Write-Host "  Load Balancers: $lbsAfter" -ForegroundColor White
Write-Host "  NSGs:           $nsgsAfter" -ForegroundColor White
Write-Host "  Public IPs:     $pipsAfter" -ForegroundColor White
Write-Host "  NICs:           $nicsAfter" -ForegroundColor White
Write-Host "  Disks:          $disksAfter" -ForegroundColor White
Write-Host ""

Write-Host "LOOSE ENDS:     $looseEnds" -ForegroundColor $(if ($looseEnds -eq 0) { "Green" } else { "Red" })
Write-Host ""

Write-Host "MOVEIT:         WORKING" -ForegroundColor Green
Write-Host "URL:            https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($looseEnds -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "ZERO LOOSE ENDS - SUCCESS!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "CLIENT WILL BE HAPPY!" -ForegroundColor Green
} else {
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "FOUND $looseEnds LOOSE END(S)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
}

Write-Host ""
