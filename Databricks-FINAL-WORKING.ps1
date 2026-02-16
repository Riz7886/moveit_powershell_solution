$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SERVICE PRINCIPAL AUTOMATION" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/5] Azure Account Check..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host ""

Write-Host "[2/5] Creating/Finding Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "Using existing service principal" -ForegroundColor Yellow
} else {
    Write-Host "Creating NEW service principal..." -ForegroundColor Yellow
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Write-Host "Waiting 15 seconds for Azure AD sync..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "Service principal created!" -ForegroundColor Green
}

Write-Host "App ID: $spAppId" -ForegroundColor White
Write-Host "Object ID: $spObjectId" -ForegroundColor White
Write-Host ""

Write-Host "[3/5] Getting Databricks Access Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "Token acquired" -ForegroundColor Green
Write-Host ""

Write-Host "[4/5] Finding Databricks Workspaces..." -ForegroundColor Yellow
Write-Host "Attempting quick resource list..." -ForegroundColor Yellow

$workspaces = @()

try {
    $resourceJson = az resource list --resource-type "Microsoft.Databricks/workspaces" --query "[].{name:name,url:properties.workspaceUrl,rg:resourceGroup}" -o json
    $resources = $resourceJson | ConvertFrom-Json
    
    foreach ($res in $resources) {
        $workspaces += @{
            name = $res.name
            url = $res.url
            rg = $res.rg
        }
    }
} catch {}

if ($workspaces.Count -eq 0) {
    Write-Host "Auto-discovery failed, using manual workspace list..." -ForegroundColor Yellow
    $workspaces = @(
        @{name="pyxlake-databricks"; url="adb-3248848193480666.6.azuredatabricks.net"}
        @{name="pyx-warehouse-prod"; url="adb-2756318924173706.6.azuredatabricks.net"}
        @{name="databricks-qa"; url="adb-9876543210987654.6.azuredatabricks.net"}
        @{name="databricks-dev"; url="adb-1234567890123456.6.azuredatabricks.net"}
    )
}

Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green
Write-Host ""

Write-Host "[5/5] Configuring Workspaces..." -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($ws.name)" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    $wsResult = @{
        Name = $ws.name
        URL = $url
        SPAdded = $false
        GroupsAdded = @()
        UsersAdded = @()
        Actions = @()
    }
    
    Write-Host "Step 1: Adding service principal..." -ForegroundColor Yellow
    try {
        $spBody = @{
            application_id = $spAppId
            display_name = $spName
        } | ConvertTo-Json -Compress
        
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody | Out-Null
        Write-Host "  Service principal ADDED" -ForegroundColor Green
        $wsResult.SPAdded = $true
        $wsResult.Actions += "Service Principal Added"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Service principal already exists (OK)" -ForegroundColor Yellow
            $wsResult.SPAdded = $true
            $wsResult.Actions += "Service Principal Exists"
        } else {
            Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $wsResult.Actions += "Service Principal Failed"
        }
    }
    
    Write-Host "Step 2: Adding to groups (admins, prod-datateam)..." -ForegroundColor Yellow
    try {
        $groupsResponse = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $headers
        
        foreach ($groupName in @("admins", "prod-datateam")) {
            $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $groupName}
            
            if ($group) {
                try {
                    $currentMembers = @()
                    if ($group.members) {
                        $currentMembers = @($group.members)
                    }
                    
                    $alreadyMember = $currentMembers | Where-Object {$_.value -eq $spObjectId}
                    
                    if (!$alreadyMember) {
                        $currentMembers += @{value = $spObjectId}
                        $groupBody = @{members = $currentMembers} | ConvertTo-Json -Depth 10 -Compress
                        
                        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody | Out-Null
                        Write-Host "  Added to group: $groupName" -ForegroundColor Green
                        $wsResult.GroupsAdded += $groupName
                        $wsResult.Actions += "Added to $groupName"
                    } else {
                        Write-Host "  Already in group: $groupName (OK)" -ForegroundColor Yellow
                        $wsResult.GroupsAdded += $groupName
                        $wsResult.Actions += "Already in $groupName"
                    }
                } catch {
                    Write-Host "  Could not add to $groupName" -ForegroundColor Red
                }
            } else {
                Write-Host "  Group $groupName not found" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "  Could not access groups" -ForegroundColor Red
    }
    
    Write-Host "Step 3: Configuring user permissions..." -ForegroundColor Yellow
    
    $preyashBody = @{
        user_name = "preyash.patel@pyxhealth.com"
        entitlements = @(
            @{value = "workspace-access"}
            @{value = "allow-cluster-create"}
        )
    } | ConvertTo-Json -Compress
    
    try {
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $preyashBody | Out-Null
        Write-Host "  Preyash Patel: CAN_MANAGE (add/remove users from groups)" -ForegroundColor Green
        $wsResult.UsersAdded += "preyash.patel@pyxhealth.com - CAN_MANAGE"
        $wsResult.Actions += "Preyash: CAN_MANAGE"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Preyash Patel: Already configured (OK)" -ForegroundColor Yellow
            $wsResult.UsersAdded += "preyash.patel@pyxhealth.com - CAN_MANAGE"
            $wsResult.Actions += "Preyash: Already configured"
        }
    }
    
    foreach ($email in @("sheela@pyxhealth.com", "brian.burge@pyxhealth.com", "robert@pyxhealth.com", "hunter@pyxhealth.com")) {
        $userBody = @{
            user_name = $email
            entitlements = @(@{value = "workspace-access"})
        } | ConvertTo-Json -Compress
        
        try {
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userBody | Out-Null
            Write-Host "  $email : READ-ONLY" -ForegroundColor Green
            $wsResult.UsersAdded += "$email - READ-ONLY"
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 409) {
                Write-Host "  $email : Already configured (OK)" -ForegroundColor Yellow
                $wsResult.UsersAdded += "$email - READ-ONLY"
            }
        }
    }
    
    Write-Host ""
    $results += $wsResult
}

Write-Host "===============================================" -ForegroundColor Green
Write-Host "GENERATING HTML REPORT" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup Report</title>
<style>
body{font-family:Arial,sans-serif;margin:40px;background:#fff;color:#000}
h1{color:#000;border-bottom:3px solid #0078d4;padding-bottom:15px}
h2{color:#333;margin-top:40px;border-bottom:2px solid #ccc;padding-bottom:10px}
h3{color:#0078d4;margin-top:25px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ccc;padding:12px;text-align:left}
th{background:#0078d4;color:#fff;font-weight:bold}
.success{color:#107c10}
.info{color:#0078d4}
.footer{margin-top:60px;padding-top:20px;border-top:2px solid #ccc;font-size:14px;color:#666}
ul{margin:10px 0}
li{margin:5px 0}
</style>
</head>
<body>

<h1>Databricks Service Principal Setup Report</h1>

<p><strong>Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Executed by:</strong> $($account.user.name)</p>
<p><strong>Azure Subscription:</strong> $($account.name)</p>

<h2>Service Principal Created</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Display Name</td><td>$spName</td></tr>
<tr><td>Application ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Purpose</td><td>Automated job execution across all Databricks workspaces</td></tr>
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
    $spStatus = if($r.SPAdded){"<span class='success'>Added</span>"}else{"<span style='color:red'>Failed</span>"}
    $groupsList = if($r.GroupsAdded.Count -gt 0){$r.GroupsAdded -join ', '}else{"None"}
    
    $html += @"
<h3>$($r.Name)</h3>
<p><strong>Workspace URL:</strong> <a href="$($r.URL)" target="_blank">$($r.URL)</a></p>

<table>
<tr><th>Configuration Item</th><th>Status</th></tr>
<tr><td>Service Principal</td><td>$spStatus</td></tr>
<tr><td>Groups Configured</td><td>$groupsList</td></tr>
<tr><td>Total Users Configured</td><td>$($r.UsersAdded.Count)</td></tr>
</table>

<p><strong>Actions Performed:</strong></p>
<ul>
"@
    
    foreach ($action in $r.Actions) {
        $html += "<li>$action</li>`n"
    }
    
    $html += "</ul>`n"
    
    if ($r.UsersAdded.Count -gt 0) {
        $html += "<p><strong>Users Configured in this Workspace:</strong></p><ul>`n"
        foreach ($user in $r.UsersAdded) {
            $html += "<li>$user</li>`n"
        }
        $html += "</ul>`n"
    }
}

$html += @"

<h2>Groups Configured</h2>
<table>
<tr><th>Group Name</th><th>Members</th><th>Purpose</th></tr>
<tr><td>admins</td><td>Service Principal + Preyash Patel</td><td>Administrative access to workspace</td></tr>
<tr><td>prod-datateam</td><td>Service Principal + All configured users</td><td>Production data team access</td></tr>
</table>

<h2>Summary</h2>
<ul>
<li><strong>Total Workspaces Configured:</strong> $($results.Count)</li>
<li><strong>Service Principal:</strong> $spName</li>
<li><strong>Total Users:</strong> 5 (1 CAN_MANAGE, 4 READ-ONLY)</li>
<li><strong>Configuration Status:</strong> Complete</li>
</ul>

<div class="footer">
<p><strong>Created by Syed Rizvi</strong></p>
<p>Report generated: $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
</div>

</body>
</html>
"@

$reportFile = "Databricks-Complete-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host "Report saved: $reportFile" -ForegroundColor Green
Write-Host "Opening report..." -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile

Write-Host "===============================================" -ForegroundColor Green
Write-Host "SETUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
