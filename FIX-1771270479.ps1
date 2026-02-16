$ErrorActionPreference = "Stop"

Write-Host "DATABRICKS SETUP STARTING..." -ForegroundColor Cyan

$spName = "databricks-jobs-service-principal"

Write-Host "[1] Login Check" -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "Logged in: $($account.user.name)" -ForegroundColor Green
$subId = $account.id

Write-Host "[2] Service Principal" -ForegroundColor Yellow
$sp = az ad sp list --display-name $spName | ConvertFrom-Json

if ($sp -and $sp.Count -gt 0) {
    $appId = $sp[0].appId
    Write-Host "Using existing: $appId" -ForegroundColor Yellow
} else {
    Write-Host "Creating new SP..." -ForegroundColor White
    $new = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 20
    $created = az ad sp show --id $new.appId | ConvertFrom-Json
    $appId = $created.appId
    Write-Host "Created: $appId" -ForegroundColor Green
}

Write-Host "[3] Finding Workspaces" -ForegroundColor Yellow
$workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subId | ConvertFrom-Json

if (-not $workspaces -or $workspaces.Count -eq 0) {
    Write-Host "Using hardcoded..." -ForegroundColor Yellow
    $workspaces = @(
        [PSCustomObject]@{
            name = "pyxlake-databricks"
            id = "/subscriptions/$subId/resourceGroups/rg-adls-poc/providers/Microsoft.Databricks/workspaces/pyxlake-databricks"
            properties = [PSCustomObject]@{workspaceUrl = "adb-3248848193480666.6.azuredatabricks.net"}
        }
        [PSCustomObject]@{
            name = "pyx-warehouse-prod"
            id = "/subscriptions/$subId/resourceGroups/rg-warehouse-preprod/providers/Microsoft.Databricks/workspaces/pyx-warehouse-prod"
            properties = [PSCustomObject]@{workspaceUrl = "adb-2756318924173706.6.azuredatabricks.net"}
        }
    )
}

Write-Host "Found: $($workspaces.Count)" -ForegroundColor Green

Write-Host "[4] Getting Token" -ForegroundColor Yellow
$token = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv
Write-Host "Token OK" -ForegroundColor Green

Write-Host "[5] Processing Workspaces" -ForegroundColor Yellow

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Host "=> $($workspace.name)" -ForegroundColor Cyan
    
    $wsUrl = "https://$($workspace.properties.workspaceUrl)"
    Write-Host "   URL: $wsUrl" -ForegroundColor White
    
    $headers = @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    try {
        Write-Host "   [A] Adding SP to workspace..." -ForegroundColor White
        
        $spBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
            applicationId = $appId
            displayName = $spName
            active = $true
        }
        
        $spJson = $spBody | ConvertTo-Json -Depth 10 -Compress
        
        try {
            $addResult = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Method Post -Headers $headers -Body $spJson -ContentType "application/json"
            Write-Host "      Added" -ForegroundColor Green
        } catch {
            $err = $_.Exception.Response.StatusCode.value__
            if ($err -eq 409) {
                Write-Host "      Already exists" -ForegroundColor Yellow
            } else {
                throw
            }
        }
        
        Write-Host "   [B] Getting SP ID..." -ForegroundColor White
        $allSPs = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals" -Headers $headers
        $targetSP = $allSPs.Resources | Where-Object { $_.applicationId -eq $appId }
        $spId = $targetSP.id
        Write-Host "      ID: $spId" -ForegroundColor Green
        
        Write-Host "   [C] Adding to groups..." -ForegroundColor White
        foreach ($groupName in @("admins", "prod-datateam")) {
            try {
                $filterQuery = "displayName eq `"$groupName`""
                $encodedFilter = [System.Uri]::EscapeDataString($filterQuery)
                $groupsResult = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups?filter=$encodedFilter" -Headers $headers
                
                if ($groupsResult.Resources -and $groupsResult.Resources.Count -gt 0) {
                    $groupId = $groupsResult.Resources[0].id
                    
                    $patchBody = @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(
                            @{
                                op = "add"
                                path = "members"
                                value = @(@{value = $spId})
                            }
                        )
                    }
                    
                    $patchJson = $patchBody | ConvertTo-Json -Depth 10 -Compress
                    
                    Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups/$groupId" -Method Patch -Headers $headers -Body $patchJson -ContentType "application/json" | Out-Null
                    Write-Host "      $groupName : OK" -ForegroundColor Green
                }
            } catch {
                Write-Host "      $groupName : SKIP" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   [D] Adding users..." -ForegroundColor White
        
        $user1Body = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "preyash.patel@pyxhealth.com"
            entitlements = @(
                @{value = "workspace-access"}
                @{value = "allow-cluster-create"}
            )
        }
        
        $user1Json = $user1Body | ConvertTo-Json -Depth 10 -Compress
        
        try {
            Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Users" -Method Post -Headers $headers -Body $user1Json -ContentType "application/json" | Out-Null
            Write-Host "      preyash.patel : OK" -ForegroundColor Green
        } catch {
            Write-Host "      preyash.patel : EXISTS" -ForegroundColor Yellow
        }
        
        foreach ($email in @("sheela@pyxhealth.com", "brian.burge@pyxhealth.com", "robert@pyxhealth.com", "hunter@pyxhealth.com")) {
            $userBody = @{
                schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
                userName = $email
                entitlements = @(@{value = "workspace-access"})
            }
            
            $userJson = $userBody | ConvertTo-Json -Depth 10 -Compress
            
            try {
                Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Users" -Method Post -Headers $headers -Body $userJson -ContentType "application/json" | Out-Null
                Write-Host "      $email : OK" -ForegroundColor Green
            } catch {
                Write-Host "      $email : EXISTS" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   WORKSPACE COMPLETE" -ForegroundColor Green
        
    } catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "SETUP COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $appId" -ForegroundColor Cyan
Write-Host ""
