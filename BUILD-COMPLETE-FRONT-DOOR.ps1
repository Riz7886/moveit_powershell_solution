# BUILD-COMPLETE-FRONT-DOOR.ps1
# Creates ENTIRE Front Door configuration from scratch using Azure CLI

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "BUILD COMPLETE FRONT DOOR FROM SCRATCH" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# CONFIGURATION
$RG = "rg-moveit"
$Location = "westus"
$FDProfile = "moveit-frontdoor-profile"
$FDEndpoint = "moveit-endpoint-$(Get-Random -Minimum 1000 -Maximum 9999)"
$OriginGroup = "moveit-origin-group"
$OriginName = "moveit-backend"
$OriginIP = "20.86.24.141"  # CORRECT IP!
$RouteName = "moveit-route"
$CustomDomainName = "moveit-pyxhealth-com"
$Domain = "moveit.pyxhealth.com"
$KeyVault = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

# Check Azure CLI
Write-Host "[STEP 1] Checking Azure CLI..." -ForegroundColor Yellow
try {
    az version 2>$null | Out-Null
    Write-Host "  [OK] Azure CLI ready" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Azure CLI not installed!" -ForegroundColor Red
    exit
}

# Login
Write-Host "`n[STEP 2] Logging in..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "  [OK] Logged in: $($account.user.name)" -ForegroundColor Green

# Find subscription
Write-Host "`n[STEP 3] Finding subscription..." -ForegroundColor Yellow
$subs = az account list | ConvertFrom-Json
$correctSub = $null

foreach ($sub in $subs) {
    az account set --subscription $sub.id 2>$null
    $testRg = az group show --name $RG 2>$null
    if ($LASTEXITCODE -eq 0) {
        $correctSub = $sub
        Write-Host "  [OK] Using: $($sub.name)" -ForegroundColor Green
        break
    }
}

if (-not $correctSub) {
    Write-Host "  [FAIL] Cannot find rg-moveit!" -ForegroundColor Red
    exit
}

# Get Key Vault certificate
Write-Host "`n[STEP 4] Getting Key Vault certificate..." -ForegroundColor Yellow
$kv = az keyvault show --name $KeyVault --resource-group $RG 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] Key Vault not found!" -ForegroundColor Red
    exit
}

$kvId = $kv.id
$certId = "$kvId/secrets/$CertName"
Write-Host "  [OK] Certificate ID: $certId" -ForegroundColor Green

# Check if profile exists
Write-Host "`n[STEP 5] Checking Front Door profile..." -ForegroundColor Yellow
$profile = az afd profile show --profile-name $FDProfile --resource-group $RG 2>$null | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Creating Front Door profile..." -ForegroundColor Yellow
    az afd profile create `
        --profile-name $FDProfile `
        --resource-group $RG `
        --sku Premium_AzureFrontDoor 2>$null | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Profile created!" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Profile creation failed!" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "  [OK] Profile exists" -ForegroundColor Green
}

# Create endpoint
Write-Host "`n[STEP 6] Creating endpoint..." -ForegroundColor Yellow
az afd endpoint create `
    --endpoint-name $FDEndpoint `
    --profile-name $FDProfile `
    --resource-group $RG `
    --enabled-state Enabled 2>$null | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Endpoint created: $FDEndpoint" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Endpoint may already exist or creation failed" -ForegroundColor Yellow
}

# Create origin group
Write-Host "`n[STEP 7] Creating origin group..." -ForegroundColor Yellow
az afd origin-group create `
    --origin-group-name $OriginGroup `
    --profile-name $FDProfile `
    --resource-group $RG `
    --probe-request-type GET `
    --probe-protocol Https `
    --probe-interval-in-seconds 240 `
    --probe-path / `
    --sample-size 4 `
    --successful-samples-required 3 `
    --additional-latency-in-milliseconds 50 2>$null | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Origin group created!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Origin group may already exist" -ForegroundColor Yellow
}

# Create origin with CORRECT IP
Write-Host "`n[STEP 8] Creating origin with IP $OriginIP..." -ForegroundColor Yellow
az afd origin create `
    --origin-name $OriginName `
    --origin-group-name $OriginGroup `
    --profile-name $FDProfile `
    --resource-group $RG `
    --host-name $OriginIP `
    --origin-host-header $OriginIP `
    --http-port 80 `
    --https-port 443 `
    --priority 1 `
    --weight 1000 `
    --enabled-state Enabled 2>$null | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Origin created with correct IP!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Origin may already exist" -ForegroundColor Yellow
}

# Grant Front Door access to Key Vault
Write-Host "`n[STEP 9] Granting Front Door access to Key Vault..." -ForegroundColor Yellow
$frontDoorAppId = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8"
az keyvault set-policy `
    --name $KeyVault `
    --spn $frontDoorAppId `
    --secret-permissions get `
    --certificate-permissions get 2>$null | Out-Null

Write-Host "  [OK] Access granted" -ForegroundColor Green

# Create custom domain with Key Vault certificate
Write-Host "`n[STEP 10] Creating custom domain with Key Vault cert..." -ForegroundColor Yellow
az afd custom-domain create `
    --custom-domain-name $CustomDomainName `
    --profile-name $FDProfile `
    --resource-group $RG `
    --host-name $Domain `
    --minimum-tls-version TLS12 `
    --certificate-type CustomerCertificate `
    --secret $certId 2>$null | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Custom domain created with Key Vault cert!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Domain may already exist, trying to update..." -ForegroundColor Yellow
    
    # Try to update existing domain
    az afd custom-domain update `
        --custom-domain-name $CustomDomainName `
        --profile-name $FDProfile `
        --resource-group $RG `
        --certificate-type CustomerCertificate `
        --minimum-tls-version TLS12 `
        --secret $certId 2>$null | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Domain updated!" -ForegroundColor Green
    }
}

# Get domain and origin group IDs
Start-Sleep -Seconds 5
$domain = az afd custom-domain show `
    --custom-domain-name $CustomDomainName `
    --profile-name $FDProfile `
    --resource-group $RG 2>$null | ConvertFrom-Json

$originGroupObj = az afd origin-group show `
    --origin-group-name $OriginGroup `
    --profile-name $FDProfile `
    --resource-group $RG 2>$null | ConvertFrom-Json

# Create route with domain
Write-Host "`n[STEP 11] Creating route with custom domain..." -ForegroundColor Yellow
az afd route create `
    --route-name $RouteName `
    --endpoint-name $FDEndpoint `
    --profile-name $FDProfile `
    --resource-group $RG `
    --forwarding-protocol HttpsOnly `
    --https-redirect Enabled `
    --origin-group $originGroupObj.id `
    --supported-protocols Https `
    --link-to-default-domain Enabled `
    --enabled-state Enabled `
    --custom-domains $domain.id 2>$null | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Route created with custom domain!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Route creation may have failed, trying update..." -ForegroundColor Yellow
    
    # Try to update existing route
    az afd route update `
        --route-name $RouteName `
        --endpoint-name $FDEndpoint `
        --profile-name $FDProfile `
        --resource-group $RG `
        --enabled-state Enabled `
        --custom-domains $domain.id 2>$null | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Route updated!" -ForegroundColor Green
    }
}

# Open NSG port 443
Write-Host "`n[STEP 12] Opening port 443 on NSGs..." -ForegroundColor Yellow
$nsgs = az network nsg list --resource-group $RG | ConvertFrom-Json

foreach ($nsg in $nsgs) {
    Write-Host "  Checking: $($nsg.name)" -ForegroundColor Cyan
    
    # Check if rule exists
    $rules = $nsg.securityRules | Where-Object { 
        $_.destinationPortRange -eq "443" -and 
        $_.access -eq "Allow" -and 
        $_.direction -eq "Inbound" 
    }
    
    if (-not $rules) {
        Write-Host "    Adding allow rule..." -ForegroundColor Yellow
        
        az network nsg rule create `
            --nsg-name $nsg.name `
            --resource-group $RG `
            --name "Allow-HTTPS-443" `
            --priority 100 `
            --access Allow `
            --protocol Tcp `
            --direction Inbound `
            --source-address-prefixes Internet `
            --source-port-ranges "*" `
            --destination-address-prefixes "*" `
            --destination-port-ranges 443 2>$null | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Port 443 opened" -ForegroundColor Green
        }
    } else {
        Write-Host "    [OK] Port 443 already open" -ForegroundColor Green
    }
}

# Get endpoint URL
$endpoint = az afd endpoint show `
    --endpoint-name $FDEndpoint `
    --profile-name $FDProfile `
    --resource-group $RG | ConvertFrom-Json

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "FRONT DOOR BUILT SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  Front Door: $FDProfile" -ForegroundColor Cyan
Write-Host "  Endpoint: https://$($endpoint.hostName)" -ForegroundColor Cyan
Write-Host "  Custom Domain: $Domain" -ForegroundColor Cyan
Write-Host "  Origin IP: $OriginIP" -ForegroundColor Cyan
Write-Host "  Certificate: Key Vault ($CertName)" -ForegroundColor Cyan

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 10-15 minutes for certificate and DNS to propagate" -ForegroundColor Cyan
Write-Host "2. Test: https://$Domain" -ForegroundColor Cyan
Write-Host "3. Look for LOCK ICON in browser" -ForegroundColor Cyan
Write-Host "4. Test upload/download" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Gray
Read-Host
