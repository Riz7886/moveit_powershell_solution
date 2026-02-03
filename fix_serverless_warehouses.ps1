$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "DATABRICKS SERVERLESS SQL WAREHOUSE AUTO-FIX" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

# ---------------------------------------------------------------
# STEP 1: Check Azure CLI
# ---------------------------------------------------------------
Write-Host "[1/8] Checking Azure CLI..." -ForegroundColor Yellow

try {
    $azVersion = az version 2>$null | ConvertFrom-Json
    Write-Host "  Azure CLI found." -ForegroundColor Green
}
catch {
    Write-Host "  FAILED: Azure CLI is not installed." -ForegroundColor Red
    Write-Host "  Install it from https://aka.ms/install-azure-cli"
    exit 1
}

# ---------------------------------------------------------------
# STEP 2: Check Azure login
# ---------------------------------------------------------------
Write-Host "[2/8] Checking Azure login..." -ForegroundColor Yellow

$accountRaw = az account show 2>$null
if (-not $accountRaw) {
    Write-Host "  Not logged in. Opening Azure login..." -ForegroundColor Yellow
    az login
    $accountRaw = az account show 2>$null
}

$account = $accountRaw | ConvertFrom-Json
$subName = $account.name
$subId = $account.id
$subState = $account.state

Write-Host "  Subscription: $subName" -ForegroundColor Green
Write-Host "  ID: $subId"
Write-Host "  State: $subState"

if ($subState -ne "Enabled") {
    Write-Host "  FAILED: Subscription state is $subState. It must be Enabled." -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------
# STEP 3: Find Databricks workspaces
# ---------------------------------------------------------------
Write-Host "[3/8] Finding Databricks workspaces in this subscription..." -ForegroundColor Yellow

$wsListRaw = az databricks workspace list -o json 2>$null
if (-not $wsListRaw) {
    Write-Host "  FAILED: Could not list Databricks workspaces." -ForegroundColor Red
    Write-Host "  Make sure Microsoft.Databricks provider is registered."
    Write-Host "  Run: az provider register --namespace Microsoft.Databricks"
    exit 1
}

$wsList = $wsListRaw | ConvertFrom-Json

if ($wsList.Count -eq 0) {
    Write-Host "  FAILED: No Databricks workspaces found." -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($wsList.Count) workspace(s):" -ForegroundColor Green
Write-Host ""

for ($i = 0; $i -lt $wsList.Count; $i++) {
    $ws = $wsList[$i]
    $wsNum = $i + 1
    Write-Host "  [$wsNum] $($ws.name)"
    Write-Host "      SKU: $($ws.sku.name)"
    Write-Host "      URL: $($ws.workspaceUrl)"
    Write-Host "      Resource Group: $($ws.resourceGroup)"
    Write-Host "      State: $($ws.provisioningState)"
    Write-Host ""
}

if ($wsList.Count -eq 1) {
    $wsIndex = 0
    Write-Host "  Auto-selecting the only workspace." -ForegroundColor Green
}
else {
    $wsNum = Read-Host "  Enter workspace number to fix [1-$($wsList.Count)]"
    $wsIndex = [int]$wsNum - 1
}
Write-Host ""

$selectedWs = $wsList[$wsIndex]
$wsName = $selectedWs.name
$wsSku = $selectedWs.sku.name
$wsRg = $selectedWs.resourceGroup
$wsUrl = $selectedWs.workspaceUrl
$wsHost = "https://$wsUrl"

# ---------------------------------------------------------------
# STEP 4: Check SKU
# ---------------------------------------------------------------
Write-Host "[4/8] Checking workspace SKU..." -ForegroundColor Yellow
Write-Host "  Workspace: $wsName"
Write-Host "  Current SKU: $wsSku"

$skuUpgraded = $false

if ($wsSku -eq "standard") {
    Write-Host ""
    Write-Host "  PROBLEM FOUND: SKU is Standard. Serverless requires Premium." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Upgrading workspace SKU from Standard to Premium..." -ForegroundColor Yellow

    try {
        az databricks workspace update --resource-group $wsRg --name $wsName --sku premium -o none 2>$null
        Write-Host "  SKU upgraded to Premium successfully." -ForegroundColor Green
        $skuUpgraded = $true
    }
    catch {
        Write-Host "  WARNING: SKU upgrade failed. You may not have permission." -ForegroundColor Yellow
        Write-Host "  Continuing with warehouse type conversion instead."
    }
}
elseif ($wsSku -eq "premium" -or $wsSku -eq "trial") {
    Write-Host "  SKU is $wsSku. This supports serverless." -ForegroundColor Green
    Write-Host "  Issue is HIPAA/HITRUST compliance blocking serverless (expected)."
}
else {
    Write-Host "  SKU is $wsSku. Unknown tier." -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------------
# STEP 5: Get Databricks API token
# ---------------------------------------------------------------
Write-Host "[5/8] Getting Databricks API token via Azure CLI..." -ForegroundColor Yellow

$dbResourceId = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"

try {
    $token = az account get-access-token --resource $dbResourceId --query accessToken -o tsv 2>$null
    if (-not $token) { throw "Empty token" }
    Write-Host "  Token obtained." -ForegroundColor Green
}
catch {
    Write-Host "  Could not get token automatically." -ForegroundColor Yellow
    $token = Read-Host "  Enter Databricks Personal Access Token (dapi...)"
}
Write-Host ""

# ---------------------------------------------------------------
# STEP 6: List SQL warehouses
# ---------------------------------------------------------------
Write-Host "[6/8] Listing SQL warehouses..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

try {
    $whResponse = Invoke-RestMethod -Uri "$wsHost/api/2.0/sql/warehouses" -Headers $headers -Method Get
}
catch {
    Write-Host "  FAILED: Could not connect to Databricks SQL API at $wsHost" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)"
    exit 1
}

$warehouses = $whResponse.warehouses

if (-not $warehouses -or $warehouses.Count -eq 0) {
    Write-Host "  No SQL warehouses found." -ForegroundColor Yellow
    exit 0
}

Write-Host "  Found $($warehouses.Count) warehouse(s):" -ForegroundColor Green
Write-Host ""
Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}" -f "Name", "Size", "Type", "State")
Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}" -f "-------------------------", "------------", "--------------", "------------")

$brokenWarehouses = @()

foreach ($wh in $warehouses) {
    $whName = $wh.name
    $whSize = $wh.cluster_size
    $whType = $wh.warehouse_type
    $whState = $wh.state
    $isServerless = ($whType -eq "TYPE_SERVERLESS") -or ($wh.enable_serverless_compute -eq $true)

    if ($isServerless) {
        $typeLabel = "SERVERLESS"
        $flag = " << BROKEN"
        $brokenWarehouses += $wh
    }
    else {
        $typeLabel = $whType -replace "TYPE_", ""
        $flag = ""
    }

    $color = if ($isServerless) { "Red" } else { "White" }
    Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}{4}" -f $whName, $whSize, $typeLabel, $whState, $flag) -ForegroundColor $color
}

Write-Host ""

# ---------------------------------------------------------------
# STEP 7: Fix broken warehouses
# ---------------------------------------------------------------
if ($brokenWarehouses.Count -eq 0) {
    Write-Host "  No serverless warehouses found. Nothing to fix." -ForegroundColor Green
    Write-Host ""
    Write-Host "DONE. All warehouses are already using Classic or Pro type." -ForegroundColor Green
    exit 0
}

Write-Host "[7/8] Converting $($brokenWarehouses.Count) serverless warehouse(s) to Pro type..." -ForegroundColor Yellow
Write-Host "  This ONLY changes the type. All other settings stay the same." -ForegroundColor Yellow
Write-Host ""

$fixed = 0
$failed = 0

foreach ($wh in $brokenWarehouses) {
    $whId = $wh.id
    $whName = $wh.name

    try {
        $currentWh = Invoke-RestMethod -Uri "$wsHost/api/2.0/sql/warehouses/$whId" -Headers $headers -Method Get
    }
    catch {
        Write-Host "  FAILED: Could not read warehouse $whName ($whId)" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)"
        $failed++
        continue
    }

    $editPayload = @{
        id                        = $whId
        name                      = $currentWh.name
        cluster_size              = $currentWh.cluster_size
        warehouse_type            = "PRO"
        enable_serverless_compute = $false
    }

    if ($currentWh.auto_stop_mins) { $editPayload.auto_stop_mins = $currentWh.auto_stop_mins }
    if ($currentWh.min_num_clusters) { $editPayload.min_num_clusters = $currentWh.min_num_clusters }
    if ($currentWh.max_num_clusters) { $editPayload.max_num_clusters = $currentWh.max_num_clusters }
    if ($currentWh.spot_instance_policy) { $editPayload.spot_instance_policy = $currentWh.spot_instance_policy }
    if ($currentWh.tags) { $editPayload.tags = $currentWh.tags }
    if ($currentWh.channel) { $editPayload.channel = $currentWh.channel }

    $editJson = $editPayload | ConvertTo-Json -Depth 10

    try {
        $result = Invoke-RestMethod -Uri "$wsHost/api/2.0/sql/warehouses/$whId/edit" -Headers $headers -Method Post -Body $editJson
        Write-Host "  FIXED: $whName" -ForegroundColor Green
        Write-Host "    ID: $whId"
        Write-Host "    Changed: warehouse_type -> PRO, enable_serverless_compute -> false"
        Write-Host "    Kept: name, size, auto_stop, clusters, tags (all unchanged)"
        $fixed++
    }
    catch {
        $errMsg = $_.Exception.Message
        try {
            $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
            $errMsg = $errBody.message
        }
        catch {}
        Write-Host "  FAILED: $whName" -ForegroundColor Red
        Write-Host "    ID: $whId"
        Write-Host "    Error: $errMsg"
        $failed++
    }
    Write-Host ""
}

# ---------------------------------------------------------------
# STEP 8: Verify
# ---------------------------------------------------------------
Write-Host "[8/8] Verifying fix..." -ForegroundColor Yellow
Write-Host ""

try {
    $verifyResponse = Invoke-RestMethod -Uri "$wsHost/api/2.0/sql/warehouses" -Headers $headers -Method Get
    $verifyWarehouses = $verifyResponse.warehouses

    Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}" -f "Name", "Size", "Type", "State")
    Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}" -f "-------------------------", "------------", "--------------", "------------")

    $stillBroken = 0
    foreach ($wh in $verifyWarehouses) {
        $isServerless = ($wh.warehouse_type -eq "TYPE_SERVERLESS") -or ($wh.enable_serverless_compute -eq $true)
        $typeLabel = if ($isServerless) { "SERVERLESS"; $stillBroken++ } else { $wh.warehouse_type -replace "TYPE_", "" }
        $color = if ($isServerless) { "Red" } else { "Green" }
        Write-Host ("  {0,-25} {1,-12} {2,-14} {3,-12}" -f $wh.name, $wh.cluster_size, $typeLabel, $wh.state) -ForegroundColor $color
    }

    Write-Host ""
    if ($stillBroken -eq 0) {
        Write-Host "  VERIFIED: All warehouses are now using Classic or Pro type." -ForegroundColor Green
        Write-Host "  No serverless warehouses remain." -ForegroundColor Green
    }
    else {
        Write-Host "  WARNING: $stillBroken serverless warehouse(s) still remain." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Could not verify. Check the Databricks UI manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Subscription: $subName"
Write-Host "  Workspace: $wsName"
if ($skuUpgraded) {
    Write-Host "  SKU: Standard -> Premium (upgraded)" -ForegroundColor Green
}
else {
    Write-Host "  SKU: $wsSku"
}
Write-Host "  Warehouses fixed: $fixed" -ForegroundColor Green
Write-Host "  Warehouses failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""
if ($fixed -gt 0 -and $failed -eq 0) {
    Write-Host "SUCCESS: All serverless warehouses have been converted to Pro." -ForegroundColor Green
    Write-Host "You can now start them from the Databricks SQL Warehouses page." -ForegroundColor Green
    Write-Host "No other settings were changed." -ForegroundColor Green
}
elseif ($failed -gt 0) {
    Write-Host "PARTIAL: $fixed fixed, $failed failed." -ForegroundColor Yellow
    Write-Host "For failed warehouses, check permissions or fix from the Databricks UI."
}
Write-Host ""
Write-Host "Completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""
