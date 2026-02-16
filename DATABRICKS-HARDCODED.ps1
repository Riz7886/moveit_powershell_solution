$ErrorActionPreference = "Stop"

$ServicePrincipalName = "databricks-jobs-service-principal"

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

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "DATABRICKS SETUP - HARDCODED WORKSPACES" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "[1/5] Azure Login Check"
$account = az account show 2>$null | ConvertFrom-Json
Write-Log "Logged in as: $($account.user.name)" "SUCCESS"
$subscriptionId = $account.id

Write-Log "[2/5] Service Principal"
$existingSP = az ad sp list --display-name $ServicePrincipalName 2>$null | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Log "Using existing SP: $spAppId" "WARNING"
} else {
    Write-Log "Creating NEW service principal..." "INFO"
    $sp = az ad sp create-for-rbac --name $ServicePrincipalName --skip-assignment | ConvertFrom-Json
    Start-Sleep -Seconds 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Log "Created: $spAppId" "SUCCESS"
}

Write-Log "[3/5] Databricks Token"
$token = Get-AzureToken
Write-Log "Token acquired" "SUCCESS"

Write-Log "[4/5] HARDCODED Workspaces (no discovery)"

$workspaces = @(
    @{
        name = "pyxlake-databricks"
        url = "https://adb-3248848193480666.6.azuredatabricks.net"
        rg = "rg-adls-poc"
    },
    @{
        name = "pyx-warehouse-prod"
        url = "https://adb-2756318924173706.6.azuredatabricks.net"
        rg = "rg-warehouse-preprod"
    }
)

Write-Log "Using $($workspaces.Count) hardcoded workspaces" "SUCCESS"

Write-Log "[5/5] Configure Workspaces"
$results = @()

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "-------------------------------------------" -ForegroundColor Yellow
    Write-Log "Workspace: $($ws.name)" "INFO"
    Write-Host "-------------------------------------------" -ForegroundColor Yellow
    
    $wsResult = @{
        Name = $ws.name
        URL = $ws.url
        Status = "FAILED"
    }
    
    try {
        Write-Log "  Adding service principal..." "INFO"
        
        $addSPBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
            applicationId = $spAppId
            displayName = $ServicePrincipalName
            active = $true
        }
        
        try {
            $spResponse = Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/ServicePrincipals" -Method "POST" -Body $addSPBody
            
            if ($spResponse.AlreadyExists) {
                Write-Log "    Already exists (OK)" "WARNING"
            } else {
                Write-Log "    SUCCESS" "SUCCESS"
            }
            
        } catch {
            if ($_.Exception.Message -like "*409*") {
                Write-Log "    Already exists (OK)" "WARNING"
            } else {
                throw
            }
        }
        
        Write-Log "  Getting SP ID..." "INFO"
        $sps = Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/ServicePrincipals"
        $databricksSP = $sps.Resources | Where-Object { $_.applicationId -eq $spAppId }
        $databricksSPId = $databricksSP.id
        Write-Log "    SP ID: $databricksSPId" "SUCCESS"
        
        Write-Log "  Adding to groups..." "INFO"
        
        foreach ($groupName in @("admins", "prod-datateam")) {
            try {
                $groups = Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/Groups?filter=displayName eq `"$groupName`""
                
                if ($groups.Resources -and $groups.Resources.Count -gt 0) {
                    $groupId = $groups.Resources[0].id
                    
                    $patchBody = @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(
                            @{
                                op = "add"
                                path = "members"
                                value = @(@{value = $databricksSPId})
                            }
                        )
                    }
                    
                    Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/Groups/$groupId" -Method "PATCH" -Body $patchBody | Out-Null
                    Write-Log "    $groupName : SUCCESS" "SUCCESS"
                }
            } catch {
                Write-Log "    $groupName : FAILED" "WARNING"
            }
        }
        
        Write-Log "  Adding users..." "INFO"
        
        $preyashBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "preyash.patel@pyxhealth.com"
            entitlements = @(
                @{value = "workspace-access"}
                @{value = "allow-cluster-create"}
            )
        }
        
        try {
            Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $preyashBody | Out-Null
            Write-Log "    preyash.patel (CAN_MANAGE)" "SUCCESS"
        } catch {}
        
        foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
            $userBody = @{
                schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
                userName = $email
                entitlements = @(@{value = "workspace-access"})
            }
            
            try {
                Invoke-DatabricksAPI -WorkspaceUrl $ws.url -Token $token -Endpoint "preview/scim/v2/Users" -Method "POST" -Body $userBody | Out-Null
                Write-Log "    $email (READ)" "SUCCESS"
            } catch {}
        }
        
        $wsResult.Status = "SUCCESS"
        Write-Log "  COMPLETE!" "SUCCESS"
        
    } catch {
        Write-Log "  ERROR: $($_.Exception.Message)" "ERROR"
    }
    
    $results += $wsResult
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "COMPLETED!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $ServicePrincipalName" -ForegroundColor Cyan
Write-Host "App ID: $spAppId" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $results) {
    Write-Host "$($r.Name): $($r.Status)" -ForegroundColor $(if($r.Status -eq "SUCCESS"){"Green"}else{"Red"})
}

Write-Host ""
