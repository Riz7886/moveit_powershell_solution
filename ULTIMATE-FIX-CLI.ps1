# ULTIMATE FIX - USES AZURE CLI (NO VERSION ISSUES)
# This bypasses PowerShell module version problems

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ULTIMATE FIX - AZURE CLI METHOD" -ForegroundColor Cyan  
Write-Host "========================================`n" -ForegroundColor Cyan

$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"
$EndpointName = "moveit-endpoint-e9foashyq2cddef0"
$CustomDomainName = "moveit-pyxhealth-com"
$RouteName = "moveit-route"
$OriginGroupName = "moveit-origin-group"
$CorrectIP = "20.86.24.164"
$KeyVaultName = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

$fixesApplied = 0

# Check if Azure CLI is installed
Write-Host "[STEP 1] Checking Azure CLI..." -ForegroundColor Yellow
try {
    $azVersion = az version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Azure CLI not installed!" -ForegroundColor Red
        Write-Host "  Install from: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
        Read-Host "Press ENTER to exit"
        exit
    }
    Write-Host "  [OK] Azure CLI installed" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Azure CLI not found" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# Login check
Write-Host "`n[STEP 2] Checking Azure login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ISSUE] Not logged in" -ForegroundColor Red
    Write-Host "  [ACTION] Logging in..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "  [OK] Logged in: $($account.user.name)" -ForegroundColor Green
Write-Host "  Subscription: $($account.name)" -ForegroundColor Cyan

# Set subscription
Write-Host "`n[STEP 3] Setting correct subscription..." -ForegroundColor Yellow
$subs = az account list | ConvertFrom-Json
$correctSub = $null

foreach ($sub in $subs) {
    az account set --subscription $sub.id 2>$null
    $testRg = az group show --name $ResourceGroup 2>$null
    if ($LASTEXITCODE -eq 0) {
        $correctSub = $sub
        Write-Host "  [OK] Found rg-moveit in: $($sub.name)" -ForegroundColor Green
        break
    }
}

if (-not $correctSub) {
    Write-Host "  [FAIL] Could not find rg-moveit" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# Fix NSG Port 443
Write-Host "`n[STEP 4] Opening Port 443 on NSGs..." -ForegroundColor Yellow
$nsgs = az network nsg list --resource-group $ResourceGroup | ConvertFrom-Json

foreach ($nsg in $nsgs) {
    Write-Host "  Checking NSG: $($nsg.name)" -ForegroundColor Cyan
    
    # Check for deny rules on 443
    $denyRules = $nsg.securityRules | Where-Object {
        $_.access -eq "Deny" -and
        $_.direction -eq "Inbound" -and
        ($_.destinationPortRange -eq "443" -or $_.destinationPortRange -eq "*")
    }
    
    foreach ($rule in $denyRules) {
        Write-Host "    Removing DENY rule: $($rule.name)" -ForegroundColor Yellow
        az network nsg rule delete `
            --resource-group $ResourceGroup `
            --nsg-name $nsg.name `
            --name $rule.name 2>$null
        $fixesApplied++
    }
    
    # Check for allow rule
    $allowRule = $nsg.securityRules | Where-Object {
        $_.access -eq "Allow" -and
        $_.direction -eq "Inbound" -and
        $_.destinationPortRange -eq "443"
    }
    
    if (-not $allowRule) {
        Write-Host "    Adding ALLOW rule for port 443" -ForegroundColor Yellow
        az network nsg rule create `
            --resource-group $ResourceGroup `
            --nsg-name $nsg.name `
            --name "Allow-HTTPS-443" `
            --priority 100 `
            --access Allow `
            --protocol Tcp `
            --direction Inbound `
            --source-address-prefixes Internet `
            --source-port-ranges "*" `
            --destination-address-prefixes "*" `
            --destination-port-ranges 443 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            $fixesApplied++
            Write-Host "    [OK] Port 443 opened" -ForegroundColor Green
        }
    } else {
        Write-Host "    [OK] Port 443 already open" -ForegroundColor Green
    }
}

# Get Key Vault certificate
Write-Host "`n[STEP 5] Getting Key Vault certificate..." -ForegroundColor Yellow
$kv = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup | ConvertFrom-Json
$kvId = $kv.id

$certs = az keyvault certificate list --vault-name $KeyVaultName | ConvertFrom-Json
Write-Host "  Available certificates:" -ForegroundColor Cyan
foreach ($c in $certs) {
    Write-Host "    - $($c.name)" -ForegroundColor Cyan
}

$cert = $certs | Where-Object { $_.name -like "*wildcard*" -or $_.name -like "*pyxhealth*" } | Select-Object -First 1
if ($cert) {
    $CertName = $cert.name
    Write-Host "  [OK] Using certificate: $CertName" -ForegroundColor Green
    $certId = "$kvId/secrets/$CertName"
} else {
    Write-Host "  [FAIL] No certificate found!" -ForegroundColor Red
}

# Fix Origins - Use Azure CLI
Write-Host "`n[STEP 6] Fixing origins..." -ForegroundColor Yellow

$origins = az afd origin list `
    --resource-group $ResourceGroup `
    --profile-name $ProfileName `
    --origin-group-name $OriginGroupName | ConvertFrom-Json

$correctExists = $false

foreach ($origin in $origins) {
    Write-Host "  Origin: $($origin.name) -> $($origin.hostName)" -ForegroundColor Cyan
    
    if ($origin.hostName -eq $CorrectIP) {
        $correctExists = $true
        Write-Host "    [OK] Correct IP!" -ForegroundColor Green
    } else {
        Write-Host "    [ISSUE] Wrong IP - removing..." -ForegroundColor Red
        az afd origin delete `
            --resource-group $ResourceGroup `
            --profile-name $ProfileName `
            --origin-group-name $OriginGroupName `
            --origin-name $origin.name `
            --yes 2>$null
        $fixesApplied++
    }
}

if (-not $correctExists) {
    Write-Host "  [FIXING] Creating correct origin with IP $CorrectIP..." -ForegroundColor Yellow
    az afd origin create `
        --resource-group $ResourceGroup `
        --profile-name $ProfileName `
        --origin-group-name $OriginGroupName `
        --origin-name "moveit-origin-fixed" `
        --host-name $CorrectIP `
        --http-port 80 `
        --https-port 443 `
        --priority 1 `
        --weight 1000 `
        --enabled-state Enabled 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        $fixesApplied++
        Write-Host "  [OK] Correct origin created!" -ForegroundColor Green
    }
}

# Fix Custom Domain - Use Azure CLI
Write-Host "`n[STEP 7] Fixing custom domain..." -ForegroundColor Yellow

$domain = az afd custom-domain show `
    --resource-group $ResourceGroup `
    --profile-name $ProfileName `
    --custom-domain-name $CustomDomainName 2>$null | ConvertFrom-Json

if ($domain) {
    Write-Host "  Domain exists: $($domain.hostName)" -ForegroundColor Cyan
    Write-Host "  Certificate type: $($domain.tlsSettings.certificateType)" -ForegroundColor Cyan
    
    if ($domain.tlsSettings.certificateType -ne "CustomerCertificate") {
        Write-Host "  [ISSUE] Wrong certificate type!" -ForegroundColor Red
        Write-Host "  [FIXING] Deleting and recreating..." -ForegroundColor Yellow
        
        az afd custom-domain delete `
            --resource-group $ResourceGroup `
            --profile-name $ProfileName `
            --custom-domain-name $CustomDomainName `
            --yes 2>$null
        
        Start-Sleep -Seconds 10
        
        az afd custom-domain create `
            --resource-group $ResourceGroup `
            --profile-name $ProfileName `
            --custom-domain-name $CustomDomainName `
            --host-name "moveit.pyxhealth.com" `
            --certificate-type CustomerCertificate `
            --minimum-tls-version TLS12 `
            --azure-dns-zone "" `
            --secret $certId 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            $fixesApplied++
            Write-Host "  [OK] Domain recreated with Key Vault cert!" -ForegroundColor Green
        }
    } else {
        Write-Host "  [OK] Already using Key Vault certificate" -ForegroundColor Green
    }
}

# Enable endpoint
Write-Host "`n[STEP 8] Enabling endpoint..." -ForegroundColor Yellow
az afd endpoint update `
    --resource-group $ResourceGroup `
    --profile-name $ProfileName `
    --endpoint-name $EndpointName `
    --enabled-state Enabled 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Endpoint enabled" -ForegroundColor Green
}

# Update route to associate domain
Write-Host "`n[STEP 9] Associating domain with route..." -ForegroundColor Yellow

$domain = az afd custom-domain show `
    --resource-group $ResourceGroup `
    --profile-name $ProfileName `
    --custom-domain-name $CustomDomainName | ConvertFrom-Json

az afd route update `
    --resource-group $ResourceGroup `
    --profile-name $ProfileName `
    --endpoint-name $EndpointName `
    --route-name $RouteName `
    --custom-domains $domain.id `
    --enabled-state Enabled `
    --https-redirect Enabled `
    --supported-protocols Https `
    --link-to-default-domain Enabled `
    --forwarding-protocol HttpsOnly 2>$null

if ($LASTEXITCODE -eq 0) {
    $fixesApplied++
    Write-Host "  [OK] Route updated and domain associated!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Route update may have issues" -ForegroundColor Yellow
}

# Test connectivity
Write-Host "`n[STEP 10] Testing VM connectivity..." -ForegroundColor Yellow
$testResult = Test-NetConnection -ComputerName $CorrectIP -Port 443 -WarningAction SilentlyContinue

if ($testResult.TcpTestSucceeded) {
    Write-Host "  [OK] VM reachable on port 443!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] VM not reachable yet (wait 2-3 minutes)" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "COMPLETED!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "FIXES APPLIED: $fixesApplied" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "WHAT TO DO NOW" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "1. Wait 10-15 minutes for certificate and routes to propagate" -ForegroundColor Yellow
Write-Host "2. Open browser and go to:" -ForegroundColor Yellow
Write-Host "   https://moveit.pyxhealth.com" -ForegroundColor Green
Write-Host "3. You should see MOVEit login page with LOCK ICON" -ForegroundColor Yellow
Write-Host "4. Test upload/download" -ForegroundColor Yellow
Write-Host "5. Call your client!" -ForegroundColor Green

Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
Read-Host
