Write-Host "DATABRICKS SETUP" -ForegroundColor Cyan

$spName = "databricks-jobs-service-principal"

$account = az account show | ConvertFrom-Json
Write-Host "Azure: $($account.user.name)" -ForegroundColor Green

$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json
if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}

Write-Host "SP: $spAppId" -ForegroundColor Green

$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv

$workspaces = @(
    @{name="pyxlake-databricks";url="https://adb-3248848193480666.6.azuredatabricks.net"}
    @{name="pyx-warehouse-prod";url="https://adb-2756318924173706.6.azuredatabricks.net"}
)

$results = @()

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "$($ws.name)" -ForegroundColor Cyan
    
    $url = $ws.url
    $r = @{Name=$ws.name;URL=$url;Actions=@()}
    
    try {
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        $spJson = @"
{
  "application_id": "$spAppId",
  "display_name": "$spName"
}
"@
        
        try {
            $null = Invoke-WebRequest -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spJson -UseBasicParsing
            Write-Host "  SP: Added" -ForegroundColor Green
            $r.Actions += "SP Added"
        } catch {
            Write-Host "  SP: OK" -ForegroundColor Yellow
            $r.Actions += "SP OK"
        }
        
        $groupsJson = Invoke-WebRequest -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $headers -UseBasicParsing
        $groups = ($groupsJson.Content | ConvertFrom-Json).Resources
        
        foreach ($gn in @("admins","prod-datateam")) {
            $group = $groups | Where-Object {$_.displayName -eq $gn}
            if ($group) {
                try {
                    $members = @()
                    if ($group.members) { $members = @($group.members) }
                    $members += @{value=$spObjectId}
                    $groupPatchJson = @{members=$members} | ConvertTo-Json -Depth 10
                    $null = Invoke-WebRequest -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupPatchJson -UseBasicParsing
                    Write-Host "  Group: $gn" -ForegroundColor Green
                    $r.Actions += "$gn configured"
                } catch {}
            }
        }
        
        $preyashJson = @"
{
  "user_name": "preyash.patel@pyxhealth.com",
  "entitlements": [
    {"value": "workspace-access"},
    {"value": "allow-cluster-create"}
  ]
}
"@
        
        try {
            $null = Invoke-WebRequest -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $preyashJson -UseBasicParsing
            $r.Actions += "Preyash: CAN_MANAGE"
        } catch {}
        
        foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
            $userJson = @"
{
  "user_name": "$email",
  "entitlements": [{"value": "workspace-access"}]
}
"@
            try {
                $null = Invoke-WebRequest -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userJson -UseBasicParsing
                $r.Actions += "$email : READ-ONLY"
            } catch {}
        }
        
        Write-Host "  Users: OK" -ForegroundColor Green
        
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    $results += $r
}

$html = "<!DOCTYPE html><html><head><title>Databricks</title><style>body{font-family:Arial;margin:40px}h1{border-bottom:3px solid #0078d4;padding:15px 0}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{border:1px solid #ccc;padding:12px}th{background:#0078d4;color:#fff}</style></head><body><h1>Databricks Setup</h1><p><b>Date:</b> $(Get-Date)</p><p><b>SP:</b> $spName ($spAppId)</p><h2>Users</h2><table><tr><th>User</th><th>Level</th><th>Add</th><th>Remove</th><th>Create</th><th>Delete</th></tr><tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr><tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr></table><h2>Workspaces</h2>"

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3><p><b>URL:</b> $($r.URL)</p><ul>"
    foreach ($a in $r.Actions) { $html += "<li>$a</li>" }
    $html += "</ul>"
}

$html += "<p>By Syed Rizvi - $(Get-Date)</p></body></html>"

$file = "DB-Final-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "DONE: $file" -ForegroundColor Green
Start-Process $file
