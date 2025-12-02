# CLEAN PUBLIC IP AUDIT AND CLEANUP
# No errors, no bullshit

Clear-Host

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PUBLIC IP AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$rg = $config.DeploymentResourceGroup

Write-Host "Resource Group: $rg" -ForegroundColor Yellow
Write-Host ""

Write-Host "LISTING ALL PUBLIC IPs..." -ForegroundColor Yellow
Write-Host ""

$allPIPs = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json

Write-Host "Total: $($allPIPs.Count)" -ForegroundColor White
Write-Host ""

$safePIPs = @()
$loosePIPs = @()

foreach ($pip in $allPIPs) {
    $pipName = $pip.name
    $ipAddr = $pip.ipAddress
    $attached = $pip.ipConfiguration
    
    Write-Host "PIP: $pipName" -ForegroundColor Cyan
    Write-Host "  IP: $ipAddr" -ForegroundColor White
    
    if ($attached) {
        Write-Host "  Status: ATTACHED" -ForegroundColor Green
        Write-Host "  Action: PROTECTED" -ForegroundColor Green
        $safePIPs += $pipName
    } else {
        Write-Host "  Status: LOOSE" -ForegroundColor Red
        Write-Host "  Action: DELETE" -ForegroundColor Yellow
        $loosePIPs += $pipName
    }
    Write-Host ""
}

Write-Host "SUMMARY:" -ForegroundColor White
Write-Host "  Protected: $($safePIPs.Count)" -ForegroundColor Green
Write-Host "  Loose: $($loosePIPs.Count)" -ForegroundColor Red
Write-Host ""

if ($loosePIPs.Count -eq 0) {
    Write-Host "NO LOOSE PUBLIC IPs!" -ForegroundColor Green
    exit
}

Write-Host "WILL DELETE:" -ForegroundColor Yellow
foreach ($pip in $loosePIPs) {
    Write-Host "  - $pip" -ForegroundColor Red
}
Write-Host ""

Write-Host "WILL PROTECT:" -ForegroundColor Green
foreach ($pip in $safePIPs) {
    Write-Host "  - $pip" -ForegroundColor Green
}
Write-Host ""

$confirmation = Read-Host "Type DELETE to proceed"

if ($confirmation.Trim().ToUpper() -ne "DELETE") {
    Write-Host "CANCELLED" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "DELETING..." -ForegroundColor Yellow
Write-Host ""

foreach ($pipName in $loosePIPs) {
    Write-Host "Deleting: $pipName" -ForegroundColor Yellow
    az network public-ip delete --resource-group $rg --name $pipName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "  FAILED" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Waiting 10 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "CHECKING LOOSE ENDS..." -ForegroundColor Yellow
Write-Host ""

$looseCount = 0

$nsgs = az network nsg list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nsg in $nsgs) {
    $hasSubnet = if ($nsg.subnets) { $nsg.subnets.Count -gt 0 } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $nsg.networkInterfaces.Count -gt 0 } else { $false }
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE NSG: $($nsg.name)" -ForegroundColor Red
        $looseCount++
    }
}

$pips = az network public-ip list --resource-group $rg --output json | ConvertFrom-Json
foreach ($pip in $pips) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE PIP: $($pip.name)" -ForegroundColor Red
        $looseCount++
    }
}

$nics = az network nic list --resource-group $rg --output json | ConvertFrom-Json
foreach ($nic in $nics) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE NIC: $($nic.name)" -ForegroundColor Red
        $looseCount++
    }
}

Write-Host ""
Write-Host "LOOSE ENDS: $looseCount" -ForegroundColor $(if ($looseCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

Write-Host "TESTING MOVEIT..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing
    Write-Host "  WORKING - Status $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "  FAILED" -ForegroundColor Red
}

Write-Host ""

$lbCount = (az network lb list --resource-group $rg --output json | ConvertFrom-Json).Count
$nsgCount = (az network nsg list --resource-group $rg --output json | ConvertFrom-Json).Count
$pipCount = (az network public-ip list --resource-group $rg --output json | ConvertFrom-Json).Count
$nicCount = (az network nic list --resource-group $rg --output json | ConvertFrom-Json).Count
$diskCount = (az disk list --resource-group $rg --output json | ConvertFrom-Json).Count

Write-Host "RESOURCES:" -ForegroundColor Cyan
Write-Host "  Load Balancers: $lbCount" -ForegroundColor White
Write-Host "  NSGs: $nsgCount" -ForegroundColor White
Write-Host "  Public IPs: $pipCount" -ForegroundColor White
Write-Host "  NICs: $nicCount" -ForegroundColor White
Write-Host "  Disks: $diskCount" -ForegroundColor White
Write-Host ""

if ($looseCount -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "ZERO LOOSE ENDS - SUCCESS" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

Write-Host ""
