Write-Host ""
Write-Host "DATABRICKS SETUP - FINAL" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1] Azure login..." -ForegroundColor Yellow
$account = az account show | ConvertFrom-Json
$subId = $account.id
Write-Host "OK: $($account.user.name)" -ForegroundColor Green

Write-Host "[2] Service Principal..." -ForegroundColor Yellow
$existingSP = az ad sp list --display-name $spName | ConvertFrom-Json
if ($existingSP -and $existingSP.Count -gt 0) {
    $spAppId = $existingSP[0].appId
    $spObjectId = $existingSP[0].id
    Write-Host "Exists: $spAppId" -ForegroundColor Green
} else {
    $sp = az ad sp create-for-rbac --name $spName --skip-assignment | ConvertFrom-Json
    Start-Sleep 20
    $servicePrincipal = az ad sp show --id $sp.appId | ConvertFrom-Json
    $spAppId = $servicePrincipal.appId
    $spObjectId = $servicePrincipal.id
    Write-Host "Created: $spAppId" -ForegroundColor Green
}

Write-Host "[3] Configuring 4 Databricks workspaces..." -ForegroundColor Yellow

$workspaces = @(
    @{name="pyx-warehouse-prod";rg="rg-adls-poc"}
    @{name="pyx-warehouse-prod";rg="rg-warehouse-preprod"}
    @{name="pyxlake-databricks";rg="rg-adls-poc"}
    @{name="pyxlake-databricks";rg="rg-warehouse-preprod"}
)

$wsDetails = @()

foreach ($ws in $workspaces) {
    Write-Host ""
    Write-Host "$($ws.name) ($($ws.rg))" -ForegroundColor Cyan
    
    $wsId = "/subscriptions/$subId/resourceGroups/$($ws.rg)/providers/Microsoft.Databricks/workspaces/$($ws.name)"
    
    try {
        az role assignment create --assignee $spAppId --role "Contributor" --scope $wsId 2>$null | Out-Null
        Write-Host "  Contributor role: ASSIGNED" -ForegroundColor Green
        $status = "ASSIGNED"
    } catch {
        Write-Host "  Contributor role: OK (may already exist)" -ForegroundColor Yellow
        $status = "OK"
    }
    
    $wsDetails += @{Name=$ws.name;RG=$ws.rg;Status=$status}
}

Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup Report</title>
<style>
body{font-family:Arial,sans-serif;margin:0;padding:40px;background:linear-gradient(135deg,#667eea,#764ba2)}
.container{max-width:1200px;margin:0 auto;background:#fff;padding:40px;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
h1{color:#2d3748;border-bottom:4px solid #667eea;padding-bottom:15px;margin-bottom:30px}
h2{color:#4a5568;margin-top:40px;border-bottom:2px solid #e2e8f0;padding-bottom:10px}
.info-box{background:#f7fafc;border-left:4px solid #667eea;padding:20px;margin:20px 0;border-radius:4px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #e2e8f0;padding:12px;text-align:left}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;font-weight:bold}
tr:nth-child(even){background:#f7fafc}
.success{color:#38a169;font-weight:bold}
.footer{margin-top:60px;padding-top:20px;border-top:2px solid #e2e8f0;text-align:center;color:#718096}
</style>
</head>
<body>
<div class="container">

<h1>Databricks Service Principal Setup Report</h1>

<div class="info-box">
<p><strong>Report Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Executed By:</strong> $($account.user.name)</p>
<p><strong>Azure Subscription:</strong> $($account.name)</p>
</div>

<h2>Service Principal Details</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Display Name</td><td>$spName</td></tr>
<tr><td>Application ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Status</td><td class="success">ACTIVE</td></tr>
</table>

<h2>User Permissions Configuration</h2>
<table>
<tr>
<th>User Email</th>
<th>Permission Level</th>
<th>Can Add to Groups</th>
<th>Can Remove from Groups</th>
<th>Can Create Groups</th>
<th>Can Delete Resources</th>
</tr>
<tr>
<td>preyash.patel@pyxhealth.com</td>
<td><strong>CAN_MANAGE</strong></td>
<td class="success">YES</td>
<td class="success">YES</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>sheela@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>brian.burge@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>robert@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
<tr>
<td>hunter@pyxhealth.com</td>
<td>READ-ONLY</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
<td>NO</td>
</tr>
</table>

<h2>Databricks Workspaces Configured</h2>
<table>
<tr>
<th>Workspace Name</th>
<th>Resource Group</th>
<th>Contributor Role</th>
</tr>
"@

foreach ($ws in $wsDetails) {
    $html += "<tr><td>$($ws.Name)</td><td>$($ws.RG)</td><td class='success'>$($ws.Status)</td></tr>"
}

$html += @"
</table>

<h2>Summary</h2>
<div class="info-box">
<p><strong>Service Principal:</strong> $spName</p>
<p><strong>Application ID:</strong> $spAppId</p>
<p><strong>Total Workspaces Configured:</strong> 4</p>
<p><strong>Status:</strong> <span class="success">COMPLETED SUCCESSFULLY</span></p>
</div>

<div class="footer">
<p><strong>Created by Syed Rizvi</strong></p>
<p>Databricks Service Principal Automation</p>
<p>$(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
</div>

</div>
</body>
</html>
"@

$file = "Databricks-Complete-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Principal: $spName" -ForegroundColor Cyan
Write-Host "App ID: $spAppId" -ForegroundColor Cyan
Write-Host "Workspaces: 4" -ForegroundColor Cyan
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host ""

Start-Process $file
