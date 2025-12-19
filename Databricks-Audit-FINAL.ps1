# DATABRICKS AUDIT SCRIPT - FIXED VERSION
# READ ONLY - NO CHANGES

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS COMPREHENSIVE AUDIT REPORT" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$ReportPath = "$env:USERPROFILE\Desktop\Databricks-Audit-Reports"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    Write-Host "Created report folder: $ReportPath" -ForegroundColor Gray
}

# STEP 1: CONNECT TO AZURE
Write-Host ""
Write-Host "Step 1: Connecting to Azure..." -ForegroundColor Yellow

$context = $null
try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
} catch { }

if (-not $context -or -not $context.Account) {
    Write-Host "Not connected. Opening Azure login..." -ForegroundColor Yellow
    try {
        Connect-AzAccount -ErrorAction Stop
        $context = Get-AzContext
    } catch {
        Write-Host "ERROR: Failed to connect to Azure. Please run Connect-AzAccount manually first." -ForegroundColor Red
        Write-Host "Then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green

# STEP 2: GET SUBSCRIPTIONS
Write-Host ""
Write-Host "Step 2: Getting subscriptions..." -ForegroundColor Yellow

$subsList = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" }

if (-not $subsList) {
    Write-Host "ERROR: No subscriptions found!" -ForegroundColor Red
    exit 1
}

$subs = @($subsList)
Write-Host "Found $($subs.Count) subscription(s)" -ForegroundColor Green
Write-Host ""
Write-Host "Available Subscriptions:" -ForegroundColor Cyan

for ($i = 0; $i -lt $subs.Count; $i++) {
    $num = $i + 1
    Write-Host "  $num. $($subs[$i].Name) ($($subs[$i].Id))" -ForegroundColor White
}

Write-Host ""
$inputVal = Read-Host "Enter subscription number (1-$($subs.Count))"

$selIndex = 0
try {
    $selIndex = [int]$inputVal - 1
} catch {
    Write-Host "Invalid input!" -ForegroundColor Red
    exit 1
}

if ($selIndex -lt 0 -or $selIndex -ge $subs.Count) {
    Write-Host "Invalid selection!" -ForegroundColor Red
    exit 1
}

$selectedSub = $subs[$selIndex]
Write-Host ""
Write-Host "Setting subscription: $($selectedSub.Name)..." -ForegroundColor Yellow

try {
    Set-AzContext -SubscriptionId $selectedSub.Id -ErrorAction Stop | Out-Null
    Write-Host "Subscription set successfully!" -ForegroundColor Green
} catch {
    Write-Host "ERROR setting subscription: $_" -ForegroundColor Red
    exit 1
}

# STEP 3: FIND DATABRICKS WORKSPACES
Write-Host ""
Write-Host "Step 3: Finding Databricks workspaces..." -ForegroundColor Yellow

$workspacesList = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces" -ErrorAction SilentlyContinue
$workspaces = @($workspacesList)

if ($workspaces.Count -eq 0) {
    Write-Host "No Databricks workspaces found in this subscription!" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($workspaces.Count) workspace(s):" -ForegroundColor Green
foreach ($ws in $workspaces) {
    Write-Host "  - $($ws.Name) (RG: $($ws.ResourceGroupName))" -ForegroundColor Cyan
}

# STEP 4: COLLECT ALL RESOURCE GROUPS
Write-Host ""
Write-Host "Step 4: Collecting resource groups..." -ForegroundColor Yellow

$rgList = @()
foreach ($ws in $workspaces) {
    if ($rgList -notcontains $ws.ResourceGroupName) {
        $rgList += $ws.ResourceGroupName
    }
    
    try {
        $wsDetails = Get-AzDatabricksWorkspace -ResourceGroupName $ws.ResourceGroupName -Name $ws.Name -ErrorAction SilentlyContinue
        if ($wsDetails -and $wsDetails.ManagedResourceGroupId) {
            $managedRG = $wsDetails.ManagedResourceGroupId.Split("/")[-1]
            if ($rgList -notcontains $managedRG) {
                $rgList += $managedRG
            }
        }
    } catch { }
}

Write-Host "Resource groups to scan: $($rgList -join ', ')" -ForegroundColor Gray

# STEP 5: SCAN ALL RESOURCES
Write-Host ""
Write-Host "Step 5: Scanning resources..." -ForegroundColor Yellow

$allResources = @()
$allVMs = @()
$allStorage = @()
$allNSGs = @()
$allVNets = @()
$allDisks = @()
$allPIPs = @()
$allNICs = @()
$idleResources = @()

foreach ($rg in $rgList) {
    Write-Host "  Scanning: $rg" -ForegroundColor Gray
    
    # All resources
    $res = Get-AzResource -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($res) { $allResources += @($res) }
    
    # VMs
    $vms = Get-AzVM -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($vm in $vms) {
        $vmStatus = Get-AzVM -ResourceGroupName $rg -Name $vm.Name -Status -ErrorAction SilentlyContinue
        $power = "Unknown"
        if ($vmStatus -and $vmStatus.Statuses) {
            $ps = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }
            if ($ps) { $power = $ps.DisplayStatus }
        }
        $running = ($power -eq "VM running")
        $allVMs += [PSCustomObject]@{
            Name = $vm.Name
            ResourceGroup = $rg
            Size = $vm.HardwareProfile.VmSize
            Location = $vm.Location
            PowerState = $power
            OsType = $vm.StorageProfile.OsDisk.OsType
            IsRunning = $running
            IsIdle = (-not $running)
        }
    }
    
    # Storage
    $stor = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($s in $stor) {
        $allStorage += [PSCustomObject]@{
            Name = $s.StorageAccountName
            ResourceGroup = $rg
            Kind = $s.Kind
            Sku = $s.Sku.Name
            Location = $s.Location
            AccessTier = $s.AccessTier
        }
    }
    
    # NSGs
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($n in $nsgs) {
        $subs = ""
        if ($n.Subnets) { $subs = ($n.Subnets.Id | ForEach-Object { $_.Split("/")[-1] }) -join "," }
        $allNSGs += [PSCustomObject]@{
            Name = $n.Name
            ResourceGroup = $rg
            Location = $n.Location
            RuleCount = $n.SecurityRules.Count
            Subnets = $subs
        }
    }
    
    # VNets
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($v in $vnets) {
        $addr = ""
        if ($v.AddressSpace -and $v.AddressSpace.AddressPrefixes) { $addr = $v.AddressSpace.AddressPrefixes -join "," }
        $subn = ""
        if ($v.Subnets) { $subn = ($v.Subnets.Name) -join "," }
        $allVNets += [PSCustomObject]@{
            Name = $v.Name
            ResourceGroup = $rg
            Location = $v.Location
            AddressSpace = $addr
            SubnetCount = $v.Subnets.Count
            Subnets = $subn
        }
    }
    
    # Disks
    $disks = Get-AzDisk -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($d in $disks) {
        $att = "Unattached"
        $unatt = $true
        if ($d.ManagedBy) { $att = $d.ManagedBy.Split("/")[-1]; $unatt = $false }
        $allDisks += [PSCustomObject]@{
            Name = $d.Name
            ResourceGroup = $rg
            SizeGB = $d.DiskSizeGB
            Sku = $d.Sku.Name
            State = $d.DiskState
            AttachedTo = $att
            IsUnattached = $unatt
        }
    }
    
    # Public IPs
    $pips = Get-AzPublicIpAddress -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($p in $pips) {
        $assoc = "Unassociated"
        $unassoc = $true
        if ($p.IpConfiguration) { $assoc = $p.IpConfiguration.Id.Split("/")[-3]; $unassoc = $false }
        $allPIPs += [PSCustomObject]@{
            Name = $p.Name
            ResourceGroup = $rg
            IPAddress = $p.IpAddress
            Allocation = $p.PublicIpAllocationMethod
            AssociatedTo = $assoc
            IsUnassociated = $unassoc
        }
    }
    
    # NICs
    $nics = Get-AzNetworkInterface -ResourceGroupName $rg -ErrorAction SilentlyContinue
    foreach ($nic in $nics) {
        $att = "Unattached"
        $unatt = $true
        if ($nic.VirtualMachine) { $att = $nic.VirtualMachine.Id.Split("/")[-1]; $unatt = $false }
        $priv = ""
        if ($nic.IpConfigurations) { $priv = ($nic.IpConfigurations.PrivateIpAddress) -join "," }
        $allNICs += [PSCustomObject]@{
            Name = $nic.Name
            ResourceGroup = $rg
            Location = $nic.Location
            PrivateIP = $priv
            AttachedTo = $att
            IsUnattached = $unatt
        }
    }
}

# STEP 6: IDENTIFY IDLE RESOURCES
Write-Host ""
Write-Host "Step 6: Identifying idle resources..." -ForegroundColor Yellow

foreach ($vm in $allVMs) {
    if ($vm.IsIdle) {
        $idleResources += [PSCustomObject]@{ Name = $vm.Name; Type = "VM"; ResourceGroup = $vm.ResourceGroup; Reason = "Stopped"; Action = "Delete if not needed" }
    }
}
foreach ($d in $allDisks) {
    if ($d.IsUnattached) {
        $idleResources += [PSCustomObject]@{ Name = $d.Name; Type = "Disk"; ResourceGroup = $d.ResourceGroup; Reason = "Unattached"; Action = "Delete if not needed" }
    }
}
foreach ($p in $allPIPs) {
    if ($p.IsUnassociated) {
        $idleResources += [PSCustomObject]@{ Name = $p.Name; Type = "PublicIP"; ResourceGroup = $p.ResourceGroup; Reason = "Unassociated"; Action = "Delete to save cost" }
    }
}
foreach ($n in $allNICs) {
    if ($n.IsUnattached) {
        $idleResources += [PSCustomObject]@{ Name = $n.Name; Type = "NIC"; ResourceGroup = $n.ResourceGroup; Reason = "Unattached"; Action = "Delete if not needed" }
    }
}

Write-Host "Found $($idleResources.Count) idle resources" -ForegroundColor Yellow

# STEP 7: GENERATE REPORTS
Write-Host ""
Write-Host "Step 7: Generating reports..." -ForegroundColor Yellow

$totalVMs = $allVMs.Count
$runningVMs = @($allVMs | Where-Object { $_.IsRunning }).Count
$stoppedVMs = $totalVMs - $runningVMs
$totalStorage = $allStorage.Count
$totalDisks = $allDisks.Count
$unattDisks = @($allDisks | Where-Object { $_.IsUnattached }).Count
$totalNSGs = $allNSGs.Count
$totalVNets = $allVNets.Count
$totalPIPs = $allPIPs.Count
$totalNICs = $allNICs.Count
$totalIdle = $idleResources.Count
$totalRes = $allResources.Count
$totalWS = $workspaces.Count
$subName = $selectedSub.Name
$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# HTML REPORT
$htmlFile = Join-Path $ReportPath "Databricks-Report-$Timestamp.html"

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("<!DOCTYPE html><html><head><title>Databricks Audit</title>")
[void]$sb.Append("<style>")
[void]$sb.Append("body{font-family:Segoe UI,Arial;margin:20px;background:#f5f5f5}")
[void]$sb.Append(".hdr{background:linear-gradient(135deg,#FF3621,#E25A1C);color:white;padding:30px;border-radius:10px;margin-bottom:20px}")
[void]$sb.Append(".hdr h1{margin:0}.hdr p{margin:10px 0 0 0}")
[void]$sb.Append(".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:15px;margin-bottom:20px}")
[void]$sb.Append(".card{background:white;padding:15px;border-radius:10px;box-shadow:0 2px 5px rgba(0,0,0,0.1);text-align:center}")
[void]$sb.Append(".card h3{margin:0;color:#666;font-size:11px;text-transform:uppercase}")
[void]$sb.Append(".card .num{font-size:28px;font-weight:bold;color:#FF3621;margin:8px 0}")
[void]$sb.Append(".card .sub{color:#999;font-size:10px}")
[void]$sb.Append(".section{background:white;padding:20px;border-radius:10px;box-shadow:0 2px 5px rgba(0,0,0,0.1);margin-bottom:20px}")
[void]$sb.Append(".section h2{color:#333;border-bottom:2px solid #FF3621;padding-bottom:10px;margin-top:0;font-size:18px}")
[void]$sb.Append("table{width:100%;border-collapse:collapse;margin-top:10px;font-size:12px}")
[void]$sb.Append("th{background:#FF3621;color:white;padding:8px;text-align:left}")
[void]$sb.Append("td{padding:6px;border-bottom:1px solid #eee}")
[void]$sb.Append("tr:hover{background:#fff8f6}")
[void]$sb.Append(".ok{color:#28a745;font-weight:bold}.bad{color:#dc3545;font-weight:bold}.warn{color:#ffc107;font-weight:bold}")
[void]$sb.Append(".idle{background:#fff3cd}")
[void]$sb.Append(".wcard{background:linear-gradient(135deg,#ffc107,#fd7e14)}.wcard .num,.wcard h3{color:#333}")
[void]$sb.Append(".footer{text-align:center;color:#666;margin-top:20px;padding:20px}")
[void]$sb.Append(".ws{background:#f8f9fa;padding:12px;border-radius:8px;margin-bottom:10px;border-left:4px solid #FF3621}")
[void]$sb.Append(".ws h4{margin:0 0 5px 0;color:#FF3621;font-size:14px}")
[void]$sb.Append("</style></head><body>")

[void]$sb.Append("<div class='hdr'><h1>Databricks Audit Report</h1><p>Subscription: $subName | Generated: $reportDate</p></div>")

[void]$sb.Append("<div class='grid'>")
[void]$sb.Append("<div class='card'><h3>Workspaces</h3><div class='num'>$totalWS</div><div class='sub'>Databricks</div></div>")
[void]$sb.Append("<div class='card'><h3>VMs</h3><div class='num'>$totalVMs</div><div class='sub'>$runningVMs running</div></div>")
[void]$sb.Append("<div class='card'><h3>Storage</h3><div class='num'>$totalStorage</div><div class='sub'>Accounts</div></div>")
[void]$sb.Append("<div class='card'><h3>Disks</h3><div class='num'>$totalDisks</div><div class='sub'>$unattDisks unattached</div></div>")
[void]$sb.Append("<div class='card'><h3>NSGs</h3><div class='num'>$totalNSGs</div><div class='sub'>Security</div></div>")
[void]$sb.Append("<div class='card'><h3>VNets</h3><div class='num'>$totalVNets</div><div class='sub'>Networks</div></div>")
[void]$sb.Append("<div class='card wcard'><h3>Idle</h3><div class='num'>$totalIdle</div><div class='sub'>Savings</div></div>")
[void]$sb.Append("<div class='card'><h3>Total</h3><div class='num'>$totalRes</div><div class='sub'>Resources</div></div>")
[void]$sb.Append("</div>")

# Workspaces
[void]$sb.Append("<div class='section'><h2>Databricks Workspaces ($totalWS)</h2>")
foreach ($ws in $workspaces) {
    [void]$sb.Append("<div class='ws'><h4>$($ws.Name)</h4><p>RG: $($ws.ResourceGroupName) | Location: $($ws.Location)</p></div>")
}
[void]$sb.Append("</div>")

# VMs
if ($allVMs.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Virtual Machines ($totalVMs)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>RG</th><th>Size</th><th>OS</th><th>State</th><th>Status</th></tr>")
    foreach ($vm in $allVMs) {
        $cls = "ok"; $stat = "Running"; $row = ""
        if (-not $vm.IsRunning) { $cls = "bad"; $stat = "Stopped"; $row = "idle" }
        [void]$sb.Append("<tr class='$row'><td>$($vm.Name)</td><td>$($vm.ResourceGroup)</td><td>$($vm.Size)</td><td>$($vm.OsType)</td><td>$($vm.PowerState)</td><td class='$cls'>$stat</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# Storage
if ($allStorage.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Storage Accounts ($totalStorage)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>RG</th><th>Kind</th><th>SKU</th><th>Tier</th><th>Location</th></tr>")
    foreach ($s in $allStorage) {
        [void]$sb.Append("<tr><td>$($s.Name)</td><td>$($s.ResourceGroup)</td><td>$($s.Kind)</td><td>$($s.Sku)</td><td>$($s.AccessTier)</td><td>$($s.Location)</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# Disks
if ($allDisks.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Managed Disks ($totalDisks)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>Size</th><th>SKU</th><th>State</th><th>Attached</th><th>Status</th></tr>")
    foreach ($d in $allDisks) {
        $cls = "ok"; $stat = "Attached"; $row = ""
        if ($d.IsUnattached) { $cls = "warn"; $stat = "Unattached"; $row = "idle" }
        [void]$sb.Append("<tr class='$row'><td>$($d.Name)</td><td>$($d.SizeGB)GB</td><td>$($d.Sku)</td><td>$($d.State)</td><td>$($d.AttachedTo)</td><td class='$cls'>$stat</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# NSGs
if ($allNSGs.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>NSGs ($totalNSGs)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>RG</th><th>Location</th><th>Rules</th><th>Subnets</th></tr>")
    foreach ($n in $allNSGs) {
        [void]$sb.Append("<tr><td>$($n.Name)</td><td>$($n.ResourceGroup)</td><td>$($n.Location)</td><td>$($n.RuleCount)</td><td>$($n.Subnets)</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# VNets
if ($allVNets.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Virtual Networks ($totalVNets)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>RG</th><th>Address Space</th><th>Subnets</th></tr>")
    foreach ($v in $allVNets) {
        [void]$sb.Append("<tr><td>$($v.Name)</td><td>$($v.ResourceGroup)</td><td>$($v.AddressSpace)</td><td>$($v.Subnets)</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# Public IPs
if ($allPIPs.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Public IPs ($totalPIPs)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>IP</th><th>Allocation</th><th>Associated</th><th>Status</th></tr>")
    foreach ($p in $allPIPs) {
        $cls = "ok"; $stat = "OK"; $row = ""
        if ($p.IsUnassociated) { $cls = "warn"; $stat = "Unassociated"; $row = "idle" }
        [void]$sb.Append("<tr class='$row'><td>$($p.Name)</td><td>$($p.IPAddress)</td><td>$($p.Allocation)</td><td>$($p.AssociatedTo)</td><td class='$cls'>$stat</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# NICs
if ($allNICs.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Network Interfaces ($totalNICs)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>RG</th><th>Private IP</th><th>Attached</th><th>Status</th></tr>")
    foreach ($n in $allNICs) {
        $cls = "ok"; $stat = "OK"; $row = ""
        if ($n.IsUnattached) { $cls = "warn"; $stat = "Unattached"; $row = "idle" }
        [void]$sb.Append("<tr class='$row'><td>$($n.Name)</td><td>$($n.ResourceGroup)</td><td>$($n.PrivateIP)</td><td>$($n.AttachedTo)</td><td class='$cls'>$stat</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# Idle Resources
if ($idleResources.Count -gt 0) {
    [void]$sb.Append("<div class='section'><h2>Idle Resources - Potential Savings ($totalIdle)</h2>")
    [void]$sb.Append("<table><tr><th>Name</th><th>Type</th><th>RG</th><th>Reason</th><th>Action</th></tr>")
    foreach ($i in $idleResources) {
        [void]$sb.Append("<tr class='idle'><td>$($i.Name)</td><td>$($i.Type)</td><td>$($i.ResourceGroup)</td><td>$($i.Reason)</td><td>$($i.Action)</td></tr>")
    }
    [void]$sb.Append("</table></div>")
}

# Resource Summary
[void]$sb.Append("<div class='section'><h2>All Resources by Type</h2>")
[void]$sb.Append("<table><tr><th>Type</th><th>Count</th></tr>")
$grouped = $allResources | Group-Object ResourceType | Sort-Object Count -Descending
foreach ($g in $grouped) {
    [void]$sb.Append("<tr><td>$($g.Name)</td><td>$($g.Count)</td></tr>")
}
[void]$sb.Append("</table></div>")

[void]$sb.Append("<div class='footer'><p>Databricks Audit | $reportDate | READ ONLY</p></div>")
[void]$sb.Append("</body></html>")

$sb.ToString() | Out-File -FilePath $htmlFile -Encoding UTF8
Write-Host "HTML: $htmlFile" -ForegroundColor Cyan

# CSV FILES
$csv1 = Join-Path $ReportPath "All-Resources-$Timestamp.csv"
$allResources | Select-Object Name, ResourceType, ResourceGroupName, Location | Export-Csv -Path $csv1 -NoTypeInformation

if ($allVMs.Count -gt 0) {
    $csv2 = Join-Path $ReportPath "VMs-$Timestamp.csv"
    $allVMs | Export-Csv -Path $csv2 -NoTypeInformation
}

if ($allStorage.Count -gt 0) {
    $csv3 = Join-Path $ReportPath "Storage-$Timestamp.csv"
    $allStorage | Export-Csv -Path $csv3 -NoTypeInformation
}

if ($allDisks.Count -gt 0) {
    $csv4 = Join-Path $ReportPath "Disks-$Timestamp.csv"
    $allDisks | Export-Csv -Path $csv4 -NoTypeInformation
}

if ($allNSGs.Count -gt 0) {
    $csv5 = Join-Path $ReportPath "NSGs-$Timestamp.csv"
    $allNSGs | Export-Csv -Path $csv5 -NoTypeInformation
}

if ($allVNets.Count -gt 0) {
    $csv6 = Join-Path $ReportPath "VNets-$Timestamp.csv"
    $allVNets | Export-Csv -Path $csv6 -NoTypeInformation
}

if ($idleResources.Count -gt 0) {
    $csv7 = Join-Path $ReportPath "IdleResources-$Timestamp.csv"
    $idleResources | Export-Csv -Path $csv7 -NoTypeInformation
}

$csv8 = Join-Path $ReportPath "Workspaces-$Timestamp.csv"
$workspaces | Select-Object Name, ResourceGroupName, Location | Export-Csv -Path $csv8 -NoTypeInformation

Write-Host "CSVs saved to: $ReportPath" -ForegroundColor Cyan

# SUMMARY
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Workspaces:  $totalWS" -ForegroundColor White
Write-Host "  VMs:         $totalVMs ($runningVMs running, $stoppedVMs stopped)" -ForegroundColor White
Write-Host "  Storage:     $totalStorage" -ForegroundColor White
Write-Host "  Disks:       $totalDisks ($unattDisks unattached)" -ForegroundColor White
Write-Host "  NSGs:        $totalNSGs" -ForegroundColor White
Write-Host "  VNets:       $totalVNets" -ForegroundColor White
Write-Host "  PIPs:        $totalPIPs" -ForegroundColor White
Write-Host "  NICs:        $totalNICs" -ForegroundColor White
Write-Host "  TOTAL:       $totalRes" -ForegroundColor Cyan
Write-Host "  IDLE:        $totalIdle" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Reports: $ReportPath" -ForegroundColor Cyan
Write-Host ""

Write-Host "Opening report..." -ForegroundColor Yellow
Start-Process $htmlFile

Write-Host "Done!" -ForegroundColor Green
