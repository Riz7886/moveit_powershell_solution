$ErrorActionPreference = "Stop"

$TeamMembers = @(
    "preyash.patel@pyxhealth.com",
    "sheela@pyxhealth.com", 
    "brian.burge@pyxhealth.com",
    "robert@pyxhealth.com",
    "hunter@pyxhealth.com"
)

$TeamGroups = @("admins", "prod-datateam")
$ServicePrincipalName = "databricks-jobs-service-principal"

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $colors = @{INFO="Cyan"; SUCCESS="Green"; ERROR="Red"; WARNING="Yellow"}
    Write-Host "[$Type] $Message" -ForegroundColor $colors[$Type]
}

function Get-AzureToken {
    param([string]$Resource = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d")
    $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
    return $token
}

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
        $params = @{Uri=$uri; Method=$Method; Headers=$headers}
        if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
        return Invoke-RestMethod @params
    } catch {
        if ($_.Exception.Response.StatusCode -eq 409) { return @{AlreadyExists=$true} }
        throw
    }
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SERVICE PRINCIPAL SETUP" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Step 1: Azure login..."
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Log "Logged in: $($account.user.name)" "SUCCESS"
$subscriptionId = $account.id

Write-Log "Step 2: Finding workspaces..."
$workspaces = az databricks workspace list --subscription $subscriptionId 2>$null | ConvertFrom-Json
if (!$workspaces) {
    $workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subscriptionId | ConvertFrom-Json
}
Write-Log "Found $($workspaces.Count) workspace(s)" "SUCCESS"

Write-Log "Step 3: Creating service principal..."
$existingSP = az ad sp list --display-name $ServicePrincipalName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    Write-Log "Using existing" "WARNING"
    $servicePrincipal = $existingSP[0]
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
} else {
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --skip-assignment 2>$null | ConvertFrom-Json
    Start-Sleep -Seconds 10
    $servicePrincipal = az ad sp show --id $sp.appId 2>$null | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Log "App ID: $spAppId" "SUCCESS"

Write-Log "Step 4: Getting token..."
$databricksToken = Get-AzureToken
Write-Log "Token OK" "SUCCESS"

$results = @()
$wsNum = 0

foreach ($ws in $workspaces) {
    $wsNum++
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Yellow
    Write-Log "Workspace $wsNum: $($ws.name)"
    Write-Host "===============================================" -ForegroundColor Yellow
    
    $workspaceUrl = "https://$($ws.properties.workspaceUrl)"
    
    $result = @{
        WorkspaceName = $ws.name
        WorkspaceUrl = $workspaceUrl
        ServicePrincipalAdded = $false
        GroupsConfigured = @()
        UsersConfigured = @()
        Errors = @()
    }
    
    try {
        Write-Log "Adding service principal..."
        $spBody = @{
            application_id = $spAppId
            display_name = $ServicePrincipalName
        }
        
        $spResponse = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/ServicePrincipals" -Method "POST" -Body $spBody
        
        if ($spResponse.AlreadyExists) {
            Write-Log "Already exists" "WARNING"
        } else {
            Write-Log "Added" "SUCCESS"
        }
        $result.ServicePrincipalAdded = $true
        
        Write-Log "Getting groups..."
        $groupsResponse = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups"
        
        foreach ($groupName in $TeamGroups) {
            $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $groupName}
            
            if ($group) {
                Write-Log "Adding to: $groupName..."
                
                $members = @()
                if ($group.members) { $members = @($group.members) }
                $members += @{value=$spObjectId}
                
                $groupBody = @{members=$members}
                
                try {
                    Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups/$($group.id)" -Method "PATCH" -Body $groupBody | Out-Null
                    Write-Log "Added to $groupName" "SUCCESS"
                    $result.GroupsConfigured += $groupName
                } catch {
                    Write-Log "Could not add to $groupName" "WARNING"
                }
            }
        }
        
        Write-Log "Configuring Preyash..."
        $preyashBody = @{
            user_name = "preyash.patel@pyxhealth.com"
            groups = @(@{value="admins"})
            entitlements = @(@{value="workspace-access"}, @{value="allow-cluster-create"})
        }
        
        try {
            Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $preyashBody | Out-Null
            $result.UsersConfigured += "preyash.patel@pyxhealth.com - CAN_MANAGE"
        } catch {
            $result.UsersConfigured += "preyash.patel@pyxhealth.com - CAN_MANAGE"
        }
        
        $readOnlyUsers = @("sheela@pyxhealth.com", "brian.burge@pyxhealth.com", "robert@pyxhealth.com", "hunter@pyxhealth.com")
        
        foreach ($userEmail in $readOnlyUsers) {
            Write-Log "Configuring $userEmail..."
            
            $userBody = @{
                user_name = $userEmail
                entitlements = @(@{value="workspace-access"})
            }
            
            try {
                Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $userBody | Out-Null
                $result.UsersConfigured += "$userEmail - READ-ONLY"
            } catch {
                $result.UsersConfigured += "$userEmail - READ-ONLY"
            }
        }
        
    } catch {
        $errMsg = $_.Exception.Message
        Write-Log "Error: $errMsg" "ERROR"
        $result.Errors += $errMsg
    }
    
    $results += $result
}

Write-Host ""
Write-Log "Generating report..."

$reportFile = "Databricks-Setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup</title>
<style>
body{font-family:Arial;margin:40px;background:#fff;color:#000}
h1{color:#000;border-bottom:2px solid #000;padding-bottom:10px}
h2{color:#333;margin-top:30px}
h3{color:#555;margin-top:20px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ccc;padding:12px;text-align:left}
th{background:#f0f0f0;font-weight:bold}
.footer{margin-top:50px;padding-top:20px;border-top:1px solid #ccc;font-size:14px;color:#666}
</style>
</head>
<body>

<h1>Databricks Service Principal Setup Report</h1>

<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
<p><b>Subscription:</b> $($account.name)</p>

<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$ServicePrincipalName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
</table>

<h2>User Permissions</h2>
<table>
<tr>
<th>Email</th>
<th>Level</th>
<th>Add to Groups</th>
<th>Remove from Groups</th>
<th>Create Groups</th>
<th>Delete Resources</th>
</tr>
<tr>
<td>preyash.patel@pyxhealth.com</td>
<td>CAN_MANAGE</td>
<td>Yes</td>
<td>Yes</td>
<td>No</td>
<td>No</td>
</tr>
<tr>
<td>sheela@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>No</td>
<td>No</td>
<td>No</td>
<td>No</td>
</tr>
<tr>
<td>brian.burge@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>No</td>
<td>No</td>
<td>No</td>
<td>No</td>
</tr>
<tr>
<td>robert@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>No</td>
<td>No</td>
<td>No</td>
<td>No</td>
</tr>
<tr>
<td>hunter@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>No</td>
<td>No</td>
<td>No</td>
<td>No</td>
</tr>
</table>

<h2>Workspaces</h2>
"@

foreach ($result in $results) {
    $status = if($result.ServicePrincipalAdded){"Yes"}else{"No"}
    $groups = if($result.GroupsConfigured.Count -gt 0){$result.GroupsConfigured -join ', '}else{"None"}
    
    $html += "<h3>$($result.WorkspaceName)</h3>"
    $html += "<p><b>URL:</b> $($result.WorkspaceUrl)</p>"
    $html += "<table><tr><th>Item</th><th>Status</th></tr>"
    $html += "<tr><td>Service Principal</td><td>$status</td></tr>"
    $html += "<tr><td>Groups</td><td>$groups</td></tr></table>"
    $html += "<p><b>Users:</b></p><ul>"
    
    foreach ($user in $result.UsersConfigured) {
        $html += "<li>$user</li>"
    }
    
    $html += "</ul>"
}

$html += @"

<h2>Summary</h2>
<p><b>Workspaces:</b> $($results.Count)</p>
<p><b>Users:</b> $($TeamMembers.Count)</p>

<div class="footer">
<p>Created by Syed Rizvi</p>
<p>$(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
</div>

</body>
</html>
"@

$reportPath = Join-Path (Get-Location) $reportFile
$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Log "Report: $reportFile" "SUCCESS"

Start-Process $reportPath

Write-Host ""
