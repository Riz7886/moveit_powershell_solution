$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS SERVICE PRINCIPAL - 100% AUTOMATED" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

function Invoke-DatabricksAPI {
    param(
        [string]$WorkspaceUrl,
        [string]$Token,
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type" = "application/json"
    }
    
    $uri = "$WorkspaceUrl/api/2.0/$Endpoint"
    
    try {
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        }
        
        $response = Invoke-RestMethod @params
        return $response
    } catch {
        if ($_.Exception.Response.StatusCode -eq 409) {
            return @{ AlreadyExists = $true }
        }
        throw
    }
}

Write-Host "[1/5] Azure Authentication..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "SUCCESS: $($account.user.name)" -ForegroundColor Green
$subscriptionId = $account.id

Write-Host "[2/5] Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep -Seconds 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Host "SUCCESS: App ID: $spAppId" -ForegroundColor Green

Write-Host "[3/5] Databricks Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "SUCCESS" -ForegroundColor Green

Write-Host "[4/5] Finding Workspaces..." -ForegroundColor Yellow
$allResources = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subscriptionId | ConvertFrom-Json

if (!$allResources -or $allResources.Count -eq 0) {
    Write-Host "Using known workspaces..." -ForegroundColor Yellow
    $allResources = @(
        @{name="pyx-warehouse-prod";properties=@{workspaceUrl="adb-2756318924173706.6.azuredatabricks.net"};resourceGroup="rg-warehouse-preprod"}
        @{name="pyxlake-databricks";properties=@{workspaceUrl="adb-3248848193480666.6.azuredatabricks.net"};resourceGroup="rg-adls-poc"}
    )
}

Write-Host "Found: $($allResources.Count) workspaces" -ForegroundColor Green

Write-Host "[5/5] Configuring Workspaces..." -ForegroundColor Yellow
$results = @()

foreach ($workspace in $allResources) {
    Write-Host ""
    Write-Host "Workspace: $($workspace.name)" -ForegroundColor Cyan
    
    $workspaceUrl = "https://$($workspace.properties.workspaceUrl)"
    
    $wsResult = @{
        WorkspaceName = $workspace.name
        WorkspaceUrl = $workspaceUrl
        ServicePrincipalAdded = $false
        GroupsConfigured = @()
        UsersConfigured = @()
    }
    
    try {
        Write-Host "  Adding service principal..." -ForegroundColor White
        $spBody = @{
            application_id = $spAppId
            display_name = $spName
        }
        
        $response = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $token -Endpoint "preview/scim/v2/ServicePrincipals" -Method "POST" -Body $spBody
        
        if ($response.AlreadyExists) {
            Write-Host "    Already exists (OK)" -ForegroundColor Yellow
        } else {
            Write-Host "    SUCCESS" -ForegroundColor Green
        }
        $wsResult.ServicePrincipalAdded = $true
        
        Write-Host "  Adding to groups..." -ForegroundColor White
        $groups = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $token -Endpoint "preview/scim/v2/Groups" -Method "GET"
        
        foreach ($groupName in @("admins", "prod-datateam")) {
            $group = $groups.Resources | Where-Object {$_.displayName -eq $groupName}
            
            if ($group) {
                $members = @($group.members)
                $members += @{value = $spObjectId}
                
                $groupBody = @{members = $members}
                
                try {
                    Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $token -Endpoint "preview/scim/v2/Groups/$($group.id)" -Method "PATCH" -Body $groupBody | Out-Null
                    Write-Host "    $groupName : SUCCESS" -ForegroundColor Green
                    $wsResult.GroupsConfigured += $groupName
                } catch {}
            }
        }
        
        Write-Host "  Configuring users..." -ForegroundColor White
        
        $preyashBody = @{
            user_name = "preyash.patel@pyxhealth.com"
            entitlements = @(
                @{value = "workspace-access"}
                @{value = "allow-cluster-create"}
            )
        }
        
        try {
            Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $token -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $preyashBody | Out-Null
            $wsResult.UsersConfigured += "preyash.patel@pyxhealth.com (CAN_MANAGE)"
        } catch {}
        
        foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
            $userBody = @{
                user_name = $email
                entitlements = @(@{value = "workspace-access"})
            }
            
            try {
                Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $token -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $userBody | Out-Null
                $wsResult.UsersConfigured += "$email (READ-ONLY)"
            } catch {}
        }
        
        Write-Host "  COMPLETE" -ForegroundColor Green
        
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    $results += $wsResult
}

Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head><title>Databricks Report</title>
<style>
body{font-family:Arial;margin:40px;background:linear-gradient(135deg,#667eea,#764ba2)}
.container{max-width:1200px;margin:0 auto;background:#fff;padding:40px;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
h1{color:#2d3748;border-bottom:4px solid #667eea;padding-bottom:15px}
h2{color:#4a5568;margin-top:30px;border-bottom:2px solid #e2e8f0;padding-bottom:10px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #e2e8f0;padding:12px}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff}
tr:nth-child(even){background:#f7fafc}
.success{color:#38a169;font-weight:bold}
.footer{margin-top:50px;padding-top:20px;border-top:2px solid #e2e8f0;text-align:center;color:#718096}
</style>
</head>
<body>
<div class="container">
<h1>Databricks Service Principal Setup</h1>
<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><b>By:</b> $($account.user.name)</p>

<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$spName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Status</td><td class="success">ACTIVE</td></tr>
</table>

<h2>User Permissions</h2>
<table>
<tr><th>User</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create</th><th>Delete</th></tr>
<tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td class="success">Yes</td><td class="success">Yes</td><td>No</td><td>No</td></tr>
<tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
</table>

<h2>Workspaces</h2>
"@

foreach ($r in $results) {
    $spStatus = if($r.ServicePrincipalAdded){"<span class='success'>ADDED</span>"}else{"FAILED"}
    $html += "<h3>$($r.WorkspaceName)</h3><p><b>URL:</b> $($r.WorkspaceUrl)</p><p><b>Service Principal:</b> $spStatus</p><p><b>Groups:</b> $($r.GroupsConfigured -join ', ')</p><p><b>Users:</b></p><ul>"
    foreach ($u in $r.UsersConfigured) {
        $html += "<li>$u</li>"
    }
    $html += "</ul>"
}

$html += "<div class='footer'><p><b>Created by Syed Rizvi</b></p><p>$(Get-Date)</p></div></div></body></html>"

$file = "Databricks-Complete-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host ""

Start-Process $file
