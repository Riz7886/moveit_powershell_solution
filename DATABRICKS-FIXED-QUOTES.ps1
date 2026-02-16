$ErrorActionPreference = "Stop"

# Configuration
$TeamMembers = @(
    "preyash.patel@pyxhealth.com",
    "sheela@pyxhealth.com", 
    "brian.burge@pyxhealth.com",
    "robert@pyxhealth.com",
    "hunter@pyxhealth.com"
)

$TeamGroups = @(
    "admins",
    "prod-datateam"
)

$ServicePrincipalName = "databricks-jobs-service-principal"

# Functions
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

# Main
Write-Host ""
Write-Host "DATABRICKS SERVICE PRINCIPAL SETUP" -ForegroundColor Cyan
Write-Host ""

Write-Log "Step 1: Checking Azure authentication..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Log "Logging in to Azure..." "WARNING"
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-Log "Logged in as: $($account.user.name)" "SUCCESS"
$subscriptionId = $account.id

Write-Log "Step 2: Auto-discovering Databricks workspaces..."
$workspaces = az databricks workspace list --subscription $subscriptionId 2>$null | ConvertFrom-Json

if (-not $workspaces -or $workspaces.Count -eq 0) {
    Write-Log "Trying alternative method..." "WARNING"
    $allResources = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subscriptionId | ConvertFrom-Json
    $workspaces = $allResources
}

Write-Log "Found $($workspaces.Count) Databricks workspace(s)" "SUCCESS"

Write-Log "Step 3: Creating Service Principal: $ServicePrincipalName"
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

Write-Log "Step 4: Getting Databricks token..."
$databricksToken = Get-AzureToken -Resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
Write-Log "Token acquired" "SUCCESS"

Write-Log "Step 5: Processing workspaces..."
$results = @()

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Log "WORKSPACE: $($workspace.name)" "INFO"
    
    $workspaceUrl = if ($workspace.properties.workspaceUrl) {
        "https://$($workspace.properties.workspaceUrl)"
    } else {
        $rgName = ($workspace.id -split '/')[4]
        $wsName = $workspace.name
        
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
    }
    
    try {
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
                Write-Log "Service principal already exists" "WARNING"
            } else {
                Write-Log "Service principal added!" "SUCCESS"
            }
            $workspaceResult.ServicePrincipalAdded = $true
            
        } catch {
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*409*") {
                Write-Log "Service principal already exists" "WARNING"
                $workspaceResult.ServicePrincipalAdded = $true
            } else {
                throw
            }
        }
        
        $sps = Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/ServicePrincipals"
        $databricksSP = $sps.Resources | Where-Object { $_.applicationId -eq $spAppId }
        $databricksSPId = $databricksSP.id
        
        Write-Log "Adding to groups..." "INFO"
        
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
                    
                    Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Groups/$groupId" -Method "PATCH" -Body $patchBody | Out-Null
                    Write-Log "Added to group: $groupName" "SUCCESS"
                    $workspaceResult.GroupsConfigured += $groupName
                }
            } catch {
                Write-Log "Could not add to group $groupName : $_" "WARNING"
            }
        }
        
        Write-Log "Configuring users..." "INFO"
        
        $preyashBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "preyash.patel@pyxhealth.com"
            entitlements = @(
                @{value = "workspace-access"}
                @{value = "allow-cluster-create"}
            )
        }
        
        try {
            Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $preyashBody | Out-Null
            $workspaceResult.UsersConfigured += "preyash.patel@pyxhealth.com (CAN_MANAGE)"
        } catch {}
        
        foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
            $userBody = @{
                schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
                userName = $email
                entitlements = @(@{value = "workspace-access"})
            }
            
            try {
                Invoke-DatabricksAPI -WorkspaceUrl $workspaceUrl -Token $databricksToken -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $userBody | Out-Null
                $workspaceResult.UsersConfigured += "$email (READ-ONLY)"
            } catch {}
        }
        
        Write-Log "WORKSPACE COMPLETE" "SUCCESS"
        
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
    }
    
    $results += $workspaceResult
}

Write-Host ""
Write-Host "SETUP COMPLETE!" -ForegroundColor Green
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $spAppId" -ForegroundColor Cyan
Write-Host ""
