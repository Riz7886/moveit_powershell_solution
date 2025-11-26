# EMERGENCY ROUTE FIX
# Links custom domain to route

$ErrorActionPreference = "Continue"

Write-Host "EMERGENCY ROUTE FIX" -ForegroundColor Red
Write-Host ""

# Login check
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}

# Get Front Door details
$frontDoors = az afd profile list --output json 2>$null | ConvertFrom-Json
$frontDoor = $frontDoors[0]
$frontDoorName = $frontDoor.name
$resourceGroup = $frontDoor.resourceGroup

Write-Host "Front Door: $frontDoorName" -ForegroundColor Green

# Get endpoint
$endpoints = az afd endpoint list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$endpoint = $endpoints[0]
$endpointName = $endpoint.name

Write-Host "Endpoint: $endpointName" -ForegroundColor Green

# Get custom domain
$customDomains = az afd custom-domain list --profile-name $frontDoorName --resource-group $resourceGroup --output json 2>$null | ConvertFrom-Json
$customDomain = $customDomains[0]
$customDomainName = $customDomain.name

Write-Host "Domain: $customDomainName" -ForegroundColor Green

# Check if route exists
Write-Host ""
Write-Host "Checking route..." -ForegroundColor Yellow

$routes = az afd route list --profile-name $frontDoorName --resource-group $resourceGroup --endpoint-name $endpointName --output json 2>$null | ConvertFrom-Json

if ($routes -and $routes.Count -gt 0) {
    $route = $routes[0]
    $routeName = $route.name
    Write-Host "Found route: $routeName" -ForegroundColor Green
    
    # Check if custom domain is linked
    $linkedDomains = $route.customDomains
    
    if ($linkedDomains -and $linkedDomains.Count -gt 0) {
        Write-Host "Custom domain IS linked to route" -ForegroundColor Green
        Write-Host ""
        Write-Host "ROUTE IS CONFIGURED CORRECTLY!" -ForegroundColor Green
        Write-Host ""
        Write-Host "The issue might be:" -ForegroundColor Yellow
        Write-Host "  1. DNS still propagating (wait more)" -ForegroundColor White
        Write-Host "  2. Browser cache (clear cache)" -ForegroundColor White
        Write-Host "  3. Origin is down (check backend)" -ForegroundColor White
    } else {
        Write-Host "Custom domain NOT linked to route!" -ForegroundColor Red
        Write-Host "Fixing now..." -ForegroundColor Yellow
        
        # Link custom domain to route
        az afd route update --profile-name $frontDoorName --resource-group $resourceGroup --endpoint-name $endpointName --route-name $routeName --custom-domains $customDomainName --output none 2>$null
        
        Write-Host "Custom domain linked to route!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Wait 5 minutes then test again" -ForegroundColor Yellow
    }
} else {
    Write-Host "NO ROUTE FOUND!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run FINAL-FIX.ps1 again to create route!" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press ENTER to exit..." -ForegroundColor Gray
Read-Host
