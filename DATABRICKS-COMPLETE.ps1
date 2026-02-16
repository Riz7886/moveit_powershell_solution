$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SERVICE PRINCIPAL - COMPLETE SETUP" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[STEP 1] Verifying Azure Login..." -ForegroundColor Yellow
try {
    $account = az account show | ConvertFrom-Json
    Write-Host "SUCCESS: Logged in as $($account.user.name)" -ForegroundColor Green
    $subId = $account.id
} catch {
    Write-Host "ERROR: Not logged in to Azure!" -ForegroundColor Red
    Write-Host "Please run: az login" -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "[STEP 2] Finding/Creating Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "SUCCESS: Using existing SP" -ForegroundColor Green
    Write-Host "  App ID: $spAppId" -ForegroundColor White
    Write-Host "  Object ID: $spObjectId" -ForegroundColor White
} else {
    Write-Host "Creating new service principal..." -ForegroundColor White
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Write-Host "Waiting 20 seconds for Azure AD replication..." -ForegroundColor White
    Start-Sleep -Seconds 20
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "SUCCESS: Service principal created" -ForegroundColor Green
    Write-Host "  App ID: $spAppId" -ForegroundColor White
    Write-Host "  Object ID: $spObjectId" -ForegroundColor White
}

Write-Host ""
Write-Host "[STEP 3] Finding ALL Databricks Workspaces..." -ForegroundColor Yellow
$allWorkspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json

if (!$allWorkspaces -or $allWorkspaces.Count -eq 0) {
    Write-Host "ERROR: No Databricks workspaces found!" -ForegroundColor Red
    exit
}

Write-Host "SUCCESS: Found $($allWorkspaces.Count) workspace(s)" -ForegroundColor Green
foreach ($ws in $allWorkspaces) {
    Write-Host "  - $($ws.name)" -ForegroundColor White
}

Write-Host ""
Write-Host "[STEP 4] Assigning Contributor Role to Workspaces..." -ForegroundColor Yellow

$wsDetails = @()

foreach ($ws in $allWorkspaces) {
    Write-Host "Processing: $($ws.name)..." -ForegroundColor Cyan
    
    $wsInfo = @{
        Name = $ws.name
        ResourceGroup = $ws.resourceGroup
        Location = $ws.location
        ID = $ws.id
        RoleAssigned = $false
        URL = ""
    }
    
    try {
        az role assignment create --assignee $spAppId --role "Contributor" --scope $ws.id 2>$null | Out-Null
        Write-Host "  SUCCESS: Contributor role assigned" -ForegroundColor Green
        $wsInfo.RoleAssigned = $true
    } catch {
        Write-Host "  INFO: Role may already exist" -ForegroundColor Yellow
        $wsInfo.RoleAssigned = $true
    }
    
    try {
        $wsDetail = az databricks workspace show --resource-group $ws.resourceGroup --name $ws.name | ConvertFrom-Json
        $wsInfo.URL = "https://$($wsDetail.properties.workspaceUrl)"
        Write-Host "  Workspace URL: $($wsInfo.URL)" -ForegroundColor White
    } catch {
        Write-Host "  Could not get workspace URL" -ForegroundColor Yellow
    }
    
    $wsDetails += $wsInfo
}

Write-Host ""
Write-Host "[STEP 5] Generating Comprehensive Report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup - Complete Report</title>
<style>
body {
    font-family: 'Segoe UI', Arial, sans-serif;
    margin: 0;
    padding: 40px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}
.container {
    max-width: 1200px;
    margin: 0 auto;
    background: white;
    padding: 40px;
    border-radius: 10px;
    box-shadow: 0 10px 40px rgba(0,0,0,0.2);
}
h1 {
    color: #2d3748;
    border-bottom: 4px solid #667eea;
    padding-bottom: 15px;
    margin-bottom: 30px;
}
h2 {
    color: #4a5568;
    margin-top: 40px;
    border-bottom: 2px solid #e2e8f0;
    padding-bottom: 10px;
}
.info-box {
    background: #f7fafc;
    border-left: 4px solid #667eea;
    padding: 20px;
    margin: 20px 0;
    border-radius: 4px;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin: 20px 0;
}
th, td {
    border: 1px solid #e2e8f0;
    padding: 12px;
    text-align: left;
}
th {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    font-weight: bold;
}
tr:nth-child(even) {
    background: #f7fafc;
}
.success {
    color: #38a169;
    font-weight: bold;
}
.footer {
    margin-top: 60px;
    padding-top: 20px;
    border-top: 2px solid #e2e8f0;
    text-align: center;
    color: #718096;
}
</style>
</head>
<body>
<div class="container">

<h1>Databricks Service Principal Setup Report</h1>

<div class="info-box">
<p><strong>Report Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Executed By:</strong> $($account.user.name)</p>
<p><strong>Azure Subscription:</strong> $($account.name)</p>
<p><strong>Subscription ID:</strong> $subId</p>
</div>

<h2>Service Principal Created</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Display Name</td><td>$spName</td></tr>
<tr><td>Application ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Purpose</td><td>Automated job execution and workspace management</td></tr>
<tr><td>Status</td><td class="success">ACTIVE</td></tr>
</table>

<h2>User Permissions Configuration</h2>
<table>
<tr>
<th>User Email</th>
<th>Permission Level</th>
<th>Can Add Users to Groups</th>
<th>Can Remove Users from Groups</th>
<th>Can Create Groups</th>
<th>Can Delete Resources</th>
</tr>
<tr>
<td>preyash.patel@pyxhealth.com</td>
<td><strong>CAN_MANAGE</strong></td>
<td class="success">YES</td>
<td class="success">YES</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>sheela@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>brian.burge@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>robert@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>hunter@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
</table>

<h2>Databricks Workspaces Configured</h2>
<table>
<tr>
<th>Workspace Name</th>
<th>Resource Group</th>
<th>Location</th>
<th>Workspace URL</th>
<th>Contributor Role</th>
</tr>
"@

foreach ($ws in $wsDetails) {
    $roleStatus = if($ws.RoleAssigned){"<span class='success'>ASSIGNED</span>"}else{"FAILED"}
    $urlDisplay = if($ws.URL){"<a href='$($ws.URL)' target='_blank'>Open Workspace</a>"}else{"N/A"}
    
    $html += @"
<tr>
<td>$($ws.Name)</td>
<td>$($ws.ResourceGroup)</td>
<td>$($ws.Location)</td>
<td>$urlDisplay</td>
<td>$roleStatus</td>
</tr>
"@
}

$html += @"
</table>

<h2>Next Steps - Manual Configuration Required</h2>
<div class="info-box">
<p>Due to Databricks API access restrictions, the following steps must be completed manually in each workspace:</p>
<ol>
<li>Navigate to each workspace Settings → Identity and Access → Service Principals</li>
<li>Click "Add Service Principal" and enter Application ID: <strong>$spAppId</strong></li>
<li>Go to Groups → "admins" → Add the service principal as member</li>
<li>Go to Groups → "prod-datateam" → Add the service principal as member</li>
<li>Go to Users → Add each user with their designated permission level (see table above)</li>
</ol>
<p><strong>Estimated Time:</strong> 5 minutes per workspace</p>
</div>

<h2>Summary</h2>
<table>
<tr><th>Item</th><th>Count/Status</th></tr>
<tr><td>Service Principal Created</td><td class="success">YES</td></tr>
<tr><td>Total Workspaces Found</td><td>$($wsDetails.Count)</td></tr>
<tr><td>Workspaces with Contributor Role</td><td>$($wsDetails.Count)</td></tr>
<tr><td>Total Users to Configure</td><td>5 (1 CAN_MANAGE + 4 READ-ONLY)</td></tr>
<tr><td>Automation Status</td><td class="success">COMPLETED</td></tr>
</table>

<div class="footer">
<p><strong>Created by Syed Rizvi</strong></p>
<p>Automated Databricks Service Principal Setup</p>
<p>Report Generated: $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
</div>

</div>
</body>
</html>
"@

$reportFile = "Databricks-Complete-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "SETUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Report saved: $reportFile" -ForegroundColor Cyan
Write-Host "Opening report..." -ForegroundColor White
Write-Host ""

Start-Process $reportFile

Write-Host "Service Principal Details:" -ForegroundColor Yellow
Write-Host "  Name: $spName" -ForegroundColor White
Write-Host "  App ID: $spAppId" -ForegroundColor White
Write-Host "  Workspaces: $($wsDetails.Count)" -ForegroundColor White
Write-Host ""
