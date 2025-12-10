param(
    [string]$DD_API_KEY = "38ff813dd7d46538706378cc3bd68e94",
    [string]$DD_SITE = "us3"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FIX FAILED DATADOG AGENT INSTALLS" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Failed VMs from your screenshot
$failedVMs = @(
    "vm-csc-gen-0",
    "vm-csc-gen-1", 
    "vm-csc-gen-2",
    "vm-fbrx-0",
    "vm-hac-0",
    "vm-poc-csc-0"
)

Write-Host "Step 1: Checking status of failed VMs..." -ForegroundColor Cyan
Write-Host ""

foreach ($vmName in $failedVMs) {
    Write-Host "Checking: $vmName" -ForegroundColor White
    
    # Find the VM
    $vm = Get-AzVM -Status | Where-Object { $_.Name -eq $vmName } -ErrorAction SilentlyContinue
    
    if (-not $vm) {
        Write-Host "  [NOT FOUND] VM does not exist in current subscription" -ForegroundColor Red
        Write-Host ""
        continue
    }
    
    $rg = $vm.ResourceGroupName
    $powerState = $vm.PowerState
    
    Write-Host "  Resource Group: $rg" -ForegroundColor Gray
    Write-Host "  Power State: $powerState" -ForegroundColor Gray
    
    if ($powerState -ne "VM running") {
        Write-Host "  [STOPPED] VM is not running - Cannot install agent" -ForegroundColor Yellow
        Write-Host "  Solution: Start the VM first, then run agent install" -ForegroundColor Yellow
        Write-Host ""
        continue
    }
    
    # VM is running - check Azure VM Agent
    $vmDetail = Get-AzVM -ResourceGroupName $rg -Name $vmName
    $vmAgentStatus = $vmDetail.OSProfile.WindowsConfiguration.ProvisionVMAgent
    
    Write-Host "  Azure VM Agent: $vmAgentStatus" -ForegroundColor Gray
    
    if ($vmAgentStatus -eq $false) {
        Write-Host "  [ISSUE] Azure VM Agent not enabled" -ForegroundColor Yellow
        Write-Host "  Solution: VM needs Azure VM Agent installed" -ForegroundColor Yellow
        Write-Host ""
        continue
    }
    
    Write-Host "  [READY] VM is ready for agent install" -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "Step 2: Would you like to retry agent installation on running VMs?" -ForegroundColor Cyan
$retry = Read-Host "Type YES to retry, or NO to skip"

if ($retry -eq "YES") {
    Write-Host ""
    Write-Host "Installing agents on running VMs..." -ForegroundColor Cyan
    Write-Host ""
    
    $successCount = 0
    $failCount = 0
    
    foreach ($vmName in $failedVMs) {
        $vm = Get-AzVM -Status | Where-Object { $_.Name -eq $vmName } -ErrorAction SilentlyContinue
        
        if (-not $vm) {
            continue
        }
        
        if ($vm.PowerState -ne "VM running") {
            Write-Host "$vmName - SKIPPED (not running)" -ForegroundColor Yellow
            continue
        }
        
        $rg = $vm.ResourceGroupName
        
        Write-Host "Installing: $vmName" -ForegroundColor White
        
        $installScript = @"
`$url = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
`$msi = "`$env:TEMP\dd.msi"
Invoke-WebRequest -Uri `$url -OutFile `$msi -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `$msi /qn APIKEY=$DD_API_KEY SITE=$DD_SITE" -Wait
Remove-Item `$msi -Force
Restart-Service datadogagent -ErrorAction SilentlyContinue
"@
        
        try {
            Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vmName -CommandId "RunPowerShellScript" -ScriptString $installScript -ErrorAction Stop | Out-Null
            Write-Host "  [OK]" -ForegroundColor Green
            $successCount++
        } catch {
            Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "RETRY COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Success: $successCount | Failed: $failCount" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host ""
Write-Host "SUMMARY OF ISSUES:" -ForegroundColor Yellow
Write-Host ""
Write-Host "If VMs are STOPPED:" -ForegroundColor White
Write-Host "  1. Start the VMs in Azure Portal" -ForegroundColor Gray
Write-Host "  2. Run this script again" -ForegroundColor Gray
Write-Host ""
Write-Host "If VMs are RUNNING but still fail:" -ForegroundColor White
Write-Host "  1. RDP into the VM manually" -ForegroundColor Gray
Write-Host "  2. Download agent: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi" -ForegroundColor Gray
Write-Host "  3. Install with: msiexec /i datadog-agent-7-latest.amd64.msi APIKEY=$DD_API_KEY SITE=$DD_SITE /qn" -ForegroundColor Gray
Write-Host ""
Write-Host "If VM not in subscription:" -ForegroundColor White
Write-Host "  - VM might be in different subscription" -ForegroundColor Gray
Write-Host "  - Run the main script on that subscription" -ForegroundColor Gray
Write-Host ""
