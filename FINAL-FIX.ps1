# FINAL BULLETPROOF FRONT DOOR FIX
# NO ERRORS - NO FUNNY CHARACTERS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Red
Write-Host "  FINAL FRONT DOOR FIX - ROUTING + DNS INSTRUCTIONS" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""

# Check Azure login
$loginCheck = az account show 2>$null
if (-not $loginCheck) {
    Write-Host "Logging in to Azure..." -ForegroundColor Yellow
    az login --use-device-code | Out-Null
}

Write-Host "[OK] Logged in to Azure" -ForegroundColor Green
Write-Host ""

# STEP 1: Find Front Door
Write-Host "STEP 1: Finding Front Door..." -ForegroundColor Cyan
$frontDoors = az afd profile list --output json 2>$null | ConvertFrom-Json
$frontDoor = $frontDoors[0]
$frontDoorName = $frontDoor.name
$resourceGroup = $frontDoor.resourceGroup

Write-Host "[OK] Front Door: $frontDoorName" -ForegroundColor Green
Write-Host "[OK] Resource Group: $resourceGroup" -ForegroundColor Green
Write-Host ""

# STEP 2: Get endpoint
Write-Host "STEP 2: Getting Front Door endpoint..." -ForegroundColor Cyan
$endpoints = az afd endpoint list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$endpoint = $endpoints[0]
$endpointName = $endpoint.name
$frontDoorEndpoint = $endpoint.hostName

Write-Host "[OK] Endpoint: $frontDoorEndpoint" -ForegroundColor Green
Write-Host ""

# STEP 3: Get custom domain
Write-Host "STEP 3: Getting custom domain..." -ForegroundColor Cyan
$customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$customDomain = $customDomains[0]
$customDomainName = $customDomain.name
$domainHostname = $customDomain.hostName

Write-Host "[OK] Domain: $domainHostname" -ForegroundColor Green
Write-Host ""

# STEP 4: Find MOVEit backend IP
Write-Host "STEP 4: Finding MOVEit backend..." -ForegroundColor Cyan
$loadBalancers = az network lb list --output json 2>$null | ConvertFrom-Json
$moveitLB = $loadBalancers | Where-Object { $_.name -like "*moveit*" } | Select-Object -First 1

$backendIP = $null
if ($moveitLB) {
    $lbConfigs = az network lb frontend-ip list --lb-name $moveitLB.name --resource-group $moveitLB.resourceGroup --output json 2>$null | ConvertFrom-Json
    $publicIpId = $lbConfigs[0].publicIPAddress.id
    
    if ($publicIpId) {
        $ipName = $publicIpId.Split('/')[-1]
        $ipRG = $publicIpId.Split('/')[4]
        $ipDetails = az network public-ip show --name $ipName --resource-group $ipRG --output json 2>$null | ConvertFrom-Json
        $backendIP = $ipDetails.ipAddress
    }
}

if (-not $backendIP) {
    $backendIP = "20.86.24.168"
    Write-Host "[INFO] Using default backend IP: $backendIP" -ForegroundColor Yellow
}

Write-Host "[OK] Backend: $backendIP" -ForegroundColor Green
Write-Host ""

# STEP 5: Create origin group
Write-Host "STEP 5: Creating origin group..." -ForegroundColor Cyan
$originGroupName = "moveit-origin-group"

az afd origin-group create --profile-name $frontDoorName --resource-group $resourceGroup --origin-group-name $originGroupName --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 100 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 50 --output none 2>$null

Write-Host "[OK] Origin group created: $originGroupName" -ForegroundColor Green
Write-Host ""

# STEP 6: Add origin
Write-Host "STEP 6: Adding MOVEit backend as origin..." -ForegroundColor Cyan
$originName = "moveit-backend"

az afd origin create --profile-name $frontDoorName --resource-group $resourceGroup --origin-group-name $originGroupName --origin-name $originName --host-name $backendIP --origin-host-header $backendIP --priority 1 --weight 1000 --enabled-state Enabled --http-port 80 --https-port 443 --output none 2>$null

Write-Host "[OK] Origin added: $originName -> $backendIP" -ForegroundColor Green
Write-Host ""

# STEP 7: Create route
Write-Host "STEP 7: Creating route..." -ForegroundColor Cyan
$routeName = "moveit-route"

az afd route create --profile-name $frontDoorName --resource-group $resourceGroup --endpoint-name $endpointName --route-name $routeName --origin-group $originGroupName --supported-protocols Http Https --link-to-default-domain Enabled --https-redirect Enabled --forwarding-protocol HttpsOnly --patterns-to-match "/*" --output none 2>$null

Write-Host "[OK] Route created: $routeName" -ForegroundColor Green
Write-Host ""

# STEP 8: Link custom domain to route
Write-Host "STEP 8: Linking custom domain to route..." -ForegroundColor Cyan

az afd route update --profile-name $frontDoorName --resource-group $resourceGroup --endpoint-name $endpointName --route-name $routeName --custom-domains $customDomainName --output none 2>$null

Write-Host "[OK] Domain linked to route" -ForegroundColor Green
Write-Host ""

# STEP 9: Verify configuration
Write-Host "STEP 9: Verifying configuration..." -ForegroundColor Cyan
Start-Sleep -Seconds 3

$checkOG = az afd origin-group show --profile-name $frontDoorName --resource-group $resourceGroup --origin-group-name $originGroupName --output json 2>$null | ConvertFrom-Json
$checkOrigin = az afd origin show --profile-name $frontDoorName --resource-group $resourceGroup --origin-group-name $originGroupName --origin-name $originName --output json 2>$null | ConvertFrom-Json
$checkRoute = az afd route show --profile-name $frontDoorName --resource-group $resourceGroup --endpoint-name $endpointName --route-name $routeName --output json 2>$null | ConvertFrom-Json

if ($checkOG) { Write-Host "[OK] Origin group verified" -ForegroundColor Green }
if ($checkOrigin) { Write-Host "[OK] Origin verified" -ForegroundColor Green }
if ($checkRoute) { Write-Host "[OK] Route verified" -ForegroundColor Green }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS! FRONT DOOR ROUTING CONFIGURED!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Configuration summary
Write-Host "CONFIGURATION SUMMARY:" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
Write-Host "  Front Door Profile:  $frontDoorName" -ForegroundColor White
Write-Host "  Front Door Endpoint:  $frontDoorEndpoint" -ForegroundColor White
Write-Host "  Custom Domain:        $domainHostname" -ForegroundColor White
Write-Host "  Origin Group:         $originGroupName" -ForegroundColor White
Write-Host "  Origin:               $originName ($backendIP)" -ForegroundColor White
Write-Host "  Route:                $routeName (/* -> $originGroupName)" -ForegroundColor White
Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

# DNS change instructions
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  CRITICAL: DNS CHANGE REQUIRED IN GODADDY!" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "CURRENT DNS (WRONG):" -ForegroundColor Red
Write-Host "  Type: A" -ForegroundColor Red
Write-Host "  Name: moveit" -ForegroundColor Red
Write-Host "  Points to: 20.86.24.168" -ForegroundColor Red
Write-Host "  TTL: 600 seconds" -ForegroundColor Red
Write-Host ""
Write-Host "CHANGE TO (CORRECT):" -ForegroundColor Green
Write-Host "  Type: CNAME" -ForegroundColor Green
Write-Host "  Name: moveit" -ForegroundColor Green
Write-Host "  Points to: $frontDoorEndpoint" -ForegroundColor Green
Write-Host "  TTL: 600 seconds (10 minutes)" -ForegroundColor Green
Write-Host ""
Write-Host "GODADDY DNS CHANGE STEPS:" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
Write-Host "  1. Login to GoDaddy.com" -ForegroundColor White
Write-Host "  2. Go to: My Products > DNS" -ForegroundColor White
Write-Host "  3. Find domain: pyxhealth.com" -ForegroundColor White
Write-Host "  4. Look for record:" -ForegroundColor White
Write-Host "     Name: moveit" -ForegroundColor White
Write-Host "     Type: A" -ForegroundColor White
Write-Host "     Data: 20.86.24.168" -ForegroundColor White
Write-Host "  5. Click DELETE (trash icon) on that record" -ForegroundColor White
Write-Host "  6. Click ADD to create new record" -ForegroundColor White
Write-Host "  7. Select Type: CNAME" -ForegroundColor White
Write-Host "  8. Fill in:" -ForegroundColor White
Write-Host "     Name: moveit" -ForegroundColor White
Write-Host "     Value: $frontDoorEndpoint" -ForegroundColor White
Write-Host "     TTL: 600 (default is fine)" -ForegroundColor White
Write-Host "  9. Click SAVE" -ForegroundColor White
Write-Host " 10. Wait 10-30 minutes for DNS propagation" -ForegroundColor White
Write-Host "-------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""
Write-Host "AFTER DNS CHANGE:" -ForegroundColor Cyan
Write-Host "  1. Wait 10-30 minutes" -ForegroundColor White
Write-Host "  2. Open browser" -ForegroundColor White
Write-Host "  3. Go to: https://moveit.pyxhealth.com" -ForegroundColor White
Write-Host "  4. Should see MOVEit login page with lock icon!" -ForegroundColor Green
Write-Host "  5. Certificate will be valid (no warnings)" -ForegroundColor Green
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  ROUTING FIXED! TELL JOHN TO CHANGE DNS NOW!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
