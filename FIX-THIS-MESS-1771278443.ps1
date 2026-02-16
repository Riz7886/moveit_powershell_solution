$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "FIXING DATABRICKS SERVICE PRINCIPAL MESS" -ForegroundColor Red
Write-Host "=========================================" -ForegroundColor Red
Write-Host ""

$spName = "databricks-jobs-service-principal"
$spAppId = "d519efa6-3cb5-4fa0-8535-c657175be154"

Write-Host "[1] Verifying Service Principal Exists" -ForegroundColor Yellow
$sp = az ad sp show --id $spAppId 2>$null | ConvertFrom-Json

if (-not $sp) {
    Write-Host "ERROR: Service Principal does not exist!" -ForegroundColor Red
    Write-Host "Creating it now..." -ForegroundColor Yellow
    
    $newSP = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 30
    $sp = az ad sp show --id $newSP.appId | ConvertFrom-Json
    $spAppId = $sp.appId
}

Write-Host "SP Found: $($sp.displayName)" -ForegroundColor Green
Write-Host "App ID: $spAppId" -ForegroundColor Green

Write-Host ""
Write-Host "[2] Getting Databricks Token" -ForegroundColor Yellow
$token = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv
Write-Host "Token acquired" -ForegroundColor Green

$workspaces = @(
    @{Name="pyx-warehouse-prod PREPROD"; Url="https://adb-2756318924173706.6.azuredatabricks.net"}
    @{Name="pyxlake-databricks PROD"; Url="https://adb-3248848193480666.6.azuredatabricks.net"}
)

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($workspace.Name)" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    
    $wsUrl = $workspace.Url
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    try {
        Write-Host "   [A] Checking if SP already exists..." -ForegroundColor White
        
        $existingSPs = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Headers $headers
        $existing = $existingSPs.Resources | Where-Object { $_.applicationId -eq $spAppId }
        
        if ($existing) {
            Write-Host "      Already exists with ID: $($existing.id)" -ForegroundColor Yellow
            $dbspId = $existing.id
        } else {
            Write-Host "   [B] Adding SP to workspace..." -ForegroundColor White
            
            $spBody = @{
                schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
                applicationId = $spAppId
                displayName = $spName
                active = $true
            }
            
            $spParams = @{
                Uri = "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals"
                Method = "POST"
                Headers = $headers
            }
            
            $spParams.Body = ($spBody | ConvertTo-Json -Depth 10 -Compress)
            
            $result = Invoke-RestMethod @spParams
            $dbspId = $result.id
            Write-Host "      Added successfully: $dbspId" -ForegroundColor Green
        }
        
        Write-Host "   [C] Adding to groups..." -ForegroundColor White
        
        foreach ($groupName in @("admins", "prod-datateam", "datateam")) {
            try {
                $filter = "displayName eq `"$groupName`""
                $encoded = [uri]::EscapeDataString($filter)
                $groups = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups?filter=$encoded" -Headers $headers
                
                if ($groups.Resources -and $groups.Resources.Count -gt 0) {
                    $groupId = $groups.Resources[0].id
                    
                    $patchBody = @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(@{op="add";path="members";value=@(@{value=$dbspId})})
                    }
                    
                    $patchParams = @{
                        Uri = "$wsUrl/api/2.0/preview/scim/v2/Groups/$groupId"
                        Method = "PATCH"
                        Headers = $headers
                    }
                    
                    $patchParams.Body = ($patchBody | ConvertTo-Json -Depth 10 -Compress)
                    
                    Invoke-RestMethod @patchParams | Out-Null
                    Write-Host "      $groupName : ADDED" -ForegroundColor Green
                }
            } catch {
                Write-Host "      $groupName : Already in or doesn't exist" -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Host "   WORKSPACE FIXED!" -ForegroundColor Green
        
    } catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "   If network error, this workspace needs manual setup!" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "FIX COMPLETE!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $spAppId" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOW TELL PREYASH TO:" -ForegroundColor Yellow
Write-Host "1. Refresh the Databricks page" -ForegroundColor White
Write-Host "2. Search for: $spAppId" -ForegroundColor White
Write-Host "3. It should show up now!" -ForegroundColor White
Write-Host ""
