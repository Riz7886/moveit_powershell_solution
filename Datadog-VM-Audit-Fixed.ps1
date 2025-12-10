#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Datadog Agent Audit Report Generator - Fixed Version
.DESCRIPTION
    Scans Azure subscriptions for VMs and checks Datadog agent installation status.
    Generates a clean HTML report without encoding issues.
.NOTES
    Author: Fixed Script
    Date: December 2025
#>

# Ensure proper encoding
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$reportPath = Join-Path $downloadsPath "Datadog-VM-Audit-$timestamp.html"
$csvPath = Join-Path $downloadsPath "Datadog-VMs-$timestamp.csv"

Write-Host "Starting Datadog Agent Audit..." -ForegroundColor Cyan
Write-Host "Report will be saved to: $reportPath" -ForegroundColor Yellow

# Get all subscriptions
try {
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    Write-Host "Found $($subscriptions.Count) active subscriptions" -ForegroundColor Green
} catch {
    Write-Host "Error getting subscriptions. Make sure you're logged in with Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# Initialize counters
$allVMs = @()
$totalVMs = 0
$vmsWithAgent = 0
$vmsWithoutAgent = 0
$runningVMs = 0
$stoppedVMs = 0
$windowsVMs = 0
$linuxVMs = 0

# Scan all subscriptions
foreach ($sub in $subscriptions) {
    Write-Host "Scanning subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $vms = Get-AzVM -Status
    
    foreach ($vm in $vms) {
        $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
        
        # Get power state
        $powerState = ($vm.PowerState -split " ")[1]
        $isRunning = $powerState -eq "running"
        
        # Determine OS type - Try multiple methods
        $osType = "Unknown"
        
        # Method 1: From StorageProfile
        if ($vmDetails.StorageProfile.OsDisk.OsType) { 
            $osType = $vmDetails.StorageProfile.OsDisk.OsType
        }
        # Method 2: From VM status
        elseif ($vm.OsName) {
            if ($vm.OsName -like "*Windows*") {
                $osType = "Windows"
            } elseif ($vm.OsName -like "*Linux*") {
                $osType = "Linux"
            }
        }
        # Method 3: From image reference
        elseif ($vmDetails.StorageProfile.ImageReference.Offer) {
            $offer = $vmDetails.StorageProfile.ImageReference.Offer
            if ($offer -like "*Windows*") {
                $osType = "Windows"
            } elseif ($offer -like "*Linux*" -or $offer -like "*Ubuntu*" -or $offer -like "*RHEL*" -or $offer -like "*CentOS*") {
                $osType = "Linux"
            }
        }
        
        # Check for Datadog agent extension
        $hasAgent = $false
        $agentStatus = "Not Installed"
        
        # Check if this is a Databricks-managed VM (cannot install extensions)
        $isDatabricksVM = $vmDetails.ResourceGroupName -like "*DATABRICKS*" -or $vmDetails.Name -like "*databricks*"
        
        if ($isDatabricksVM) {
            $agentStatus = "Cannot Install (Databricks)"
        }
        elseif ($vmDetails.Extensions) {
            $datadogExt = $vmDetails.Extensions | Where-Object { 
                $_.Publisher -eq "Datadog.Agent" -or $_.VirtualMachineExtensionType -like "*Datadog*"
            }
            if ($datadogExt) {
                $hasAgent = $true
                $agentStatus = "Installed"
                $vmsWithAgent++
            } else {
                $vmsWithoutAgent++
            }
        } else {
            if (-not $isDatabricksVM) {
                $vmsWithoutAgent++
            }
        }
        
        # Update counters
        $totalVMs++
        if ($isRunning) { $runningVMs++ } else { $stoppedVMs++ }
        if ($osType -eq "Windows") { $windowsVMs++ } else { $linuxVMs++ }
        
        # Store VM details
        $allVMs += [PSCustomObject]@{
            VMName = $vm.Name
            Subscription = $sub.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            OS = $osType
            PowerState = $powerState
            Status = if ($isRunning) { "Running" } else { "Stopped" }
            HasAgent = $hasAgent
            AgentStatus = $agentStatus
        }
    }
}

Write-Host "`nAudit complete. Generating report..." -ForegroundColor Cyan

# Generate HTML Report
$htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Datadog Agent Audit Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f7fa;
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
        }
        
        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
            font-weight: 600;
        }
        
        .metadata {
            font-size: 14px;
            opacity: 0.9;
        }
        
        .content {
            padding: 30px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat-card {
            padding: 20px;
            border-radius: 8px;
            color: white;
            position: relative;
            overflow: hidden;
        }
        
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            right: 0;
            bottom: 0;
            left: 0;
            background: linear-gradient(135deg, transparent 0%, rgba(255,255,255,0.1) 100%);
        }
        
        .stat-card.blue { background: #3b82f6; }
        .stat-card.green { background: #10b981; }
        .stat-card.pink { background: #ec4899; }
        .stat-card.purple { background: #8b5cf6; }
        .stat-card.gray { background: #6b7280; }
        .stat-card.cyan { background: #06b6d4; }
        
        .stat-number {
            font-size: 48px;
            font-weight: 700;
            margin-bottom: 8px;
            position: relative;
        }
        
        .stat-label {
            font-size: 14px;
            opacity: 0.95;
            font-weight: 500;
            position: relative;
        }
        
        .alert-box {
            background: #fef3c7;
            border-left: 4px solid #f59e0b;
            padding: 20px;
            margin-bottom: 30px;
            border-radius: 4px;
        }
        
        .alert-box strong {
            color: #92400e;
            font-size: 16px;
            display: block;
            margin-bottom: 8px;
        }
        
        .alert-box p {
            color: #78350f;
            font-size: 14px;
        }
        
        .section {
            margin-bottom: 40px;
        }
        
        .section-title {
            font-size: 24px;
            font-weight: 600;
            color: #1f2937;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e5e7eb;
        }
        
        .subscription-group {
            margin-bottom: 30px;
        }
        
        .subscription-header {
            background: #f9fafb;
            padding: 15px 20px;
            border-radius: 6px;
            margin-bottom: 15px;
            border-left: 4px solid #667eea;
        }
        
        .subscription-header h3 {
            font-size: 18px;
            color: #1f2937;
            margin-bottom: 5px;
        }
        
        .subscription-stats {
            font-size: 14px;
            color: #6b7280;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            font-size: 14px;
        }
        
        thead {
            background: #f9fafb;
        }
        
        th {
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #374151;
            border-bottom: 2px solid #e5e7eb;
        }
        
        td {
            padding: 12px;
            border-bottom: 1px solid #e5e7eb;
            color: #4b5563;
        }
        
        tr:hover {
            background: #f9fafb;
        }
        
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 500;
        }
        
        .badge.running { background: #d1fae5; color: #065f46; }
        .badge.stopped { background: #fee2e2; color: #991b1b; }
        .badge.not-installed { background: #fecaca; color: #991b1b; }
        .badge.installed { background: #d1fae5; color: #065f46; }
        .badge.unknown { background: #fef3c7; color: #92400e; }
        .badge.windows { background: #dbeafe; color: #1e40af; }
        .badge.linux { background: #fce7f3; color: #9f1239; }
        .badge.databricks { background: #e0e7ff; color: #3730a3; font-style: italic; }
        
        .footer {
            background: #f9fafb;
            padding: 20px 30px;
            text-align: center;
            color: #6b7280;
            font-size: 13px;
            border-top: 1px solid #e5e7eb;
        }
        
        @media print {
            body { background: white; padding: 0; }
            .container { box-shadow: none; }
            .alert-box { page-break-inside: avoid; }
            table { page-break-inside: auto; }
            tr { page-break-inside: avoid; page-break-after: auto; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Datadog Agent Audit Report</h1>
            <div class="metadata">
                <div>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</div>
                <div>Subscriptions Scanned: $($subscriptions.Count)</div>
            </div>
        </div>
        
        <div class="content">
            <div class="stats-grid">
                <div class="stat-card blue">
                    <div class="stat-number">$totalVMs</div>
                    <div class="stat-label">Total VMs</div>
                </div>
                <div class="stat-card green">
                    <div class="stat-number">$vmsWithAgent</div>
                    <div class="stat-label">VMs with Agent</div>
                </div>
                <div class="stat-card pink">
                    <div class="stat-number">$vmsWithoutAgent</div>
                    <div class="stat-label">VMs without Agent</div>
                </div>
                <div class="stat-card purple">
                    <div class="stat-number">$runningVMs</div>
                    <div class="stat-label">Running VMs</div>
                </div>
                <div class="stat-card gray">
                    <div class="stat-number">$stoppedVMs</div>
                    <div class="stat-label">Stopped VMs</div>
                </div>
                <div class="stat-card cyan">
                    <div class="stat-number">$windowsVMs</div>
                    <div class="stat-label">Windows VMs</div>
                </div>
            </div>
"@

# Add alert if there are VMs without agents
if ($vmsWithoutAgent -gt 0) {
    $runningWithoutAgent = ($allVMs | Where-Object { $_.Status -eq "Running" -and -not $_.HasAgent }).Count
    $htmlReport += @"
            <div class="alert-box">
                <strong>ACTION REQUIRED</strong>
                <p>$vmsWithoutAgent VMs do not have Datadog agents installed and need attention ($runningWithoutAgent are currently running).</p>
            </div>
"@
}

# Group VMs by subscription
$vmsBySubscription = $allVMs | Group-Object Subscription

$htmlReport += @"
            <div class="section">
                <h2 class="section-title">VMs Missing Agents (Running)</h2>
"@

foreach ($subGroup in $vmsBySubscription) {
    $runningWithoutAgent = $subGroup.Group | Where-Object { $_.Status -eq "Running" -and -not $_.HasAgent }
    
    if ($runningWithoutAgent.Count -gt 0) {
        $htmlReport += @"
                <div class="subscription-group">
                    <div class="subscription-header">
                        <h3>$($subGroup.Name)</h3>
                        <div class="subscription-stats">
                            Total VMs: $($subGroup.Group.Count) | Running: $($subGroup.Group | Where-Object { $_.Status -eq "Running" } | Measure-Object | Select-Object -ExpandProperty Count) | With Agent: $($subGroup.Group | Where-Object { $_.HasAgent } | Measure-Object | Select-Object -ExpandProperty Count)
                        </div>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>VM Name</th>
                                <th>Resource Group</th>
                                <th>Location</th>
                                <th>OS</th>
                                <th>Status</th>
                                <th>Agent Status</th>
                            </tr>
                        </thead>
                        <tbody>
"@
        foreach ($vm in $runningWithoutAgent) {
            # Determine agent badge class
            if ($vm.AgentStatus -like "*Databricks*") {
                $agentBadge = "databricks"
            } else {
                $agentBadge = "not-installed"
            }
            
            $htmlReport += @"
                            <tr>
                                <td><strong>$($vm.VMName)</strong></td>
                                <td>$($vm.ResourceGroup)</td>
                                <td>$($vm.Location)</td>
                                <td><span class="badge $($vm.OS.ToLower())">$($vm.OS)</span></td>
                                <td><span class="badge running">$($vm.Status)</span></td>
                                <td><span class="badge $agentBadge">$($vm.AgentStatus)</span></td>
                            </tr>
"@
        }
        $htmlReport += @"
                        </tbody>
                    </table>
                </div>
"@
    }
}

$htmlReport += @"
            </div>
"@

# Add stopped VMs section
$stoppedWithoutAgent = $allVMs | Where-Object { $_.Status -ne "Running" -and -not $_.HasAgent }
if ($stoppedWithoutAgent.Count -gt 0) {
    $htmlReport += @"
            <div class="section">
                <h2 class="section-title">Stopped VMs (Cannot Install Agents)</h2>
                <p style="margin-bottom: 20px; color: #6b7280;">These VMs are currently stopped or deallocated. Start them before installing agents.</p>
                <table>
                    <thead>
                        <tr>
                            <th>VM Name</th>
                            <th>Subscription</th>
                            <th>Resource Group</th>
                            <th>Location</th>
                            <th>OS</th>
                            <th>Power State</th>
                        </tr>
                    </thead>
                    <tbody>
"@
    foreach ($vm in $stoppedWithoutAgent) {
        $htmlReport += @"
                        <tr>
                            <td><strong>$($vm.VMName)</strong></td>
                            <td>$($vm.Subscription)</td>
                            <td>$($vm.ResourceGroup)</td>
                            <td>$($vm.Location)</td>
                            <td><span class="badge $($vm.OS.ToLower())">$($vm.OS)</span></td>
                            <td><span class="badge stopped">$($vm.PowerState)</span></td>
                        </tr>
"@
    }
    $htmlReport += @"
                    </tbody>
                </table>
            </div>
"@
}

# Add all VMs section
$htmlReport += @"
            <div class="section">
                <h2 class="section-title">All VMs by Subscription</h2>
"@

foreach ($subGroup in $vmsBySubscription) {
    $htmlReport += @"
                <div class="subscription-group">
                    <div class="subscription-header">
                        <h3>$($subGroup.Name)</h3>
                        <div class="subscription-stats">
                            Total VMs: $($subGroup.Group.Count) | Running: $($subGroup.Group | Where-Object { $_.Status -eq "Running" } | Measure-Object | Select-Object -ExpandProperty Count) | With Agent: $($subGroup.Group | Where-Object { $_.HasAgent } | Measure-Object | Select-Object -ExpandProperty Count)
                        </div>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>VM Name</th>
                                <th>Resource Group</th>
                                <th>Location</th>
                                <th>OS</th>
                                <th>Status</th>
                                <th>Agent Status</th>
                            </tr>
                        </thead>
                        <tbody>
"@
    foreach ($vm in $subGroup.Group | Sort-Object VMName) {
        $statusBadge = if ($vm.Status -eq "Running") { "running" } else { "stopped" }
        
        # Determine agent badge class
        if ($vm.AgentStatus -like "*Databricks*") {
            $agentBadge = "databricks"
        } elseif ($vm.HasAgent) {
            $agentBadge = "installed"
        } else {
            $agentBadge = "not-installed"
        }
        
        $htmlReport += @"
                            <tr>
                                <td><strong>$($vm.VMName)</strong></td>
                                <td>$($vm.ResourceGroup)</td>
                                <td>$($vm.Location)</td>
                                <td><span class="badge $($vm.OS.ToLower())">$($vm.OS)</span></td>
                                <td><span class="badge $statusBadge">$($vm.Status)</span></td>
                                <td><span class="badge $agentBadge">$($vm.AgentStatus)</span></td>
                            </tr>
"@
    }
    $htmlReport += @"
                        </tbody>
                    </table>
                </div>
"@
}

$htmlReport += @"
            </div>
        </div>
        
        <div class="footer">
            Datadog Agent Audit Report | Generated on $(Get-Date -Format "MMMM dd, yyyy") | For assistance, run the agent installation script
        </div>
    </div>
</body>
</html>
"@

# Write report to file with proper encoding
try {
    [System.IO.File]::WriteAllText($reportPath, $htmlReport, [System.Text.UTF8Encoding]::new($false))
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "SUCCESS! Report generated!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nReport saved to: $reportPath" -ForegroundColor Cyan
} catch {
    Write-Host "`nERROR writing HTML file: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  Total VMs: $totalVMs"
Write-Host "  VMs with Agent: $vmsWithAgent" -ForegroundColor Green
Write-Host "  VMs without Agent: $vmsWithoutAgent" -ForegroundColor Red
Write-Host "  Running VMs: $runningVMs"
Write-Host "  Stopped VMs: $stoppedVMs"

# Export VM list to CSV for bulk operations
try {
    $allVMs | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nVM list exported to: $csvPath" -ForegroundColor Green
} catch {
    Write-Host "`nWarning: Could not export CSV: $_" -ForegroundColor Yellow
}

# Open the HTML report in default browser
Write-Host "`nOpening report in browser..." -ForegroundColor Cyan
try {
    Start-Process $reportPath
    Write-Host "Report opened successfully!" -ForegroundColor Green
} catch {
    Write-Host "Could not auto-open browser. Please open manually: $reportPath" -ForegroundColor Yellow
}
