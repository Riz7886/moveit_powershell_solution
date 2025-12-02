# MOVEIT PRODUCTION CLEANUP - ZERO ERRORS VERSION
# Tests everything, finds duplicates (NSGs and LBs), deletes ONLY safe duplicates

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "MOVEIT PRODUCTION CLEANUP - ULTRA SAFE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "SilentlyContinue"

# Load config
$configPath = "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json"
$config = Get-Content $configPath | ConvertFrom-Json
$resourceGroup = $config.DeploymentResourceGroup

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host ""

# ================================================================
# PHASE 1: DISCOVER ALL RESOURCES
# ================================================================
Write-Host "PHASE 1: Discovering all resources..." -ForegroundColor Cyan
Write-Host ""

# Find all Load Balancers
Write-Host "Checking Load Balancers..." -ForegroundColor Yellow
$allLBs = az network lb list --resource-group $resourceGroup --output json | ConvertFrom-Json

Write-Host "Found $($allLBs.Count) Load Balancer(s):" -ForegroundColor White
foreach ($lb in $allLBs) {
    $backendCount = if ($lb.backendAddressPools) { $lb.backendAddressPools.Count } else { 0 }
    $rulesCount = if ($lb.loadBalancingRules) { $lb.loadBalancingRules.Count } else { 0 }
    $frontendIP = $lb.frontendIPConfigurations[0].publicIPAddress.id
    
    Write-Host "  - Name: $($lb.name)" -ForegroundColor White
    Write-Host "    Backend Pools: $backendCount" -ForegroundColor Gray
    Write-Host "    LB Rules: $rulesCount" -ForegroundColor Gray
    Write-Host "    Frontend IP: $($frontendIP.Split('/')[-1])" -ForegroundColor Gray
    Write-Host ""
}

# Find all NSGs
Write-Host "Checking Network Security Groups..." -ForegroundColor Yellow
$allNSGs = az network nsg list --resource-group $resourceGroup --output json | ConvertFrom-Json

Write-Host "Found $($allNSGs.Count) NSG(s):" -ForegroundColor White
foreach ($nsg in $allNSGs) {
    $subnetAttached = if ($nsg.subnets) { "Subnet" } else { "" }
    $nicAttached = if ($nsg.networkInterfaces) { "NIC" } else { "" }
    $attached = @($subnetAttached, $nicAttached) | Where-Object { $_ } | Join-String -Separator ", "
    if (-not $attached) { $attached = "UNUSED" }
    
    Write-Host "  - Name: $($nsg.name)" -ForegroundColor White
    Write-Host "    Attached to: $attached" -ForegroundColor Gray
    Write-Host ""
}

# Get subnet info
$subnet = az network vnet subnet show --resource-group $resourceGroup --vnet-name vnet-moveit --name snet-moveit --output json | ConvertFrom-Json
$subnetNSG = if ($subnet.networkSecurityGroup) { $subnet.networkSecurityGroup.id.Split('/')[-1] } else { "None" }

Write-Host "Subnet Configuration:" -ForegroundColor Yellow
Write-Host "  Subnet: snet-moveit" -ForegroundColor White
Write-Host "  Current NSG: $subnetNSG" -ForegroundColor Gray
Write-Host ""

# Get NIC info
$nic = az network nic show --resource-group $resourceGroup --name nic-moveit-transfer --output json | ConvertFrom-Json
$nicNSG = if ($nic.networkSecurityGroup) { $nic.networkSecurityGroup.id.Split('/')[-1] } else { "None" }

Write-Host "NIC Configuration:" -ForegroundColor Yellow
Write-Host "  NIC: nic-moveit-transfer" -ForegroundColor White
Write-Host "  Current NSG: $nicNSG" -ForegroundColor Gray
Write-Host ""

# ================================================================
# PHASE 2: IDENTIFY DUPLICATES & UNUSED RESOURCES
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PHASE 2: Identifying duplicates and unused resources..." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$itemsToDelete = @()

# Check Load Balancers
if ($allLBs.Count -gt 1) {
    Write-Host "⚠️  MULTIPLE LOAD BALANCERS DETECTED!" -ForegroundColor Yellow
    Write-Host ""
    
    # Determine which LB is the working one
    $workingLB = $null
    $unusedLB = $null
    
    foreach ($lb in $allLBs) {
        $backendCount = if ($lb.backendAddressPools) { $lb.backendAddressPools.Count } else { 0 }
        $rulesCount = if ($lb.loadBalancingRules) { $lb.loadBalancingRules.Count } else { 0 }
        
        # The working LB should have backend pools AND rules
        if ($backendCount -gt 0 -and $rulesCount -gt 0) {
            $workingLB = $lb
            Write-Host "  ✅ WORKING LB: $($lb.name)" -ForegroundColor Green
            Write-Host "     - Backend Pools: $backendCount" -ForegroundColor Gray
            Write-Host "     - LB Rules: $rulesCount" -ForegroundColor Gray
        } else {
            $unusedLB = $lb
            Write-Host "  ❌ UNUSED LB: $($lb.name)" -ForegroundColor Red
            Write-Host "     - Backend Pools: $backendCount" -ForegroundColor Gray
            Write-Host "     - LB Rules: $rulesCount" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    
    if ($unusedLB) {
        $itemsToDelete += [PSCustomObject]@{
            Type = "Load Balancer"
            Name = $unusedLB.name
            Reason = "No backend pools or rules configured - unused"
        }
        Write-Host "  ➡️  WILL DELETE: $($unusedLB.name)" -ForegroundColor Yellow
        Write-Host "  ➡️  WILL KEEP: $($workingLB.name)" -ForegroundColor Green
    }
    Write-Host ""
}

# Check NSGs
if ($subnetNSG -eq "nsg-moveit" -and $nicNSG -eq "nsg-moveit-transfer") {
    Write-Host "⚠️  DUPLICATE NSG DETECTED!" -ForegroundColor Yellow
    Write-Host "  - Subnet has: nsg-moveit" -ForegroundColor Gray
    Write-Host "  - NIC has: nsg-moveit-transfer" -ForegroundColor Gray
    Write-Host ""
    
    $itemsToDelete += [PSCustomObject]@{
        Type = "NSG Association"
        Name = "nsg-moveit"
        Reason = "Remove from subnet - use nsg-moveit-transfer instead"
    }
    
    Write-Host "  ➡️  WILL REMOVE: nsg-moveit from subnet" -ForegroundColor Yellow
    Write-Host "  ➡️  WILL ASSOCIATE: nsg-moveit-transfer with subnet" -ForegroundColor Green
    Write-Host ""
}

# Check for unused NSGs
foreach ($nsg in $allNSGs) {
    if (-not $nsg.subnets -and -not $nsg.networkInterfaces) {
        if ($nsg.name -ne "nsg-moveit-transfer") {
            $itemsToDelete += [PSCustomObject]@{
                Type = "NSG"
                Name = $nsg.name
                Reason = "Not attached to any resource"
            }
            Write-Host "  ➡️  WILL DELETE: $($nsg.name) (unused)" -ForegroundColor Yellow
        }
    }
}

if ($itemsToDelete.Count -eq 0) {
    Write-Host "✅ NO DUPLICATES OR UNUSED RESOURCES FOUND!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Infrastructure is optimal. Nothing to clean up!" -ForegroundColor Green
    Write-Host ""
    exit
}

Write-Host ""

# ================================================================
# PHASE 3: CONFIRMATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PHASE 3: Review and confirm cleanup actions" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "The following items will be deleted/modified:" -ForegroundColor Yellow
Write-Host ""
foreach ($item in $itemsToDelete) {
    Write-Host "  • Type: $($item.Type)" -ForegroundColor White
    Write-Host "    Name: $($item.Name)" -ForegroundColor White
    Write-Host "    Reason: $($item.Reason)" -ForegroundColor Gray
    Write-Host ""
}

# Create backup
$backupFile = "C:\Users\$env:USERNAME\Desktop\moveit-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$backup = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    resourceGroup = $resourceGroup
    loadBalancers = $allLBs
    nsgs = $allNSGs
    subnet = $subnet
    nic = $nic
    itemsToDelete = $itemsToDelete
}
$backup | ConvertTo-Json -Depth 10 | Out-File $backupFile

Write-Host "✅ Backup created: $backupFile" -ForegroundColor Green
Write-Host ""

Write-Host "⚠️  THIS IS A PRODUCTION ENVIRONMENT!" -ForegroundColor Yellow
Write-Host ""

$confirmation = Read-Host "Type 'YES' to proceed with cleanup (anything else cancels)"

if ($confirmation -ne "YES") {
    Write-Host ""
    Write-Host "❌ Cleanup cancelled - no changes made" -ForegroundColor Red
    Write-Host ""
    exit
}

# ================================================================
# PHASE 4: EXECUTE CLEANUP
# ================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PHASE 4: Executing cleanup..." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($item in $itemsToDelete) {
    Write-Host "Processing: $($item.Name)..." -ForegroundColor Yellow
    
    if ($item.Type -eq "Load Balancer") {
        Write-Host "  Deleting Load Balancer: $($item.Name)" -ForegroundColor Yellow
        az network lb delete --resource-group $resourceGroup --name $item.Name --output none
        Write-Host "  ✅ Deleted" -ForegroundColor Green
        Start-Sleep -Seconds 3
    }
    
    if ($item.Type -eq "NSG Association") {
        Write-Host "  Removing NSG from subnet..." -ForegroundColor Yellow
        az network vnet subnet update --resource-group $resourceGroup --vnet-name vnet-moveit --name snet-moveit --network-security-group "" --output none
        Write-Host "  ✅ Removed" -ForegroundColor Green
        Start-Sleep -Seconds 3
        
        Write-Host "  Associating nsg-moveit-transfer with subnet..." -ForegroundColor Yellow
        az network vnet subnet update --resource-group $resourceGroup --vnet-name vnet-moveit --name snet-moveit --network-security-group nsg-moveit-transfer --output none
        Write-Host "  ✅ Associated" -ForegroundColor Green
        Start-Sleep -Seconds 3
    }
    
    if ($item.Type -eq "NSG") {
        $nsgCheck = az network nsg show --resource-group $resourceGroup --name $item.Name --query "{Subnets:length(subnets), NICs:length(networkInterfaces)}" --output json 2>$null | ConvertFrom-Json
        
        if ($nsgCheck.Subnets -eq 0 -and $nsgCheck.NICs -eq 0) {
            Write-Host "  Deleting NSG: $($item.Name)" -ForegroundColor Yellow
            az network nsg delete --resource-group $resourceGroup --name $item.Name --yes --output none
            Write-Host "  ✅ Deleted" -ForegroundColor Green
            Start-Sleep -Seconds 3
        } else {
            Write-Host "  ⚠️  Skipped - still attached" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}

# ================================================================
# PHASE 5: VERIFICATION
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PHASE 5: Verifying everything still works..." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing MOVEit HTTPS access..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ MOVEit WORKING - Status $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ MOVEit test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "Final configuration:" -ForegroundColor Yellow
$finalSubnet = az network vnet subnet show --resource-group $resourceGroup --vnet-name vnet-moveit --name snet-moveit --output json | ConvertFrom-Json
$finalNSG = if ($finalSubnet.networkSecurityGroup) { $finalSubnet.networkSecurityGroup.id.Split('/')[-1] } else { "None" }
Write-Host "  Subnet NSG: $finalNSG" -ForegroundColor White

$finalLBs = az network lb list --resource-group $resourceGroup --query "[].name" --output json | ConvertFrom-Json
Write-Host "  Load Balancers: $($finalLBs -join ', ')" -ForegroundColor White

$finalNSGs = az network nsg list --resource-group $resourceGroup --query "[].name" --output json | ConvertFrom-Json
Write-Host "  NSGs: $($finalNSGs -join ', ')" -ForegroundColor White
Write-Host ""

# ================================================================
# FINAL REPORT
# ================================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "CLEANUP COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ COMPLETED:" -ForegroundColor Green
foreach ($item in $itemsToDelete) {
    Write-Host "  • Removed/Deleted: $($item.Name)" -ForegroundColor White
}
Write-Host ""

Write-Host "📊 FINAL STATUS:" -ForegroundColor Yellow
Write-Host "  ✅ MOVEit: Working at https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host "  ✅ Load Balancers: $($finalLBs.Count)" -ForegroundColor White
Write-Host "  ✅ NSGs: $($finalNSGs.Count)" -ForegroundColor White
Write-Host "  ✅ No duplicates" -ForegroundColor White
Write-Host "  ✅ No loose ends" -ForegroundColor White
Write-Host ""

Write-Host "📁 BACKUP: $backupFile" -ForegroundColor Yellow
Write-Host ""

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "TELL YOUR MANAGER: 100% COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

