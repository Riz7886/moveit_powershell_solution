# DELETE LAST LOOSE PUBLIC IP
# Deletes: vm-moveit-xfrRestoredip

Clear-Host
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DELETE LAST LOOSE PUBLIC IP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

$pipName = "vm-moveit-xfrRestoredip"

Write-Host "Checking for: $pipName" -ForegroundColor Yellow
$pipCheck = az network public-ip show --resource-group $rg --name $pipName --output json 2>$null

if ($pipCheck) {
    $pip = $pipCheck | ConvertFrom-Json
    Write-Host "  FOUND!" -ForegroundColor Green
    Write-Host "  IP Address: $($pip.ipAddress)" -ForegroundColor White
    
    if ($pip.ipConfiguration) {
        Write-Host "  ERROR: This Public IP is ATTACHED!" -ForegroundColor Red
        Write-Host "  Cannot delete - it's in use!" -ForegroundColor Red
        exit
    } else {
        Write-Host "  Status: UNATTACHED - safe to delete" -ForegroundColor Green
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
    Write-Host "Deleting Public IP: $pipName..." -ForegroundColor Yellow
    az network public-ip delete --resource-group $rg --name $pipName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  DELETED!" -ForegroundColor Green
    } else {
        Write-Host "  FAILED!" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Write-Host ""
} else {
    Write-Host "  NOT FOUND - Already deleted!" -ForegroundColor Green
    Write-Host ""
}

# Verify
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL VERIFICATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking all loose ends..." -ForegroundColor Yellow
Write-Host ""

$looseEnds = 0

Write-Host "NSGs..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE: $($nsg.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "Public IPs..." -ForegroundColor Yellow
$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $allPIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE: $($pip.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "NICs..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE: $($nic.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host ""

if ($looseEnds -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "ZERO LOOSE ENDS!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "LOOSE ENDS: $looseEnds" -ForegroundColor Red
}

Write-Host ""

# Test MOVEit
Write-Host "Testing MOVEit..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "  WORKING - Status $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "  FAILED" -ForegroundColor Red
}

Write-Host ""

# Resource counts
$lbs = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgs = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pips = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nics = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$disks = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FINAL RESOURCE COUNTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Load Balancers: $lbs" -ForegroundColor White
Write-Host "  NSGs:           $nsgs" -ForegroundColor White
Write-Host "  Public IPs:     $pips" -ForegroundColor White
Write-Host "  NICs:           $nics" -ForegroundColor White
Write-Host "  Disks:          $disks" -ForegroundColor White
Write-Host ""
Write-Host "  LOOSE ENDS:     $looseEnds" -ForegroundColor $(if ($looseEnds -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($looseEnds -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "100% CLEAN - PRODUCTION READY!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "CLIENT WILL BE HAPPY NOW!" -ForegroundColor Green
}

Write-Host ""
