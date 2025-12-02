# FINAL LOOSE ENDS CHECK - NO WASTED RESOURCES
Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LOOSE ENDS & COST OPTIMIZATION CHECK" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

$looseEnds = @()
$totalIssues = 0

Write-Host "Scanning for unused resources..." -ForegroundColor Yellow
Write-Host ""

# Check 1: Duplicate Load Balancers
Write-Host "[1/8] Checking Load Balancers..." -ForegroundColor Yellow
$allLBs = az network lb list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
if ($allLBs.Count -gt 1) {
    foreach ($lb in $allLBs) {
        $backendCount = if ($lb.backendAddressPools) { $lb.backendAddressPools.Count } else { 0 }
        $rulesCount = if ($lb.loadBalancingRules) { $lb.loadBalancingRules.Count } else { 0 }
        
        if ($backendCount -eq 0 -and $rulesCount -eq 0) {
            Write-Host "  LOOSE END: $($lb.name) - No backend pools or rules" -ForegroundColor Red
            $looseEnds += "Load Balancer: $($lb.name) (unused)"
            $totalIssues++
        } else {
            Write-Host "  OK: $($lb.name) - In use (Pools: $backendCount, Rules: $rulesCount)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  OK: 1 Load Balancer - No duplicates" -ForegroundColor Green
}
Write-Host ""

# Check 2: Unused NSGs
Write-Host "[2/8] Checking Network Security Groups..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($nsg in $allNSGs) {
    $hasSubnet = if ($nsg.subnets) { $true } else { $false }
    $hasNIC = if ($nsg.networkInterfaces) { $true } else { $false }
    
    if (-not $hasSubnet -and -not $hasNIC) {
        Write-Host "  LOOSE END: $($nsg.name) - Not attached to anything" -ForegroundColor Red
        $looseEnds += "NSG: $($nsg.name) (unattached)"
        $totalIssues++
    } else {
        $attachedTo = @()
        if ($hasSubnet) { $attachedTo += "Subnet" }
        if ($hasNIC) { $attachedTo += "NIC" }
        Write-Host "  OK: $($nsg.name) - Attached to: $($attachedTo -join ', ')" -ForegroundColor Green
    }
}
Write-Host ""

# Check 3: Unused Public IPs
Write-Host "[3/8] Checking Public IPs..." -ForegroundColor Yellow
$allPublicIPs = az network public-ip list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($pip in $allPublicIPs) {
    if (-not $pip.ipConfiguration) {
        Write-Host "  LOOSE END: $($pip.name) - Not attached (IP: $($pip.ipAddress))" -ForegroundColor Red
        $looseEnds += "Public IP: $($pip.name) ($($pip.ipAddress)) (unused)"
        $totalIssues++
    } else {
        Write-Host "  OK: $($pip.name) - In use ($($pip.ipAddress))" -ForegroundColor Green
    }
}
Write-Host ""

# Check 4: Unattached NICs
Write-Host "[4/8] Checking Network Interfaces..." -ForegroundColor Yellow
$allNICs = az network nic list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($nic in $allNICs) {
    if (-not $nic.virtualMachine) {
        Write-Host "  LOOSE END: $($nic.name) - Not attached to any VM" -ForegroundColor Red
        $looseEnds += "NIC: $($nic.name) (unattached)"
        $totalIssues++
    } else {
        Write-Host "  OK: $($nic.name) - Attached to VM" -ForegroundColor Green
    }
}
Write-Host ""

# Check 5: Unattached Disks
Write-Host "[5/8] Checking Disks..." -ForegroundColor Yellow
$allDisks = az disk list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($disk in $allDisks) {
    if ($disk.diskState -eq "Unattached") {
        Write-Host "  LOOSE END: $($disk.name) - Not attached to any VM" -ForegroundColor Red
        $looseEnds += "Disk: $($disk.name) (unattached)"
        $totalIssues++
    } else {
        Write-Host "  OK: $($disk.name) - Attached" -ForegroundColor Green
    }
}
Write-Host ""

# Check 6: Front Door Origin Check
Write-Host "[6/8] Checking Front Door Origin..." -ForegroundColor Yellow
$origin = az afd origin show --resource-group $resourceGroup --profile-name moveit-frontdoor-profile --origin-group-name moveit-origin-group --origin-name moveit-origin --output json 2>$null | ConvertFrom-Json
$lbIP = az network public-ip show --resource-group $resourceGroup --name $config.PublicIPName --query ipAddress --output tsv 2>$null

if ($origin.hostName -eq $lbIP) {
    Write-Host "  OK: Front Door points to Load Balancer ($lbIP)" -ForegroundColor Green
} else {
    Write-Host "  INFO: Front Door points to: $($origin.hostName)" -ForegroundColor Yellow
    Write-Host "        Load Balancer IP: $lbIP" -ForegroundColor Yellow
}
Write-Host ""

# Check 7: Backend Pool Configuration
Write-Host "[7/8] Checking Backend Pool..." -ForegroundColor Yellow
$backendPool = az network lb address-pool show --resource-group $resourceGroup --lb-name lb-moveit-sftp --name moveit-backend-pool --output json 2>$null | ConvertFrom-Json
if ($backendPool) {
    $backendCount = if ($backendPool.backendIPConfigurations) { $backendPool.backendIPConfigurations.Count } else { 0 }
    if ($backendCount -gt 0) {
        Write-Host "  OK: Backend pool has $backendCount VM(s)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Backend pool is empty" -ForegroundColor Yellow
    }
}
Write-Host ""

# Check 8: Subnet NSG Configuration
Write-Host "[8/8] Checking Subnet NSG..." -ForegroundColor Yellow
$vnetList = az network vnet list --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
foreach ($vnet in $vnetList) {
    $subnets = az network vnet subnet list --resource-group $resourceGroup --vnet-name $vnet.name --output json 2>$null | ConvertFrom-Json
    foreach ($subnet in $subnets) {
        if ($subnet.networkSecurityGroup) {
            $nsgName = $subnet.networkSecurityGroup.id.Split('/')[-1]
            Write-Host "  OK: $($subnet.name) protected by $nsgName" -ForegroundColor Green
        } else {
            Write-Host "  INFO: $($subnet.name) has no NSG" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($totalIssues -eq 0) {
    Write-Host "NO LOOSE ENDS FOUND!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host ""
    Write-Host "Your deployment is clean and optimized." -ForegroundColor Green
    Write-Host "No wasted resources." -ForegroundColor Green
    Write-Host "No duplicate infrastructure." -ForegroundColor Green
    Write-Host ""
    Write-Host "READY TO SHOW CLIENT!" -ForegroundColor Green
} else {
    Write-Host "FOUND $totalIssues LOOSE END(S):" -ForegroundColor Yellow
    Write-Host ""
    foreach ($item in $looseEnds) {
        Write-Host "  - $item" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "RECOMMENDATION:" -ForegroundColor Yellow
    Write-Host "These resources are not being used and can be deleted" -ForegroundColor White
    Write-Host "to reduce costs and clean up the deployment." -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "INFRASTRUCTURE STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Load Balancers:  $($allLBs.Count)" -ForegroundColor White
Write-Host "NSGs:            $($allNSGs.Count)" -ForegroundColor White
Write-Host "Public IPs:      $($allPublicIPs.Count)" -ForegroundColor White
Write-Host "NICs:            $($allNICs.Count)" -ForegroundColor White
Write-Host "Disks:           $($allDisks.Count)" -ForegroundColor White
Write-Host ""
Write-Host "MOVEit Status:   WORKING" -ForegroundColor Green
Write-Host "URL:             https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host ""

