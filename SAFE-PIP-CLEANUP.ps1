# ULTRA-SAFE PUBLIC IP AUDIT AND CLEANUP
# Shows ALL Public IPs and their status BEFORE deleting anything

Clear-Host
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PUBLIC IP AUDIT - ULTRA SAFE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "LISTING ALL PUBLIC IPs" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json

Write-Host "Total Public IPs found: $($allPIPs.Count)" -ForegroundColor White
Write-Host ""

$safePIPs = @()
$loosePIPs = @()

foreach ($pip in $allPIPs) {
    $pipName = $pip.name
    $ipAddress = if ($pip.ipAddress) { $pip.ipAddress } else { "Not assigned" }
    $isAttached = $null -ne $pip.ipConfiguration
    
    Write-Host "PUBLIC IP: $pipName" -ForegroundColor Cyan
    Write-Host "  IP Address: $ipAddress" -ForegroundColor White
    
    if ($isAttached) {
        Write-Host "  Status: ATTACHED (IN USE)" -ForegroundColor Green
        Write-Host "  Attached to: $($pip.ipConfiguration.id)" -ForegroundColor Green
        Write-Host "  ACTION: PROTECTED - WILL NOT DELETE" -ForegroundColor Green -BackgroundColor DarkGreen
        $safePIPs += $pipName
    } else {
        Write-Host "  Status: NOT ATTACHED (LOOSE END)" -ForegroundColor Red
        Write-Host "  ACTION: CANDIDATE FOR DELETION" -ForegroundColor Yellow
        $loosePIPs += $pipName
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor White
Write-Host "SUMMARY" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-Host "PROTECTED Public IPs (in use): $($safePIPs.Count)" -ForegroundColor Green
foreach ($pip in $safePIPs) {
    Write-Host "  ✓ $pip" -ForegroundColor Green
}
Write-Host ""

Write-Host "LOOSE Public IPs (not in use): $($loosePIPs.Count)" -ForegroundColor Yellow
foreach ($pip in $loosePIPs) {
    Write-Host "  ✗ $pip" -ForegroundColor Red
}
Write-Host ""

if ($loosePIPs.Count -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "NO LOOSE PUBLIC IPs FOUND!" -ForegroundColor Green
    Write-Host "All Public IPs are properly attached." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    exit
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "DELETION PLAN" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "The following Public IPs will be DELETED:" -ForegroundColor Yellow
foreach ($pip in $loosePIPs) {
    Write-Host "  - $pip" -ForegroundColor Red
}
Write-Host ""

Write-Host "The following Public IPs are PROTECTED and will NOT be deleted:" -ForegroundColor Green
foreach ($pip in $safePIPs) {
    Write-Host "  - $pip" -ForegroundColor Green
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Red
Write-Host "PRODUCTION ENVIRONMENT!" -ForegroundColor Red -BackgroundColor DarkRed
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

Write-Host "Review the list above carefully." -ForegroundColor Yellow
Write-Host "Protected IPs are attached to resources and will NOT be deleted." -ForegroundColor Green
Write-Host ""

$confirmation = Read-Host "Type DELETE to delete $($loosePIPs.Count) loose Public IP(s)"
$confirmation = $confirmation.Trim().ToUpper()

if ($confirmation -ne "DELETE") {
    Write-Host ""
    Write-Host "CANCELLED - No changes made" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "DELETING LOOSE PUBLIC IPs" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($pipName in $loosePIPs) {
    Write-Host "Deleting: $pipName..." -ForegroundColor Yellow
    
    $output = az network public-ip delete --resource-group $rg --name $pipName 2>&1
    
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

Write-Host "Waiting 10 seconds for Azure to propagate..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
Write-Host ""

# Final verification
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "FINAL VERIFICATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
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
        Write-Host "  LOOSE NSG: $($nsg.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "Public IPs..." -ForegroundColor Yellow
$allPIPsAfter = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $allPIPsAfter) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE PIP: $($pip.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host "NICs..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE NIC: $($nic.name)" -ForegroundColor Red
        $looseEnds++
    }
}

Write-Host ""

if ($looseEnds -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "ZERO LOOSE ENDS!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "Remaining loose ends: $looseEnds" -ForegroundColor Red
}

Write-Host ""

# Test MOVEit
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "TESTING MOVEIT" -ForegroundColor Yellow
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

# Final resource counts
$lbs = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgs = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pips = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nics = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$disks = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

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

Write-Host "LOOSE ENDS:     $looseEnds" -ForegroundColor $(if ($looseEnds -eq 0) { "Green" } else { "Red" })
Write-Host "MOVEIT:         $(if ($moveitWorking) { 'WORKING' } else { 'FAILED' })" -ForegroundColor $(if ($moveitWorking) { "Green" } else { "Red" })
Write-Host "URL:            https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

if ($looseEnds -eq 0 -and $moveitWorking) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "100% CLEAN - PRODUCTION READY!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "ALL SYSTEMS GO!" -ForegroundColor Green
    Write-Host "CLIENT WILL BE HAPPY!" -ForegroundColor Green
}

Write-Host ""
