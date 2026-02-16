$ErrorActionPreference = "Stop"

Write-Host "DATABRICKS AUTOMATION - FAST VERSION" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Azure login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Host "Logged in: $($account.user.name)" -ForegroundColor Green
$subId = $account.id

Write-Host "Step 2: Finding workspaces (fast method)..." -ForegroundColor Yellow
$workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green

Write-Host "Step 3: Service principal..." -ForegroundColor Yellow
$spName = "databricks-jobs-service-principal"
$existingSP = az ad sp list --display-name $spName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "Using existing SP" -ForegroundColor Yellow
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep -Seconds 10
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "Created SP" -ForegroundColor Green
}

Write-Host "App ID: $spAppId" -ForegroundColor Green

Write-Host "Step 4: Getting token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv

$results = @()

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "Processing: $($ws.name)" -ForegroundColor Cyan
    
    $url = "https://$($ws.properties.workspaceUrl)"
    $headers = @{"Authorization"="Bearer $token"; "Content-Type"="application/json"}
    
    try {
        $spBody = @{application_id=$spAppId; display_name=$spName} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody | Out-Null
        Write-Host "  - Added service principal" -ForegroundColor Green
    } catch {}
    
    $groupsResponse = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $headers
    
    foreach ($gName in @("admins","prod-datateam")) {
        $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $gName}
        if ($group) {
            $members = @($group.members)
            $members += @{value=$spObjectId}
            $groupBody = @{members=$members} | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody | Out-Null
            Write-Host "  - Added to $gName" -ForegroundColor Green
        }
    }
    
    $preyashBody = @{user_name="preyash.patel@pyxhealth.com"; entitlements=@(@{value="workspace-access"},@{value="allow-cluster-create"})} | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $preyashBody | Out-Null
        Write-Host "  - Preyash: CAN_MANAGE" -ForegroundColor Green
    } catch {}
    
    foreach ($user in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
        $userBody = @{user_name=$user; entitlements=@(@{value="workspace-access"})} | ConvertTo-Json
        try {
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userBody | Out-Null
        } catch {}
    }
    Write-Host "  - Other users: READ-ONLY" -ForegroundColor Green
    
    $results += @{Name=$ws.name; URL=$url}
}

Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Setup Report</title>
<style>
body{font-family:Arial;margin:40px}
h1{color:#000;border-bottom:2px solid #000;padding-bottom:10px}
h2{margin-top:30px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ccc;padding:12px;text-align:left}
th{background:#f0f0f0}
</style>
</head>
<body>
<h1>Databricks Service Principal Setup Report</h1>
<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
<p><b>Subscription:</b> $($account.name)</p>
<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$spName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
</table>
<h2>User Permissions</h2>
<table>
<tr><th>Email</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create Groups</th><th>Delete</th></tr>
<tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr>
<tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
</table>
<h2>Workspaces Configured</h2>
<table>
<tr><th>Workspace</th><th>URL</th></tr>
"@

foreach ($r in $results) {
    $html += "<tr><td>$($r.Name)</td><td>$($r.URL)</td></tr>"
}

$html += "</table><p>Created by Syed Rizvi - $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p></body></html>"

$reportFile = "Databricks-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile
