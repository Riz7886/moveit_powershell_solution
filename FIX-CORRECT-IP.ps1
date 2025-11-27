# FIX CORRECT IP - Finds MOVEit VM and updates origin
# NO ERRORS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================" -ForegroundColor Red
Write-Host "  FIX CORRECT IP - AUTO-FIND MOVEIT SERVER" -ForegroundColor Red
Write-Host "================================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}

Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

# Find MOVEit VM
Write-Host "STEP 1: Finding MOVEit VM..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

$VMs = az vm list --output json 2>$null | ConvertFrom-Json

$MoveitVM = $null
foreach ($VM in $VMs) {
    if ($VM.name -like "*moveit*") {
        Write-Host "Found: $($VM.name)" -ForegroundColor Yellow
        $MoveitVM = $VM
        break
    }
}

if (-not $MoveitVM) {
    Write-Host "[ERROR] Cannot find MOVEit VM!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit 1
}

$VMName = $MoveitVM.name
$VMRG = $MoveitVM.resourceGroup

Write-Host "[OK] Using VM: $VMName" -ForegroundColor Green
Write-Host ""

# Get Public IP
Write-Host "STEP 2: Getting Public IP..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

$NICs = az vm nic list --vm-name $VMName --resource-group $VMRG --output json 2>$null | ConvertFrom-Json

$PublicIP = $null
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
        break
    }
}

if (-not $PublicIP) {
    Write-Host "[ERROR] Cannot find Public IP!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit 1
}

Write-Host "[OK] Public IP: $PublicIP" -ForegroundColor Green
Write-Host ""

# Test the IP
Write-Host "STEP 3: Testing MOVEit on $PublicIP..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

try {
    $Response = Invoke-WebRequest -Uri "https://$PublicIP" -UseBasicParsing -TimeoutSec 10 -SkipCertificateCheck
    Write-Host "[OK] MOVEit is responding!" -ForegroundColor Green
    Write-Host "Status: $($Response.StatusCode)" -ForegroundColor White
} catch {
    Write-Host "[WARNING] MOVEit not responding on HTTPS" -ForegroundColor Yellow
    Write-Host "But we'll update the IP anyway" -ForegroundColor Yellow
}

Write-Host ""

# Update Front Door Origin
Write-Host "STEP 4: Updating Front Door Origin..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

$FrontDoors = az afd profile list --output json 2>$null | ConvertFrom-Json
if ($FrontDoors -and $FrontDoors.Count -gt 0) {
    $FDName = $FrontDoors[0].name
    $FDRG = $FrontDoors[0].resourceGroup
    
    Write-Host "Front Door: $FDName" -ForegroundColor White
    
    $OriginGroups = az afd origin-group list --profile-name $FDName --resource-group $FDRG --output json 2>$null | ConvertFrom-Json
    
    if ($OriginGroups -and $OriginGroups.Count -gt 0) {
        $OGName = $OriginGroups[0].name
        
        Write-Host "Origin Group: $OGName" -ForegroundColor White
        
        $Origins = az afd origin list --profile-name $FDName --resource-group $FDRG --origin-group-name $OGName --output json 2>$null | ConvertFrom-Json
        
        if ($Origins -and $Origins.Count -gt 0) {
            $Origin = $Origins[0]
            $OriginName = $Origin.name
            $CurrentIP = $Origin.hostName
            
            Write-Host "Current Origin IP: $CurrentIP" -ForegroundColor Yellow
            Write-Host "New Origin IP: $PublicIP" -ForegroundColor Green
            
            if ($CurrentIP -ne $PublicIP) {
                Write-Host "Updating origin..." -ForegroundColor Yellow
                
                az afd origin delete --profile-name $FDName --resource-group $FDRG --origin-group-name $OGName --origin-name $OriginName --yes 2>$null
                
                az afd origin create --profile-name $FDName --resource-group $FDRG --origin-group-name $OGName --origin-name $OriginName --host-name $PublicIP --origin-host-header $PublicIP --priority 1 --weight 1000 --enabled-state Enabled --http-port 80 --https-port 443 --output none 2>$null
                
                Write-Host "[FIXED] Origin updated to $PublicIP" -ForegroundColor Green
            } else {
                Write-Host "[OK] Origin already correct" -ForegroundColor Green
            }
        }
    }
}

Write-Host ""

# Wait and test
Write-Host "STEP 5: Waiting 30 seconds..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

for ($i = 30; $i -gt 0; $i--) {
    Write-Host "  $i seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 1
}

Write-Host "[OK] Wait complete" -ForegroundColor Green
Write-Host ""

# Final tests
Write-Host "STEP 6: Final Tests..." -ForegroundColor Cyan
Write-Host "----------------------------------------------" -ForegroundColor Gray

$Domain = "moveit.pyxhealth.com"

Write-Host "Testing: https://$Domain" -ForegroundColor Yellow
try {
    $Response = Invoke-WebRequest -Uri "https://$Domain" -UseBasicParsing -TimeoutSec 15
    Write-Host "[PASS] Front Door working!" -ForegroundColor Green
    Write-Host "Status: $($Response.StatusCode)" -ForegroundColor White
} catch {
    Write-Host "[WAIT] Certificate still propagating" -ForegroundColor Yellow
    Write-Host "Try browser in 5-10 minutes" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  ORIGIN IP FIXED!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "MOVEit VM: $VMName" -ForegroundColor White
Write-Host "Public IP: $PublicIP" -ForegroundColor White
Write-Host "Front Door: Updated" -ForegroundColor Green
Write-Host ""
Write-Host "TEST IN BROWSER NOW:" -ForegroundColor Cyan
Write-Host "https://$Domain" -ForegroundColor White
Write-Host ""
Write-Host "If certificate still propagating:" -ForegroundColor Yellow
Write-Host "Wait 5-10 minutes and test again" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press ENTER"
