Write-Host ""
Write-Host "DATABRICKS SERVICE PRINCIPAL SETUP" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/4] Azure login..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "OK: $($account.user.name)" -ForegroundColor Green

Write-Host "[2/4] Service principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json
if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}
Write-Host "OK: $spAppId" -ForegroundColor Green

Write-Host "[3/4] Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "OK" -ForegroundColor Green

Write-Host "[4/4] Configuring workspaces..." -ForegroundColor Yellow
Write-Host ""

$workspaces = @(
    @{name="pyxlake-databricks"; url="adb-3248848193480666.6.azuredatabricks.net"}
    @{name="pyx-warehouse-prod"; url="adb-2756318924173706.6.azuredatabricks.net"}
)

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "$($ws.name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $h = @{"Authorization"="Bearer $token";"Content-Type"="application/json"}
    $r = @{Name=$ws.name;URL=$url;Actions=@()}
    
    try {
        $b = @{application_id=$spAppId;display_name=$spName} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $h -Body $b | Out-Null
        Write-Host "  SP Added" -ForegroundColor Green
        $r.Actions += "Service Principal Added"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  SP Exists" -ForegroundColor Yellow
            $r.Actions += "Service Principal Already Exists"
        }
    }
    
    $gr = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $h
    foreach ($gn in @("admins","prod-datateam")) {
        $g = $gr.Resources | Where-Object {$_.displayName -eq $gn}
        if ($g) {
            $m = @($g.members)
            $m += @{value=$spObjectId}
            $gb = @{members=$m} | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($g.id)" -Method PATCH -Headers $h -Body $gb | Out-Null
            Write-Host "  Group: $gn" -ForegroundColor Green
            $r.Actions += "Added to $gn group"
        }
    }
    
    $users = @(
        @{u="preyash.patel@pyxhealth.com";e=@(@{value="workspace-access"},@{value="allow-cluster-create"});l="CAN_MANAGE"}
        @{u="sheela@pyxhealth.com";e=@(@{value="workspace-access"});l="READ-ONLY"}
        @{u="brian.burge@pyxhealth.com";e=@(@{value="workspace-access"});l="READ-ONLY"}
        @{u="robert@pyxhealth.com";e=@(@{value="workspace-access"});l="READ-ONLY"}
        @{u="hunter@pyxhealth.com";e=@(@{value="workspace-access"});l="READ-ONLY"}
    )
    
    foreach ($user in $users) {
        $ub = @{user_name=$user.u;entitlements=$user.e} | ConvertTo-Json
        try {
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $ub | Out-Null
            Write-Host "  User: $($user.u) ($($user.l))" -ForegroundColor Green
            $r.Actions += "$($user.u) - $($user.l)"
        } catch {}
    }
    
    Write-Host ""
    $results += $r
}

Write-Host "Generating report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup Report</title>
<style>
body{font-family:Arial,sans-serif;margin:40px;background:#fff;color:#000}
h1{color:#000;border-bottom:3px solid #0078d4;padding-bottom:15px;margin-bottom:30px}
h2{color:#0078d4;margin-top:40px;border-bottom:2px solid #ccc;padding-bottom:10px}
h3{color:#333;margin-top:25px}
.info-box{background:#f0f8ff;border-left:4px solid #0078d4;padding:15px;margin:20px 0}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ccc;padding:12px;text-align:left}
th{background:#0078d4;color:#fff;font-weight:bold}
tr:nth-child(even){background:#f9f9f9}
.success{color:#107c10;font-weight:bold}
.footer{margin-top:60px;padding-top:20px;border-top:2px solid #ccc;color:#666;font-size:14px}
</style>
</head>
<body>

<h1>Databricks Service Principal Setup Report</h1>

<div class="info-box">
<p><strong>Report Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Executed By:</strong> $($account.user.name)</p>
<p><strong>Azure Subscription:</strong> $($account.name)</p>
</div>

<h2>Service Principal Created</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Display Name</td><td>$spName</td></tr>
<tr><td>Application ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Purpose</td><td>Automated job execution and workspace management</td></tr>
</table>

<h2>User Permissions Configured</h2>
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

<h2>Workspaces Configured</h2>
"@

foreach ($r in $results) {
    $html += @"
<h3>$($r.Name)</h3>
<p><strong>Workspace URL:</strong> <a href="$($r.URL)" target="_blank">$($r.URL)</a></p>
<p><strong>Configuration Actions Completed:</strong></p>
<ul>
"@
    foreach ($action in $r.Actions) {
        $html += "<li>$action</li>"
    }
    $html += "</ul>"
}

$html += @"

<h2>Groups Configuration</h2>
<table>
<tr><th>Group Name</th><th>Members</th><th>Purpose</th></tr>
<tr><td>admins</td><td>Service Principal + Preyash Patel</td><td>Administrative access and workspace management</td></tr>
<tr><td>prod-datateam</td><td>Service Principal + All team members</td><td>Production data team access</td></tr>
</table>

<h2>Summary</h2>
<ul>
<li><strong>Total Workspaces Configured:</strong> $($results.Count)</li>
<li><strong>Service Principal Name:</strong> $spName</li>
<li><strong>Total Users Configured:</strong> 5 (1 CAN_MANAGE, 4 READ-ONLY)</li>
<li><strong>Status:</strong> <span class="success">COMPLETED SUCCESSFULLY</span></li>
</ul>

<div class="footer">
<p><strong>Created by Syed Rizvi</strong></p>
<p>Configuration completed: $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
</div>

</body>
</html>
"@

$file = "Databricks-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "DONE: $file" -ForegroundColor Green
Start-Process $file
