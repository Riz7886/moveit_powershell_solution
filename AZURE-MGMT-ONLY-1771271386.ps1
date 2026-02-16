$ErrorActionPreference = "Stop"

$spName = "databricks-jobs-service-principal"

Write-Host ""
Write-Host "DATABRICKS SETUP - AZURE MANAGEMENT API ONLY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] Login Check" -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "User: $($account.user.name)" -ForegroundColor Green

Write-Host "[2] Finding ALL Subscriptions" -ForegroundColor Yellow
$allSubs = az account list | ConvertFrom-Json
Write-Host "Found: $($allSubs.Count) subscriptions" -ForegroundColor Green

Write-Host "[3] Searching for Databricks Workspaces" -ForegroundColor Yellow
$workspaces = @()

foreach ($sub in $allSubs) {
    Write-Host "   $($sub.name)..." -ForegroundColor White
    az account set --subscription $sub.id | Out-Null
    $ws = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
    
    if ($ws -and $ws.Count -gt 0) {
        Write-Host "      Found: $($ws.Count)" -ForegroundColor Green
        foreach ($w in $ws) {
            $workspaces += [PSCustomObject]@{
                Name = $w.name
                ResourceGroup = $w.resourceGroup
                Subscription = $sub.name
                SubscriptionId = $sub.id
                ResourceId = $w.id
            }
        }
    }
}

Write-Host ""
Write-Host "TOTAL WORKSPACES FOUND: $($workspaces.Count)" -ForegroundColor Green
foreach ($w in $workspaces) {
    Write-Host "   - $($w.Name) [$($w.Subscription)]" -ForegroundColor Cyan
}

if ($workspaces.Count -eq 0) {
    Write-Host "ERROR: No workspaces found!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4] Creating/Finding Service Principal" -ForegroundColor Yellow
$sp = az ad sp list --display-name $spName | ConvertFrom-Json

if ($sp -and $sp.Count -gt 0) {
    $appId = $sp[0].appId
    $spObjectId = $sp[0].id
    Write-Host "Using existing: $appId" -ForegroundColor Yellow
} else {
    Write-Host "Creating new..." -ForegroundColor White
    $new = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 25
    $created = az ad sp show --id $new.appId | ConvertFrom-Json
    $appId = $created.appId
    $spObjectId = $created.id
    Write-Host "Created: $appId" -ForegroundColor Green
}

Write-Host ""
Write-Host "[5] Assigning Azure-Level Permissions" -ForegroundColor Yellow

foreach ($workspace in $workspaces) {
    Write-Host ""
    Write-Host "=> $($workspace.Name)" -ForegroundColor Cyan
    
    az account set --subscription $workspace.SubscriptionId | Out-Null
    
    try {
        Write-Host "   Contributor role..." -ForegroundColor White
        az role assignment create --assignee $appId --role "Contributor" --scope $workspace.ResourceId 2>$null | Out-Null
        Write-Host "      SUCCESS" -ForegroundColor Green
    } catch {
        Write-Host "      Already assigned" -ForegroundColor Yellow
    }
    
    try {
        Write-Host "   Owner role..." -ForegroundColor White
        az role assignment create --assignee $appId --role "Owner" --scope $workspace.ResourceId 2>$null | Out-Null
        Write-Host "      SUCCESS" -ForegroundColor Green
    } catch {
        Write-Host "      Already assigned" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "AZURE-LEVEL SETUP COMPLETE!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $appId" -ForegroundColor Cyan
Write-Host "Object ID: $spObjectId" -ForegroundColor Cyan
Write-Host "Workspaces: $($workspaces.Count)" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS (5 min per workspace):" -ForegroundColor Yellow
Write-Host "1. Go to each Databricks workspace in Azure Portal" -ForegroundColor White
Write-Host "2. Click the workspace URL to open it" -ForegroundColor White
Write-Host "3. Go to: Settings > Identity and Access > Service Principals" -ForegroundColor White
Write-Host "4. Click 'Add service principal'" -ForegroundColor White
Write-Host "5. Enter App ID: $appId" -ForegroundColor White
Write-Host "6. Add to groups: admins, prod-datateam" -ForegroundColor White
Write-Host "7. Add users:" -ForegroundColor White
Write-Host "   - preyash.patel@pyxhealth.com (CAN_MANAGE)" -ForegroundColor White
Write-Host "   - sheela@pyxhealth.com (READ)" -ForegroundColor White
Write-Host "   - brian.burge@pyxhealth.com (READ)" -ForegroundColor White
Write-Host "   - robert@pyxhealth.com (READ)" -ForegroundColor White
Write-Host "   - hunter@pyxhealth.com (READ)" -ForegroundColor White
Write-Host ""
Write-Host "WHY MANUAL? Your laptop cannot connect to Databricks workspace APIs." -ForegroundColor Yellow
Write-Host "This is likely due to IP restrictions on the workspaces." -ForegroundColor Yellow
Write-Host ""
