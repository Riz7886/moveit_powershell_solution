param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_APP_KEY = "PASTE_YOUR_APP_KEY_HERE",
    [string]$DD_SITE = "us3"
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATADOG AGENT AUDIT REPORT" -ForegroundColor White
Write-Host "  All Subscriptions" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DD_APP_KEY -eq "PASTE_YOUR_APP_KEY_HERE") {
    Write-Host "ERROR: Replace PASTE_YOUR_APP_KEY_HERE with your Application Key" -ForegroundColor Red
    exit 1
}

Write-Host "Step 1: Getting list of hosts from Datadog..." -ForegroundColor Cyan

$datadogUrl = "https://api.$DD_SITE.datadoghq.com/api/v1/hosts"
$headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
}

try {
    $ddHosts = Invoke-RestMethod -Uri $datadogUrl -Method Get -Headers $headers -ErrorAction Stop
    $connectedHosts = @{}
    foreach ($host in $ddHosts.host_list) {
        $hostname = $host.name.ToLower()
        $connectedHosts[$hostname] = $true
    }
    Write-Host "Found $($ddHosts.host_list.Count) hosts reporting to Datadog" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not get Datadog host list" -ForegroundColor Yellow
    Write-Host "Will mark all VMs as 'Unknown' agent status" -ForegroundColor Yellow
    $connectedHosts = @{}
}

Write-Host ""
Write-Host "Step 2: Scanning all Azure subscriptions..." -ForegroundColor Cyan
Write-Host ""

$allSubs = Get-AzSubscription
Write-Host "Found $($allSubs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$allVMs = @()
$totalVMs = 0
$runningVMs = 0
$stoppedVMs = 0
$withAgent = 0
$withoutAgent = 0
$unknownAgent = 0
$windowsCount = 0
$linuxCount = 0

foreach ($sub in $allSubs) {
    Write-Host "Scanning: $($sub.Name)" -ForegroundColor White
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        
        $vms = Get-AzVM -Status -ErrorAction Stop
        
        if (-not $vms -or $vms.Count -eq 0) {
            Write-Host "  No VMs found" -ForegroundColor Gray
            Write-Host ""
            continue
        }
        
        Write-Host "  Found $($vms.Count) VMs" -ForegroundColor Green
        $totalVMs += $vms.Count
        
        foreach ($vm in $vms) {
            $vmName = $vm.Name
            $vmNameLower = $vmName.ToLower()
            $rg = $vm.ResourceGroupName
            $location = $vm.Location
            $powerState = $vm.PowerState
            $os = $vm.StorageProfile.OsDisk.OsType
            
            # Count OS types
            if ($os -eq "Windows") {
                $windowsCount++
            } else {
                $linuxCount++
            }
            
            # Check if running
            if ($powerState -eq "VM running") {
                $runningVMs++
                $status = "Running"
            } else {
                $stoppedVMs++
                $status = "Stopped"
            }
            
            # Check if agent installed
            if ($connectedHosts.ContainsKey($vmNameLower)) {
                $agentStatus = "Installed"
                $withAgent++
            } elseif ($powerState -ne "VM running") {
                $agentStatus = "Unknown"
                $unknownAgent++
            } else {
                $agentStatus = "Not Installed"
                $withoutAgent++
            }
            
            # Add to report
            $vmInfo = [PSCustomObject]@{
                Subscription = $sub.Name
                VMName = $vmName
                ResourceGroup = $rg
                Location = $location
                OS = $os
                Status = $status
                PowerState = $powerState
                AgentStatus = $agentStatus
            }
            
            $allVMs += $vmInfo
        }
        
        Write-Host ""
        
    } catch {
        Write-Host "  ERROR: Failed to scan subscription" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host ""
    }
}

Write-Host ""
Write-Host "Step 3: Generating HTML Report..." -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dateFormatted = Get-Date -Format "MMMM dd, yyyy HH:mm:ss"

# Build HTML Report
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Datadog Agent Audit Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #632ca6;
            border-bottom: 3px solid #632ca6;
            padding-bottom: 10px;
        }
        h2 {
            color: #444;
            margin-top: 30px;
            border-left: 4px solid #632ca6;
            padding-left: 15px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .stat-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .stat-box.success {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }
        .stat-box.warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }
        .stat-box.info {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
        }
        .stat-number {
            font-size: 36px;
            font-weight: bold;
            margin: 10px 0;
        }
        .stat-label {
            font-size: 14px;
            opacity: 0.9;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        th {
            background-color: #632ca6;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f9f9f9;
        }
        .status-running {
            color: #28a745;
            font-weight: bold;
        }
        .status-stopped {
            color: #dc3545;
            font-weight: bold;
        }
        .agent-installed {
            background-color: #d4edda;
            color: #155724;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        .agent-not-installed {
            background-color: #f8d7da;
            color: #721c24;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        .agent-unknown {
            background-color: #fff3cd;
            color: #856404;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
        .os-windows {
            color: #0078d4;
        }
        .os-linux {
            color: #f0ad4e;
        }
        .alert-box {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
        }
        .success-box {
            background-color: #d4edda;
            border-left: 4px solid #28a745;
            padding: 15px;
            margin: 20px 0;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 2px solid #ddd;
            text-align: center;
            color: #666;
            font-size: 12px;
        }
        .subscription-section {
            margin: 30px 0;
            padding: 20px;
            background-color: #f8f9fa;
            border-radius: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Datadog Agent Audit Report</h1>
        <p><strong>Generated:</strong> $dateFormatted</p>
        <p><strong>Subscriptions Scanned:</strong> $($allSubs.Count)</p>
        
        <h2>📊 Overall Statistics</h2>
        <div class="summary">
            <div class="stat-box info">
                <div class="stat-label">Total VMs</div>
                <div class="stat-number">$totalVMs</div>
            </div>
            <div class="stat-box success">
                <div class="stat-label">VMs with Agent</div>
                <div class="stat-number">$withAgent</div>
            </div>
            <div class="stat-box warning">
                <div class="stat-label">VMs without Agent</div>
                <div class="stat-number">$withoutAgent</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">Running VMs</div>
                <div class="stat-number">$runningVMs</div>
            </div>
            <div class="stat-box">
                <div class="stat-label">Stopped VMs</div>
                <div class="stat-number">$stoppedVMs</div>
            </div>
            <div class="stat-box info">
                <div class="stat-label">Windows VMs</div>
                <div class="stat-number">$windowsCount</div>
            </div>
            <div class="stat-box info">
                <div class="stat-label">Linux VMs</div>
                <div class="stat-number">$linuxCount</div>
            </div>
        </div>
"@

# Add success or alert message
if ($withoutAgent -gt 0) {
    $htmlContent += @"
        <div class="alert-box">
            <h3>⚠️ Action Required</h3>
            <p><strong>$withoutAgent running VMs</strong> do not have Datadog agents installed and need attention.</p>
        </div>
"@
} else {
    $htmlContent += @"
        <div class="success-box">
            <h3>✅ All Running VMs Have Agents</h3>
            <p>Congratulations! All running VMs are reporting to Datadog.</p>
        </div>
"@
}

# VMs Missing Agents Section
$missingAgents = $allVMs | Where-Object { $_.AgentStatus -eq "Not Installed" -and $_.Status -eq "Running" }
if ($missingAgents.Count -gt 0) {
    $htmlContent += @"
        <h2>🚨 VMs Missing Agents (Running)</h2>
        <table>
            <tr>
                <th>VM Name</th>
                <th>Subscription</th>
                <th>Resource Group</th>
                <th>Location</th>
                <th>OS</th>
                <th>Status</th>
            </tr>
"@
    foreach ($vm in $missingAgents) {
        $osClass = if ($vm.OS -eq "Windows") { "os-windows" } else { "os-linux" }
        $htmlContent += @"
            <tr>
                <td><strong>$($vm.VMName)</strong></td>
                <td>$($vm.Subscription)</td>
                <td>$($vm.ResourceGroup)</td>
                <td>$($vm.Location)</td>
                <td class="$osClass">$($vm.OS)</td>
                <td class="status-running">$($vm.Status)</td>
            </tr>
"@
    }
    $htmlContent += "</table>"
}

# Stopped VMs Section
$stoppedList = $allVMs | Where-Object { $_.Status -eq "Stopped" }
if ($stoppedList.Count -gt 0) {
    $htmlContent += @"
        <h2>⏸️ Stopped VMs (Cannot Install Agents)</h2>
        <p>These VMs are currently stopped or deallocated. Start them before installing agents.</p>
        <table>
            <tr>
                <th>VM Name</th>
                <th>Subscription</th>
                <th>Resource Group</th>
                <th>Location</th>
                <th>OS</th>
                <th>Power State</th>
            </tr>
"@
    foreach ($vm in $stoppedList) {
        $osClass = if ($vm.OS -eq "Windows") { "os-windows" } else { "os-linux" }
        $htmlContent += @"
            <tr>
                <td><strong>$($vm.VMName)</strong></td>
                <td>$($vm.Subscription)</td>
                <td>$($vm.ResourceGroup)</td>
                <td>$($vm.Location)</td>
                <td class="$osClass">$($vm.OS)</td>
                <td class="status-stopped">$($vm.PowerState)</td>
            </tr>
"@
    }
    $htmlContent += "</table>"
}

# All VMs by Subscription
$htmlContent += @"
        <h2>📋 All VMs by Subscription</h2>
"@

foreach ($sub in $allSubs) {
    $subVMs = $allVMs | Where-Object { $_.Subscription -eq $sub.Name }
    
    if ($subVMs.Count -eq 0) {
        continue
    }
    
    $subRunning = ($subVMs | Where-Object { $_.Status -eq "Running" }).Count
    $subWithAgent = ($subVMs | Where-Object { $_.AgentStatus -eq "Installed" }).Count
    
    $htmlContent += @"
        <div class="subscription-section">
            <h3>$($sub.Name)</h3>
            <p><strong>Total VMs:</strong> $($subVMs.Count) | <strong>Running:</strong> $subRunning | <strong>With Agent:</strong> $subWithAgent</p>
            <table>
                <tr>
                    <th>VM Name</th>
                    <th>Resource Group</th>
                    <th>Location</th>
                    <th>OS</th>
                    <th>Status</th>
                    <th>Agent Status</th>
                </tr>
"@
    
    foreach ($vm in $subVMs) {
        $statusClass = if ($vm.Status -eq "Running") { "status-running" } else { "status-stopped" }
        $osClass = if ($vm.OS -eq "Windows") { "os-windows" } else { "os-linux" }
        
        $agentClass = switch ($vm.AgentStatus) {
            "Installed" { "agent-installed" }
            "Not Installed" { "agent-not-installed" }
            default { "agent-unknown" }
        }
        
        $htmlContent += @"
                <tr>
                    <td><strong>$($vm.VMName)</strong></td>
                    <td>$($vm.ResourceGroup)</td>
                    <td>$($vm.Location)</td>
                    <td class="$osClass">$($vm.OS)</td>
                    <td class="$statusClass">$($vm.Status)</td>
                    <td><span class="$agentClass">$($vm.AgentStatus)</span></td>
                </tr>
"@
    }
    
    $htmlContent += "</table></div>"
}

$htmlContent += @"
        <div class="footer">
            <p>Datadog Agent Audit Report | Generated on $dateFormatted</p>
            <p>For assistance, run: Datadog-COMPLETE-WITH-SECURITY.ps1 or Fix-Linux-Agent-Install.ps1</p>
        </div>
    </div>
</body>
</html>
"@

# Save HTML report
$htmlPath = "Datadog-VM-Audit-$timestamp.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

# Also save CSV for Excel
$csvPath = "Datadog-VM-Audit-$timestamp.csv"
$allVMs | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "========================================" -ForegroundColor Green
Write-Host "REPORTS GENERATED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "HTML Report: $htmlPath" -ForegroundColor Cyan
Write-Host "CSV Report: $csvPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Opening HTML report in browser..." -ForegroundColor Yellow
Start-Process $htmlPath

Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Yellow
Write-Host "  Total VMs: $totalVMs" -ForegroundColor White
Write-Host "  Running: $runningVMs | Stopped: $stoppedVMs" -ForegroundColor White
Write-Host "  With Agent: $withAgent | Without Agent: $withoutAgent" -ForegroundColor White
Write-Host ""

if ($withoutAgent -gt 0) {
    Write-Host "⚠️  ACTION REQUIRED: $withoutAgent running VMs need agents" -ForegroundColor Red
} else {
    Write-Host "✅ SUCCESS: All running VMs have agents!" -ForegroundColor Green
}

Write-Host ""
