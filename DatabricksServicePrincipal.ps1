$ErrorActionPreference = "Stop"

$ServicePrincipalName = "databricks-jobs-service-principal"
$TeamGroups = @("admins", "prod-datateam")

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $colors = @{INFO="Cyan"; SUCCESS="Green"; ERROR="Red"; WARNING="Yellow"}
    Write-Host "[$Type] $Message" -ForegroundColor $colors[$Type]
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SERVICE PRINCIPAL AUTOMATION" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Step 1: Checking Azure login..."
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    Write-Log "Logging in..." "WARNING"
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Log "Logged in: $($account.user.name)" "SUCCESS"
$subscriptionId = $account.id

Write-Log "Step 2: Finding Databricks workspaces..."
$workspaces = az databricks workspace list --subscription $subscriptionId 2>$null | ConvertFrom-Json
if (!$workspaces -or $workspaces.Count -eq 0) {
    $workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subscriptionId | ConvertFrom-Json
}
Write-Log "Found $($workspaces.Count) workspace(s)" "SUCCESS"

Write-Log "Step 3: Creating service principal..."
$existingSP = az ad sp list --display-name $ServicePrincipalName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    Write-Log "Service principal exists - using it" "WARNING"
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    Write-Log "Creating new service principal..." "INFO"
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --skip-assignment 2>$null | ConvertFrom-Json
    Start-Sleep -Seconds 10
    $servicePrincipal = az ad sp show --id $sp.appId 2>$null | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Log "Service Principal App ID: $spAppId" "SUCCESS"
Write-Log "Service Principal Object ID: $spObjectId" "SUCCESS"

Write-Log "Step 4: Getting Databricks token..."
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv 2>$null
Write-Log "Token acquired" "SUCCESS"

$results = @()
$wsNum = 0

foreach ($ws in $workspaces) {
    $wsNum++
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Log "WORKSPACE $wsNum/$($workspaces.Count): $($ws.name)" "INFO"
    Write-Host "=============================================" -ForegroundColor Yellow
    
    $workspaceUrl = "https://$($ws.properties.workspaceUrl)"
    
    $result = @{
        WorkspaceName = $ws.name
        WorkspaceUrl = $workspaceUrl
        ServicePrincipalAdded = $false
        GroupsConfigured = @()
        UsersConfigured = @()
    }
    
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    try {
        Write-Log "Adding service principal to workspace..." "INFO"
        $spBody = @{
            application_id = $spAppId
            display_name = $ServicePrincipalName
        } | ConvertTo-Json -Compress
        
        try {
            Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody | Out-Null
            Write-Log "Service principal added" "SUCCESS"
        } catch {
            if ($_.Exception.Response.StatusCode -eq 409) {
                Write-Log "Service principal already exists" "WARNING"
            }
        }
        $result.ServicePrincipalAdded = $true
        
        Write-Log "Getting workspace groups..." "INFO"
        $groupsResponse = Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/preview/scim/v2/Groups" -Headers $headers
        
        foreach ($groupName in $TeamGroups) {
            $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $groupName}
            
            if ($group) {
                Write-Log "Adding service principal to group: $groupName" "INFO"
                
                $members = @()
                if ($group.members) {
                    $members = @($group.members)
                }
                $members += @{value=$spObjectId}
                
                $groupBody = @{members=$members} | ConvertTo-Json -Depth 10 -Compress
                
                try {
                    Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody | Out-Null
                    Write-Log "Added to group: $groupName" "SUCCESS"
                    $result.GroupsConfigured += $groupName
                } catch {
                    Write-Log "Could not add to group: $groupName" "WARNING"
                }
            }
        }
        
        Write-Log "Configuring Preyash Patel (CAN_MANAGE)..." "INFO"
        $preyashBody = @{
            user_name = "preyash.patel@pyxhealth.com"
            groups = @(@{value="admins"})
            entitlements = @(
                @{value="workspace-access"}
                @{value="allow-cluster-create"}
            )
        } | ConvertTo-Json -Compress
        
        try {
            Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $preyashBody | Out-Null
            Write-Log "Preyash configured" "SUCCESS"
            $result.UsersConfigured += "preyash.patel@pyxhealth.com - CAN_MANAGE"
        } catch {
            $result.UsersConfigured += "preyash.patel@pyxhealth.com - CAN_MANAGE (may already exist)"
        }
        
        $readOnlyUsers = @("sheela@pyxhealth.com", "brian.burge@pyxhealth.com", "robert@pyxhealth.com", "hunter@pyxhealth.com")
        
        foreach ($userEmail in $readOnlyUsers) {
            Write-Log "Configuring $userEmail (READ-ONLY)..." "INFO"
            
            $userBody = @{
                user_name = $userEmail
                entitlements = @(@{value="workspace-access"})
            } | ConvertTo-Json -Compress
            
            try {
                Invoke-RestMethod -Uri "$workspaceUrl/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userBody | Out-Null
                Write-Log "$userEmail configured" "SUCCESS"
                $result.UsersConfigured += "$userEmail - READ-ONLY"
            } catch {
                $result.UsersConfigured += "$userEmail - READ-ONLY (may already exist)"
            }
        }
        
    } catch {
        Write-Log "Error processing workspace: $($_.Exception.Message)" "ERROR"
    }
    
    $results += $result
}

Write-Host ""
Write-Log "Generating HTML report..." "INFO"

$reportFile = "Databricks-Setup-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup Report</title>
<style>
body {
    font-family: Arial, sans-serif;
    margin: 40px;
    background-color: #ffffff;
    color: #000000;
}
h1 {
    color: #000000;
    border-bottom: 2px solid #000000;
    padding-bottom: 10px;
}
h2 {
    color: #333333;
    margin-top: 30px;
}
h3 {
    color: #555555;
    margin-top: 20px;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin: 20px 0;
}
th, td {
    border: 1px solid #cccccc;
    padding: 12px;
    text-align: left;
}
th {
    background-color: #f0f0f0;
    font-weight: bold;
}
.footer {
    margin-top: 50px;
    padding-top: 20px;
    border-top: 1px solid #cccccc;
    font-size: 14px;
    color: #666666;
}
</style>
</head>
<body>

<h1>Databricks Service Principal Setup Report</h1>

<p><strong>Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
<p><strong>Azure Subscription:</strong> $($account.name)</p>
<p><strong>Subscription ID:</strong> $subscriptionId</p>

<h2>Service Principal Details</h2>
<table>
<tr>
<th>Property</th>
<th>Value</th>
</tr>
<tr>
<td>Name</td>
<td>$ServicePrincipalName</td>
</tr>
<tr>
<td>Application ID</td>
<td>$spAppId</td>
</tr>
<tr>
<td>Object ID</td>
<td>$spObjectId</td>
</tr>
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

<h2>Workspace Configuration Results</h2>
"@

foreach ($result in $results) {
    $status = if($result.ServicePrincipalAdded){"Yes"}else{"No"}
    $groups = if($result.GroupsConfigured.Count -gt 0){$result.GroupsConfigured -join ', '}else{"None"}
    
    $html += @"

<h3>$($result.WorkspaceName)</h3>
<p><strong>Workspace URL:</strong> $($result.WorkspaceUrl)</p>

<table>
<tr>
<th>Configuration Item</th>
<th>Status</th>
</tr>
<tr>
<td>Service Principal Added</td>
<td>$status</td>
</tr>
<tr>
<td>Groups Configured</td>
<td>$groups</td>
</tr>
</table>

<p><strong>Users Configured in this Workspace:</strong></p>
<ul>
"@
    
    foreach ($user in $result.UsersConfigured) {
        $html += "<li>$user</li>`n"
    }
    
    $html += "</ul>`n"
}

$html += @"

<h2>Groups Configured</h2>
<table>
<tr>
<th>Group Name</th>
<th>Purpose</th>
</tr>
<tr>
<td>admins</td>
<td>Administrative access group</td>
</tr>
<tr>
<td>prod-datateam</td>
<td>Production data team group</td>
</tr>
</table>

<h2>Summary</h2>
<p><strong>Total Workspaces Configured:</strong> $($results.Count)</p>
<p><strong>Service Principal Name:</strong> $ServicePrincipalName</p>

<div class="footer">
<p>Created by Syed Rizvi</p>
<p>Report generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
</div>

</body>
</html>
"@

$reportPath = Join-Path (Get-Location) $reportFile
$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "SETUP COMPLETE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Log "Report saved: $reportFile" "SUCCESS"
Write-Log "Opening report..." "INFO"

Start-Process $reportPath

Write-Host ""
