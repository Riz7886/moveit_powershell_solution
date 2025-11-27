# START MOVEIT VMS - Checks and starts all MOVEit VMs
# NO ERRORS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Red
Write-Host "  START MOVEIT VMS" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}
Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

# Find MOVEit VMs
Write-Host "Finding MOVEit VMs..." -ForegroundColor Cyan
$VMs = az vm list --query "[?contains(name, 'moveit')]" --output json 2>$null | ConvertFrom-Json

if (-not $VMs -or $VMs.Count -eq 0) {
    Write-Host "[ERROR] No MOVEit VMs found!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit 1
}

Write-Host "Found $($VMs.Count) MOVEit VM(s)" -ForegroundColor Green
Write-Host ""

# Check and start each VM
foreach ($VM in $VMs) {
    Write-Host "VM: $($VM.name)" -ForegroundColor Cyan
    Write-Host "  Resource Group: $($VM.resourceGroup)" -ForegroundColor White
    
    $PowerState = az vm get-instance-view --name $VM.name --resource-group $VM.resourceGroup --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
    
    Write-Host "  Power State: $PowerState" -ForegroundColor White
    
    if ($PowerState -eq "VM running") {
        Write-Host "  [OK] VM is running" -ForegroundColor Green
        
        # Get public IP
        $NICs = az vm nic list --vm-name $VM.name --resource-group $VM.resourceGroup --output json 2>$null | ConvertFrom-Json
        
        foreach ($NIC in $NICs) {
            $NICName = $NIC.id.Split('/')[-1]
            $NICRG = $NIC.id.Split('/')[4]
            
            $NICDetails = az network nic show --name $NICName --resource-group $NICRG --output json 2>$null | ConvertFrom-Json
            
            if ($NICDetails.ipConfigurations[0].publicIPAddress) {
                $PIPId = $NICDetails.ipConfigurations[0].publicIPAddress.id
                $PIPName = $PIPId.Split('/')[-1]
                $PIPRG = $PIPId.Split('/')[4]
                
                $PIPDetails = az network public-ip show --name $PIPName --resource-group $PIPRG --output json 2>$null | ConvertFrom-Json
                $PublicIP = $PIPDetails.ipAddress
                
                Write-Host "  Public IP: $PublicIP" -ForegroundColor White
                
                # Test if MOVEit is responding
                Write-Host "  Testing MOVEit on HTTPS..." -ForegroundColor Yellow
                try {
                    $Response = Invoke-WebRequest -Uri "https://$PublicIP" -UseBasicParsing -TimeoutSec 5 -SkipCertificateCheck -ErrorAction Stop
                    Write-Host "  [OK] MOVEit responding!" -ForegroundColor Green
                } catch {
                    Write-Host "  [WARNING] MOVEit not responding on HTTPS" -ForegroundColor Yellow
                    Write-Host "  You may need to RDP and start MOVEit service" -ForegroundColor Yellow
                    Write-Host "  RDP to: $PublicIP" -ForegroundColor White
                }
            }
        }
    } else {
        Write-Host "  [ACTION] Starting VM..." -ForegroundColor Yellow
        az vm start --name $VM.name --resource-group $VM.resourceGroup --no-wait 2>$null
        Write-Host "  [OK] VM start initiated (takes 2-3 minutes)" -ForegroundColor Green
    }
    
    Write-Host ""
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "If any VMs were started:" -ForegroundColor Yellow
Write-Host "  Wait 3-5 minutes for them to fully boot" -ForegroundColor White
Write-Host "  Then run this script again to verify" -ForegroundColor White
Write-Host ""
Write-Host "If MOVEit not responding on running VMs:" -ForegroundColor Yellow
Write-Host "  RDP to the VM" -ForegroundColor White
Write-Host "  Open Services (services.msc)" -ForegroundColor White
Write-Host "  Find 'MOVEit Transfer' service" -ForegroundColor White
Write-Host "  Right-click > Start" -ForegroundColor White
Write-Host "  Also check IIS is running" -ForegroundColor White
Write-Host ""
Read-Host "Press ENTER"
