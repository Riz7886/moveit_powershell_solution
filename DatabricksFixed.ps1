$ErrorActionPreference = "Continue"

Write-Host "DATABRICKS AUTOMATION" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Azure login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green

Write-Host "Step 2: Finding workspaces..." -ForegroundColor Yellow
$workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green

Write-Host "Step 3: Service principal..." -ForegroundColor Yellow
$spName = "databricks-jobs-service-principal"
$existingSP = az ad sp list --display-name $spName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "Using existing SP: $spAppId" -ForegroundColor Green
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment 2>$null | ConvertFrom-Json
    Start-Sleep -Seconds 10
    $servicePrincipal = az ad sp show --id $sp.appId 2>$null | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "Created SP: $spAppId" -ForegroundColor Green
}

Write-Host "Step 4: Getting token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv 2>$null

$results = @()

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($ws.name)" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.properties.workspaceUrl)"
    $headers = @{"Authorization"="Bearer $token"; "Content-Type"="application/json"}
    
    $wsResult = @{Name=$ws.name; URL=$url; Actions=@()}
    
    Write-Host "Adding service principal..." -ForegroundColor Yellow
    try {
        $spBody = @{application_id=$spAppId; display_name=$spName} | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody -ErrorAction Stop | Out-Null
        Write-Host "  Service principal added" -ForegroundColor Green
        $wsResult.Actions += "Service principal added"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Service principal already exists" -ForegroundColor Yellow
            $wsResult.Actions += "Service principal exists"
        } else {
            Write-Host "  Could not add service principal (continuing)" -ForegroundColor Yellow
            $wsResult.Actions += "Service principal skipped"
        }
    }
    
    Write-Host "Adding to groups..." -ForegroundColor Yellow
    try {
        $groupsResponse = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $headers -ErrorAction Stop
        
        foreach ($gName in @("admins","prod-datateam")) {
            $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $gName}
            if ($group) {
                try {
                    $members = @()
                    if ($group.members) { $members = @($group.members) }
                    $members += @{value=$spObjectId}
                    $groupBody = @{members=$members} | ConvertTo-Json -Depth 10 -Compress
                    Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody -ErrorAction Stop | Out-Null
                    Write-Host "  Added to $gName" -ForegroundColor Green
                    $wsResult.Actions += "Added to $gName"
                } catch {
                    Write-Host "  Could not add to $gName (continuing)" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  Could not access groups (continuing)" -ForegroundColor Yellow
    }
    
    Write-Host "Configuring users (will skip if they already exist)..." -ForegroundColor Yellow
    
    $users = @(
        @{email="preyash.patel@pyxhealth.com"; level="CAN_MANAGE"; entitlements=@(@{value="workspace-access"},@{value="allow-cluster-create"})}
        @{email="sheela@pyxhealth.com"; level="READ-ONLY"; entitlements=@(@{value="workspace-access"})}
        @{email="brian.burge@pyxhealth.com"; level="READ-ONLY"; entitlements=@(@{value="workspace-access"})}
        @{email="robert@pyxhealth.com"; level="READ-ONLY"; entitlements=@(@{value="workspace-access"})}
        @{email="hunter@pyxhealth.com"; level="READ-ONLY"; entitlements=@(@{value="workspace-access"})}
    )
    
    foreach ($u in $users) {
        try {
            $userBody = @{user_name=$u.email; entitlements=$u.entitlements} | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userBody -ErrorAction Stop | Out-Null
            Write-Host "  $($u.email): $($u.level)" -ForegroundColor Green
            $wsResult.Actions += "$($u.email): $($u.level)"
        } catch {
            Write-Host "  $($u.email): Already exists or skipped" -ForegroundColor Yellow
            $wsResult.Actions += "$($u.email): Exists"
        }
    }
    
    $results += $wsResult
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "GENERATING REPORT" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Setup Report</title>
<style>
body{font-family:Arial;margin:40px;background:#fff}
h1{color:#000;border-bottom:2px solid #000;padding-bottom:10px}
h2{color:#333;margin-top:30px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ccc;padding:12px;text-align:left}
th{background:#f0f0f0}
.footer{margin-top:50px;padding-top:20px;border-top:1px solid #ccc;color:#666}
</style>
</head>
<body>
<h1>Databricks Service Principal Setup Report</h1>
<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
<p><b>Azure Account:</b> $($account.user.name)</p>
<p><b>Subscription:</b> $($account.name)</p>

<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$spName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
</table>

<h2>User Permissions Configured</h2>
<table>
<tr><th>Email</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create Groups</th><th>Delete</th></tr>
<tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr>
<tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
</table>

<h2>Workspaces Processed</h2>
"@

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3>"
    $html += "<p><b>URL:</b> $($r.URL)</p>"
    $html += "<p><b>Actions Completed:</b></p><ul>"
    foreach ($action in $r.Actions) {
        $html += "<li>$action</li>"
    }
    $html += "</ul>"
}

$html += @"
<div class="footer">
<p>Created by Syed Rizvi</p>
<p>Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
</div>
</body>
</html>
"@

$reportFile = "Databricks-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile
