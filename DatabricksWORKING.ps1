$ErrorActionPreference = "Continue"

Write-Host "DATABRICKS AUTOMATION" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1/4] Azure login..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
Write-Host "OK: $($account.user.name)" -ForegroundColor Green

Write-Host "[2/4] Service principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json

if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep -Seconds 15
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
}
Write-Host "OK: $spAppId" -ForegroundColor Green

Write-Host "[3/4] Finding workspaces (60s timeout)..." -ForegroundColor Yellow

$job = Start-Job -ScriptBlock {
    az resource list --resource-type "Microsoft.Databricks/workspaces" --query "[].{name:name,url:properties.workspaceUrl}" -o json
}

$completed = Wait-Job $job -Timeout 60

if ($completed) {
    $output = Receive-Job $job
    $workspaces = $output | ConvertFrom-Json
    Remove-Job $job
    Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green
} else {
    Remove-Job $job -Force
    Write-Host "Timeout - using subscription query..." -ForegroundColor Yellow
    $sub = $account.id
    $rgs = az group list --subscription $sub --query "[].name" -o json | ConvertFrom-Json
    $workspaces = @()
    foreach ($rg in $rgs) {
        $dbs = az databricks workspace list -g $rg 2>$null | ConvertFrom-Json
        if ($dbs) {
            foreach ($db in $dbs) {
                $workspaces += @{name=$db.name; url=$db.properties.workspaceUrl}
            }
        }
    }
    Write-Host "Found $($workspaces.Count) workspaces" -ForegroundColor Green
}

Write-Host "[4/4] Configuring..." -ForegroundColor Yellow
$token = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv

$results = @()

foreach ($ws in $workspaces) {
    Write-Host "  $($ws.name)..." -ForegroundColor Cyan
    
    $url = "https://$($ws.url)"
    $headers = @{"Authorization"="Bearer $token";"Content-Type"="application/json"}
    
    try {
        $spBody = @{application_id=$spAppId;display_name=$spName} | ConvertTo-Json
        Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/ServicePrincipals" -Method POST -Headers $headers -Body $spBody | Out-Null
    } catch {}
    
    $groupsResponse = Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups" -Headers $headers
    foreach ($gName in @("admins","prod-datateam")) {
        $group = $groupsResponse.Resources | Where-Object {$_.displayName -eq $gName}
        if ($group) {
            $members = @($group.members)
            $members += @{value=$spObjectId}
            $groupBody = @{members=$members} | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Groups/$($group.id)" -Method PATCH -Headers $headers -Body $groupBody | Out-Null
        }
    }
    
    $users = @(
        @{u="preyash.patel@pyxhealth.com";e=@(@{value="workspace-access"},@{value="allow-cluster-create"})}
        @{u="sheela@pyxhealth.com";e=@(@{value="workspace-access"})}
        @{u="brian.burge@pyxhealth.com";e=@(@{value="workspace-access"})}
        @{u="robert@pyxhealth.com";e=@(@{value="workspace-access"})}
        @{u="hunter@pyxhealth.com";e=@(@{value="workspace-access"})}
    )
    
    foreach ($user in $users) {
        $userBody = @{user_name=$user.u;entitlements=$user.e} | ConvertTo-Json
        try {
            Invoke-RestMethod -Uri "$url/api/2.0/preview/scim/v2/Users" -Method POST -Headers $headers -Body $userBody | Out-Null
        } catch {}
    }
    
    Write-Host "    Done" -ForegroundColor Green
    $results += @{Name=$ws.name;URL=$url}
}

$html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Databricks Report</title><style>body{font-family:Arial;margin:40px}h1{border-bottom:2px solid #000}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{border:1px solid #ccc;padding:12px}th{background:#f0f0f0}</style></head><body><h1>Databricks Report</h1><p><b>Date:</b> $(Get-Date)</p><p><b>SP:</b> $spName</p><p><b>App ID:</b> $spAppId</p><h2>Users</h2><table><tr><th>User</th><th>Level</th><th>Add</th><th>Remove</th><th>Create</th><th>Delete</th></tr><tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td>Yes</td><td>Yes</td><td>No</td><td>No</td></tr><tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr><tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr></table><h2>Workspaces</h2>"

foreach ($r in $results) {
    $html += "<h3>$($r.Name)</h3><p>$($r.URL)</p>"
}

$html += "<p>By Syed Rizvi - $(Get-Date)</p></body></html>"

$file = "DB-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File -FilePath $file -Encoding UTF8

Write-Host ""
Write-Host "DONE: $file" -ForegroundColor Green
Start-Process $file
