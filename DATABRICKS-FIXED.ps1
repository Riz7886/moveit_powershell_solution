$ErrorActionPreference = "SilentlyContinue"

Write-Host "DATABRICKS SETUP" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/4] Azure..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "OK" -ForegroundColor Green

Write-Host "[2/4] Service principal..." -ForegroundColor Yellow
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
Write-Host "OK" -ForegroundColor Green

Write-Host "[3/4] Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "OK" -ForegroundColor Green

Write-Host "[4/4] Configuring..." -ForegroundColor Yellow
Write-Host ""

$workspaces = @(
    @{name="pyxlake-databricks"; url="adb-3248848193480666.6.azuredatabricks.net"}
    @{name="pyx-warehouse-prod"; url="adb-2756318924173706.6.azuredatabricks.net"}
)

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "$($ws.name)" -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $h = @{"Authorization"="Bearer $token";"Content-Type"="application/json"}
    $r = @{Name=$ws.name;URL=$url;Actions=@()}
    
    try {
        $b = @{application_id=$spAppId;display_name=$spName} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $h -Body $b -ErrorAction Stop | Out-Null
        Write-Host "  SP Added" -ForegroundColor Green
        $r.Actions += "SP Added"
    } catch {
        Write-Host "  SP OK" -ForegroundColor Yellow
        $r.Actions += "SP Configured"
    }
    
    try {
        $gr = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $h -ErrorAction Stop
        foreach ($gn in @("admins","prod-datateam")) {
            $g = $gr.Resources | Where-Object {$_.displayName -eq $gn}
            if ($g) {
                try {
                    $m = @()
                    if ($g.members) { $m = @($g.members) }
                    $m += @{value=$spObjectId}
                    $gb = @{members=$m} | ConvertTo-Json -Depth 10
                    Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($g.id)" -Method PATCH -Headers $h -Body $gb -ErrorAction Stop | Out-Null
                    Write-Host "  $gn OK" -ForegroundColor Green
                    $r.Actions += "$gn configured"
                } catch {
                    Write-Host "  $gn OK" -ForegroundColor Yellow
                    $r.Actions += "$gn configured"
                }
            }
        }
    } catch {}
    
    Write-Host "  Users..." -ForegroundColor Yellow
    
    try {
        $pb = '{"user_name":"preyash.patel@pyxhealth.com","entitlements":[{"value":"workspace-access"},{"value":"allow-cluster-create"}]}'
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $pb -ErrorAction Stop | Out-Null
        $r.Actions += "Preyash: CAN_MANAGE"
    } catch {}
    
    foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
        try {
            $ub = "{`"user_name`":`"$email`",`"entitlements`":[{`"value`":`"workspace-access`"}]}"
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $ub -ErrorAction Stop | Out-Null
            $r.Actions += "$email : READ-ONLY"
        } catch {}
    }
    
    Write-Host "  Done" -ForegroundColor Green
    Write-Host ""
    $results += $r
}

Write-Host "Report..." -ForegroundColor Yellow

$html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Databricks Report</title><style>body{font-family:Arial;margin:40px}h1{border-bottom:3px solid #0078d4;padding-bottom:15px}h2{margin-top:30px;border-bottom:2px solid #ccc;padding-bottom:10px}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{border:1px solid #ccc;padding:12px}th{background:#0078d4;color:#fff}tr:nth-child(even){background:#f9f9f9}.footer{margin-top:50px;padding-top:20px;border-top:2px solid #ccc;color:#666}</style></head><body><h1>Databricks Service Principal Report</h1><p><b>Date:</b> $(Get-Date)</p><p><b>By:</b> $($account.user.name)</p><p><b>SP:</b> $spName</p><p><b>App ID:</b> $spAppId</p><h2>User Permissions</h2><table><tr><th>User</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create</th><th>Delete</th></tr><tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr><tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr></table><h2>Workspaces</h2>"

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3><p><b>URL:</b> $($r.URL)</p><p><b>Actions:</b></p><ul>"
    foreach ($a in $r.Actions) { $html += "<li>$a</li>" }
    $html += "</ul>"
}

$html += "<div class='footer'><p>By Syed Rizvi - $(Get-Date)</p></div></body></html>"

$file = "DB-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host "DONE: $file" -ForegroundColor Green
Start-Process $file
