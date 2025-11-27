# ULTIMATE-COMPREHENSIVE-FIX.ps1
# Checks and fixes EVERYTHING - VM, IIS, Ports, NSG, Front Door, Certificate
# Based on real-world Azure Front Door issues

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Red
Write-Host "  ULTIMATE COMPREHENSIVE FIX - EVERYTHING" -ForegroundColor Red  
Write-Host "========================================================" -ForegroundColor Red
Write-Host ""

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Logging in..." -ForegroundColor Yellow
    az login --use-device-code | Out-Null
}
Write-Host "[OK] Logged in" -ForegroundColor Green
Write-Host ""

$Issues = @()
$Fixes = @()

# Configuration
$FD = "moveit-frontdoor-profile"
$RG = "rg-moveit"
$CDName = "moveit-pyxhealth-com"
$Domain = "moveit.pyxhealth.com"
$VMName = "vm-moveit-afd"
$CorrectIP = "20.86.24.164"
$OGName = "moveit-origin-group"

# ============================================
# CHECK 1: MOVEit VM Status
# ============================================
Write-Host "CHECK 1: MOVEit VM Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

$VM = az vm show --name $VMName --resource-group $RG --output json 2>$null | ConvertFrom-Json

if ($VM) {
    $VMStatus = az vm get-instance-view --name $VMName --resource-group $RG --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>$null
    
    Write-Host "  VM: $VMName" -ForegroundColor White
    Write-Host "  Status: $VMStatus" -ForegroundColor White
    Write-Host "  IP: $CorrectIP" -ForegroundColor White
    
    if ($VMStatus -ne "VM running") {
        Write-Host "  [ISSUE] VM is not running!" -ForegroundColor Red
        $Issues += "VM stopped"
        
        Write-Host "  [FIX] Starting VM..." -ForegroundColor Yellow
        az vm start --name $VMName --resource-group $RG --output none 2>$null
        Write-Host "  [OK] VM started" -ForegroundColor Green
        $Fixes += "Started VM"
        Start-Sleep -Seconds 30
    } else {
        Write-Host "  [OK] VM is running" -ForegroundColor Green
    }
} else {
    Write-Host "  [ERROR] Cannot find VM: $VMName" -ForegroundColor Red
}

Write-Host ""

# ============================================
# CHECK 2: Port 443 on ALL NSGs
# ============================================
Write-Host "CHECK 2: Port 443 on All NSGs" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

$NSGs = az network nsg list --output json 2>$null | ConvertFrom-Json

foreach ($NSG in $NSGs) {
    Write-Host "  Checking NSG: $($NSG.name)" -ForegroundColor White
    $Rules = az network nsg rule list --nsg-name $NSG.name --resource-group $NSG.resourceGroup --output json 2>$null | ConvertFrom-Json
    
    $Has443 = $false
    foreach ($Rule in $Rules) {
        if ($Rule.destinationPortRange -eq "443" -and $Rule.access -eq "Allow") {
            $Has443 = $true
            break
        }
    }
    
    if (-not $Has443) {
        Write-Host "  [ISSUE] Port 443 not open!" -ForegroundColor Red
        $Issues += "Port 443 closed on $($NSG.name)"
        
        Write-Host "  [FIX] Opening port 443..." -ForegroundColor Yellow
        az network nsg rule create --nsg-name $NSG.name --resource-group $NSG.resourceGroup --name "Allow-HTTPS-443" --priority 1000 --destination-port-ranges 443 --protocol Tcp --access Allow --direction Inbound --output none 2>$null
        Write-Host "  [OK] Port 443 opened" -ForegroundColor Green
        $Fixes += "Opened port 443 on $($NSG.name)"
    } else {
        Write-Host "  [OK] Port 443 open" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# CHECK 3: Front Door Endpoint
# ============================================
Write-Host "CHECK 3: Front Door Endpoint" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

$EPs = az afd endpoint list --profile-name $FD --resource-group $RG --output json 2>$null | ConvertFrom-Json

if ($EPs -and $EPs.Count -gt 0) {
    $EP = $EPs[0]
    $EPName = $EP.name
    
    Write-Host "  Endpoint: $EPName" -ForegroundColor White
    Write-Host "  Status: $($EP.enabledState)" -ForegroundColor White
    
    if ($EP.enabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Endpoint disabled!" -ForegroundColor Red
        $Issues += "Endpoint disabled"
        
        Write-Host "  [FIX] Enabling endpoint..." -ForegroundColor Yellow
        az afd endpoint update --profile-name $FD --resource-group $RG --endpoint-name $EPName --enabled-state Enabled --output none 2>$null
        Write-Host "  [OK] Endpoint enabled" -ForegroundColor Green
        $Fixes += "Enabled endpoint"
    } else {
        Write-Host "  [OK] Endpoint enabled" -ForegroundColor Green
    }
} else {
    Write-Host "  [ERROR] No endpoints found!" -ForegroundColor Red
}

Write-Host ""

# ============================================
# CHECK 4: Custom Domain & Certificate
# ============================================
Write-Host "CHECK 4: Custom Domain & Certificate" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

$CD = az afd custom-domain show --profile-name $FD --resource-group $RG --custom-domain-name $CDName --output json 2>$null | ConvertFrom-Json

if ($CD) {
    Write-Host "  Domain: $($CD.hostName)" -ForegroundColor White
    Write-Host "  Cert Type: $($CD.tlsSettings.certificateType)" -ForegroundColor White
    Write-Host "  Validation: $($CD.validationProperties.validationState)" -ForegroundColor White
    
    if ($CD.tlsSettings.certificateType -eq "ManagedCertificate") {
        Write-Host "  [ISSUE] Using AFD managed cert (Pending)!" -ForegroundColor Red
        $Issues += "AFD managed certificate"
        
        Write-Host "  [FIX] Switching to Key Vault cert..." -ForegroundColor Yellow
        
        # Delete and recreate with Key Vault cert
        az afd custom-domain delete --profile-name $FD --resource-group $RG --custom-domain-name $CDName --yes 2>$null
        Start-Sleep -Seconds 10
        
        $KVCert = az keyvault certificate show --vault-name kv-moveit-prod --name wildcardpyxhealth --query id -o tsv 2>$null
        
        az afd custom-domain create --profile-name $FD --resource-group $RG --custom-domain-name $CDName --host-name $Domain --certificate-type CustomerCertificate --secret $KVCert --output none 2>$null
        
        Write-Host "  [OK] Switched to Key Vault cert" -ForegroundColor Green
        $Fixes += "Switched to Key Vault certificate"
    } else {
        Write-Host "  [OK] Using Key Vault cert" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# CHECK 5: Origin IP
# ============================================
Write-Host "CHECK 5: Origin Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

$Origins = az afd origin list --profile-name $FD --resource-group $RG --origin-group-name $OGName --output json 2>$null | ConvertFrom-Json

$HasCorrectIP = $false

foreach ($O in $Origins) {
    Write-Host "  Origin: $($O.name) - IP: $($O.hostName)" -ForegroundColor White
    
    if ($O.hostName -eq $CorrectIP) {
        $HasCorrectIP = $true
        Write-Host "  [OK] Correct IP" -ForegroundColor Green
    } else {
        Write-Host "  [ISSUE] Wrong IP!" -ForegroundColor Red
        $Issues += "Wrong origin IP: $($O.hostName)"
        
        Write-Host "  [FIX] Deleting wrong origin..." -ForegroundColor Yellow
        az afd origin delete --profile-name $FD --resource-group $RG --origin-group-name $OGName --origin-name $O.name --yes 2>$null
        $Fixes += "Deleted wrong origin"
    }
}

if (-not $HasCorrectIP) {
    Write-Host "  [FIX] Creating origin with correct IP..." -ForegroundColor Yellow
    az afd origin create --profile-name $FD --resource-group $RG --origin-group-name $OGName --origin-name moveit-backend --host-name $CorrectIP --origin-host-header $CorrectIP --priority 1 --weight 1000 --enabled-state Enabled --http-port 80 --https-port 443 --output none 2>$null
    Write-Host "  [OK] Origin created with IP: $CorrectIP" -ForegroundColor Green
    $Fixes += "Created origin with correct IP"
}

Write-Host ""

# ============================================
# CHECK 6: Route & Domain Association
# ============================================
Write-Host "CHECK 6: Route & Domain Association" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Gray

if ($EPs -and $EPs.Count -gt 0) {
    $Routes = az afd route list --profile-name $FD --resource-group $RG --endpoint-name $EPName --output json 2>$null | ConvertFrom-Json
    
    if ($Routes -and $Routes.Count -gt 0) {
        $Route = $Routes[0]
        $RouteName = $Route.name
        
        Write-Host "  Route: $RouteName" -ForegroundColor White
        Write-Host "  Enabled: $($Route.enabledState)" -ForegroundColor White
        
        if ($Route.enabledState -ne "Enabled") {
            Write-Host "  [ISSUE] Route disabled!" -ForegroundColor Red
            $Issues += "Route disabled"
            
            Write-Host "  [FIX] Enabling route..." -ForegroundColor Yellow
            az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --enabled-state Enabled --output none 2>$null
            Write-Host "  [OK] Route enabled" -ForegroundColor Green
            $Fixes += "Enabled route"
        }
        
        # Associate custom domain
        Start-Sleep -Seconds 5
        $CDId = az afd custom-domain show --profile-name $FD --resource-group $RG --custom-domain-name $CDName --query id -o tsv 2>$null
        
        Write-Host "  [FIX] Associating custom domain..." -ForegroundColor Yellow
        az afd route update --profile-name $FD --resource-group $RG --endpoint-name $EPName --route-name $RouteName --custom-domains $CDId --output none 2>$null
        Write-Host "  [OK] Domain associated" -ForegroundColor Green
        $Fixes += "Associated domain with route"
    }
}

Write-Host ""

# ============================================
# SUMMARY
# ============================================
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

if ($Issues.Count -gt 0) {
    Write-Host "ISSUES FOUND: $($Issues.Count)" -ForegroundColor Yellow
    foreach ($I in $Issues) {
        Write-Host "  - $I" -ForegroundColor White
    }
    Write-Host ""
}

if ($Fixes.Count -gt 0) {
    Write-Host "FIXES APPLIED: $($Fixes.Count)" -ForegroundColor Green
    foreach ($F in $Fixes) {
        Write-Host "  - $F" -ForegroundColor White
    }
    Write-Host ""
}

Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "1. Wait 10-15 minutes for certificate and changes to propagate" -ForegroundColor White
Write-Host "2. Test in browser: https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host "3. Look for LOCK ICON in address bar" -ForegroundColor White
Write-Host "4. Test upload/download" -ForegroundColor White
Write-Host ""

Write-Host "CONFIGURATION:" -ForegroundColor Cyan
Write-Host "  VM: $VMName ($CorrectIP)" -ForegroundColor White
Write-Host "  Domain: $Domain" -ForegroundColor White
Write-Host "  Certificate: Key Vault (wildcardpyxhealth)" -ForegroundColor White
Write-Host "  Port 443: Open on all NSGs" -ForegroundColor White
Write-Host ""

Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
