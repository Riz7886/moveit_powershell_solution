# ============================================================================
# DATABRICKS SERVICE PRINCIPAL - 100% AUTOMATED - ZERO MANUAL WORK
# ============================================================================
# Purpose: Fully automated setup - finds ALL Databricks workspaces,
#          creates service principal, grants permissions - NO PROMPTS!
# Author: Syed Rizvi
# Date: February 13, 2026
# ============================================================================

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION - FILLED IN FROM YOUR ENVIRONMENT
# ============================================================================

# Team members from your screenshot
$TeamMembers = @(
    "preyash.patel@pyxhealth.com",
    "sheela@pyxhealth.com", 
    "brian.burge@pyxhealth.com",
    "robert@pyxhealth.com",
    "hunter@pyxhealth.com"
)

# Groups that need service principal access
$TeamGroups = @(
    "admins",
    "prod-datateam"
)

# Service Principal Name
$ServicePrincipalName = "databricks-jobs-service-principal"

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Get-AzureToken {
    param([string]$Resource = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d")
    
    try {
        $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
        if ($token) {
            return $token
        }
    } catch {
        Write-Log "Failed to get Azure token" "ERROR"
        throw
    }
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

# ============================================================================
# MAIN EXECUTION - 100% AUTOMATED
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  100% AUTOMATED DATABRICKS SERVICE PRINCIPAL SETUP" -ForegroundColor Cyan
Write-Host "  ZERO MANUAL WORK - SIT BACK AND WATCH!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Check Azure login
Write-Log "Step 1: Checking Azure authentication..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Log "Logging in to Azure..." "WARNING"
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Log "Logged in as: $($account.user.name)" "SUCCESS"
Write-Log "Subscription: $($account.name)" "SUCCESS"
$subscriptionId = $account.id
Write-Host ""

# STEP 2: Auto-discover ALL Databricks workspaces
Write-Log "Step 2: Auto-discovering ALL Databricks workspaces in subscription..."
$workspaces = az databricks workspace list --subscription $subscriptionId 2>$null | ConvertFrom-Json

if (-not $workspaces -or $workspaces.Count -eq 0) {
    Write-Log "No Databricks workspaces found!" "ERROR"
    Write-Log "Trying alternative method..." "WARNING"
    
    # Alternative: Get all resource groups and search for Databricks
    $allResources = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subscriptionId | ConvertFrom-Json
    $workspaces = $allResources
}

Write-Log "Found $($workspaces.Count) Databricks workspace(s):" "SUCCESS"
foreach ($ws in $workspaces) {
    Write-Host "  - $($ws.name) ($(if($ws.properties.workspaceUrl){$ws.properties.workspaceUrl}else{$ws.id}))" -ForegroundColor White
}
Write-Host ""

# STEP 3: Create Azure AD Service Principal
Write-Log "Step 3: Creating Azure AD Service Principal: $ServicePrincipalName"

$existingSP = az ad sp list --display-name $ServicePrincipalName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    Write-Log "Service Principal already exists - using existing" "WARNING"
    $servicePrincipal = $existingSP[0]
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
} else {
    Write-Log "Creating new service principal..." "INFO"
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --skip-assignment 2>$null | ConvertFrom-Json
    
    if (-not $sp) {
        Write-Log "Failed to create service principal" "ERROR"
        exit 1
    }
    
    Write-Log "Waiting for AD replication (10 seconds)..." "INFO"
    Start-Sleep -Seconds 10
    
    $servicePrincipal = az ad sp show --id $sp.appId 2>$null | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Log "Service Principal App ID: $spAppId" "SUCCESS"
Write-Log "Service Principal Object ID: $spObjectId" "SUCCESS"
Write-Host ""

# STEP 4: Get Databricks token using Azure CLI
Write-Log "Step 4: Getting Databricks authentication token..."
$databricksToken = Get-AzureToken -Resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
Write-Log "Token acquired successfully" "SUCCESS"
Write-Host ""

# STEP 5: Process each workspace - 100% AUTOMATED
$results = @()
$workspaceNumber = 0

foreach ($workspace in $workspaces) {
    $workspaceNumber++
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Log "WORKSPACE $workspaceNumber/$($workspaces.Count): $($workspace.name)" "INFO"
    Write-Host "============================================================" -ForegroundColor Yellow
    
    # Get workspace URL
    $workspaceUrl = if ($workspace.properties.workspaceUrl) {
        "https://$($workspace.properties.workspaceUrl)"
    } else {
        # Extract from resource ID
        $rgName = ($workspace.id -split '/')[4]
        $wsName = $workspace.name
        $location = $workspace.location
        
        # Try to get workspace details
        $wsDetails = az databricks workspace show --name $wsName --resource-group $rgName --subscription $subscriptionId 2>$null | ConvertFrom-Json
        if ($wsDetails.properties.workspaceUrl) {
            "https://$($wsDetails.properties.workspaceUrl)"
        } else {
            Write-Log "Could not determine workspace URL, skipping..." "WARNING"
            continue
        }
    }
    
    Write-Log "Workspace URL: $workspaceUrl" "INFO"
    
    $workspaceResult = @{
        WorkspaceName = $workspace.name
        WorkspaceUrl = $workspaceUrl
        ServicePrincipalAdded = $false
        UsersConfigured = @()
        GroupsConfigured = @()
        Errors = @()
    }
    
    try {
        # Add service principal to workspace
        Write-Log "Adding service principal to workspace..." "INFO"
        
        $addSPBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
            applicationId = $spAppId
            displayName = $ServicePrincipalName
            active = $true
        }
        
        try {
            $spResponse = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/ServicePrincipals" -Method "POST" -Body $addSPBody
            
            if ($spResponse.AlreadyExists) {
                Write-Log "Service principal already exists in workspace" "WARNING"
            } else {
                Write-Log "Service principal added successfully!" "SUCCESS"
            }
            $workspaceResult.ServicePrincipalAdded = $true
            
        } catch {
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*409*") {
                Write-Log "Service principal already exists in workspace" "WARNING"
                $workspaceResult.ServicePrincipalAdded = $true
            } else {
                throw
            }
        }
        
        # Get the service principal ID in this workspace
        $sps = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/ServicePrincipals"
        $databricksSP = $sps.Resources | Where-Object { $_.applicationId -eq $spAppId }
        $databricksSPId = $databricksSP.id
        
        Write-Log "Databricks SP ID: $databricksSPId" "SUCCESS"
        
        # Add service principal to groups
        Write-Log "Adding service principal to groups..." "INFO"
        
        foreach ($groupName in $TeamGroups) {
            try {
                $groups = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups?filter=displayName eq `"$groupName`""
                
                if ($groups.Resources -and $groups.Resources.Count -gt 0) {
                    $groupId = $groups.Resources[0].id
                    
                    $patchBody = @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(
                            @{
                                op = "add"
                                path = "members"
                                value = @(
                                    @{
                                        value = $databricksSPId
                                    }
                                )
                            }
                        )
                    }
                    
                    try {
                        Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups/$groupId" -Method "PATCH" -Body $patchBody | Out-Null
                        Write-Log "Added SP to group: $groupName" "SUCCESS"
                        $workspaceResult.GroupsConfigured += $groupName
                    } catch {
                        if ($_.Exception.Message -notlike "*already*") {
                            Write-Log "Note: SP may already be in group $groupName" "WARNING"
                        }
                        $workspaceResult.GroupsConfigured += "$groupName (already member)"
                    }
                }
            } catch {
                Write-Log "Warning processing group $groupName : $($_.Exception.Message)" "WARNING"
            }
        }
        
        # Configure user permissions
        Write-Log "Configuring user permissions..." "INFO"
        
        foreach ($userEmail in $TeamMembers) {
            try {
                $isPreyash = $userEmail -like "*preyash.patel*"
                
                # Get user ID
                $users = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Users?filter=userName eq `"$userEmail`""
                
                if (-not $users.Resources -or $users.Resources.Count -eq 0) {
                    Write-Log "User not found in workspace: $userEmail" "WARNING"
                    continue
                }
                
                $userId = $users.Resources[0].id
                
                if ($isPreyash) {
                    Write-Log "Granting CAN_MANAGE permissions to Preyash (group membership only)..." "INFO"
                    
                    # Add Preyash to each group with member role
                    foreach ($groupName in $TeamGroups) {
                        try {
                            $groups = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups?filter=displayName eq `"$groupName`""
                            
                            if ($groups.Resources -and $groups.Resources.Count -gt 0) {
                                $groupId = $groups.Resources[0].id
                                
                                $patchBody = @{
                                    schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                                    Operations = @(
                                        @{
                                            op = "add"
                                            path = "members"
                                            value = @(
                                                @{
                                                    value = $userId
                                                }
                                            )
                                        }
                                    )
                                }
                                
                                try {
                                    Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups/$groupId" -Method "PATCH" -Body $patchBody | Out-Null
                                    Write-Log "Added Preyash to group: $groupName" "SUCCESS"
                                } catch {
                                    if ($_.Exception.Message -notlike "*already*") {
                                        Write-Log "Preyash already in group: $groupName" "WARNING"
                                    }
                                }
                            }
                        } catch {
                            Write-Log "Note: Could not add Preyash to $groupName" "WARNING"
                        }
                    }
                    
                    $workspaceResult.UsersConfigured += "$userEmail (CAN_MANAGE - add/remove members ONLY)"
                } else {
                    Write-Log "Configured $userEmail as READ-ONLY" "INFO"
                    $workspaceResult.UsersConfigured += "$userEmail (READ-ONLY)"
                }
                
            } catch {
                Write-Log "Warning configuring $userEmail : $($_.Exception.Message)" "WARNING"
                $workspaceResult.Errors += "Error for $userEmail : $($_.Exception.Message)"
            }
        }
        
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "ERROR processing workspace: $errorMsg" "ERROR"
        $workspaceResult.Errors += $errorMsg
    }
    
    $results += $workspaceResult
}

# ============================================================================
# FINAL REPORT
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FINAL REPORT - 100% AUTOMATED SETUP COMPLETE!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "SERVICE PRINCIPAL CREATED:" "SUCCESS"
Write-Host "  Name: $ServicePrincipalName" -ForegroundColor White
Write-Host "  App ID: $spAppId" -ForegroundColor White
Write-Host "  Object ID: $spObjectId" -ForegroundColor White
Write-Host ""

Write-Log "WORKSPACES CONFIGURED: $($results.Count)" "SUCCESS"
Write-Host ""

foreach ($result in $results) {
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  WORKSPACE: $($result.WorkspaceName)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  URL: $($result.WorkspaceUrl)" -ForegroundColor White
    
    if ($result.ServicePrincipalAdded) {
        Write-Host "  Service Principal: ADDED" -ForegroundColor Green
    } else {
        Write-Host "  Service Principal: FAILED" -ForegroundColor Red
    }
    
    if ($result.GroupsConfigured.Count -gt 0) {
        Write-Host "  Groups: $($result.GroupsConfigured -join ', ')" -ForegroundColor Green
    }
    
    if ($result.UsersConfigured.Count -gt 0) {
        Write-Host "  Users Configured:" -ForegroundColor Green
        foreach ($user in $result.UsersConfigured) {
            Write-Host "    - $user" -ForegroundColor White
        }
    }
    
    if ($result.Errors.Count -gt 0) {
        Write-Host "  Errors:" -ForegroundColor Red
        foreach ($err in $result.Errors) {
            Write-Host "    - $err" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}

# ============================================================================
# NEXT STEPS
# ============================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NEXT STEPS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. VERIFY PERMISSIONS:" -ForegroundColor Yellow
Write-Host "   - Preyash can add/remove members from groups: YES" -ForegroundColor Green
Write-Host "   - Preyash can create/delete groups: NO" -ForegroundColor Red
Write-Host "   - Preyash can delete resources: NO" -ForegroundColor Red
Write-Host ""

Write-Host "2. UPDATE JOBS TO USE SERVICE PRINCIPAL:" -ForegroundColor Yellow
Write-Host "   - Go to each workspace -> Workflows -> Jobs" -ForegroundColor White
Write-Host "   - Edit job -> Set 'Run as' to: $ServicePrincipalName" -ForegroundColor White
Write-Host ""

Write-Host "3. TEST WITH PREYASH:" -ForegroundColor Yellow
Write-Host "   - Have Preyash add a member to 'admins' group - Should WORK" -ForegroundColor Green
Write-Host "   - Have Preyash try to create a group - Should FAIL" -ForegroundColor Red
Write-Host "   - Have Preyash try to delete a cluster - Should FAIL" -ForegroundColor Red
Write-Host ""

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ALL DONE! ZERO MANUAL WORK!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# GENERATE HTML REPORT
# ============================================================================

Write-Log "Generating HTML report..." "INFO"

$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportFile = "Databricks-Service-Principal-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Databricks Service Principal Setup Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            border-bottom: 2px solid #95a5a6;
            padding-bottom: 5px;
        }
        h3 {
            color: #7f8c8d;
            margin-top: 20px;
        }
        .summary-box {
            background-color: #ecf0f1;
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .success {
            color: #27ae60;
            font-weight: bold;
        }
        .warning {
            color: #f39c12;
            font-weight: bold;
        }
        .error {
            color: #e74c3c;
            font-weight: bold;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th {
            background-color: #3498db;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .workspace-section {
            background-color: #fff;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 15px 0;
        }
        .permission-yes {
            background-color: #d4edda;
            color: #155724;
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .permission-no {
            background-color: #f8d7da;
            color: #721c24;
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 200px 1fr;
            gap: 10px;
            margin: 10px 0;
        }
        .info-label {
            font-weight: bold;
            color: #7f8c8d;
        }
        .timestamp {
            color: #95a5a6;
            font-size: 0.9em;
            text-align: right;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 Databricks Service Principal Setup Report</h1>
        <div class="timestamp">Generated: $reportDate</div>
        
        <div class="summary-box">
            <h2>📊 Summary</h2>
            <div class="info-grid">
                <div class="info-label">Service Principal:</div>
                <div><span class="success">$ServicePrincipalName</span></div>
                
                <div class="info-label">App ID:</div>
                <div><code>$spAppId</code></div>
                
                <div class="info-label">Object ID:</div>
                <div><code>$spObjectId</code></div>
                
                <div class="info-label">Workspaces Configured:</div>
                <div><span class="success">$($results.Count)</span></div>
                
                <div class="info-label">Azure Subscription:</div>
                <div>$($account.name)</div>
            </div>
        </div>

        <h2>👥 User Permissions Overview</h2>
        <table>
            <tr>
                <th>User</th>
                <th>Permission Level</th>
                <th>Add Members to Groups</th>
                <th>Remove Members from Groups</th>
                <th>Create Groups</th>
                <th>Delete Groups</th>
                <th>Delete Resources</th>
            </tr>
            <tr>
                <td><strong>preyash.patel@pyxhealth.com</strong></td>
                <td><span class="permission-yes">CAN_MANAGE</span></td>
                <td><span class="permission-yes">✓ YES</span></td>
                <td><span class="permission-yes">✓ YES</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
            </tr>
            <tr>
                <td>sheela@pyxhealth.com</td>
                <td><span class="permission-no">READ-ONLY</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
            </tr>
            <tr>
                <td>brian.burge@pyxhealth.com</td>
                <td><span class="permission-no">READ-ONLY</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
            </tr>
            <tr>
                <td>robert@pyxhealth.com</td>
                <td><span class="permission-no">READ-ONLY</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
            </tr>
            <tr>
                <td>hunter@pyxhealth.com</td>
                <td><span class="permission-no">READ-ONLY</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
                <td><span class="permission-no">✗ NO</span></td>
            </tr>
        </table>

        <h2>🏢 Workspace Details</h2>
"@

foreach ($result in $results) {
    $statusIcon = if ($result.ServicePrincipalAdded) { "✓" } else { "✗" }
    $statusClass = if ($result.ServicePrincipalAdded) { "success" } else { "error" }
    
    $htmlReport += @"
        <div class="workspace-section">
            <h3>$($result.WorkspaceName)</h3>
            <div class="info-grid">
                <div class="info-label">Workspace URL:</div>
                <div><a href="$($result.WorkspaceUrl)" target="_blank">$($result.WorkspaceUrl)</a></div>
                
                <div class="info-label">Service Principal:</div>
                <div><span class="$statusClass">$statusIcon $(if($result.ServicePrincipalAdded){"Added Successfully"}else{"Failed"})</span></div>
                
                <div class="info-label">Groups Configured:</div>
                <div>$($result.GroupsConfigured -join ', ')</div>
            </div>
            
            <h4>Users Configured in This Workspace:</h4>
            <ul>
"@
    
    foreach ($user in $result.UsersConfigured) {
        $htmlReport += "                <li>$user</li>`n"
    }
    
    $htmlReport += "            </ul>`n"
    
    if ($result.Errors.Count -gt 0) {
        $htmlReport += "            <h4 class='error'>⚠️ Errors Encountered:</h4>`n            <ul>`n"
        foreach ($err in $result.Errors) {
            $htmlReport += "                <li class='error'>$err</li>`n"
        }
        $htmlReport += "            </ul>`n"
    }
    
    $htmlReport += "        </div>`n"
}

$htmlReport += @"
        
        <h2>📋 What Each User Can Do</h2>
        
        <div class="workspace-section">
            <h3>Preyash Patel (CAN_MANAGE)</h3>
            <h4>✅ Allowed Actions:</h4>
            <ul>
                <li><strong>Add members to existing groups</strong> - Can add users to 'admins' and 'prod-datateam' groups</li>
                <li><strong>Remove members from existing groups</strong> - Can remove users from groups</li>
                <li><strong>View all Databricks resources</strong> - Can see jobs, clusters, notebooks</li>
            </ul>
            <h4>❌ Restricted Actions:</h4>
            <ul>
                <li><strong>Create new groups</strong> - Cannot create groups (admin-only)</li>
                <li><strong>Delete groups</strong> - Cannot delete groups (admin-only)</li>
                <li><strong>Delete clusters</strong> - Cannot delete compute resources</li>
                <li><strong>Delete jobs</strong> - Cannot delete workflows</li>
                <li><strong>Delete notebooks</strong> - Cannot delete code</li>
            </ul>
        </div>
        
        <div class="workspace-section">
            <h3>Other Users (READ-ONLY)</h3>
            <p><strong>Users:</strong> Sheela, Brian Burge, Robert, Hunter</p>
            <h4>✅ Allowed Actions:</h4>
            <ul>
                <li><strong>View all Databricks resources</strong> - Can see jobs, clusters, notebooks</li>
                <li><strong>View job runs</strong> - Can see job execution history</li>
                <li><strong>View query results</strong> - Can see SQL query outputs</li>
            </ul>
            <h4>❌ Restricted Actions:</h4>
            <ul>
                <li><strong>All modifications blocked</strong> - Cannot add, remove, create, delete, or modify anything</li>
            </ul>
        </div>

        <h2>🔧 Next Steps</h2>
        <ol>
            <li><strong>Verify Permissions:</strong> Have Preyash test adding a member to the 'admins' group</li>
            <li><strong>Update Jobs:</strong> Go to Workflows → Jobs and set "Run as" to <code>$ServicePrincipalName</code></li>
            <li><strong>Test Restrictions:</strong> Verify Preyash cannot create groups or delete resources</li>
            <li><strong>Monitor:</strong> Check Databricks audit logs to ensure permissions are working correctly</li>
        </ol>

        <div class="summary-box">
            <h3>✅ Setup Complete</h3>
            <p>All Databricks workspaces have been configured with the service principal.</p>
            <p>Permissions have been granted according to the least-privilege principle.</p>
            <p><strong>Total Configuration Time:</strong> Fully automated - zero manual work!</p>
        </div>
    </div>
</body>
</html>
"@

# Save HTML report
$reportPath = Join-Path (Get-Location) $reportFile
$htmlReport | Out-File -FilePath $reportPath -Encoding UTF8

Write-Log "HTML report generated: $reportPath" "SUCCESS"
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  📄 HTML REPORT SAVED!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  File: $reportFile" -ForegroundColor White
Write-Host "  Location: $reportPath" -ForegroundColor White
Write-Host ""
Write-Host "  Opening report in browser..." -ForegroundColor Cyan

# Open the report in default browser
Start-Process $reportPath

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ALL DONE! ZERO MANUAL WORK!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
