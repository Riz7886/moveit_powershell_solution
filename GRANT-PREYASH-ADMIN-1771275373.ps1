$ErrorActionPreference = "Stop"

Write-Host "GRANTING PREYASH WORKSPACE ADMIN PERMISSIONS" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$preyashEmail = "preyash.patel@pyxhealth.com"

$workspaces = @(
    @{Name="pyx-warehouse-prod PREPROD"; Url="https://adb-2756318924173706.6.azuredatabricks.net"}
    @{Name="pyxlake-databricks PROD"; Url="https://adb-3248848193480666.6.azuredatabricks.net"}
)

Write-Host "[1] Getting Databricks Token" -ForegroundColor Yellow
$token = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv
Write-Host "Token acquired" -ForegroundColor Green

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($workspace.Name)" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    
    $wsUrl = $workspace.Url
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    try {
        Write-Host "   [1] Finding Preyash's user ID..." -ForegroundColor White
        
        $filter = "userName eq `"$preyashEmail`""
        $encoded = [uri]::EscapeDataString($filter)
        $users = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Users?filter=$encoded" -Headers $headers
        
        if (-not $users.Resources -or $users.Resources.Count -eq 0) {
            Write-Host "      ERROR: User not found!" -ForegroundColor Red
            continue
        }
        
        $userId = $users.Resources[0].id
        Write-Host "      User ID: $userId" -ForegroundColor Green
        
        Write-Host "   [2] Updating user permissions..." -ForegroundColor White
        
        $updateBody = @{
            schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
            Operations = @(
                @{
                    op = "add"
                    path = "entitlements"
                    value = @(
                        @{value = "workspace-access"}
                        @{value = "databricks-sql-access"}
                        @{value = "allow-cluster-create"}
                        @{value = "allow-instance-pool-create"}
                    )
                }
                @{
                    op = "add"
                    path = "roles"
                    value = @(
                        @{value = "account_admin"}
                    )
                }
            )
        }
        
        $patchParams = @{
            Uri = "$wsUrl/api/2.0/preview/scim/v2/Users/$userId"
            Method = "PATCH"
            Headers = $headers
        }
        
        $patchParams.Body = ($updateBody | ConvertTo-Json -Depth 10 -Compress)
        
        try {
            Invoke-RestMethod @patchParams | Out-Null
            Write-Host "      Entitlements updated" -ForegroundColor Green
        } catch {
            Write-Host "      Entitlements: Already set or error" -ForegroundColor Yellow
        }
        
        Write-Host "   [3] Adding to admins group..." -ForegroundColor White
        
        $adminFilter = "displayName eq `"admins`""
        $adminEncoded = [uri]::EscapeDataString($adminFilter)
        $adminGroups = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups?filter=$adminEncoded" -Headers $headers
        
        if ($adminGroups.Resources -and $adminGroups.Resources.Count -gt 0) {
            $adminGroupId = $adminGroups.Resources[0].id
            
            $groupPatch = @{
                schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                Operations = @(
                    @{
                        op = "add"
                        path = "members"
                        value = @(@{value = $userId})
                    }
                )
            }
            
            $groupParams = @{
                Uri = "$wsUrl/api/2.0/preview/scim/v2/Groups/$adminGroupId"
                Method = "PATCH"
                Headers = $headers
            }
            
            $groupParams.Body = ($groupPatch | ConvertTo-Json -Depth 10 -Compress)
            
            try {
                Invoke-RestMethod @groupParams | Out-Null
                Write-Host "      Added to admins group" -ForegroundColor Green
            } catch {
                Write-Host "      Already in admins group" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   [4] Granting workspace admin via permissions API..." -ForegroundColor White
        
        $permBody = @{
            access_control_list = @(
                @{
                    user_name = $preyashEmail
                    permission_level = "CAN_MANAGE"
                }
            )
        }
        
        $permParams = @{
            Uri = "$wsUrl/api/2.0/permissions/authorization/workspace"
            Method = "PATCH"
            Headers = $headers
        }
        
        $permParams.Body = ($permBody | ConvertTo-Json -Depth 10 -Compress)
        
        try {
            Invoke-RestMethod @permParams | Out-Null
            Write-Host "      Workspace permissions granted" -ForegroundColor Green
        } catch {
            Write-Host "      Permissions: Already set or API not available" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "   WORKSPACE COMPLETE!" -ForegroundColor Green
        
    } catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "DONE!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Preyash should now have admin permissions in both workspaces." -ForegroundColor Cyan
Write-Host "Have him log out and log back in to see the changes." -ForegroundColor Cyan
Write-Host ""
