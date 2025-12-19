# DATABRICKS COMPREHENSIVE AUDIT SCRIPT
# READ ONLY - NO CHANGES - Lists all resources, costs, idle detection
# Generates HTML and CSV reports

param(
    [int]$MonthsBack = 5
)

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS COMPREHENSIVE AUDIT REPORT" -ForegroundColor Cyan
Write-Host "  Resources - Costs - Idle Detection - Full Breakdown" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  *** READ ONLY - NO CHANGES WILL BE MADE ***" -ForegroundColor Green
Write-Host ""

$ReportPath = "$env:USERPROFILE\Desktop\Databricks-Audit-Reports"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

function Connect-ToAzure {
    Write-Host "Step 1: Checking Azure connection..." -ForegroundColor Yellow
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "Not logged in. Opening browser..." -ForegroundColor Yellow
            Connect-AzAccount
            $context = Get-AzContext
        }
        Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "ERROR: Could not connect to Azure" -ForegroundColor Red
        return $false
    }
}

function Select-AzureSubscription {
    Write-Host ""
    Write-Host "Step 2: Getting subscriptions..." -ForegroundColor Yellow
    $subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    Write-Host ""
    $i = 1
    foreach ($s in $subs) {
        Write-Host "  $i. $($s.Name)" -ForegroundColor White
        $i++
    }
    Write-Host ""
    $selection = Read-Host "Select subscription number"
    $selectedSub = $subs[$selection - 1]
    Set-AzContext -Subscription $selectedSub.Id | Out-Null
    Write-Host "Selected: $($selectedSub.Name)" -ForegroundColor Green
    return $selectedSub
}

function Get-DatabricksWorkspaces {
    Write-Host ""
    Write-Host "Step 3: Finding Databricks workspaces..." -ForegroundColor Yellow
    $workspaces = @()
    try {
        $workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces"
    } catch { }
    if ($workspaces -and $workspaces.Count -gt 0) {
        Write-Host "Found $($workspaces.Count) Databricks workspace(s)" -ForegroundColor Green
        foreach ($ws in $workspaces) {
            Write-Host "  - $($ws.Name) (RG: $($ws.ResourceGroupName))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "No Databricks workspaces found." -ForegroundColor Yellow
    }
    return $workspaces
}

function Get-WorkspaceDetails {
    param($Workspace)
    try {
        $details = Get-AzDatabricksWorkspace -ResourceGroupName $Workspace.ResourceGroupName -Name $Workspace.Name -ErrorAction SilentlyContinue
        return $details
    } catch {
        return $null
    }
}

function Get-RGResources {
    param([string]$RGName)
    try {
        $resources = Get-AzResource -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        return $resources
    } catch {
        return @()
    }
}

function Get-VMInfo {
    param([string]$RGName)
    $vmList = @()
    try {
        $vms = Get-AzVM -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($vm in $vms) {
            $status = Get-AzVM -ResourceGroupName $RGName -Name $vm.Name -Status -ErrorAction SilentlyContinue
            $powerState = "Unknown"
            if ($status -and $status.Statuses) {
                $pwrStatus = $status.Statuses | Where-Object { $_.Code -like "PowerState/*" }
                if ($pwrStatus) { $powerState = $pwrStatus.DisplayStatus }
            }
            $isRunning = $powerState -eq "VM running"
            $vmObj = [PSCustomObject]@{
                Name = $vm.Name
                ResourceGroup = $RGName
                Size = $vm.HardwareProfile.VmSize
                Location = $vm.Location
                PowerState = $powerState
                OsType = $vm.StorageProfile.OsDisk.OsType
                IsRunning = $isRunning
                IsIdle = (-not $isRunning)
            }
            $vmList += $vmObj
        }
    } catch { }
    return $vmList
}

function Get-StorageInfo {
    param([string]$RGName)
    $storageList = @()
    try {
        $accounts = Get-AzStorageAccount -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($sa in $accounts) {
            $saObj = [PSCustomObject]@{
                Name = $sa.StorageAccountName
                ResourceGroup = $RGName
                Kind = $sa.Kind
                Sku = $sa.Sku.Name
                Location = $sa.Location
                AccessTier = $sa.AccessTier
            }
            $storageList += $saObj
        }
    } catch { }
    return $storageList
}

function Get-NSGInfo {
    param([string]$RGName)
    $nsgList = @()
    try {
        $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($nsg in $nsgs) {
            $subnetNames = ""
            if ($nsg.Subnets) {
                $subnetNames = ($nsg.Subnets | ForEach-Object { $_.Id.Split("/")[-1] }) -join ", "
            }
            $nsgObj = [PSCustomObject]@{
                Name = $nsg.Name
                ResourceGroup = $RGName
                Location = $nsg.Location
                RuleCount = $nsg.SecurityRules.Count
                AssociatedSubnets = $subnetNames
            }
            $nsgList += $nsgObj
        }
    } catch { }
    return $nsgList
}

function Get-VNetInfo {
    param([string]$RGName)
    $vnetList = @()
    try {
        $vnets = Get-AzVirtualNetwork -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($vnet in $vnets) {
            $addressSpace = ""
            if ($vnet.AddressSpace -and $vnet.AddressSpace.AddressPrefixes) {
                $addressSpace = $vnet.AddressSpace.AddressPrefixes -join ", "
            }
            $subnetInfo = ""
            if ($vnet.Subnets) {
                $subnetInfo = ($vnet.Subnets | ForEach-Object { $_.Name }) -join ", "
            }
            $vnetObj = [PSCustomObject]@{
                Name = $vnet.Name
                ResourceGroup = $RGName
                Location = $vnet.Location
                AddressSpace = $addressSpace
                SubnetCount = $vnet.Subnets.Count
                Subnets = $subnetInfo
            }
            $vnetList += $vnetObj
        }
    } catch { }
    return $vnetList
}

function Get-DiskInfo {
    param([string]$RGName)
    $diskList = @()
    try {
        $disks = Get-AzDisk -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($disk in $disks) {
            $attachedTo = "Unattached"
            $isUnattached = $true
            if ($disk.ManagedBy) {
                $attachedTo = $disk.ManagedBy.Split("/")[-1]
                $isUnattached = $false
            }
            $diskObj = [PSCustomObject]@{
                Name = $disk.Name
                ResourceGroup = $RGName
                SizeGB = $disk.DiskSizeGB
                Sku = $disk.Sku.Name
                State = $disk.DiskState
                AttachedTo = $attachedTo
                IsUnattached = $isUnattached
            }
            $diskList += $diskObj
        }
    } catch { }
    return $diskList
}

function Get-PublicIPInfo {
    param([string]$RGName)
    $pipList = @()
    try {
        $pips = Get-AzPublicIpAddress -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($pip in $pips) {
            $associatedTo = "Unassociated"
            $isUnassociated = $true
            if ($pip.IpConfiguration) {
                $associatedTo = $pip.IpConfiguration.Id.Split("/")[-3]
                $isUnassociated = $false
            }
            $pipObj = [PSCustomObject]@{
                Name = $pip.Name
                ResourceGroup = $RGName
                IPAddress = $pip.IpAddress
                AllocationMethod = $pip.PublicIpAllocationMethod
                Sku = $pip.Sku.Name
                AssociatedTo = $associatedTo
                IsUnassociated = $isUnassociated
            }
            $pipList += $pipObj
        }
    } catch { }
    return $pipList
}

function Get-NICInfo {
    param([string]$RGName)
    $nicList = @()
    try {
        $nics = Get-AzNetworkInterface -ResourceGroupName $RGName -ErrorAction SilentlyContinue
        foreach ($nic in $nics) {
            $attachedTo = "Unattached"
            $isUnattached = $true
            if ($nic.VirtualMachine) {
                $attachedTo = $nic.VirtualMachine.Id.Split("/")[-1]
                $isUnattached = $false
            }
            $privateIP = ""
            if ($nic.IpConfigurations) {
                $privateIP = ($nic.IpConfigurations | ForEach-Object { $_.PrivateIpAddress }) -join ", "
            }
            $nicObj = [PSCustomObject]@{
                Name = $nic.Name
                ResourceGroup = $RGName
                Location = $nic.Location
                PrivateIP = $privateIP
                AttachedTo = $attachedTo
                IsUnattached = $isUnattached
            }
            $nicList += $nicObj
        }
    } catch { }
    return $nicList
}

function Get-CostInfo {
    param([string]$RGName, [int]$Months)
    $costList = @()
    try {
        $endDate = Get-Date
        $startDate = $endDate.AddMonths(-$Months)
        $usage = Get-AzConsumptionUsageDetail -ResourceGroup $RGName -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue
        if ($usage) {
            $grouped = $usage | Group-Object { $_.UsageStart.ToString("yyyy-MM") }
            foreach ($g in $grouped) {
                $totalCost = ($g.Group | Measure-Object -Property PretaxCost -Sum).Sum
                $currency = $g.Group[0].Currency
                $costObj = [PSCustomObject]@{
                    Month = $g.Name
                    Cost = [math]::Round($totalCost, 2)
                    Currency = $currency
                    ResourceGroup = $RGName
                }
                $costList += $costObj
            }
        }
    } catch { }
    return $costList
}

function New-HTMLReport {
    param($Workspaces, $AllResources, $VMData, $StorageData, $NSGData, $VNetData, $DiskData, $PublicIPData, $NICData, $CostData, $IdleData, $SubName)
    
    $htmlFile = Join-Path $ReportPath "Databricks-Audit-Report-$Timestamp.html"
    
    $totalVMs = $VMData.Count
    $runningVMs = ($VMData | Where-Object { $_.IsRunning }).Count
    $stoppedVMs = $totalVMs - $runningVMs
    $totalStorage = $StorageData.Count
    $totalDisks = $DiskData.Count
    $unattachedDisks = ($DiskData | Where-Object { $_.IsUnattached }).Count
    $totalNSGs = $NSGData.Count
    $totalVNets = $VNetData.Count
    $totalPIPs = $PublicIPData.Count
    $totalNICs = $NICData.Count
    $totalIdle = $IdleData.Count
    $totalResources = $AllResources.Count
    $totalWorkspaces = $Workspaces.Count
    $totalCost = 0
    if ($CostData) { $totalCost = [math]::Round(($CostData | Measure-Object -Property Cost -Sum).Sum, 2) }
    $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @()
    $html += "<!DOCTYPE html>"
    $html += "<html><head><title>Databricks Audit Report</title>"
    $html += "<style>"
    $html += "body{font-family:Segoe UI,Arial,sans-serif;margin:20px;background:#f5f5f5}"
    $html += ".header{background:linear-gradient(135deg,#FF3621,#E25A1C);color:white;padding:30px;border-radius:10px;margin-bottom:20px}"
    $html += ".header h1{margin:0;font-size:28px}.header p{margin:10px 0 0 0;opacity:0.9}"
    $html += ".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:15px;margin-bottom:20px}"
    $html += ".card{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 5px rgba(0,0,0,0.1);text-align:center}"
    $html += ".card h3{margin:0;color:#666;font-size:12px;text-transform:uppercase}"
    $html += ".card .num{font-size:32px;font-weight:bold;color:#FF3621;margin:10px 0}"
    $html += ".card .sub{color:#999;font-size:11px}"
    $html += ".section{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 5px rgba(0,0,0,0.1);margin-bottom:20px}"
    $html += ".section h2{color:#333;border-bottom:2px solid #FF3621;padding-bottom:10px;margin-top:0}"
    $html += "table{width:100%;border-collapse:collapse;margin-top:15px;font-size:13px}"
    $html += "th{background:#FF3621;color:white;padding:10px;text-align:left}"
    $html += "td{padding:8px;border-bottom:1px solid #eee}"
    $html += "tr:hover{background:#fff8f6}"
    $html += ".running{color:#28a745;font-weight:bold}.stopped{color:#dc3545;font-weight:bold}.warning{color:#ffc107;font-weight:bold}"
    $html += ".idle-row{background:#fff3cd}"
    $html += ".cost-card{background:linear-gradient(135deg,#28a745,#20c997)}.cost-card .num{color:white}.cost-card h3{color:rgba(255,255,255,0.9)}.cost-card .sub{color:rgba(255,255,255,0.8)}"
    $html += ".warn-card{background:linear-gradient(135deg,#ffc107,#fd7e14)}.warn-card .num{color:#333}.warn-card h3{color:#333}"
    $html += ".footer{text-align:center;color:#666;margin-top:20px;padding:20px}"
    $html += ".ws-box{background:#f8f9fa;padding:15px;border-radius:8px;margin-bottom:15px;border-left:4px solid #FF3621}"
    $html += ".ws-box h4{margin:0 0 10px 0;color:#FF3621}"
    $html += "</style></head><body>"
    
    $html += "<div class='header'><h1>Databricks Comprehensive Audit Report</h1>"
    $html += "<p>Subscription: $SubName | Generated: $reportDate</p></div>"
    
    $html += "<div class='grid'>"
    $html += "<div class='card'><h3>Workspaces</h3><div class='num'>$totalWorkspaces</div><div class='sub'>Databricks</div></div>"
    $html += "<div class='card'><h3>Virtual Machines</h3><div class='num'>$totalVMs</div><div class='sub'>$runningVMs running, $stoppedVMs stopped</div></div>"
    $html += "<div class='card'><h3>Storage Accounts</h3><div class='num'>$totalStorage</div><div class='sub'>DBFS and workspace</div></div>"
    $html += "<div class='card'><h3>Managed Disks</h3><div class='num'>$totalDisks</div><div class='sub'>$unattachedDisks unattached</div></div>"
    $html += "<div class='card'><h3>NSGs</h3><div class='num'>$totalNSGs</div><div class='sub'>Security groups</div></div>"
    $html += "<div class='card'><h3>VNets</h3><div class='num'>$totalVNets</div><div class='sub'>Virtual networks</div></div>"
    $html += "<div class='card warn-card'><h3>Idle Resources</h3><div class='num'>$totalIdle</div><div class='sub'>Potential savings</div></div>"
    $html += "<div class='card cost-card'><h3>Total Cost</h3><div class='num'>$totalCost</div><div class='sub'>USD (last $MonthsBack months)</div></div>"
    $html += "</div>"
    
    $html += "<div class='section'><h2>Databricks Workspaces</h2>"
    foreach ($ws in $Workspaces) {
        $html += "<div class='ws-box'><h4>$($ws.Name)</h4>"
        $html += "<p><strong>Resource Group:</strong> $($ws.ResourceGroupName)</p>"
        $html += "<p><strong>Location:</strong> $($ws.Location)</p></div>"
    }
    $html += "</div>"
    
    $html += "<div class='section'><h2>Virtual Machines</h2>"
    $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Size</th><th>OS</th><th>Power State</th><th>Status</th></tr>"
    foreach ($vm in $VMData) {
        $sc = "running"; $st = "Running"; $rc = ""
        if (-not $vm.IsRunning) { $sc = "stopped"; $st = "Stopped"; $rc = "idle-row" }
        $html += "<tr class='$rc'><td>$($vm.Name)</td><td>$($vm.ResourceGroup)</td><td>$($vm.Size)</td><td>$($vm.OsType)</td><td>$($vm.PowerState)</td><td class='$sc'>$st</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Storage Accounts</h2>"
    $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Kind</th><th>SKU</th><th>Access Tier</th><th>Location</th></tr>"
    foreach ($sa in $StorageData) {
        $html += "<tr><td>$($sa.Name)</td><td>$($sa.ResourceGroup)</td><td>$($sa.Kind)</td><td>$($sa.Sku)</td><td>$($sa.AccessTier)</td><td>$($sa.Location)</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Managed Disks</h2>"
    $html += "<table><tr><th>Name</th><th>Size GB</th><th>SKU</th><th>State</th><th>Attached To</th><th>Status</th></tr>"
    foreach ($disk in $DiskData) {
        $sc = "running"; $st = "Attached"; $rc = ""
        if ($disk.IsUnattached) { $sc = "warning"; $st = "Unattached"; $rc = "idle-row" }
        $html += "<tr class='$rc'><td>$($disk.Name)</td><td>$($disk.SizeGB)</td><td>$($disk.Sku)</td><td>$($disk.State)</td><td>$($disk.AttachedTo)</td><td class='$sc'>$st</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Network Security Groups</h2>"
    $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Location</th><th>Rules</th><th>Associated Subnets</th></tr>"
    foreach ($nsg in $NSGData) {
        $html += "<tr><td>$($nsg.Name)</td><td>$($nsg.ResourceGroup)</td><td>$($nsg.Location)</td><td>$($nsg.RuleCount)</td><td>$($nsg.AssociatedSubnets)</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Virtual Networks</h2>"
    $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Address Space</th><th>Subnet Count</th><th>Subnets</th></tr>"
    foreach ($vnet in $VNetData) {
        $html += "<tr><td>$($vnet.Name)</td><td>$($vnet.ResourceGroup)</td><td>$($vnet.AddressSpace)</td><td>$($vnet.SubnetCount)</td><td>$($vnet.Subnets)</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Public IP Addresses</h2>"
    $html += "<table><tr><th>Name</th><th>IP Address</th><th>Allocation</th><th>SKU</th><th>Associated To</th><th>Status</th></tr>"
    foreach ($pip in $PublicIPData) {
        $sc = "running"; $st = "Associated"; $rc = ""
        if ($pip.IsUnassociated) { $sc = "warning"; $st = "Unassociated"; $rc = "idle-row" }
        $html += "<tr class='$rc'><td>$($pip.Name)</td><td>$($pip.IPAddress)</td><td>$($pip.AllocationMethod)</td><td>$($pip.Sku)</td><td>$($pip.AssociatedTo)</td><td class='$sc'>$st</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Network Interfaces</h2>"
    $html += "<table><tr><th>Name</th><th>Resource Group</th><th>Private IP</th><th>Attached To</th><th>Status</th></tr>"
    foreach ($nic in $NICData) {
        $sc = "running"; $st = "Attached"; $rc = ""
        if ($nic.IsUnattached) { $sc = "warning"; $st = "Unattached"; $rc = "idle-row" }
        $html += "<tr class='$rc'><td>$($nic.Name)</td><td>$($nic.ResourceGroup)</td><td>$($nic.PrivateIP)</td><td>$($nic.AttachedTo)</td><td class='$sc'>$st</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='section'><h2>Idle Resources - Potential Cost Savings</h2>"
    $html += "<table><tr><th>Resource Name</th><th>Type</th><th>Resource Group</th><th>Reason</th><th>Recommendation</th></tr>"
    foreach ($idle in $IdleData) {
        $html += "<tr class='idle-row'><td>$($idle.Name)</td><td>$($idle.Type)</td><td>$($idle.ResourceGroup)</td><td>$($idle.Reason)</td><td>$($idle.Recommendation)</td></tr>"
    }
    $html += "</table></div>"
    
    if ($CostData -and $CostData.Count -gt 0) {
        $html += "<div class='section'><h2>Cost Breakdown by Month</h2>"
        $html += "<table><tr><th>Month</th><th>Resource Group</th><th>Cost</th><th>Currency</th></tr>"
        foreach ($cost in $CostData) {
            $html += "<tr><td>$($cost.Month)</td><td>$($cost.ResourceGroup)</td><td>$($cost.Cost)</td><td>$($cost.Currency)</td></tr>"
        }
        $html += "</table></div>"
    }
    
    $html += "<div class='section'><h2>All Resources Summary</h2>"
    $html += "<table><tr><th>Resource Type</th><th>Count</th></tr>"
    $grouped = $AllResources | Group-Object ResourceType | Sort-Object Count -Descending
    foreach ($g in $grouped) {
        $html += "<tr><td>$($g.Name)</td><td>$($g.Count)</td></tr>"
    }
    $html += "</table></div>"
    
    $html += "<div class='footer'><p>Generated by Databricks Audit Script | $reportDate</p>"
    $html += "<p>*** READ ONLY REPORT - NO CHANGES WERE MADE ***</p></div>"
    $html += "</body></html>"
    
    $html -join "`n" | Out-File -FilePath $htmlFile -Encoding UTF8
    return $htmlFile
}

function Export-AllCSV {
    param($AllResources, $VMData, $StorageData, $NSGData, $VNetData, $DiskData, $PublicIPData, $NICData, $IdleData, $Workspaces, $CostData)
    
    $csvFiles = @()
    
    $p1 = Join-Path $ReportPath "All-Resources-$Timestamp.csv"
    $AllResources | Select-Object Name, ResourceType, ResourceGroupName, Location | Export-Csv -Path $p1 -NoTypeInformation
    $csvFiles += $p1
    
    if ($VMData.Count -gt 0) {
        $p2 = Join-Path $ReportPath "VirtualMachines-$Timestamp.csv"
        $VMData | Export-Csv -Path $p2 -NoTypeInformation
        $csvFiles += $p2
    }
    
    if ($StorageData.Count -gt 0) {
        $p3 = Join-Path $ReportPath "StorageAccounts-$Timestamp.csv"
        $StorageData | Export-Csv -Path $p3 -NoTypeInformation
        $csvFiles += $p3
    }
    
    if ($NSGData.Count -gt 0) {
        $p4 = Join-Path $ReportPath "NetworkSecurityGroups-$Timestamp.csv"
        $NSGData | Export-Csv -Path $p4 -NoTypeInformation
        $csvFiles += $p4
    }
    
    if ($VNetData.Count -gt 0) {
        $p5 = Join-Path $ReportPath "VirtualNetworks-$Timestamp.csv"
        $VNetData | Export-Csv -Path $p5 -NoTypeInformation
        $csvFiles += $p5
    }
    
    if ($DiskData.Count -gt 0) {
        $p6 = Join-Path $ReportPath "ManagedDisks-$Timestamp.csv"
        $DiskData | Export-Csv -Path $p6 -NoTypeInformation
        $csvFiles += $p6
    }
    
    if ($PublicIPData.Count -gt 0) {
        $p7 = Join-Path $ReportPath "PublicIPs-$Timestamp.csv"
        $PublicIPData | Export-Csv -Path $p7 -NoTypeInformation
        $csvFiles += $p7
    }
    
    if ($NICData.Count -gt 0) {
        $p8 = Join-Path $ReportPath "NetworkInterfaces-$Timestamp.csv"
        $NICData | Export-Csv -Path $p8 -NoTypeInformation
        $csvFiles += $p8
    }
    
    if ($IdleData.Count -gt 0) {
        $p9 = Join-Path $ReportPath "IdleResources-$Timestamp.csv"
        $IdleData | Export-Csv -Path $p9 -NoTypeInformation
        $csvFiles += $p9
    }
    
    if ($Workspaces.Count -gt 0) {
        $p10 = Join-Path $ReportPath "DatabricksWorkspaces-$Timestamp.csv"
        $Workspaces | Select-Object Name, ResourceGroupName, Location | Export-Csv -Path $p10 -NoTypeInformation
        $csvFiles += $p10
    }
    
    if ($CostData -and $CostData.Count -gt 0) {
        $p11 = Join-Path $ReportPath "CostData-$Timestamp.csv"
        $CostData | Export-Csv -Path $p11 -NoTypeInformation
        $csvFiles += $p11
    }
    
    return $csvFiles
}

$connected = Connect-ToAzure
if (-not $connected) { Write-Host "Cannot proceed without Azure connection." -ForegroundColor Red; exit 1 }

$subscription = Select-AzureSubscription
$workspaces = Get-DatabricksWorkspaces

if (-not $workspaces -or $workspaces.Count -eq 0) {
    Write-Host "No Databricks workspaces found. Exiting." -ForegroundColor Yellow
    exit 0
}

$allResources = @()
$allVMs = @()
$allStorage = @()
$allNSGs = @()
$allVNets = @()
$allDisks = @()
$allPublicIPs = @()
$allNICs = @()
$idleResources = @()
$allCosts = @()

Write-Host ""
Write-Host "Step 4: Analyzing resources..." -ForegroundColor Yellow

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "Processing workspace: $($ws.Name)" -ForegroundColor Cyan
    
    $wsDetails = Get-WorkspaceDetails -Workspace $ws
    $managedRGName = ""
    if ($wsDetails -and $wsDetails.ManagedResourceGroupId) {
        $managedRGName = $wsDetails.ManagedResourceGroupId.Split("/")[-1]
    } else {
        $managedRGName = "databricks-rg-$($ws.Name)"
    }
    
    Write-Host "  Scanning RG: $($ws.ResourceGroupName)" -ForegroundColor Gray
    $rgRes = Get-RGResources -RGName $ws.ResourceGroupName
    $allResources += $rgRes
    
    Write-Host "  Scanning managed RG: $managedRGName" -ForegroundColor Gray
    $mrgRes = Get-RGResources -RGName $managedRGName
    $allResources += $mrgRes
    
    Write-Host "  Getting VMs..." -ForegroundColor Gray
    $vms = Get-VMInfo -RGName $managedRGName
    $allVMs += $vms
    
    Write-Host "  Getting storage..." -ForegroundColor Gray
    $stor1 = Get-StorageInfo -RGName $managedRGName
    $stor2 = Get-StorageInfo -RGName $ws.ResourceGroupName
    $allStorage += $stor1
    $allStorage += $stor2
    
    Write-Host "  Getting NSGs..." -ForegroundColor Gray
    $nsgs = Get-NSGInfo -RGName $managedRGName
    $allNSGs += $nsgs
    
    Write-Host "  Getting VNets..." -ForegroundColor Gray
    $vnets1 = Get-VNetInfo -RGName $managedRGName
    $vnets2 = Get-VNetInfo -RGName $ws.ResourceGroupName
    $allVNets += $vnets1
    $allVNets += $vnets2
    
    Write-Host "  Getting disks..." -ForegroundColor Gray
    $disks = Get-DiskInfo -RGName $managedRGName
    $allDisks += $disks
    
    Write-Host "  Getting public IPs..." -ForegroundColor Gray
    $pips = Get-PublicIPInfo -RGName $managedRGName
    $allPublicIPs += $pips
    
    Write-Host "  Getting NICs..." -ForegroundColor Gray
    $nics = Get-NICInfo -RGName $managedRGName
    $allNICs += $nics
    
    Write-Host "  Getting cost data..." -ForegroundColor Gray
    $cost1 = Get-CostInfo -RGName $ws.ResourceGroupName -Months $MonthsBack
    $cost2 = Get-CostInfo -RGName $managedRGName -Months $MonthsBack
    $allCosts += $cost1
    $allCosts += $cost2
}

Write-Host ""
Write-Host "Step 5: Identifying idle resources..." -ForegroundColor Yellow

foreach ($vm in $allVMs) {
    if ($vm.IsIdle) {
        $idleResources += [PSCustomObject]@{ Name = $vm.Name; Type = "Virtual Machine"; ResourceGroup = $vm.ResourceGroup; Reason = "VM is stopped"; Recommendation = "Delete if not needed" }
    }
}

foreach ($disk in $allDisks) {
    if ($disk.IsUnattached) {
        $idleResources += [PSCustomObject]@{ Name = $disk.Name; Type = "Managed Disk"; ResourceGroup = $disk.ResourceGroup; Reason = "Not attached to any VM"; Recommendation = "Delete if not needed" }
    }
}

foreach ($pip in $allPublicIPs) {
    if ($pip.IsUnassociated) {
        $idleResources += [PSCustomObject]@{ Name = $pip.Name; Type = "Public IP"; ResourceGroup = $pip.ResourceGroup; Reason = "Not associated"; Recommendation = "Delete to stop billing" }
    }
}

foreach ($nic in $allNICs) {
    if ($nic.IsUnattached) {
        $idleResources += [PSCustomObject]@{ Name = $nic.Name; Type = "Network Interface"; ResourceGroup = $nic.ResourceGroup; Reason = "Not attached to any VM"; Recommendation = "Delete if not needed" }
    }
}

Write-Host ""
Write-Host "Step 6: Generating reports..." -ForegroundColor Yellow

$htmlPath = New-HTMLReport -Workspaces $workspaces -AllResources $allResources -VMData $allVMs -StorageData $allStorage -NSGData $allNSGs -VNetData $allVNets -DiskData $allDisks -PublicIPData $allPublicIPs -NICData $allNICs -CostData $allCosts -IdleData $idleResources -SubName $subscription.Name

$csvPaths = Export-AllCSV -AllResources $allResources -VMData $allVMs -StorageData $allStorage -NSGData $allNSGs -VNetData $allVNets -DiskData $allDisks -PublicIPData $allPublicIPs -NICData $allNICs -IdleData $idleResources -Workspaces $workspaces -CostData $allCosts

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  DATABRICKS AUDIT COMPLETE" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Databricks Workspaces:   $($workspaces.Count)" -ForegroundColor White
Write-Host "  Virtual Machines:        $($allVMs.Count)" -ForegroundColor White
Write-Host "  Storage Accounts:        $($allStorage.Count)" -ForegroundColor White
Write-Host "  Managed Disks:           $($allDisks.Count)" -ForegroundColor White
Write-Host "  NSGs:                    $($allNSGs.Count)" -ForegroundColor White
Write-Host "  VNets:                   $($allVNets.Count)" -ForegroundColor White
Write-Host "  Public IPs:              $($allPublicIPs.Count)" -ForegroundColor White
Write-Host "  NICs:                    $($allNICs.Count)" -ForegroundColor White
Write-Host "  TOTAL RESOURCES:         $($allResources.Count)" -ForegroundColor Cyan
Write-Host "  IDLE RESOURCES:          $($idleResources.Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Reports saved to: $ReportPath" -ForegroundColor Cyan
Write-Host ""

Write-Host "Opening HTML report..." -ForegroundColor Yellow
Start-Process $htmlPath

Write-Host "Done" -ForegroundColor Green
