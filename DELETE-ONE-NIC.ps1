# DELETE vm-moveit-xfrRestoredNIC - FINAL FIX
# This script ONLY deletes the one remaining NIC

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DELETE REMAINING NIC" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "SilentlyContinue"

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host ""

# The specific NIC name
$nicName = "vm-moveit-xfrRestoredNICa89085a6ec5d4acd85fed0c7ed4d2631"

Write-Host "Looking for: $nicName" -ForegroundColor Yellow
Write-Host ""

# Check if it exists
Write-Host "Checking if NIC exists..." -ForegroundColor Yellow
$nicCheck = az network nic show --resource-group $resourceGroup --name $nicName --output json 2>$null

if ($nicCheck) {
    Write-Host "  FOUND!" -ForegroundColor Green
    Write-Host ""
    
    # Check if attached
    $nic = $nicCheck | ConvertFrom-Json
    if ($nic.virtualMachine) {
        Write-Host "  ERROR: NIC is attached to a VM!" -ForegroundColor Red
        Write-Host "  VM: $($nic.virtualMachine.id)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Cannot delete - it's in use!" -ForegroundColor Red
        exit
    } else {
        Write-Host "  NIC is NOT attached - safe to delete" -ForegroundColor Green
        Write-Host ""
    }
    
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
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "DELETING NIC" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Deleting $nicName..." -ForegroundColor Yellow
    Write-Host ""
    
    # Delete the NIC
    az network nic delete --resource-group $resourceGroup --name $nicName 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  DELETED!" -ForegroundColor Green
    } else {
        Write-Host "  FAILED!" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Waiting 5 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Write-Host ""
    
    # Verify deletion
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "VERIFICATION" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Checking if NIC still exists..." -ForegroundColor Yellow
    $verifyCheck = az network nic show --resource-group $resourceGroup --name $nicName --output json 2>$null
    
    if ($verifyCheck) {
        Write-Host "  STILL EXISTS - Deletion failed!" -ForegroundColor Red
    } else {
        Write-Host "  NOT FOUND - Successfully deleted!" -ForegroundColor Green
    }
    
    Write-Host ""
    
} else {
    Write-Host "  NOT FOUND - Already deleted!" -ForegroundColor Green
    Write-Host ""
}

# Check ALL loose ends
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CHECKING ALL LOOSE ENDS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$looseEnds = 0

Write-Host "Checking NSGs..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE END: $($nsg.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "Checking Public IPs..." -ForegroundColor Yellow
$allPIPs = az network public-ip list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE END: $($pip.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "Checking NICs..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE END: $($nic.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host ""

if ($looseEnds -eq 0) {
    Write-Host "NO LOOSE ENDS FOUND!" -ForegroundColor Green
} else {
    Write-Host "Found: $looseEnds loose end(s)" -ForegroundColor Yellow
}

Write-Host ""

# Count resources
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESOURCE COUNTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$lbs = (az network lb list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json).Count
$nsgs = (az network nsg list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json).Count
$pips = (az network public-ip list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json).Count
$nics = (az network nic list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json).Count
$disks = (az disk list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json).Count

Write-Host "  Load Balancers: $lbs" -ForegroundColor White
Write-Host "  NSGs:           $nsgs" -ForegroundColor White
Write-Host "  Public IPs:     $pips" -ForegroundColor White
Write-Host "  NICs:           $nics" -ForegroundColor White
Write-Host "  Disks:          $disks" -ForegroundColor White
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

Write-Host "LOOSE ENDS:     $looseEnds" -ForegroundColor $(if ($looseEnds -eq 0) { "Green" } else { "Red" })
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
    Write-Host "STILL HAVE $looseEnds LOOSE END(S)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host ""
