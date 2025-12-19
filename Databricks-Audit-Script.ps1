# DATABRICKS COMPREHENSIVE AUDIT SCRIPT
# Lists all resources, costs, idle resources - READ ONLY - NO CHANGES
# Generates HTML and CSV reports

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS COMPREHENSIVE AUDIT REPORT" -ForegroundColor Cyan
Write-Host "  Resources | Costs | Idle Detection | Full Breakdown" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  *** READ ONLY - NO CHANGES WILL BE MADE ***" -ForegroundColor Green
Write-Host ""

# Configuration
$ReportPath = "$env:USERPROFILE\Desktop\Databricks-Audit-Reports"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MonthsBack = 5

# Create report folder
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

# ============================================================
# FUNCTION: Connect to Azure
# ============================================================
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
        Write-Host "ERROR: Could not connect to Azure - $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================
# FUNCTION: Select Subscription
# ============================================================
function Select-AzureSubscription {
    Write-Host ""
    Write-Host "Step 2: Getting subscriptions..." -ForegroundColor Yellow
    
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    
    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    Write-Host ""
    
    $i = 1
    foreach ($sub in $subscriptions) {
        Write-Host "  $i. $($sub.Name)" -ForegroundColor White
        $i++
    }
    
    Write-Host ""
    $selection = Read-Host "Select subscription number (1-$($subscriptions.Count))"
    
    $selectedSub = $subscriptions[$selection - 1]
    Set-AzContext -Subscription $selectedSub.Id | Out-Null
    
    Write-Host "Selected: $($selectedSub.Name)" -ForegroundColor Green
    return $selectedSub
}

# ============================================================
# FUNCTION: Get Databricks Workspaces
# ============================================================
function Get-DatabricksWorkspaces {
    Write-Host ""
    Write-Host "Step 3: Finding Databricks workspaces..." -ForegroundColor Yellow
    
    $workspaces = Get-AzDatabricksWorkspace -ErrorAction SilentlyContinue
    
    if (-not $workspaces -or $workspaces.Count -eq 0) {
        # Try alternative method
        $workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces"
    }
    
    if ($workspaces -and $workspaces.Count -gt 0) {
        Write-Host "Found $($workspaces.Count) Databricks workspace(s)!" -ForegroundColor Green
        
        foreach ($ws in $workspaces) {
            Write-Host "  - $($ws.Name) (RG: $($ws.ResourceGroupName))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "No Databricks workspaces found in this subscription." -ForegroundColor Yellow
    }
    
    return $workspaces
}

# ============================================================
# FUNCTION: Get All Resources in Resource Group
# ============================================================
function Get-ResourceGroupResources {
    param([string]$ResourceGroupName)
    
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    return $resources
}

# ============================================================
# FUNCTION: Get Managed Resource Group Resources
# ============================================================
function Get-ManagedResourceGroupResources {
    param([string]$ManagedResourceGroupName)
    
    try {
        $resources = Get-AzResource -ResourceGroupName $ManagedResourceGroupName -ErrorAction SilentlyContinue
        return $resources
    } catch {
        return $null
    }
}

# ============================================================
# FUNCTION: Get Cost Data
# ============================================================
function Get-CostData {
    param(
        [string]$ResourceGroupName,
        [int]$MonthsBack = 5
    )
    
    $costData = @()
    $endDate = Get-Date
    $startDate = $endDate.AddMonths(-$MonthsBack)
    
    Write-Host "  Getting cost data for last $MonthsBack months..." -ForegroundColor Gray
    
    try {
        # Get consumption usage
        $usage = Get-AzConsumptionUsageDetail -ResourceGroup $ResourceGroupName -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue
        
        if ($usage) {
            # Group by month
            $monthlyData = $usage | Group-Object { $_.UsageStart.ToString("yyyy-MM") } | ForEach-Object {
                [PSCustomObject]@{
                    Month = $_.Name
                    Cost = [math]::Round(($_.Group | Measure-Object -Property PretaxCost -Sum).Sum, 2)
                    Currency = $_.Group[0].Currency
                }
            }
            return $monthlyData
        }
    } catch {
        Write-Host "  Note: Cost data requires Cost Management access" -ForegroundColor Gray
    }
    
    return $null
}

# ============================================================
# FUNCTION: Get VM Details
# ============================================================
function Get-VMDetails {
    param([string]$ResourceGroupName)
    
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $vmDetails = @()
    
    foreach ($vm in $vms) {
        $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
        
        $vmDetails += [PSCustomObject]@{
            Name = $vm.Name
            ResourceGroup = $ResourceGroupName
            Size = $vm.HardwareProfile.VmSize
            Location = $vm.Location
            PowerState = $powerState
            OsType = $vm.StorageProfile.OsDisk.OsType
            IsRunning = $powerState -eq "VM running"
            IsIdle = $powerState -ne "VM running"
        }
    }
    
    return $vmDetails
}

# ============================================================
# FUNCTION: Get Storage Accounts
# ============================================================
function Get-StorageDetails {
    param([string]$ResourceGroupName)
    
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $storageDetails = @()
    
    foreach ($sa in $storageAccounts) {
        $storageDetails += [PSCustomObject]@{
            Name = $sa.StorageAccountName
            ResourceGroup = $ResourceGroupName
            Kind = $sa.Kind
            Sku = $sa.Sku.Name
            Location = $sa.Location
            AccessTier = $sa.AccessTier
            CreatedTime = $sa.CreationTime
        }
    }
    
    return $storageDetails
}

# ============================================================
# FUNCTION: Get NSG Details
# ============================================================
function Get-NSGDetails {
    param([string]$ResourceGroupName)
    
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $nsgDetails = @()
    
    foreach ($nsg in $nsgs) {
        $nsgDetails += [PSCustomObject]@{
            Name = $nsg.Name
            ResourceGroup = $ResourceGroupName
            Location = $nsg.Location
            RuleCount = $nsg.SecurityRules.Count
            DefaultRuleCount = $nsg.DefaultSecurityRules.Count
            AssociatedSubnets = ($nsg.Subnets | ForEach-Object { $_.Id.Split('/')[-1] }) -join ", "
            AssociatedNICs = ($nsg.NetworkInterfaces | ForEach-Object { $_.Id.Split('/')[-1] }) -join ", "
        }
    }
    
    return $nsgDetails
}

# ============================================================
# FUNCTION: Get VNet Details
# ============================================================
function Get-VNetDetails {
    param([string]$ResourceGroupName)
    
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $vnetDetails = @()
    
    foreach ($vnet in $vnets) {
        $vnetDetails += [PSCustomObject]@{
            Name = $vnet.Name
            ResourceGroup = $ResourceGroupName
            Location = $vnet.Location
            AddressSpace = ($vnet.AddressSpace.AddressPrefixes) -join ", "
            SubnetCount = $vnet.Subnets.Count
            Subnets = ($vnet.Subnets | ForEach-Object { "$($_.Name) ($($_.AddressPrefix))" }) -join "; "
        }
    }
    
    return $vnetDetails
}

# ============================================================
# FUNCTION: Get Disk Details
# ============================================================
function Get-DiskDetails {
    param([string]$ResourceGroupName)
    
    $disks = Get-AzDisk -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $diskDetails = @()
    
    foreach ($disk in $disks) {
        $diskDetails += [PSCustomObject]@{
            Name = $disk.Name
            ResourceGroup = $ResourceGroupName
            SizeGB = $disk.DiskSizeGB
            Sku = $disk.Sku.Name
            State = $disk.DiskState
            OsType = $disk.OsType
            AttachedTo = if ($disk.ManagedBy) { $disk.ManagedBy.Split('/')[-1] } else { "Unattached" }
            IsUnattached = [string]::IsNullOrEmpty($disk.ManagedBy)
            TimeCreated = $disk.TimeCreated
        }
    }
    
    return $diskDetails
}

# ============================================================
# FUNCTION: Get Public IP Details
# ============================================================
function Get-PublicIPDetails {
    param([string]$ResourceGroupName)
    
    $publicIPs = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $pipDetails = @()
    
    foreach ($pip in $publicIPs) {
        $pipDetails += [PSCustomObject]@{
            Name = $pip.Name
            ResourceGroup = $ResourceGroupName
            IPAddress = $pip.IpAddress
            AllocationMethod = $pip.PublicIpAllocationMethod
            Sku = $pip.Sku.Name
            AssociatedTo = if ($pip.IpConfiguration) { $pip.IpConfiguration.Id.Split('/')[-3] } else { "Unassociated" }
            IsUnassociated = [string]::IsNullOrEmpty($pip.IpConfiguration)
        }
    }
    
    return $pipDetails
}

# ============================================================
# FUNCTION: Get Network Interface Details
# ============================================================
function Get-NICDetails {
    param([string]$ResourceGroupName)
    
    $nics = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $nicDetails = @()
    
    foreach ($nic in $nics) {
        $nicDetails += [PSCustomObject]@{
            Name = $nic.Name
            ResourceGroup = $ResourceGroupName
            Location = $nic.Location
            PrivateIP = ($nic.IpConfigurations | ForEach-Object { $_.PrivateIpAddress }) -join ", "
            AttachedTo = if ($nic.VirtualMachine) { $nic.VirtualMachine.Id.Split('/')[-1] } else { "Unattached" }
            IsUnattached = [string]::IsNullOrEmpty($nic.VirtualMachine)
        }
    }
    
    return $nicDetails
}

# ============================================================
# FUNCTION: Get Databricks Clusters (via API)
# ============================================================
function Get-DatabricksClusters {
    param($Workspace)
    
    # Note: This would require Databricks API token
    # For now, we'll document this as requiring manual check
    return $null
}

# ============================================================
# FUNCTION: Calculate Estimated Monthly Cost
# ============================================================
function Get-EstimatedMonthlyCost {
    param($AllResources)
    
    $estimatedCosts = @{
        "Microsoft.Compute/virtualMachines" = 150  # Average VM cost
        "Microsoft.Storage/storageAccounts" = 25   # Average storage cost
        "Microsoft.Network/publicIPAddresses" = 5  # Public IP cost
        "Microsoft.Network/networkInterfaces" = 0  # NICs are free
        "Microsoft.Network/networkSecurityGroups" = 0  # NSGs are free
        "Microsoft.Network/virtualNetworks" = 0    # VNets are free (mostly)
        "Microsoft.Compute/disks" = 20             # Average disk cost
        "Microsoft.Databricks/workspaces" = 0      # Workspace itself is free, DBUs charged separately
    }
    
    $totalEstimate = 0
    foreach ($resource in $AllResources) {
        if ($estimatedCosts.ContainsKey($resource.ResourceType)) {
            $totalEstimate += $estimatedCosts[$resource.ResourceType]
        }
    }
    
    return $totalEstimate
}

# ============================================================
# FUNCTION: Generate HTML Report
# ============================================================
function Generate-HTMLReport {
    param(
        $Workspaces,
        $AllResources,
        $VMDetails,
        $StorageDetails,
        $NSGDetails,
        $VNetDetails,
        $DiskDetails,
        $PublicIPDetails,
        $NICDetails,
        $CostData,
        $IdleResources,
        $Subscription
    )
    
    $htmlPath = Join-Path $ReportPath "Databricks-Audit-Report-$Timestamp.html"
    
    # Calculate totals
    $totalVMs = $VMDetails.Count
    $runningVMs = ($VMDetails | Where-Object { $_.IsRunning }).Count
    $stoppedVMs = $totalVMs - $runningVMs
    $totalStorage = $StorageDetails.Count
    $totalDisks = $DiskDetails.Count
    $unattachedDisks = ($DiskDetails | Where-Object { $_.IsUnattached }).Count
    $totalNSGs = $NSGDetails.Count
    $totalVNets = $VNetDetails.Count
    $totalPublicIPs = $PublicIPDetails.Count
    $unassociatedIPs = ($PublicIPDetails | Where-Object { $_.IsUnassociated }).Count
    $totalNICs = $NICDetails.Count
    $unattachedNICs = ($NICDetails | Where-Object { $_.IsUnattached }).Count
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Databricks Audit Report - $($Subscription.Name)</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background: linear-gradient(135deg, #FF3621 0%, #E25A1C 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 20px; }
        .header h1 { margin: 0; font-size: 28px; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .summary-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); text-align: center; }
        .summary-card h3 { margin: 0; color: #666; font-size: 14px; text-transform: uppercase; }
        .summary-card .value { font-size: 36px; font-weight: bold; color: #FF3621; margin: 10px 0; }
        .summary-card .subtitle { color: #999; font-size: 12px; }
        .section { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .section h2 { color: #333; border-bottom: 2px solid #FF3621; padding-bottom: 10px; margin-top: 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th { background: #FF3621; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #eee; }
        tr:hover { background-color: #fff8f6; }
        .status-running { color: #28a745; font-weight: bold; }
        .status-stopped { color: #dc3545; font-weight: bold; }
        .status-warning { color: #ffc107; font-weight: bold; }
        .idle-warning { background-color: #fff3cd; }
        .cost-card { background: linear-gradient(135deg, #28a745 0%, #20c997 100%); color: white; }
        .cost-card .value { color: white; }
        .warning-card { background: linear-gradient(135deg, #ffc107 0%, #fd7e14 100%); color: #333; }
        .warning-card .value { color: #333; }
        .footer { text-align: center; color: #666; margin-top: 20px; padding: 20px; }
        .workspace-info { background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px; }
        .workspace-info h4 { margin: 0 0 10px 0; color: #FF3621; }
        .tag { display: inline-block; background: #e9ecef; padding: 3px 8px; border-radius: 4px; margin: 2px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔶 Databricks Comprehensive Audit Report</h1>
        <p>Subscription: $($Subscription.Name) | Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    
    <div class="summary-grid">
        <div class="summary-card">
            <h3>Databricks Workspaces</h3>
            <div class="value">$($Workspaces.Count)</div>
            <div class="subtitle">Active workspaces</div>
        </div>
        <div class="summary-card">
            <h3>Virtual Machines</h3>
            <div class="value">$totalVMs</div>
            <div class="subtitle">$runningVMs running, $stoppedVMs stopped</div>
        </div>
        <div class="summary-card">
            <h3>Storage Accounts</h3>
            <div class="value">$totalStorage</div>
            <div class="subtitle">DBFS & workspace storage</div>
        </div>
        <div class="summary-card">
            <h3>Managed Disks</h3>
            <div class="value">$totalDisks</div>
            <div class="subtitle">$unattachedDisks unattached</div>
        </div>
        <div class="summary-card warning-card">
            <h3>Idle Resources</h3>
            <div class="value">$($IdleResources.Count)</div>
            <div class="subtitle">Potential cost savings</div>
        </div>
        <div class="summary-card">
            <h3>Total Resources</h3>
            <div class="value">$($AllResources.Count)</div>
            <div class="subtitle">All resource types</div>
        </div>
    </div>
    
    <div class="section">
        <h2>📊 Databricks Workspaces</h2>
"@

    foreach ($ws in $Workspaces) {
        $html += @"
        <div class="workspace-info">
            <h4>$($ws.Name)</h4>
            <p><strong>Resource Group:</strong> $($ws.ResourceGroupName)</p>
            <p><strong>Location:</strong> $($ws.Location)</p>
            <p><strong>Pricing Tier:</strong> $($ws.Sku.Name)</p>
            <p><strong>Managed RG:</strong> $($ws.ManagedResourceGroupId.Split('/')[-1])</p>
            <p><strong>URL:</strong> <a href="https://$($ws.WorkspaceUrl)" target="_blank">$($ws.WorkspaceUrl)</a></p>
        </div>
"@
    }

    $html += @"
    </div>
    
    <div class="section">
        <h2>💻 Virtual Machines</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>Resource Group</th>
                <th>Size</th>
                <th>OS Type</th>
                <th>Power State</th>
                <th>Status</th>
            </tr>
"@

    foreach ($vm in $VMDetails) {
        $statusClass = if ($vm.IsRunning) { "status-running" } else { "status-stopped" }
        $statusText = if ($vm.IsRunning) { "Running" } else { "Stopped (Idle)" }
        $rowClass = if (-not $vm.IsRunning) { "idle-warning" } else { "" }
        
        $html += @"
            <tr class="$rowClass">
                <td>$($vm.Name)</td>
                <td>$($vm.ResourceGroup)</td>
                <td>$($vm.Size)</td>
                <td>$($vm.OsType)</td>
                <td>$($vm.PowerState)</td>
                <td class="$statusClass">$statusText</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>💾 Storage Accounts</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>Resource Group</th>
                <th>Kind</th>
                <th>SKU</th>
                <th>Access Tier</th>
                <th>Location</th>
            </tr>
"@

    foreach ($sa in $StorageDetails) {
        $html += @"
            <tr>
                <td>$($sa.Name)</td>
                <td>$($sa.ResourceGroup)</td>
                <td>$($sa.Kind)</td>
                <td>$($sa.Sku)</td>
                <td>$($sa.AccessTier)</td>
                <td>$($sa.Location)</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>💿 Managed Disks</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>Size (GB)</th>
                <th>SKU</th>
                <th>State</th>
                <th>Attached To</th>
                <th>Status</th>
            </tr>
"@

    foreach ($disk in $DiskDetails) {
        $statusClass = if ($disk.IsUnattached) { "status-warning" } else { "status-running" }
        $statusText = if ($disk.IsUnattached) { "⚠️ Unattached" } else { "✓ Attached" }
        $rowClass = if ($disk.IsUnattached) { "idle-warning" } else { "" }
        
        $html += @"
            <tr class="$rowClass">
                <td>$($disk.Name)</td>
                <td>$($disk.SizeGB)</td>
                <td>$($disk.Sku)</td>
                <td>$($disk.State)</td>
                <td>$($disk.AttachedTo)</td>
                <td class="$statusClass">$statusText</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>🔒 Network Security Groups</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>Resource Group</th>
                <th>Location</th>
                <th>Custom Rules</th>
                <th>Associated Subnets</th>
            </tr>
"@

    foreach ($nsg in $NSGDetails) {
        $html += @"
            <tr>
                <td>$($nsg.Name)</td>
                <td>$($nsg.ResourceGroup)</td>
                <td>$($nsg.Location)</td>
                <td>$($nsg.RuleCount)</td>
                <td>$($nsg.AssociatedSubnets)</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>🌐 Virtual Networks</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>Resource Group</th>
                <th>Address Space</th>
                <th>Subnet Count</th>
                <th>Subnets</th>
            </tr>
"@

    foreach ($vnet in $VNetDetails) {
        $html += @"
            <tr>
                <td>$($vnet.Name)</td>
                <td>$($vnet.ResourceGroup)</td>
                <td>$($vnet.AddressSpace)</td>
                <td>$($vnet.SubnetCount)</td>
                <td>$($vnet.Subnets)</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>🌍 Public IP Addresses</h2>
        <table>
            <tr>
                <th>Name</th>
                <th>IP Address</th>
                <th>Allocation</th>
                <th>SKU</th>
                <th>Associated To</th>
                <th>Status</th>
            </tr>
"@

    foreach ($pip in $PublicIPDetails) {
        $statusClass = if ($pip.IsUnassociated) { "status-warning" } else { "status-running" }
        $statusText = if ($pip.IsUnassociated) { "⚠️ Unassociated" } else { "✓ Associated" }
        $rowClass = if ($pip.IsUnassociated) { "idle-warning" } else { "" }
        
        $html += @"
            <tr class="$rowClass">
                <td>$($pip.Name)</td>
                <td>$($pip.IPAddress)</td>
                <td>$($pip.AllocationMethod)</td>
                <td>$($pip.Sku)</td>
                <td>$($pip.AssociatedTo)</td>
                <td class="$statusClass">$statusText</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>⚠️ Idle/Unused Resources (Potential Cost Savings)</h2>
        <p>These resources are not being actively used and may be incurring unnecessary costs:</p>
        <table>
            <tr>
                <th>Resource Name</th>
                <th>Type</th>
                <th>Resource Group</th>
                <th>Reason</th>
                <th>Recommendation</th>
            </tr>
"@

    foreach ($idle in $IdleResources) {
        $html += @"
            <tr class="idle-warning">
                <td>$($idle.Name)</td>
                <td>$($idle.Type)</td>
                <td>$($idle.ResourceGroup)</td>
                <td>$($idle.Reason)</td>
                <td>$($idle.Recommendation)</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="section">
        <h2>📋 All Resources Summary</h2>
        <table>
            <tr>
                <th>Resource Type</th>
                <th>Count</th>
            </tr>
"@

    $resourceGroups = $AllResources | Group-Object ResourceType | Sort-Object Count -Descending
    foreach ($rg in $resourceGroups) {
        $html += @"
            <tr>
                <td>$($rg.Name)</td>
                <td>$($rg.Count)</td>
            </tr>
"@
    }

    $html += @"
        </table>
    </div>
    
    <div class="footer">
        <p>Generated by Databricks Audit Script | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p>*** READ ONLY REPORT - NO CHANGES WERE MADE ***</p>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    return $htmlPath
}

# ============================================================
# FUNCTION: Export CSV Reports
# ============================================================
function Export-CSVReports {
    param(
        $AllResources,
        $VMDetails,
        $StorageDetails,
        $NSGDetails,
        $VNetDetails,
        $DiskDetails,
        $PublicIPDetails,
        $NICDetails,
        $IdleResources,
        $Workspaces
    )
    
    $csvPaths = @()
    
    # All Resources
    $allResourcesPath = Join-Path $ReportPath "All-Resources-$Timestamp.csv"
    $AllResources | Select-Object Name, ResourceType, ResourceGroupName, Location | Export-Csv -Path $allResourcesPath -NoTypeInformation
    $csvPaths += $allResourcesPath
    
    # VMs
    if ($VMDetails.Count -gt 0) {
        $vmPath = Join-Path $ReportPath "VirtualMachines-$Timestamp.csv"
        $VMDetails | Export-Csv -Path $vmPath -NoTypeInformation
        $csvPaths += $vmPath
    }
    
    # Storage
    if ($StorageDetails.Count -gt 0) {
        $storagePath = Join-Path $ReportPath "StorageAccounts-$Timestamp.csv"
        $StorageDetails | Export-Csv -Path $storagePath -NoTypeInformation
        $csvPaths += $storagePath
    }
    
    # NSGs
    if ($NSGDetails.Count -gt 0) {
        $nsgPath = Join-Path $ReportPath "NetworkSecurityGroups-$Timestamp.csv"
        $NSGDetails | Export-Csv -Path $nsgPath -NoTypeInformation
        $csvPaths += $nsgPath
    }
    
    # VNets
    if ($VNetDetails.Count -gt 0) {
        $vnetPath = Join-Path $ReportPath "VirtualNetworks-$Timestamp.csv"
        $VNetDetails | Export-Csv -Path $vnetPath -NoTypeInformation
        $csvPaths += $vnetPath
    }
    
    # Disks
    if ($DiskDetails.Count -gt 0) {
        $diskPath = Join-Path $ReportPath "ManagedDisks-$Timestamp.csv"
        $DiskDetails | Export-Csv -Path $diskPath -NoTypeInformation
        $csvPaths += $diskPath
    }
    
    # Public IPs
    if ($PublicIPDetails.Count -gt 0) {
        $pipPath = Join-Path $ReportPath "PublicIPs-$Timestamp.csv"
        $PublicIPDetails | Export-Csv -Path $pipPath -NoTypeInformation
        $csvPaths += $pipPath
    }
    
    # NICs
    if ($NICDetails.Count -gt 0) {
        $nicPath = Join-Path $ReportPath "NetworkInterfaces-$Timestamp.csv"
        $NICDetails | Export-Csv -Path $nicPath -NoTypeInformation
        $csvPaths += $nicPath
    }
    
    # Idle Resources
    if ($IdleResources.Count -gt 0) {
        $idlePath = Join-Path $ReportPath "IdleResources-$Timestamp.csv"
        $IdleResources | Export-Csv -Path $idlePath -NoTypeInformation
        $csvPaths += $idlePath
    }
    
    # Workspaces
    if ($Workspaces.Count -gt 0) {
        $wsPath = Join-Path $ReportPath "DatabricksWorkspaces-$Timestamp.csv"
        $Workspaces | Select-Object Name, ResourceGroupName, Location, @{N='PricingTier';E={$_.Sku.Name}}, WorkspaceUrl | Export-Csv -Path $wsPath -NoTypeInformation
        $csvPaths += $wsPath
    }
    
    return $csvPaths
}

# ============================================================
# MAIN SCRIPT
# ============================================================

# Connect to Azure
$connected = Connect-ToAzure
if (-not $connected) {
    Write-Host "Cannot proceed without Azure connection." -ForegroundColor Red
    exit 1
}

# Select subscription
$subscription = Select-AzureSubscription

# Get Databricks workspaces
$workspaces = Get-DatabricksWorkspaces

if (-not $workspaces -or $workspaces.Count -eq 0) {
    Write-Host ""
    Write-Host "No Databricks workspaces found. Exiting." -ForegroundColor Yellow
    exit 0
}

# Initialize collections
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

# Process each workspace
Write-Host ""
Write-Host "Step 4: Analyzing resources..." -ForegroundColor Yellow

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Host "Processing workspace: $($workspace.Name)" -ForegroundColor Cyan
    
    # Get workspace resource group resources
    Write-Host "  Scanning resource group: $($workspace.ResourceGroupName)" -ForegroundColor Gray
    $rgResources = Get-ResourceGroupResources -ResourceGroupName $workspace.ResourceGroupName
    $allResources += $rgResources
    
    # Get managed resource group resources (where VMs, storage, etc. live)
    $managedRGName = $workspace.ManagedResourceGroupId.Split('/')[-1]
    Write-Host "  Scanning managed resource group: $managedRGName" -ForegroundColor Gray
    $managedResources = Get-ManagedResourceGroupResources -ManagedResourceGroupName $managedRGName
    if ($managedResources) {
        $allResources += $managedResources
    }
    
    # Get VMs
    Write-Host "  Getting VM details..." -ForegroundColor Gray
    $vms = Get-VMDetails -ResourceGroupName $managedRGName
    $allVMs += $vms
    
    # Get Storage
    Write-Host "  Getting storage accounts..." -ForegroundColor Gray
    $storage = Get-StorageDetails -ResourceGroupName $managedRGName
    $allStorage += $storage
    $storage2 = Get-StorageDetails -ResourceGroupName $workspace.ResourceGroupName
    $allStorage += $storage2
    
    # Get NSGs
    Write-Host "  Getting NSGs..." -ForegroundColor Gray
    $nsgs = Get-NSGDetails -ResourceGroupName $managedRGName
    $allNSGs += $nsgs
    
    # Get VNets
    Write-Host "  Getting VNets..." -ForegroundColor Gray
    $vnets = Get-VNetDetails -ResourceGroupName $managedRGName
    $allVNets += $vnets
    $vnets2 = Get-VNetDetails -ResourceGroupName $workspace.ResourceGroupName
    $allVNets += $vnets2
    
    # Get Disks
    Write-Host "  Getting managed disks..." -ForegroundColor Gray
    $disks = Get-DiskDetails -ResourceGroupName $managedRGName
    $allDisks += $disks
    
    # Get Public IPs
    Write-Host "  Getting public IPs..." -ForegroundColor Gray
    $pips = Get-PublicIPDetails -ResourceGroupName $managedRGName
    $allPublicIPs += $pips
    
    # Get NICs
    Write-Host "  Getting network interfaces..." -ForegroundColor Gray
    $nics = Get-NICDetails -ResourceGroupName $managedRGName
    $allNICs += $nics
    
    # Get Cost Data
    Write-Host "  Getting cost data (last $MonthsBack months)..." -ForegroundColor Gray
    $costs = Get-CostData -ResourceGroupName $workspace.ResourceGroupName -MonthsBack $MonthsBack
    if ($costs) { $allCosts += $costs }
    $costs2 = Get-CostData -ResourceGroupName $managedRGName -MonthsBack $MonthsBack
    if ($costs2) { $allCosts += $costs2 }
}

# Identify idle resources
Write-Host ""
Write-Host "Step 5: Identifying idle resources..." -ForegroundColor Yellow

# Stopped VMs
foreach ($vm in $allVMs) {
    if ($vm.IsIdle) {
        $idleResources += [PSCustomObject]@{
            Name = $vm.Name
            Type = "Virtual Machine"
            ResourceGroup = $vm.ResourceGroup
            Reason = "VM is stopped/deallocated"
            Recommendation = "Delete if not needed, or start if needed"
        }
    }
}

# Unattached disks
foreach ($disk in $allDisks) {
    if ($disk.IsUnattached) {
        $idleResources += [PSCustomObject]@{
            Name = $disk.Name
            Type = "Managed Disk"
            ResourceGroup = $disk.ResourceGroup
            Reason = "Disk is not attached to any VM"
            Recommendation = "Delete if not needed (check for backups first)"
        }
    }
}

# Unassociated Public IPs
foreach ($pip in $allPublicIPs) {
    if ($pip.IsUnassociated) {
        $idleResources += [PSCustomObject]@{
            Name = $pip.Name
            Type = "Public IP"
            ResourceGroup = $pip.ResourceGroup
            Reason = "Public IP is not associated"
            Recommendation = "Delete if not needed to stop billing"
        }
    }
}

# Unattached NICs
foreach ($nic in $allNICs) {
    if ($nic.IsUnattached) {
        $idleResources += [PSCustomObject]@{
            Name = $nic.Name
            Type = "Network Interface"
            ResourceGroup = $nic.ResourceGroup
            Reason = "NIC is not attached to any VM"
            Recommendation = "Delete if not needed"
        }
    }
}

# Generate reports
Write-Host ""
Write-Host "Step 6: Generating reports..." -ForegroundColor Yellow

$htmlPath = Generate-HTMLReport -Workspaces $workspaces -AllResources $allResources -VMDetails $allVMs -StorageDetails $allStorage -NSGDetails $allNSGs -VNetDetails $allVNets -DiskDetails $allDisks -PublicIPDetails $allPublicIPs -NICDetails $allNICs -CostData $allCosts -IdleResources $idleResources -Subscription $subscription

$csvPaths = Export-CSVReports -AllResources $allResources -VMDetails $allVMs -StorageDetails $allStorage -NSGDetails $allNSGs -VNetDetails $allVNets -DiskDetails $allDisks -PublicIPDetails $allPublicIPs -NICDetails $allNICs -IdleResources $idleResources -Workspaces $workspaces

# Summary
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  DATABRICKS AUDIT COMPLETE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  SUMMARY:" -ForegroundColor Cyan
Write-Host "  -----------------------------------------" -ForegroundColor Gray
Write-Host "  Databricks Workspaces:    $($workspaces.Count)" -ForegroundColor White
Write-Host "  Virtual Machines:         $($allVMs.Count) ($($($allVMs | Where-Object {$_.IsRunning}).Count) running)" -ForegroundColor White
Write-Host "  Storage Accounts:         $($allStorage.Count)" -ForegroundColor White
Write-Host "  Managed Disks:            $($allDisks.Count) ($($($allDisks | Where-Object {$_.IsUnattached}).Count) unattached)" -ForegroundColor White
Write-Host "  Network Security Groups:  $($allNSGs.Count)" -ForegroundColor White
Write-Host "  Virtual Networks:         $($allVNets.Count)" -ForegroundColor White
Write-Host "  Public IP Addresses:      $($allPublicIPs.Count)" -ForegroundColor White
Write-Host "  Network Interfaces:       $($allNICs.Count)" -ForegroundColor White
Write-Host "  -----------------------------------------" -ForegroundColor Gray
Write-Host "  TOTAL RESOURCES:          $($allResources.Count)" -ForegroundColor Cyan
Write-Host "  IDLE RESOURCES:           $($idleResources.Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  REPORTS SAVED TO:" -ForegroundColor Cyan
Write-Host "  $ReportPath" -ForegroundColor White
Write-Host ""
Write-Host "  HTML Report: Databricks-Audit-Report-$Timestamp.html" -ForegroundColor White
Write-Host ""
Write-Host "  CSV Reports:" -ForegroundColor White
foreach ($csv in $csvPaths) {
    Write-Host "    - $(Split-Path $csv -Leaf)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  *** READ ONLY - NO CHANGES WERE MADE ***" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

# Open HTML report
Write-Host "Opening HTML report..." -ForegroundColor Yellow
Start-Process $htmlPath

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
