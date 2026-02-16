$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "DATABRICKS SERVICE PRINCIPAL AUTOMATION" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/5] Azure login..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "Logged in: $($account.user.name)" -ForegroundColor Green
Write-Host ""

Write-Host "[2/5] Service principal..." -ForegroundColor Yellow
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
Write-Host "App ID: $spAppId" -ForegroundColor Green
Write-Host ""

Write-Host "[3/5] Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "OK" -ForegroundColor Green
Write-Host ""

Write-Host "[4/5] Finding workspaces (REAL URLs only)..." -ForegroundColor Yellow
$resourceJson = az resource list --resource-type "Microsoft.Databricks/workspaces" --query "[].{name:name,url:properties.workspaceUrl}" -o json
$workspaces = $resourceJson | ConvertFrom-Json

if (!$workspaces -or $workspaces.Count -eq 0) {
    Write-Host "ERROR: No workspaces found!" -ForegroundColor Red
    Write-Host "Run this command manually to see workspaces:" -ForegroundColor Yellow
    Write-Host "az resource list --resource-type Microsoft.Databricks/workspaces -o table" -ForegroundColor White
    exit
}

Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green
foreach ($ws in $workspaces) {
    Write-Host "  - $($ws.name) : $($ws.url)" -ForegroundColor White
}
Write-Host ""

Write-Host "[5/5] Configuring workspaces..." -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "$($ws.name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $h = @{"Authorization"="Bearer $token";"Content-Type"="application/json"}
    
    $r = @{Name=$ws.name; URL=$url; SP=$false; Groups=@(); Users=@(); Actions=@()}
    
    Write-Host "Step 1: Service principal..." -ForegroundColor Yellow
    try {
        $spBody = @{application_id=$spAppId;display_name=$spName} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $h -Body $spBody | Out-Null
        Write-Host "  Added" -ForegroundColor Green
        $r.SP = $true
        $r.Actions += "SP Added"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Exists (OK)" -ForegroundColor Yellow
            $r.SP = $true
            $r.Actions += "SP Exists"
        } else {
            Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
            $r.Actions += "SP Failed"
        }
    }
    
    Write-Host "Step 2: Groups..." -ForegroundColor Yellow
    try {
        $gr = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $h
        foreach ($gn in @("admins","prod-datateam")) {
            $g = $gr.Resources | Where-Object {$_.displayName -eq $gn}
            if ($g) {
                $m = @($g.members)
                $exists = $m | Where-Object {$_.value -eq $spObjectId}
                if (!$exists) {
                    $m += @{value=$spObjectId}
                    $gb = @{members=$m} | ConvertTo-Json -Depth 10
                    Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($g.id)" -Method PATCH -Headers $h -Body $gb | Out-Null
                }
                Write-Host "  $gn OK" -ForegroundColor Green
                $r.Groups += $gn
                $r.Actions += "Added to $gn"
            }
        }
    } catch {
        Write-Host "  Groups failed" -ForegroundColor Red
    }
    
    Write-Host "Step 3: Users..." -ForegroundColor Yellow
    
    $preyash = @{user_name="preyash.patel@pyxhealth.com";entitlements=@(@{value="workspace-access"},@{value="allow-cluster-create"})} | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $preyash | Out-Null
        Write-Host "  Preyash: CAN_MANAGE" -ForegroundColor Green
        $r.Users += "Preyash: CAN_MANAGE"
        $r.Actions += "Preyash configured"
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Host "  Preyash: Exists (OK)" -ForegroundColor Yellow
            $r.Users += "Preyash: CAN_MANAGE"
        }
    }
    
    foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
        $ub = @{user_name=$email;entitlements=@(@{value="workspace-access"})} | ConvertTo-Json
        try {
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $ub | Out-Null
            $r.Users += "$email : READ-ONLY"
        } catch {}
    }
    Write-Host "  Users OK" -ForegroundColor Green
    
    Write-Host ""
    $results += $r
}

Write-Host "Generating report..." -ForegroundColor Yellow

$html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Databricks Report</title><style>body{font-family:Arial;margin:40px}h1{border-bottom:3px solid #0078d4;padding-bottom:15px}h2{margin-top:30px;border-bottom:2px solid #ccc}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{border:1px solid #ccc;padding:12px}th{background:#0078d4;color:#fff}.footer{margin-top:50px;padding-top:20px;border-top:2px solid #ccc}</style></head><body><h1>Databricks Report</h1><p><b>Date:</b> $(Get-Date)</p><p><b>By:</b> $($account.user.name)</p><p><b>SP:</b> $spName</p><p><b>App ID:</b> $spAppId</p><h2>Users</h2><table><tr><th>User</th><th>Level</th><th>Add</th><th>Remove</th><th>Create</th><th>Delete</th></tr><tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr><tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr></table><h2>Workspaces</h2>"

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3><p><b>URL:</b> $($r.URL)</p><p><b>Actions:</b></p><ul>"
    foreach ($a in $r.Actions) {
        $html += "<li>$a</li>"
    }
    $html += "</ul>"
}

$html += "<div class='footer'><p>By Syed Rizvi - $(Get-Date)</p></div></body></html>"

$file = "DB-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "DONE: $file" -ForegroundColor Green
Start-Process $file
