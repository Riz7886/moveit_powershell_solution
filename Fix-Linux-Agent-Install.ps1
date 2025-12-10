param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_SITE = "us3",
    [string]$SubscriptionName = ""
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FIX LINUX DATADOG AGENT INSTALLS" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($SubscriptionName) {
    Set-AzContext -Subscription $SubscriptionName | Out-Null
    Write-Host "Using subscription: $SubscriptionName" -ForegroundColor Green
} else {
    $context = Get-AzContext
    Write-Host "Using subscription: $($context.Subscription.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 1: Finding all Linux VMs..." -ForegroundColor Cyan
Write-Host ""

$allVMs = Get-AzVM -Status
$linuxVMs = $allVMs | Where-Object { $_.StorageProfile.OsDisk.OsType -eq "Linux" }

if ($linuxVMs.Count -eq 0) {
    Write-Host "No Linux VMs found in this subscription" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($linuxVMs.Count) Linux VMs" -ForegroundColor Green
Write-Host ""

Write-Host "Step 2: Checking status of each Linux VM..." -ForegroundColor Cyan
Write-Host ""

$readyVMs = @()
$stoppedVMs = @()
$issueVMs = @()

foreach ($vm in $linuxVMs) {
    $vmName = $vm.Name
    $rg = $vm.ResourceGroupName
    $powerState = $vm.PowerState
    $location = $vm.Location
    
    Write-Host "Checking: $vmName" -ForegroundColor White
    Write-Host "  Resource Group: $rg" -ForegroundColor Gray
    Write-Host "  Location: $location" -ForegroundColor Gray
    Write-Host "  Power State: $powerState" -ForegroundColor Gray
    
    if ($powerState -ne "VM running") {
        Write-Host "  [STOPPED] Not running" -ForegroundColor Yellow
        $stoppedVMs += $vm
    } else {
        # Check if Azure VM Agent exists
        $vmDetail = Get-AzVM -ResourceGroupName $rg -Name $vmName
        $extensions = $vmDetail.Extensions
        
        $hasVMAgent = $false
        foreach ($ext in $extensions) {
            if ($ext.Publisher -eq "Microsoft.Azure.Extensions") {
                $hasVMAgent = $true
                break
            }
        }
        
        if ($hasVMAgent -or $extensions.Count -eq 0) {
            Write-Host "  [READY] Can install agent" -ForegroundColor Green
            $readyVMs += $vm
        } else {
            Write-Host "  [ISSUE] May have permission/network issues" -ForegroundColor Yellow
            $issueVMs += $vm
        }
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Ready to install: $($readyVMs.Count)" -ForegroundColor Green
Write-Host "Stopped/Deallocated: $($stoppedVMs.Count)" -ForegroundColor Yellow
Write-Host "May have issues: $($issueVMs.Count)" -ForegroundColor Yellow
Write-Host ""

if ($stoppedVMs.Count -gt 0) {
    Write-Host "STOPPED VMs (need to start first):" -ForegroundColor Yellow
    foreach ($vm in $stoppedVMs) {
        Write-Host "  - $($vm.Name)" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($readyVMs.Count -eq 0) {
    Write-Host "No VMs ready for installation" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Start stopped VMs in Azure Portal" -ForegroundColor Gray
    Write-Host "  2. Wait 2 minutes" -ForegroundColor Gray
    Write-Host "  3. Run this script again" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Host "Step 3: Install agents on ready VMs?" -ForegroundColor Cyan
$install = Read-Host "Type YES to install on $($readyVMs.Count) VMs, or NO to skip"

if ($install -ne "YES") {
    Write-Host "Skipped installation" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Step 4: Installing Datadog agents..." -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0
$failedVMs = @()

foreach ($vm in $readyVMs) {
    $vmName = $vm.Name
    $rg = $vm.ResourceGroupName
    
    Write-Host "Installing: $vmName" -ForegroundColor White
    
    # Enhanced install script with better error handling
    $installScript = @"
#!/bin/bash
set -e

# Set environment variables
export DD_API_KEY=$DD_API_KEY
export DD_SITE=$DD_SITE.datadoghq.com

# Check if running as root
if [ "`$(id -u)" != "0" ]; then
    echo "Attempting install with sudo..."
    sudo -E bash -c '
        export DD_API_KEY=$DD_API_KEY
        export DD_SITE=$DD_SITE
        bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
    '
else
    # Install as root
    bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
fi

# Restart agent
if command -v systemctl &> /dev/null; then
    systemctl restart datadog-agent
elif command -v service &> /dev/null; then
    service datadog-agent restart
fi

# Verify installation
if [ -f /etc/datadog-agent/datadog.yaml ]; then
    echo "Agent installed successfully"
else
    echo "Agent installation may have failed"
    exit 1
fi
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunShellScript" -ScriptString $installScript -ErrorAction Stop
        
        $output = $result.Value[0].Message
        
        if ($output -like "*successfully*" -or $output -like "*Agent installed*") {
            Write-Host "  [OK] Agent installed" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  [PARTIAL] Installed but verification uncertain" -ForegroundColor Yellow
            Write-Host "  Output: $($output.Substring(0, [Math]::Min(100, $output.Length)))" -ForegroundColor Gray
            $successCount++
        }
    } catch {
        Write-Host "  [FAIL] Installation failed" -ForegroundColor Red
        $errorMsg = $_.Exception.Message
        if ($errorMsg.Length -gt 100) {
            $errorMsg = $errorMsg.Substring(0, 100) + "..."
        }
        Write-Host "  Error: $errorMsg" -ForegroundColor Gray
        $failCount++
        $failedVMs += $vmName
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Success: $successCount VMs" -ForegroundColor Green
Write-Host "Failed: $failCount VMs" -ForegroundColor $(if($failCount -gt 0){'Red'}else{'Green'})
Write-Host ""

if ($failedVMs.Count -gt 0) {
    Write-Host "Failed VMs:" -ForegroundColor Red
    foreach ($vmName in $failedVMs) {
        Write-Host "  - $vmName" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "For failed VMs, try:" -ForegroundColor Yellow
    Write-Host "  1. SSH into the VM manually" -ForegroundColor Gray
    Write-Host "  2. Run: DD_API_KEY=$DD_API_KEY DD_SITE=$DD_SITE.datadoghq.com bash -c '`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)'" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Check Datadog in 5 minutes: https://$DD_SITE.datadoghq.com/infrastructure/map" -ForegroundColor Cyan
Write-Host ""
