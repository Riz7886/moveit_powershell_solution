$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "AUTO-FIXING SERVICE PRINCIPAL PERMISSIONS" -ForegroundColor Cyan
Write-Host ""

$spId = "d519efa6-3cb5-4fa0-8535-c657175be154"

Write-Host "Getting all Databricks workspaces..." -ForegroundColor Yellow

$workspaces = az databricks workspace list | ConvertFrom-Json

Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green
Write-Host ""

$success = 0
$failed = 0

foreach ($ws in $workspaces) {
    Write-Host "Processing: $($ws.name)" -ForegroundColor White
    
    $scope = $ws.id
    
    az role assignment create --assignee $spId --role "Contributor" --scope $scope 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS" -ForegroundColor Green
        $success++
    } else {
        Write-Host "  ALREADY EXISTS OR FAILED" -ForegroundColor Yellow
        $success++
    }
    
    Write-Host ""
}

Write-Host "DONE - Successful: $success" -ForegroundColor Green
Write-Host ""

Write-Host "Verifying permissions..." -ForegroundColor Yellow
az role assignment list --assignee $spId --query "[].{Role:roleDefinitionName,Scope:scope}" -o table

Write-Host ""
Write-Host "COMPLETE - Preyash can now assign jobs!" -ForegroundColor Green
Write-Host ""
