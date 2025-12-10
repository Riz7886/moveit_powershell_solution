#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Manual Datadog Agent Installation - For VMs that failed automated installation
.DESCRIPTION
    Installs Datadog agents on specific VMs using Azure Run Command (no RDP/SSH needed)
.PARAMETER DatadogApiKey
    Your Datadog API key (required)
.PARAMETER VMs
    Array of VMs to install agents on. Format: @{Name="vm-name"; ResourceGroup="rg-name"; OS="Windows"}
.EXAMPLE
    .\Install-Datadog-Manual.ps1 -DatadogApiKey "your-key" -VMs @(@{Name="vm-test"; ResourceGroup="rg-test"; OS="Windows"})
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DatadogApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogSite = "datadoghq.com"
)

# Ensure proper encoding
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MANUAL DATADOG AGENT INSTALLATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================================================
# DEFINE YOUR VMs HERE
# ============================================================================
# Based on your audit report, list VMs that need manual installation
# Format: @{Name="vm-name"; ResourceGroup="resource-group-name"; OS="Windows"/"Linux"}

$vmsToInstall = @(
    # EXAMPLE - Replace with your actual VMs:
    # @{Name="vm-example-windows"; ResourceGroup="rg-example"; OS="Windows"},
    # @{Name="vm-example-linux"; ResourceGroup="rg-example"; OS="Linux"}
    
    # TODO: ADD YOUR VMs BELOW THIS LINE
    # Check your audit report for VMs with:
    # - Status: Running
    # - Agent Status: Not Installed
    # - NOT Databricks VMs (those need different approach)
    
)

# ============================================================================

if ($vmsToInstall.Count -eq 0) {
    Write-Host "`nNO VMs DEFINED!" -ForegroundColor Red
    Write-Host "`nPlease edit this script and add your VMs to the `$vmsToInstall array." -ForegroundColor Yellow
    Write-Host "Format: @{Name=`"vm-name`"; ResourceGroup=`"rg-name`"; OS=`"Windows`"}" -ForegroundColor Yellow
    Write-Host "`nCheck your audit report to see which VMs need agents installed." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nVMs to process: $($vmsToInstall.Count)" -ForegroundColor Green
Write-Host "Datadog Site: $DatadogSite" -ForegroundColor Green

# Confirm before proceeding
Write-Host "`nReady to install Datadog agents on these VMs:" -ForegroundColor Yellow
foreach ($vm in $vmsToInstall) {
    Write-Host "  - $($vm.Name) [$($vm.OS)] in $($vm.ResourceGroup)" -ForegroundColor White
}

$confirm = Read-Host "`nProceed with installation? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Installation cancelled." -ForegroundColor Yellow
    exit 0
}

# Track results
$results = @{
    Successful = 0
    Failed = 0
    Errors = @()
}

# Install on each VM
foreach ($vm in $vmsToInstall) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Processing: $($vm.Name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    try {
        if ($vm.OS -eq "Windows") {
            Write-Host "Installing Datadog agent on Windows VM..." -ForegroundColor Yellow
            
            $script = @"
`$ErrorActionPreference = 'Stop'
try {
    Write-Host 'Downloading Datadog agent...'
    `$url = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
    `$tempPath = Join-Path `$env:TEMP 'datadog-agent.msi'
    
    # Create temp directory if it doesn't exist
    if (-not (Test-Path `$env:TEMP)) {
        New-Item -ItemType Directory -Path `$env:TEMP -Force | Out-Null
    }
    
    Invoke-WebRequest -Uri `$url -OutFile `$tempPath -UseBasicParsing
    Write-Host 'Download complete.'
    
    Write-Host 'Installing Datadog agent...'
    Start-Process msiexec.exe -ArgumentList "/i ```"`$tempPath```" APIKEY=$DatadogApiKey SITE=$DatadogSite /quiet /qn" -Wait -NoNewWindow
    Write-Host 'Installation complete.'
    
    Write-Host 'Starting Datadog service...'
    Start-Sleep -Seconds 5
    Start-Service datadogagent -ErrorAction SilentlyContinue
    Write-Host 'Service started.'
    
    # Verify
    `$service = Get-Service datadogagent -ErrorAction SilentlyContinue
    if (`$service.Status -eq 'Running') {
        Write-Host 'SUCCESS: Datadog agent is running!'
    } else {
        Write-Host 'WARNING: Service exists but may not be running yet. Wait 1-2 minutes.'
    }
} catch {
    Write-Host "ERROR: `$_"
    throw
}
"@
            
            $result = Invoke-AzVMRunCommand `
                -ResourceGroupName $vm.ResourceGroup `
                -VMName $vm.Name `
                -CommandId "RunPowerShellScript" `
                -Script $script `
                -ErrorAction Stop
            
            Write-Host "`n--- Output from $($vm.Name) ---" -ForegroundColor Gray
            Write-Host $result.Value[0].Message -ForegroundColor Gray
            Write-Host "--- End of output ---`n" -ForegroundColor Gray
            
            if ($result.Value[0].Message -match "SUCCESS") {
                Write-Host "✓ Successfully installed on $($vm.Name)" -ForegroundColor Green
                $results.Successful++
            } else {
                Write-Host "⚠ Installation completed but verify manually: $($vm.Name)" -ForegroundColor Yellow
                $results.Successful++
            }
            
        } elseif ($vm.OS -eq "Linux") {
            Write-Host "Installing Datadog agent on Linux VM..." -ForegroundColor Yellow
            
            $script = @"
#!/bin/bash
set -e
echo 'Installing Datadog agent on Linux...'

export DD_API_KEY=$DatadogApiKey
export DD_SITE=$DatadogSite

echo 'Running Datadog installation script...'
DD_API_KEY=`$DD_API_KEY DD_SITE=`$DD_SITE bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"

echo 'Waiting for service to start...'
sleep 5

echo 'Checking agent status...'
if systemctl is-active --quiet datadog-agent; then
    echo 'SUCCESS: Datadog agent is running!'
else
    echo 'WARNING: Service may not be running yet. Wait 1-2 minutes.'
fi
"@
            
            $result = Invoke-AzVMRunCommand `
                -ResourceGroupName $vm.ResourceGroup `
                -VMName $vm.Name `
                -CommandId "RunShellScript" `
                -Script $script `
                -ErrorAction Stop
            
            Write-Host "`n--- Output from $($vm.Name) ---" -ForegroundColor Gray
            Write-Host $result.Value[0].Message -ForegroundColor Gray
            Write-Host "--- End of output ---`n" -ForegroundColor Gray
            
            if ($result.Value[0].Message -match "SUCCESS") {
                Write-Host "✓ Successfully installed on $($vm.Name)" -ForegroundColor Green
                $results.Successful++
            } else {
                Write-Host "⚠ Installation completed but verify manually: $($vm.Name)" -ForegroundColor Yellow
                $results.Successful++
            }
        } else {
            Write-Host "✗ Unknown OS type: $($vm.OS)" -ForegroundColor Red
            $results.Failed++
            $results.Errors += "$($vm.Name): Unknown OS type - $($vm.OS)"
        }
        
    } catch {
        Write-Host "✗ Failed to install on $($vm.Name): $_" -ForegroundColor Red
        $results.Failed++
        $results.Errors += "$($vm.Name): $_"
    }
    
    Start-Sleep -Seconds 2
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "INSTALLATION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total VMs Processed: $($vmsToInstall.Count)" -ForegroundColor White
Write-Host "Successful: $($results.Successful)" -ForegroundColor Green
Write-Host "Failed: $($results.Failed)" -ForegroundColor Red

if ($results.Errors.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    foreach ($error in $results.Errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. Wait 5-10 minutes for agents to connect to Datadog" -ForegroundColor Yellow
Write-Host "2. Login to Datadog → Infrastructure → Host Map" -ForegroundColor Yellow
Write-Host "3. Verify your VMs appear in the list" -ForegroundColor Yellow
Write-Host "4. Run the audit script again to confirm installation" -ForegroundColor Yellow

Write-Host "`n✅ DONE!" -ForegroundColor Green
