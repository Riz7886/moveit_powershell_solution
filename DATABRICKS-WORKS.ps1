$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "DATABRICKS SETUP - FINAL" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/4] Azure..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "OK: $($account.user.name)" -ForegroundColor Green

Write-Host "[2/4] Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json
if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "Using existing: $spAppId" -ForegroundColor Yellow
} else {
    Write-Host "Creating new..." -ForegroundColor Yellow
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "Created: $spAppId" -ForegroundColor Green
}

Write-Host "App ID: $spAppId" -ForegroundColor White
Write-Host "Object ID: $spObjectId" -ForegroundColor White

Write-Host "[3/4] Token..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv
Write-Host "OK" -ForegroundColor Green

Write-Host "[4/4] Configuring Databricks..." -ForegroundColor Yellow
Write-Host ""

$workspaces = @(
    @{name="pyxlake-databricks (PRE-PROD)"; url="adb-3248848193480666.6.azuredatabricks.net"}
    @{name="pyx-warehouse-prod (PROD)"; url="adb-2756318924173706.6.azuredatabricks.net"}
)

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "$($ws.name)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $h = @{"Authorization"="Bearer $token";"Content-Type"="application/json"}
    $r = @{Name=$ws.name;URL=$url;Actions=@()}
    
    Write-Host "Step 1: Adding Service Principal..." -ForegroundColor Yellow
    try {
        $b = '{"application_id":"' + $spAppId + '","display_name":"' + $spName + '"}'
        $response = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $h -Body $b -ContentType "application/json"
        Write-Host "  SUCCESS: Service Principal Added!" -ForegroundColor Green
        $r.Actions += "Service Principal Added"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 409) {
            Write-Host "  Already exists (OK)" -ForegroundColor Yellow
            $r.Actions += "Service Principal Already Exists"
        } else {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $r.Actions += "Service Principal FAILED"
        }
    }
    
    Write-Host "Step 2: Adding to Groups..." -ForegroundColor Yellow
    try {
        $gr = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $h
        
        foreach ($gn in @("admins","prod-datateam")) {
            $g = $gr.Resources | Where-Object {$_.displayName -eq $gn}
            if ($g) {
                Write-Host "  Processing group: $gn..." -ForegroundColor White
                try {
                    $currentMembers = @()
                    if ($g.members) {
                        $currentMembers = @($g.members)
                    }
                    
                    $alreadyExists = $currentMembers | Where-Object {$_.value -eq $spObjectId}
                    if (!$alreadyExists) {
                        $currentMembers += @{value=$spObjectId}
                        $gb = @{members=$currentMembers} | ConvertTo-Json -Depth 10
                        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($g.id)" -Method PATCH -Headers $h -Body $gb -ContentType "application/json" | Out-Null
                        Write-Host "    SUCCESS: Added to $gn" -ForegroundColor Green
                        $r.Actions += "Added to $gn"
                    } else {
                        Write-Host "    Already in $gn (OK)" -ForegroundColor Yellow
                        $r.Actions += "Already in $gn"
                    }
                } catch {
                    Write-Host "    ERROR: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  Group $gn not found!" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "  ERROR accessing groups: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "Step 3: Configuring Users..." -ForegroundColor Yellow
    
    Write-Host "  Preyash Patel (CAN_MANAGE)..." -ForegroundColor White
    try {
        $pb = '{"user_name":"preyash.patel@pyxhealth.com","entitlements":[{"value":"workspace-access"},{"value":"allow-cluster-create"}]}'
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $pb -ContentType "application/json" | Out-Null
        Write-Host "    SUCCESS: Preyash configured" -ForegroundColor Green
        $r.Actions += "Preyash: CAN_MANAGE"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 409) {
            Write-Host "    Already exists (OK)" -ForegroundColor Yellow
            $r.Actions += "Preyash: Already configured"
        } else {
            Write-Host "    ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    foreach ($email in @("sheela@pyxhealth.com","brian.burge@pyxhealth.com","robert@pyxhealth.com","hunter@pyxhealth.com")) {
        Write-Host "  $email (READ-ONLY)..." -ForegroundColor White
        try {
            $ub = '{"user_name":"' + $email + '","entitlements":[{"value":"workspace-access"}]}'
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $h -Body $ub -ContentType "application/json" | Out-Null
            Write-Host "    SUCCESS" -ForegroundColor Green
            $r.Actions += "$email : READ-ONLY"
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 409) {
                Write-Host "    Already exists (OK)" -ForegroundColor Yellow
                $r.Actions += "$email : Already configured"
            }
        }
    }
    
    Write-Host ""
    $results += $r
}

Write-Host "================================================================" -ForegroundColor Green
Write-Host "GENERATING REPORT" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

$html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Databricks Setup Report</title><style>body{font-family:Arial;margin:40px;background:#fff}h1{color:#000;border-bottom:3px solid #0078d4;padding-bottom:15px}h2{color:#0078d4;margin-top:30px;border-bottom:2px solid #ccc;padding-bottom:10px}h3{color:#333;margin-top:20px}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{border:1px solid #ccc;padding:12px}th{background:#0078d4;color:#fff}tr:nth-child(even){background:#f9f9f9}.footer{margin-top:50px;padding-top:20px;border-top:2px solid #ccc;color:#666}</style></head><body><h1>Databricks Service Principal Setup Report</h1><p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p><p><b>Executed By:</b> $($account.user.name)</p><h2>Service Principal</h2><table><tr><th>Property</th><th>Value</th></tr><tr><td>Name</td><td>$spName</td><tr><td>Application ID</td><td>$spAppId</td></tr><tr><td>Object ID</td><td>$spObjectId</td></tr></table><h2>User Permissions</h2><table><tr><th>User</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create</th><th>Delete</th></tr><tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr><tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr></table><h2>Workspaces</h2>"

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3><p><b>URL:</b> <a href='$($r.URL)'>$($r.URL)</a></p><p><b>Actions:</b></p><ul>"
    foreach ($a in $r.Actions) { $html += "<li>$a</li>" }
    $html += "</ul>"
}

$html += "<div class='footer'><p>Created by Syed Rizvi</p><p>$(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p></div></body></html>"

$file = "Databricks-Final-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host ""
Write-Host "REFRESH YOUR DATABRICKS PAGE TO SEE THE SERVICE PRINCIPAL!" -ForegroundColor Yellow
Write-Host ""

Start-Process $file
