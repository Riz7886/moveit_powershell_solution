# NUCLEAR-REBUILD-COMPLETE.ps1
# DELETES EVERYTHING and REBUILDS FROM SCRATCH

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "NUCLEAR OPTION - DELETE AND REBUILD ALL" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

# CONFIGURATION
$RG = "rg-moveit"
$FDProfile = "moveit-frontdoor-profile"
$Location = "westus"
$OriginIP = "20.86.24.141"
$Domain = "moveit.pyxhealth.com"
$KeyVault = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

Write-Host "This will DELETE and RECREATE everything!" -ForegroundColor Yellow
Write-Host "Type YES to continue: " -NoNewline
$confirm = Read-Host

if ($confirm -ne "YES") {
    Write-Host "Cancelled" -ForegroundColor Gray
    exit
}

# Login
Write-Host "`n[STEP 1] Logging in to Azure..." -ForegroundColor Yellow
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login
}

$account = az account show | ConvertFrom-Json
Write-Host "  [OK] Logged in: $($account.user.name)" -ForegroundColor Green

# Find subscription
Write-Host "`n[STEP 2] Finding subscription..." -ForegroundColor Yellow
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
    Read-Host "Press ENTER"
    exit
}

# DELETE ENTIRE FRONT DOOR PROFILE
Write-Host "`n[STEP 3] DELETING Front Door profile..." -ForegroundColor Yellow
Write-Host "  This may take 5 minutes..." -ForegroundColor Cyan

az afd profile delete --profile-name $FDProfile --resource-group $RG --yes 2>$null

Write-Host "  Waiting for deletion..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

# Verify deleted
$profile = az afd profile show --profile-name $FDProfile --resource-group $RG 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [OK] Profile deleted!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Profile may still exist, continuing anyway..." -ForegroundColor Yellow
}

# CREATE NEW PROFILE
Write-Host "`n[STEP 4] Creating NEW Front Door profile..." -ForegroundColor Yellow
az afd profile create `
    --profile-name $FDProfile `
    --resource-group $RG `
    --sku Premium_AzureFrontDoor

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Profile created!" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Profile creation failed!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit
}

# CREATE ENDPOINT
Write-Host "`n[STEP 5] Creating endpoint..." -ForegroundColor Yellow
$endpointName = "moveit-ep-$(Get-Random -Minimum 1000 -Maximum 9999)"

az afd endpoint create `
    --endpoint-name $endpointName `
    --profile-name $FDProfile `
    --resource-group $RG `
    --enabled-state Enabled

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Endpoint created: $endpointName" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Endpoint creation failed!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit
}

# GET ENDPOINT DETAILS
$endpoint = az afd endpoint show `
    --endpoint-name $endpointName `
    --profile-name $FDProfile `
    --resource-group $RG | ConvertFrom-Json

Write-Host "  Endpoint URL: https://$($endpoint.hostName)" -ForegroundColor Cyan

# CREATE ORIGIN GROUP
Write-Host "`n[STEP 6] Creating origin group..." -ForegroundColor Yellow
az afd origin-group create `
    --origin-group-name moveit-origin-group `
    --profile-name $FDProfile `
    --resource-group $RG `
    --probe-request-type GET `
    --probe-protocol Https `
    --probe-interval-in-seconds 240 `
    --probe-path / `
    --sample-size 4 `
    --successful-samples-required 3 `
    --additional-latency-in-milliseconds 50

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Origin group created!" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Origin group creation failed!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit
}

# CREATE ORIGIN
Write-Host "`n[STEP 7] Creating origin with IP $OriginIP..." -ForegroundColor Yellow
az afd origin create `
    --origin-name moveit-backend `
    --origin-group-name moveit-origin-group `
    --profile-name $FDProfile `
    --resource-group $RG `
    --host-name $OriginIP `
    --origin-host-header $OriginIP `
    --http-port 80 `
    --https-port 443 `
    --priority 1 `
    --weight 1000 `
    --enabled-state Enabled

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Origin created with IP $OriginIP!" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Origin creation failed!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit
}

# GET KEY VAULT CERT
Write-Host "`n[STEP 8] Getting Key Vault certificate..." -ForegroundColor Yellow
$kv = az keyvault show --name $KeyVault --resource-group $RG | ConvertFrom-Json
$kvId = $kv.id
$certId = "$kvId/secrets/$CertName"
Write-Host "  [OK] Certificate ID: $certId" -ForegroundColor Green

# GRANT FRONT DOOR ACCESS
Write-Host "`n[STEP 9] Granting Front Door access to Key Vault..." -ForegroundColor Yellow
$fdAppId = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8"
az keyvault set-policy `
    --name $KeyVault `
    --spn $fdAppId `
    --secret-permissions get `
    --certificate-permissions get

Write-Host "  [OK] Access granted!" -ForegroundColor Green

# CREATE CUSTOM DOMAIN
Write-Host "`n[STEP 10] Creating custom domain with Key Vault cert..." -ForegroundColor Yellow
az afd custom-domain create `
    --custom-domain-name moveit-pyxhealth-com `
    --profile-name $FDProfile `
    --resource-group $RG `
    --host-name $Domain `
    --minimum-tls-version TLS12 `
    --certificate-type CustomerCertificate `
    --secret $certId

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Custom domain created!" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Custom domain creation failed!" -ForegroundColor Red
    Read-Host "Press ENTER"
    exit
}

# GET DOMAIN AND ORIGIN GROUP IDs
Start-Sleep -Seconds 10

$domain = az afd custom-domain show `
    --custom-domain-name moveit-pyxhealth-com `
    --profile-name $FDProfile `
    --resource-group $RG | ConvertFrom-Json

$originGroup = az afd origin-group show `
    --origin-group-name moveit-origin-group `
    --profile-name $FDProfile `
    --resource-group $RG | ConvertFrom-Json

# CREATE ROUTE WITH DOMAIN
Write-Host "`n[STEP 11] Creating route with custom domain..." -ForegroundColor Yellow
az afd route create `
    --route-name moveit-route `
    --endpoint-name $endpointName `
    --profile-name $FDProfile `
    --resource-group $RG `
    --forwarding-protocol HttpsOnly `
    --https-redirect Enabled `
    --origin-group $originGroup.id `
    --supported-protocols Https `
    --link-to-default-domain Enabled `
    --enabled-state Enabled `
    --custom-domains $domain.id

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Route created with custom domain!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Route creation may have failed!" -ForegroundColor Yellow
}

# OPEN NSG PORT 443
Write-Host "`n[STEP 12] Opening port 443 on NSGs..." -ForegroundColor Yellow
$nsgs = az network nsg list --resource-group $RG | ConvertFrom-Json

foreach ($nsg in $nsgs) {
    Write-Host "  Checking: $($nsg.name)" -ForegroundColor Cyan
    
    $hasRule = $false
    foreach ($rule in $nsg.securityRules) {
        if ($rule.destinationPortRange -eq "443" -and $rule.access -eq "Allow" -and $rule.direction -eq "Inbound") {
            $hasRule = $true
            break
        }
    }
    
    if (-not $hasRule) {
        Write-Host "    Adding rule..." -ForegroundColor Yellow
        az network nsg rule create `
            --nsg-name $nsg.name `
            --resource-group $RG `
            --name Allow-HTTPS-443 `
            --priority 100 `
            --access Allow `
            --protocol Tcp `
            --direction Inbound `
            --source-address-prefixes Internet `
            --source-port-ranges "*" `
            --destination-address-prefixes "*" `
            --destination-port-ranges 443 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Port 443 opened" -ForegroundColor Green
        }
    } else {
        Write-Host "    [OK] Port 443 already open" -ForegroundColor Green
    }
}

# FINAL SUMMARY
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "REBUILD COMPLETE!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "NEW CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  Front Door: $FDProfile" -ForegroundColor Cyan
Write-Host "  Endpoint: $endpointName" -ForegroundColor Cyan
Write-Host "  Endpoint URL: https://$($endpoint.hostName)" -ForegroundColor Cyan
Write-Host "  Custom Domain: $Domain" -ForegroundColor Cyan
Write-Host "  Origin IP: $OriginIP" -ForegroundColor Cyan
Write-Host "  Certificate: Key Vault ($CertName)" -ForegroundColor Cyan

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 15-20 minutes for everything to propagate" -ForegroundColor Cyan
Write-Host "2. Test: https://$Domain" -ForegroundColor Cyan
Write-Host "3. Look for LOCK ICON in browser" -ForegroundColor Cyan
Write-Host "4. Test upload/download" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Gray
Read-Host
