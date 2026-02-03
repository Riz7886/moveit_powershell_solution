$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS SERVICE ACCOUNT SETUP" -ForegroundColor Cyan
Write-Host "  Fully Automated - Creates SP, Adds to All Workspaces" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

$spName = "databricks-service-principal"
$dbResource = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
$reportData = @{
    date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    spName = $spName
    appId = ""
    objectId = ""
    tenantId = ""
    secretName = ""
    secretValue = ""
    secretExpiry = ""
    subscription = ""
    subscriptionId = ""
    workspaces = @()
    errors = @()
}

# ---------------------------------------------------------------
# STEP 1: Azure Login
# ---------------------------------------------------------------
Write-Host "[1/7] Checking Azure login..." -ForegroundColor Yellow

try {
    $acct = az account show 2>$null | ConvertFrom-Json
    if (-not $acct) { throw "not logged in" }
    Write-Host "  Logged in as: $($acct.user.name)" -ForegroundColor Green
    Write-Host "  Subscription: $($acct.name)" -ForegroundColor Green
    Write-Host "  Tenant: $($acct.tenantId)" -ForegroundColor Green
    $reportData.subscription = $acct.name
    $reportData.subscriptionId = $acct.id
    $reportData.tenantId = $acct.tenantId
}
catch {
    Write-Host "  Not logged in. Opening browser..." -ForegroundColor Yellow
    az login | Out-Null
    $acct = az account show | ConvertFrom-Json
    Write-Host "  Logged in as: $($acct.user.name)" -ForegroundColor Green
    $reportData.subscription = $acct.name
    $reportData.subscriptionId = $acct.id
    $reportData.tenantId = $acct.tenantId
}
Write-Host ""

# ---------------------------------------------------------------
# STEP 2: Create Azure AD App Registration
# ---------------------------------------------------------------
Write-Host "[2/7] Creating Azure AD App Registration..." -ForegroundColor Yellow

$existingApp = az ad app list --display-name $spName -o json 2>$null | ConvertFrom-Json

if ($existingApp -and $existingApp.Count -gt 0) {
    Write-Host "  App '$spName' already exists. Using existing." -ForegroundColor Yellow
    $appId = $existingApp[0].appId
    $appObjectId = $existingApp[0].id
    Write-Host "  App ID: $appId" -ForegroundColor Green
}
else {
    Write-Host "  Creating new app registration: $spName" -ForegroundColor Yellow
    $newApp = az ad app create --display-name $spName -o json 2>$null | ConvertFrom-Json
    $appId = $newApp.appId
    $appObjectId = $newApp.id
    Write-Host "  Created App ID: $appId" -ForegroundColor Green
}

$reportData.appId = $appId
Write-Host ""

# ---------------------------------------------------------------
# STEP 3: Create Service Principal for the App
# ---------------------------------------------------------------
Write-Host "[3/7] Creating Service Principal..." -ForegroundColor Yellow

$existingSp = az ad sp list --filter "appId eq '$appId'" -o json 2>$null | ConvertFrom-Json

if ($existingSp -and $existingSp.Count -gt 0) {
    Write-Host "  Service Principal already exists. Using existing." -ForegroundColor Yellow
    $spObjectId = $existingSp[0].id
}
else {
    Write-Host "  Creating service principal..." -ForegroundColor Yellow
    $newSp = az ad sp create --id $appId -o json 2>$null | ConvertFrom-Json
    $spObjectId = $newSp.id
    Write-Host "  Created." -ForegroundColor Green
}

$reportData.objectId = $spObjectId
Write-Host "  SP Object ID: $spObjectId" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------
# STEP 4: Create Client Secret
# ---------------------------------------------------------------
Write-Host "[4/7] Creating client secret..." -ForegroundColor Yellow

$secretName = "databricks-auto-$(Get-Date -Format 'yyyyMMdd')"
$secret = az ad app credential reset --id $appId --display-name $secretName --years 1 -o json 2>$null | ConvertFrom-Json

if ($secret) {
    $reportData.secretValue = $secret.password
    $reportData.secretName = $secretName
    $reportData.secretExpiry = (Get-Date).AddYears(1).ToString("yyyy-MM-dd")
    Write-Host "  Secret created: $secretName" -ForegroundColor Green
    Write-Host "  Expires: $($reportData.secretExpiry)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  *** SAVE THIS - YOU WILL NOT SEE IT AGAIN ***" -ForegroundColor Red
    Write-Host "  Client Secret: $($secret.password)" -ForegroundColor Red
    Write-Host ""
}
else {
    Write-Host "  WARNING: Could not create secret. You may need to create one manually." -ForegroundColor Yellow
    $reportData.errors += "Could not create client secret automatically"
}
Write-Host ""

# ---------------------------------------------------------------
# STEP 5: Assign Contributor role on Databricks workspaces
# ---------------------------------------------------------------
Write-Host "[5/7] Assigning Contributor role on Databricks resources..." -ForegroundColor Yellow

$allSubs = az account list --query "[?state=='Enabled']" -o json 2>$null | ConvertFrom-Json

foreach ($sub in $allSubs) {
    try {
        $resources = az resource list --subscription $sub.id --resource-type "Microsoft.Databricks/workspaces" -o json 2>$null | ConvertFrom-Json

        if ($resources -and $resources.Count -gt 0) {
            foreach ($r in $resources) {
                Write-Host "  Assigning Contributor on: $($r.name)..." -ForegroundColor Gray -NoNewline

                try {
                    az role assignment create --assignee $appId --role "Contributor" --scope $r.id --subscription $sub.id 2>$null | Out-Null
                    Write-Host " done" -ForegroundColor Green
                }
                catch {
                    $existingRole = az role assignment list --assignee $appId --scope $r.id --subscription $sub.id -o json 2>$null | ConvertFrom-Json
                    if ($existingRole -and $existingRole.Count -gt 0) {
                        Write-Host " already assigned" -ForegroundColor Green
                    }
                    else {
                        Write-Host " failed" -ForegroundColor Yellow
                        $reportData.errors += "Could not assign Contributor on $($r.name)"
                    }
                }
            }
        }
    }
    catch {}
}
Write-Host ""

# ---------------------------------------------------------------
# STEP 6: Add SP to each Databricks workspace via SCIM API
# ---------------------------------------------------------------
Write-Host "[6/7] Adding Service Principal to Databricks workspaces..." -ForegroundColor Yellow
Write-Host ""

$allWorkspaces = @()

foreach ($sub in $allSubs) {
    try {
        az account set --subscription $sub.id 2>$null
        $resources = az resource list --resource-type "Microsoft.Databricks/workspaces" -o json 2>$null | ConvertFrom-Json

        if ($resources -and $resources.Count -gt 0) {
            $token = (az account get-access-token --resource $dbResource --query accessToken -o tsv 2>$null)
            if ($token) { $token = $token.Trim() }

            foreach ($r in $resources) {
                try {
                    $detail = az resource show --ids $r.id -o json 2>$null | ConvertFrom-Json
                    $wsUrl = "https://$($detail.properties.workspaceUrl)"

                    $wsInfo = @{
                        name = $r.name
                        url = $wsUrl
                        subscription = $sub.name
                        sku = $detail.sku.name
                        location = $r.location
                        resourceGroup = $r.resourceGroup
                        spAdded = $false
                        spAdmin = $false
                        error = ""
                    }

                    $headers = @{
                        "Authorization" = "Bearer $token"
                        "Content-Type" = "application/json"
                    }

                    Write-Host "  Workspace: $($r.name) ($wsUrl)" -ForegroundColor White

                    # Check if SP already exists in workspace
                    try {
                        $existingScim = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId+eq+%22$appId%22" -Headers $headers -Method Get
                        if ($existingScim.Resources -and $existingScim.Resources.Count -gt 0) {
                            Write-Host "    SP already exists in workspace." -ForegroundColor Yellow
                            $wsSpId = $existingScim.Resources[0].id
                            $wsInfo.spAdded = $true
                        }
                    }
                    catch {}

                    # Add SP to workspace if not already there
                    if (-not $wsInfo.spAdded) {
                        try {
                            $scimPayload = @{
                                schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
                                applicationId = $appId
                                displayName = $spName
                                active = $true
                            } | ConvertTo-Json -Depth 5

                            $scimResult = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Headers $headers -Method Post -Body $scimPayload
                            $wsSpId = $scimResult.id
                            $wsInfo.spAdded = $true
                            Write-Host "    Added SP to workspace. Workspace SP ID: $wsSpId" -ForegroundColor Green
                        }
                        catch {
                            $errMsg = $_.Exception.Message
                            try { $errMsg = ($_.ErrorDetails.Message | ConvertFrom-Json).detail } catch {}
                            Write-Host "    Could not add SP: $errMsg" -ForegroundColor Yellow
                            $wsInfo.error = $errMsg
                        }
                    }

                    # Grant admin permissions
                    if ($wsInfo.spAdded -and $wsSpId) {
                        try {
                            # Add to admins group
                            $adminGroup = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+%22admins%22" -Headers $headers -Method Get

                            if ($adminGroup.Resources -and $adminGroup.Resources.Count -gt 0) {
                                $adminGroupId = $adminGroup.Resources[0].id

                                $patchPayload = @{
                                    schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                                    Operations = @(
                                        @{
                                            op = "add"
                                            value = @{
                                                members = @(
                                                    @{
                                                        value = $wsSpId
                                                    }
                                                )
                                            }
                                        }
                                    )
                                } | ConvertTo-Json -Depth 10

                                Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups/$adminGroupId" -Headers $headers -Method Patch -Body $patchPayload | Out-Null
                                $wsInfo.spAdmin = $true
                                Write-Host "    Granted admin access." -ForegroundColor Green
                            }
                        }
                        catch {
                            $errMsg = $_.Exception.Message
                            try { $errMsg = ($_.ErrorDetails.Message | ConvertFrom-Json).detail } catch {}
                            Write-Host "    Could not grant admin: $errMsg" -ForegroundColor Yellow
                            if (-not $wsInfo.error) { $wsInfo.error = "Admin grant failed: $errMsg" }
                        }
                    }

                    # Check SQL warehouse permissions
                    if ($wsInfo.spAdded) {
                        try {
                            $warehouses = Invoke-RestMethod -Uri "$wsUrl/api/2.0/sql/warehouses" -Headers $headers -Method Get
                            $wsInfo | Add-Member -NotePropertyName warehouseCount -NotePropertyValue $warehouses.warehouses.Count -Force
                            Write-Host "    SQL Warehouses visible: $($warehouses.warehouses.Count)" -ForegroundColor Green
                        }
                        catch {
                            $wsInfo | Add-Member -NotePropertyName warehouseCount -NotePropertyValue 0 -Force
                        }
                    }

                    $allWorkspaces += $wsInfo
                    Write-Host ""
                }
                catch {}
            }
        }
    }
    catch {}
}

$reportData.workspaces = $allWorkspaces
Write-Host ""

# ---------------------------------------------------------------
# STEP 7: Generate HTML Report
# ---------------------------------------------------------------
Write-Host "[7/7] Generating HTML report..." -ForegroundColor Yellow

$wsRows = ""
foreach ($ws in $allWorkspaces) {
    $statusColor = if ($ws.spAdded) { "#4ade80" } else { "#f87171" }
    $adminColor = if ($ws.spAdmin) { "#4ade80" } else { "#fbbf24" }
    $statusText = if ($ws.spAdded) { "Added" } else { "Failed" }
    $adminText = if ($ws.spAdmin) { "Admin" } else { "Pending" }
    $errorText = if ($ws.error) { $ws.error } else { "-" }

    $wsRows += @"
<tr>
<td>$($ws.name)</td>
<td><a href="$($ws.url)" target="_blank">$($ws.url)</a></td>
<td>$($ws.subscription)</td>
<td>$($ws.sku)</td>
<td>$($ws.location)</td>
<td style="color: $statusColor; font-weight: bold;">$statusText</td>
<td style="color: $adminColor; font-weight: bold;">$adminText</td>
<td>$errorText</td>
</tr>
"@
}

$errorsSection = ""
if ($reportData.errors.Count -gt 0) {
    $errorItems = ""
    foreach ($e in $reportData.errors) {
        $errorItems += "<li>$e</li>"
    }
    $errorsSection = @"
<div class="section">
<h2>Errors / Warnings</h2>
<ul style="color: #fbbf24;">$errorItems</ul>
</div>
"@
}

$htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Databricks Service Account Report</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f172a; color: #e2e8f0; padding: 40px; }
.container { max-width: 1200px; margin: 0 auto; }
.header { background: linear-gradient(135deg, #1e3a5f 0%, #0f172a 100%); border: 1px solid #334155; border-radius: 12px; padding: 30px; margin-bottom: 30px; text-align: center; }
.header h1 { font-size: 28px; color: #60a5fa; margin-bottom: 8px; }
.header p { color: #94a3b8; font-size: 14px; }
.section { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 24px; margin-bottom: 20px; }
.section h2 { color: #60a5fa; font-size: 20px; margin-bottom: 16px; border-bottom: 1px solid #334155; padding-bottom: 8px; }
.cred-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.cred-item { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 16px; }
.cred-item .label { font-size: 12px; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px; }
.cred-item .value { font-size: 14px; color: #f1f5f9; word-break: break-all; font-family: 'Consolas', monospace; }
.secret-box { background: #7f1d1d; border: 2px solid #dc2626; border-radius: 8px; padding: 20px; margin-top: 16px; }
.secret-box .label { color: #fca5a5; font-size: 14px; font-weight: bold; margin-bottom: 8px; }
.secret-box .value { color: #fef2f2; font-size: 16px; font-family: 'Consolas', monospace; word-break: break-all; }
.secret-box .warning { color: #fca5a5; font-size: 12px; margin-top: 8px; }
table { width: 100%; border-collapse: collapse; margin-top: 12px; }
th { background: #334155; color: #e2e8f0; padding: 12px; text-align: left; font-size: 13px; }
td { padding: 12px; border-bottom: 1px solid #334155; font-size: 13px; }
tr:hover { background: #334155; }
a { color: #60a5fa; text-decoration: none; }
a:hover { text-decoration: underline; }
.status-ok { color: #4ade80; font-weight: bold; }
.status-warn { color: #fbbf24; font-weight: bold; }
.status-fail { color: #f87171; font-weight: bold; }
.usage-section { margin-top: 16px; }
.usage-section h3 { color: #94a3b8; font-size: 14px; margin-bottom: 8px; }
code { background: #0f172a; padding: 2px 6px; border-radius: 4px; font-family: 'Consolas', monospace; font-size: 13px; color: #fbbf24; }
pre { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 16px; overflow-x: auto; font-family: 'Consolas', monospace; font-size: 13px; color: #e2e8f0; margin-top: 8px; }
.footer { text-align: center; color: #64748b; font-size: 12px; margin-top: 30px; padding: 20px; }
@media print { body { background: white; color: black; } .section { border-color: #ccc; } th { background: #eee; color: black; } .header { background: #f0f0f0; } .header h1 { color: #1e40af; } }
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>Databricks Service Account Report</h1>
<p>Auto-generated on $($reportData.date)</p>
<p>Incident: Serverless to PRO migration - Service Account Setup</p>
</div>

<div class="section">
<h2>Service Principal Details</h2>
<div class="cred-grid">
<div class="cred-item">
<div class="label">Display Name</div>
<div class="value">$($reportData.spName)</div>
</div>
<div class="cred-item">
<div class="label">Application (Client) ID</div>
<div class="value">$($reportData.appId)</div>
</div>
<div class="cred-item">
<div class="label">Object ID</div>
<div class="value">$($reportData.objectId)</div>
</div>
<div class="cred-item">
<div class="label">Tenant ID</div>
<div class="value">$($reportData.tenantId)</div>
</div>
<div class="cred-item">
<div class="label">Subscription</div>
<div class="value">$($reportData.subscription)</div>
</div>
<div class="cred-item">
<div class="label">Secret Expiry</div>
<div class="value">$($reportData.secretExpiry)</div>
</div>
</div>

<div class="secret-box">
<div class="label">CLIENT SECRET (SAVE THIS NOW)</div>
<div class="value">$($reportData.secretValue)</div>
<div class="warning">This secret will NOT be shown again. Save it in a secure vault (Azure Key Vault, etc.)</div>
</div>
</div>

<div class="section">
<h2>Workspace Access</h2>
<table>
<thead>
<tr>
<th>Workspace</th>
<th>URL</th>
<th>Subscription</th>
<th>SKU</th>
<th>Region</th>
<th>SP Status</th>
<th>Admin</th>
<th>Notes</th>
</tr>
</thead>
<tbody>
$wsRows
</tbody>
</table>
</div>

<div class="section">
<h2>How to Use This Service Principal</h2>

<div class="usage-section">
<h3>1. Databricks SQL Connection (Python)</h3>
<pre>
from databricks import sql
import os

connection = sql.connect(
    server_hostname = "adb-XXXXX.X.azuredatabricks.net",
    http_path       = "/sql/1.0/warehouses/WAREHOUSE_ID",
    access_token    = "SERVICE_PRINCIPAL_TOKEN"
)
</pre>
</div>

<div class="usage-section">
<h3>2. Get OAuth Token for Service Principal</h3>
<pre>
# PowerShell
`$body = @{
    grant_type    = "client_credentials"
    client_id     = "$($reportData.appId)"
    client_secret = "YOUR_SECRET"
    scope         = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/.default"
}
`$token = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($reportData.tenantId)/oauth2/v2.0/token" -Method Post -Body `$body
`$token.access_token
</pre>
</div>

<div class="usage-section">
<h3>3. Python OAuth Token</h3>
<pre>
import requests

token_url = "https://login.microsoftonline.com/$($reportData.tenantId)/oauth2/v2.0/token"
data = {
    "grant_type": "client_credentials",
    "client_id": "$($reportData.appId)",
    "client_secret": "YOUR_SECRET",
    "scope": "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/.default"
}
response = requests.post(token_url, data=data)
token = response.json()["access_token"]
</pre>
</div>

<div class="usage-section">
<h3>4. Store Secret Securely in Azure Key Vault</h3>
<pre>
az keyvault secret set --vault-name YOUR_VAULT --name databricks-sp-secret --value "YOUR_SECRET"
</pre>
</div>
</div>

<div class="section">
<h2>Next Steps</h2>
<table>
<thead><tr><th>#</th><th>Action</th><th>Owner</th><th>Status</th></tr></thead>
<tbody>
<tr><td>1</td><td>Save client secret to Azure Key Vault or secure password manager</td><td>Syed Rizvi</td><td class="status-warn">Pending</td></tr>
<tr><td>2</td><td>Update SQL Python connector scripts to use service principal instead of Shaun Raj's account</td><td>Syed Rizvi / Dev Team</td><td class="status-warn">Pending</td></tr>
<tr><td>3</td><td>Test connections from all warehouses using new service principal</td><td>Brian Burge / Team</td><td class="status-warn">Pending</td></tr>
<tr><td>4</td><td>Remove Shaun Raj personal account from production workloads</td><td>Admin</td><td class="status-warn">Pending</td></tr>
<tr><td>5</td><td>Set up secret rotation reminder (expires $($reportData.secretExpiry))</td><td>Syed Rizvi</td><td class="status-warn">Pending</td></tr>
<tr><td>6</td><td>Document service principal in team runbook</td><td>Syed Rizvi</td><td class="status-warn">Pending</td></tr>
</tbody>
</table>
</div>

$errorsSection

<div class="section">
<h2>Context: Why This Was Created</h2>
<p style="line-height: 1.8;">
SQL Python connector scripts on pyx-warehouse-prod were running under <strong>Shaun Raj's personal user account</strong>.
John Pinto flagged this at 1:28 PM on Feb 3, 2026, recommending migration to a service account.
This service principal (<code>$($reportData.spName)</code>) was created to replace the personal account dependency.
Using a service principal ensures that production workloads are not tied to any individual user and continue
running even when employees leave or change roles.
</p>
</div>

<div class="footer">
<p>Generated by Databricks Service Account Setup Script</p>
<p>$($reportData.date)</p>
</div>
</div>
</body>
</html>
"@

$reportPath = Join-Path $PSScriptRoot "databricks_service_account_report.html"
$htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "  Report saved: $reportPath" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  DONE - SERVICE ACCOUNT CREATED" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Service Principal: $spName" -ForegroundColor Green
Write-Host "  App (Client) ID:  $appId" -ForegroundColor Green
Write-Host "  Object ID:        $spObjectId" -ForegroundColor Green
Write-Host "  Tenant ID:        $($acct.tenantId)" -ForegroundColor Green
Write-Host ""
Write-Host "  CLIENT SECRET:    $($reportData.secretValue)" -ForegroundColor Red
Write-Host "  *** SAVE THIS NOW - IT WILL NOT BE SHOWN AGAIN ***" -ForegroundColor Red
Write-Host ""

$addedCount = ($allWorkspaces | Where-Object { $_.spAdded }).Count
$totalCount = $allWorkspaces.Count
Write-Host "  Workspaces: $addedCount / $totalCount configured" -ForegroundColor Green
Write-Host "  Report: $reportPath" -ForegroundColor Green
Write-Host ""
Write-Host "  Next: Update your SQL Python scripts to use this SP" -ForegroundColor Yellow
Write-Host "  instead of Shaun Raj's personal account." -ForegroundColor Yellow
Write-Host ""
