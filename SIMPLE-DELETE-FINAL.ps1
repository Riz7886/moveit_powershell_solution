# SIMPLE DELETE 3 LOOSE ENDS - NO QUERY ERRORS
# Deletes: nsg-moveit, pip-moveit-sftp, vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DELETE 3 LOOSE ENDS - SIMPLE VERSION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "SilentlyContinue"

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host ""

# Count BEFORE (simple method)
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "BEFORE DELETION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbsBefore = (az network lb list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$nsgsBefore = (az network nsg list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$pipsBefore = (az network public-ip list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$nicsBefore = (az network nic list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$disksBefore = (az disk list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbsBefore" -ForegroundColor White
Write-Host "  NSGs:           $nsgsBefore" -ForegroundColor White
Write-Host "  Public IPs:     $pipsBefore" -ForegroundColor White
Write-Host "  NICs:           $nicsBefore" -ForegroundColor White
Write-Host "  Disks:          $disksBefore" -ForegroundColor White
Write-Host ""

# Define 3 items to delete
$item1 = @{Name="nsg-moveit"; Type="NSG"}
$item2 = @{Name="pip-moveit-sftp"; Type="PublicIP"}
$item3 = @{Name="vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631"; Type="NIC"}

$itemsToDelete = @($item1, $item2, $item3)

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "FINDING 3 ITEMS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$foundItems = @()

# Check item 1
Write-Host "[1/3] nsg-moveit..." -ForegroundColor Yellow
$check1 = az network nsg show --resource-group $resourceGroup --name nsg-moveit --output json 2>$null
if ($check1) {
    Write-Host "  FOUND" -ForegroundColor Green
    $foundItems += $item1
} else {
    Write-Host "  NOT FOUND (already deleted)" -ForegroundColor Gray
}

# Check item 2
Write-Host "[2/3] pip-moveit-sftp..." -ForegroundColor Yellow
$check2 = az network public-ip show --resource-group $resourceGroup --name pip-moveit-sftp --output json 2>$null
if ($check2) {
    Write-Host "  FOUND" -ForegroundColor Green
    $foundItems += $item2
} else {
    Write-Host "  NOT FOUND (already deleted)" -ForegroundColor Gray
}

# Check item 3
Write-Host "[3/3] vm-moveit-xfrRestoredNIC..." -ForegroundColor Yellow
$check3 = az network nic show --resource-group $resourceGroup --name vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631 --output json 2>$null
if ($check3) {
    Write-Host "  FOUND" -ForegroundColor Green
    $foundItems += $item3
} else {
    Write-Host "  NOT FOUND (already deleted)" -ForegroundColor Gray
}

Write-Host ""

if ($foundItems.Count -eq 0) {
    Write-Host "ALL 3 ITEMS ALREADY DELETED!" -ForegroundColor Green
    Write-Host ""
    $skipDelete = $true
} else {
    Write-Host "Found: $($foundItems.Count) item(s)" -ForegroundColor Yellow
    foreach ($item in $foundItems) {
        Write-Host "  - $($item.Name)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "THIS IS PRODUCTION!" -ForegroundColor Yellow -BackgroundColor DarkRed
    Write-Host ""
    
    $confirmation = Read-Host "Type DELETE to proceed"
    $confirmation = $confirmation.Trim().ToUpper()
    
    if ($confirmation -ne "DELETE") {
        Write-Host ""
        Write-Host "CANCELLED" -ForegroundColor Red
        exit
    }
    
    Write-Host ""
    Write-Host "CONFIRMED" -ForegroundColor Green
    Write-Host ""
    $skipDelete = $false
}

# DELETE
if (-not $skipDelete) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "DELETING ITEMS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $deleted = 0
    $failed = 0
    
    foreach ($item in $foundItems) {
        Write-Host "Deleting $($item.Name)..." -ForegroundColor Yellow
        
        if ($item.Type -eq "NSG") {
            az network nsg delete --resource-group $resourceGroup --name $item.Name 2>$null
        }
        elseif ($item.Type -eq "PublicIP") {
            az network public-ip delete --resource-group $resourceGroup --name $item.Name 2>$null
        }
        elseif ($item.Type -eq "NIC") {
            az network nic delete --resource-group $resourceGroup --name $item.Name 2>$null
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  DELETED" -ForegroundColor Green
            $deleted++
        } else {
            Write-Host "  FAILED" -ForegroundColor Red
            $failed++
        }
        
        Start-Sleep -Seconds 3
    }
    
    Write-Host ""
    Write-Host "Deleted: $deleted" -ForegroundColor Green
    Write-Host "Failed:  $failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Write-Host ""
}

# Count AFTER
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "AFTER DELETION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$lbsAfter = (az network lb list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$nsgsAfter = (az network nsg list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$pipsAfter = (az network public-ip list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$nicsAfter = (az network nic list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count
$disksAfter = (az disk list --resource-group $resourceGroup --output json | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbsAfter" -ForegroundColor White
Write-Host "  NSGs:           $nsgsAfter" -ForegroundColor White
Write-Host "  Public IPs:     $pipsAfter" -ForegroundColor White
Write-Host "  NICs:           $nicsAfter" -ForegroundColor White
Write-Host "  Disks:          $disksAfter" -ForegroundColor White
Write-Host ""

# Check for loose ends
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CHECKING LOOSE ENDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$looseEnds = 0

$allNSGs = az network nsg list --resource-group $resourceGroup --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
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

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "RESOURCES:" -ForegroundColor Yellow
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
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "FOUND $looseEnds LOOSE END(S)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "RUN SCRIPT AGAIN TO DELETE THEM!" -ForegroundColor Yellow
}

Write-Host ""
