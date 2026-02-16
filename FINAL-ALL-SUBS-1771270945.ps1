$ErrorActionPreference = "Stop"

$spName = "databricks-jobs-service-principal"

Write-Host ""
Write-Host "DATABRICKS SETUP - ALL SUBSCRIPTIONS" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] Login Check" -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "User: $($account.user.name)" -ForegroundColor Green

Write-Host "[2] Finding ALL Subscriptions" -ForegroundColor Yellow
$allSubs = az account list | ConvertFrom-Json
Write-Host "Found: $($allSubs.Count) subscriptions" -ForegroundColor Green

Write-Host "[3] Searching for Databricks in ALL Subscriptions" -ForegroundColor Yellow
$allWorkspaces = @()

foreach ($sub in $allSubs) {
    Write-Host "   Checking: $($sub.name)" -ForegroundColor White
    
    az account set --subscription $sub.id | Out-Null
    
    $ws = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
    
    if ($ws -and $ws.Count -gt 0) {
        Write-Host "      Found $($ws.Count) Databricks workspace(s)" -ForegroundColor Green
        foreach ($w in $ws) {
            $allWorkspaces += @{
                name = $w.name
                id = $w.id
                subscription = $sub.name
                subscriptionId = $sub.id
                url = if ($w.properties.workspaceUrl) { $w.properties.workspaceUrl } else { $null }
                resourceGroup = $w.resourceGroup
            }
        }
    }
}

Write-Host ""
Write-Host "TOTAL DATABRICKS WORKSPACES: $($allWorkspaces.Count)" -ForegroundColor Green
foreach ($w in $allWorkspaces) {
    Write-Host "   - $($w.name) ($($w.subscription))" -ForegroundColor Cyan
}

if ($allWorkspaces.Count -eq 0) {
    Write-Host "ERROR: No Databricks workspaces found in any subscription!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4] Service Principal" -ForegroundColor Yellow
$sp = az ad sp list --display-name $spName | ConvertFrom-Json

if ($sp -and $sp.Count -gt 0) {
    $appId = $sp[0].appId
    Write-Host "Using existing: $appId" -ForegroundColor Yellow
} else {
    Write-Host "Creating new..." -ForegroundColor White
    $new = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 20
    $created = az ad sp show --id $new.appId | ConvertFrom-Json
    $appId = $created.appId
    Write-Host "Created: $appId" -ForegroundColor Green
}

Write-Host "[5] Getting Token" -ForegroundColor Yellow
$token = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv
Write-Host "Token acquired" -ForegroundColor Green

Write-Host "[6] Configuring Workspaces" -ForegroundColor Yellow

foreach ($workspace in $allWorkspaces) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "WORKSPACE: $($workspace.name)" -ForegroundColor Cyan
    Write-Host "SUBSCRIPTION: $($workspace.subscription)" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    
    if (-not $workspace.url) {
        Write-Host "   No URL - getting details..." -ForegroundColor Yellow
        az account set --subscription $workspace.subscriptionId | Out-Null
        $details = az databricks workspace show --name $workspace.name --resource-group $workspace.resourceGroup | ConvertFrom-Json
        $workspace.url = $details.workspaceUrl
    }
    
    $wsUrl = "https://$($workspace.url)"
    Write-Host "   URL: $wsUrl" -ForegroundColor White
    
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    
    try {
        Write-Host "   [A] Adding Service Principal..." -ForegroundColor White
        
        $spBody = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
            applicationId = $appId
            displayName = $spName
            active = $true
        }
        
        $spParams = @{
            Uri = "$wsUrl/api/2.0/preview/scim/v2/ServicePrincipals"
            Method = "POST"
            Headers = $headers
        }
        
        $spParams.Body = ($spBody | ConvertTo-Json -Depth 10 -Compress)
        
        try {
            Invoke-RestMethod @spParams | Out-Null
            Write-Host "      SUCCESS" -ForegroundColor Green
        } catch {
            if ($_.Exception.Response.StatusCode -eq 409) {
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
        
        Write-Host "   [C] Adding to Groups..." -ForegroundColor White
        foreach ($groupName in @("admins", "prod-datateam")) {
            try {
                $filter = "displayName eq `"$groupName`""
                $encoded = [uri]::EscapeDataString($filter)
                $groups = Invoke-RestMethod -Uri "$wsUrl/api/2.0/preview/scim/v2/Groups?filter=$encoded" -Headers $headers
                
                if ($groups.Resources -and $groups.Resources.Count -gt 0) {
                    $groupId = $groups.Resources[0].id
                    
                    $patchBody = @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(@{op="add";path="members";value=@(@{value=$spId})})
                    }
                    
                    $patchParams = @{
                        Uri = "$wsUrl/api/2.0/preview/scim/v2/Groups/$groupId"
                        Method = "PATCH"
                        Headers = $headers
                    }
                    
                    $patchParams.Body = ($patchBody | ConvertTo-Json -Depth 10 -Compress)
                    
                    Invoke-RestMethod @patchParams | Out-Null
                    Write-Host "      $groupName : SUCCESS" -ForegroundColor Green
                }
            } catch {
                Write-Host "      $groupName : SKIP" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   [D] Adding Users..." -ForegroundColor White
        
        $user1 = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "preyash.patel@pyxhealth.com"
            entitlements = @(@{value="workspace-access"},@{value="allow-cluster-create"})
        }
        
        $user1Params = @{
            Uri = "$wsUrl/api/2.0/preview/scim/v2/Users"
            Method = "POST"
            Headers = $headers
        }
        
        $user1Params.Body = ($user1 | ConvertTo-Json -Depth 10 -Compress)
        
        try {
            Invoke-RestMethod @user1Params | Out-Null
            Write-Host "      preyash.patel : SUCCESS" -ForegroundColor Green
        } catch {
            Write-Host "      preyash.patel : EXISTS" -ForegroundColor Yellow
        }
        
        foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
            $userBody = @{
                schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
                userName = $email
                entitlements = @(@{value="workspace-access"})
            }
            
            $userParams = @{
                Uri = "$wsUrl/api/2.0/preview/scim/v2/Users"
                Method = "POST"
                Headers = $headers
            }
            
            $userParams.Body = ($userBody | ConvertTo-Json -Depth 10 -Compress)
            
            try {
                Invoke-RestMethod @userParams | Out-Null
                Write-Host "      $email : SUCCESS" -ForegroundColor Green
            } catch {
                Write-Host "      $email : EXISTS" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   WORKSPACE COMPLETE!" -ForegroundColor Green
        
    } catch {
        Write-Host "   ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "ALL DONE!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $appId" -ForegroundColor Cyan
Write-Host "Workspaces Configured: $($allWorkspaces.Count)" -ForegroundColor Cyan
Write-Host ""
