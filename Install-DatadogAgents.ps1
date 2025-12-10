#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bulk Install Datadog Agents on Azure VMs
.DESCRIPTION
    Installs Datadog monitoring agents on all running Azure VMs that don't have them.
.PARAMETER DatadogApiKey
    Your Datadog API key (required)
.PARAMETER DatadogSite
    Datadog site (default: datadoghq.com)
.PARAMETER DryRun
    Test mode - shows what would be installed without actually installing
.PARAMETER SubscriptionFilter
    Optional: Only process specific subscription name(s)
.EXAMPLE
    .\Install-DatadogAgents.ps1 -DatadogApiKey "your-api-key-here"
.EXAMPLE
    .\Install-DatadogAgents.ps1 -DatadogApiKey "your-api-key-here" -DryRun
.EXAMPLE
    .\Install-DatadogAgents.ps1 -DatadogApiKey "your-api-key-here" -SubscriptionFilter "Azure subscription 1"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DatadogApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogSite = "datadoghq.com",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [string[]]$SubscriptionFilter
)

# Ensure proper encoding
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$logFile = Join-Path $downloadsPath "Datadog-Agent-Install-Log-$timestamp.txt"

Write-Host "Installation log will be saved to: $logFile" -ForegroundColor Yellow

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

function Install-DatadogAgentOnVM {
    param(
        [string]$VMName,
        [string]$ResourceGroup,
        [string]$OS,
        [bool]$DryRunMode
    )
    
    try {
        if ($DryRunMode) {
            Write-Log "DRY RUN: Would install Datadog agent on $OS VM: $VMName" "INFO"
            return $true
        }
        
        Write-Log "Installing Datadog agent on $OS VM: $VMName" "INFO"
        
        if ($OS -eq "Windows") {
            # Windows installation
            $settings = @{
                "api_key" = $DatadogApiKey
                "site" = $DatadogSite
            }
            
            $result = Set-AzVMExtension `
                -ResourceGroupName $ResourceGroup `
                -VMName $VMName `
                -Name "DatadogWindowsAgent" `
                -Publisher "Datadog.Agent" `
                -ExtensionType "DatadogWindowsAgent" `
                -TypeHandlerVersion "6.0" `
                -Settings $settings `
                -ErrorAction Stop
            
            if ($result.IsSuccessStatusCode) {
                Write-Log "Successfully installed Datadog agent on Windows VM: $VMName" "SUCCESS"
                return $true
            } else {
                Write-Log "Failed to install on Windows VM: $VMName - Status: $($result.StatusCode)" "ERROR"
                return $false
            }
        }
        else {
            # Linux installation
            $settings = @{
                "api_key" = $DatadogApiKey
                "site" = $DatadogSite
            }
            
            $result = Set-AzVMExtension `
                -ResourceGroupName $ResourceGroup `
                -VMName $VMName `
                -Name "DatadogLinuxAgent" `
                -Publisher "Datadog.Agent" `
                -ExtensionType "DatadogLinuxAgent" `
                -TypeHandlerVersion "6.0" `
                -Settings $settings `
                -ErrorAction Stop
            
            if ($result.IsSuccessStatusCode) {
                Write-Log "Successfully installed Datadog agent on Linux VM: $VMName" "SUCCESS"
                return $true
            } else {
                Write-Log "Failed to install on Linux VM: $VMName - Status: $($result.StatusCode)" "ERROR"
                return $false
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        # Check for specific error types
        if ($errorMsg -like "*403*" -or $errorMsg -like "*Forbidden*") {
            Write-Log "AUTHORIZATION DENIED for $VMName - Check RBAC permissions or system deny assignments" "ERROR"
        }
        elseif ($errorMsg -like "*deny assignment*") {
            Write-Log "SYSTEM DENY ASSIGNMENT blocks $VMName - This VM is managed and cannot have extensions" "ERROR"
        }
        elseif ($errorMsg -like "*timeout*" -or $errorMsg -like "*Long running operation failed*") {
            Write-Log "TIMEOUT installing on $VMName - VM may not be properly provisioned or network issue" "ERROR"
        }
        else {
            Write-Log "Exception installing agent on $VMName`: $errorMsg" "ERROR"
        }
        return $false
    }
}

# Main execution
Write-Log "========================================" "INFO"
Write-Log "Datadog Agent Bulk Installation Script" "INFO"
Write-Log "========================================" "INFO"

if ($DryRun) {
    Write-Log "RUNNING IN DRY-RUN MODE - No changes will be made" "WARN"
}

# Get subscriptions
try {
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
    
    if ($SubscriptionFilter) {
        $subscriptions = $subscriptions | Where-Object { $SubscriptionFilter -contains $_.Name }
        Write-Log "Filtered to $($subscriptions.Count) subscription(s)" "INFO"
    }
    
    Write-Log "Found $($subscriptions.Count) subscription(s) to process" "INFO"
} catch {
    Write-Log "Error getting subscriptions. Make sure you're logged in with Connect-AzAccount" "ERROR"
    exit 1
}

# Track results
$results = @{
    TotalProcessed = 0
    SuccessfulInstalls = 0
    FailedInstalls = 0
    AlreadyInstalled = 0
    Skipped = 0
}

# Process each subscription
foreach ($sub in $subscriptions) {
    Write-Log "Processing subscription: $($sub.Name)" "INFO"
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    # Get all running VMs
    $vms = Get-AzVM -Status | Where-Object { 
        $_.PowerState -eq "VM running" 
    }
    
    Write-Log "Found $($vms.Count) running VMs in subscription: $($sub.Name)" "INFO"
    
    foreach ($vm in $vms) {
        $results.TotalProcessed++
        
        # Get full VM details
        try {
            $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
        } catch {
            Write-Log "Failed to get details for: $($vm.Name) - $_" "ERROR"
            $results.Skipped++
            continue
        }
        
        # SKIP DATABRICKS MANAGED VMs - They have system deny assignments
        if ($vmDetails.ResourceGroupName -like "*DATABRICKS*" -or $vmDetails.Name -like "*databricks*") {
            Write-Log "SKIPPING Databricks-managed VM: $($vm.Name) (Cannot install extensions on Databricks VMs)" "WARN"
            $results.Skipped++
            continue
        }
        
        # Check if agent is already installed
        $hasDatadogAgent = $false
        if ($vmDetails.Extensions) {
            $hasDatadogAgent = $vmDetails.Extensions | Where-Object { 
                $_.Publisher -eq "Datadog.Agent" -or 
                $_.VirtualMachineExtensionType -like "*Datadog*"
            }
        }
        
        if ($hasDatadogAgent) {
            Write-Log "Datadog agent already installed on: $($vm.Name)" "INFO"
            $results.AlreadyInstalled++
            continue
        }
        
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
        
        if ($osType -eq "Unknown") {
            Write-Log "Cannot determine OS type for: $($vm.Name) - Try installing manually" "WARN"
            $results.Skipped++
            continue
        }
        
        # Install agent
        $installSuccess = Install-DatadogAgentOnVM `
            -VMName $vm.Name `
            -ResourceGroup $vm.ResourceGroupName `
            -OS $osType `
            -DryRunMode $DryRun
        
        if ($installSuccess) {
            $results.SuccessfulInstalls++
        } else {
            $results.FailedInstalls++
        }
        
        # Small delay to avoid API throttling
        Start-Sleep -Seconds 2
    }
}

# Summary report
Write-Log "`n========================================" "INFO"
Write-Log "Installation Summary" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Total VMs Processed: $($results.TotalProcessed)" "INFO"
Write-Log "Successful Installs: $($results.SuccessfulInstalls)" "SUCCESS"
Write-Log "Failed Installs: $($results.FailedInstalls)" "ERROR"
Write-Log "Already Installed: $($results.AlreadyInstalled)" "INFO"
Write-Log "Skipped: $($results.Skipped)" "WARN"
Write-Log "`nLog file saved to: $logFile" "INFO"

if ($DryRun) {
    Write-Log "`nThis was a DRY RUN. Run without -DryRun to actually install agents." "WARN"
}

# Generate summary report
$summaryHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Datadog Agent Installation Summary</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #f5f7fa;
            padding: 40px 20px;
        }
        .container {
            max-width: 800px;
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
            font-size: 28px;
            margin-bottom: 10px;
        }
        .content {
            padding: 30px;
        }
        .stat-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .stat-card {
            padding: 20px;
            border-radius: 8px;
            color: white;
            text-align: center;
        }
        .stat-card.blue { background: #3b82f6; }
        .stat-card.green { background: #10b981; }
        .stat-card.red { background: #ef4444; }
        .stat-card.gray { background: #6b7280; }
        .stat-card.yellow { background: #f59e0b; }
        .stat-number {
            font-size: 36px;
            font-weight: 700;
            margin-bottom: 5px;
        }
        .stat-label {
            font-size: 12px;
            opacity: 0.95;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Datadog Agent Installation Summary</h1>
            <div>Completed: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</div>
        </div>
        <div class="content">
            <div class="stat-grid">
                <div class="stat-card blue">
                    <div class="stat-number">$($results.TotalProcessed)</div>
                    <div class="stat-label">Total Processed</div>
                </div>
                <div class="stat-card green">
                    <div class="stat-number">$($results.SuccessfulInstalls)</div>
                    <div class="stat-label">Successful</div>
                </div>
                <div class="stat-card red">
                    <div class="stat-number">$($results.FailedInstalls)</div>
                    <div class="stat-label">Failed</div>
                </div>
                <div class="stat-card gray">
                    <div class="stat-number">$($results.AlreadyInstalled)</div>
                    <div class="stat-label">Already Installed</div>
                </div>
                <div class="stat-card yellow">
                    <div class="stat-number">$($results.Skipped)</div>
                    <div class="stat-label">Skipped</div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"@

$summaryPath = Join-Path $downloadsPath "Datadog-Install-Summary-$timestamp.html"
[System.IO.File]::WriteAllText($summaryPath, $summaryHtml, [System.Text.UTF8Encoding]::new($false))
Write-Log "Summary report saved to: $summaryPath" "INFO"

# Open the summary report
try {
    Start-Process $summaryPath
    Write-Log "Summary report opened in browser" "INFO"
} catch {
    Write-Log "Could not auto-open browser. Please open manually: $summaryPath" "WARN"
}
