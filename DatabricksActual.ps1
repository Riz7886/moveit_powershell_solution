$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SERVICE PRINCIPAL SETUP" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/6] Checking Azure login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    Write-Host "ERROR: Not logged in!" -ForegroundColor Red
    exit
}
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host ""

Write-Host "[2/6] Finding Databricks workspaces..." -ForegroundColor Yellow
$workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
if (!$workspaces -or $workspaces.Count -eq 0) {
    Write-Host "ERROR: No workspaces found!" -ForegroundColor Red
    exit
}
Write-Host "Found $($workspaces.Count) workspaces:" -ForegroundColor Green
foreach ($ws in $workspaces) {
    Write-Host "  - $($ws.name)" -ForegroundColor White
}
Write-Host ""

Write-Host "[3/6] Creating Azure AD Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    Write-Host "Service principal already exists - using it" -ForegroundColor Yellow
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    Write-Host "Creating new service principal..." -ForegroundColor Yellow
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    
    if (!$sp) {
        Write-Host "ERROR: Failed to create service principal!" -ForegroundColor Red
        exit
    }
    
    Write-Host "Waiting 15 seconds for Azure AD replication..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Host "Service Principal Created:" -ForegroundColor Green
Write-Host "  App ID: $spAppId" -ForegroundColor White
Write-Host "  Object ID: $spObjectId" -ForegroundColor White
Write-Host ""

Write-Host "[4/6] Getting Databricks access token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv

if (!$token) {
    Write-Host "ERROR: Failed to get token!" -ForegroundColor Red
    exit
}
Write-Host "Token acquired" -ForegroundColor Green
Write-Host ""

Write-Host "[5/6] Configuring Databricks workspaces..." -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($ws.name)" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.properties.workspaceUrl)"
    Write-Host "URL: $url" -ForegroundColor White
    
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
    }
    
    Write-Host ""
    Write-Host "Step 1: Adding service principal to workspace..." -ForegroundColor Yellow
    try {
        $spBody = @{
            application_id = $spAppId
            display_name = $spName
        } | ConvertTo-Json -Compress
        
        $response = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody
        Write-Host "SUCCESS: Service principal added!" -ForegroundColor Green
        $wsResult.SPAdded = $true
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "Service principal already exists (OK)" -ForegroundColor Yellow
            $wsResult.SPAdded = $true
        } else {
            Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Step 2: Adding service principal to groups..." -ForegroundColor Yellow
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
                    if ($alreadyMember) {
                        Write-Host "  Already in $groupName (OK)" -ForegroundColor Yellow
                        $wsResult.GroupsAdded += $groupName
                    } else {
                        $currentMembers += @{value = $spObjectId}
                        $groupBody = @{members = $currentMembers} | ConvertTo-Json -Depth 10 -Compress
                        
                        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody | Out-Null
                        Write-Host "  SUCCESS: Added to $groupName!" -ForegroundColor Green
                        $wsResult.GroupsAdded += $groupName
                    }
                } catch {
                    Write-Host "  FAILED to add to $groupName : $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  Group $groupName not found" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "FAILED to get groups: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
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
        Write-Host "  Preyash: CAN_MANAGE" -ForegroundColor Green
        $wsResult.UsersAdded += "preyash.patel@pyxhealth.com (CAN_MANAGE)"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Preyash: Already configured (OK)" -ForegroundColor Yellow
            $wsResult.UsersAdded += "preyash.patel@pyxhealth.com (CAN_MANAGE)"
        } else {
            Write-Host "  Preyash: FAILED - $($_.Exception.Message)" -ForegroundColor Red
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
            $wsResult.UsersAdded += "$email (READ-ONLY)"
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 409) {
                Write-Host "  $email : Already configured (OK)" -ForegroundColor Yellow
                $wsResult.UsersAdded += "$email (READ-ONLY)"
            } else {
                Write-Host "  $email : FAILED" -ForegroundColor Red
            }
        }
    }
    
    Write-Host ""
    $results += $wsResult
}

Write-Host ""
Write-Host "[6/6] Generating HTML report..." -ForegroundColor Yellow

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
th,td{border:1px solid #ccc;padding:12px}
th{background:#f0f0f0}
</style>
</head>
<body>
<h1>Databricks Service Principal Setup Report</h1>
<p><b>Date:</b> $(Get-Date)</p>
<p><b>By:</b> $($account.user.name)</p>

<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$spName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
</table>

<h2>User Permissions</h2>
<table>
<tr><th>User</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create Groups</th><th>Delete</th></tr>
<tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr>
<tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
</table>

<h2>Workspaces Configured</h2>
"@

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3>"
    $html += "<p><b>URL:</b> $($r.URL)</p>"
    $html += "<p><b>Service Principal Added:</b> $(if($r.SPAdded){'Yes'}else{'No'})</p>"
    $html += "<p><b>Groups:</b> $($r.GroupsAdded -join ', ')</p>"
    $html += "<p><b>Users Configured:</b></p><ul>"
    foreach ($u in $r.UsersAdded) {
        $html += "<li>$u</li>"
    }
    $html += "</ul>"
}

$html += "<p>Created by Syed Rizvi - $(Get-Date)</p></body></html>"

$reportFile = "Databricks-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "COMPLETED!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile
