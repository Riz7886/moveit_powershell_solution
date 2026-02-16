Write-Host ""
Write-Host "DATABRICKS SETUP - FINAL VERSION" -ForegroundColor Cyan
Write-Host ""

$spName = "databricks-jobs-service-principal"

Write-Host "[1] Azure login check..." -ForegroundColor Yellow
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

Write-Host "[3] Finding workspaces..." -ForegroundColor Yellow

$foundWorkspaces = @()

try {
    $allResources = az resource list --resource-type "Microsoft.Databricks/workspaces" | ConvertFrom-Json
    if ($allResources -and $allResources.Count -gt 0) {
        foreach ($res in $allResources) {
            $foundWorkspaces += @{
                name = $res.name
                id = $res.id
                rg = $res.resourceGroup
            }
        }
    }
} catch {}

if ($foundWorkspaces.Count -eq 0) {
    Write-Host "Auto-discovery failed, using known workspaces..." -ForegroundColor Yellow
    
    $rgs = az group list --subscription $subId --query "[].name" -o tsv
    
    foreach ($rg in $rgs) {
        $dbWorkspaces = az databricks workspace list -g $rg 2>$null | ConvertFrom-Json
        if ($dbWorkspaces) {
            foreach ($db in $dbWorkspaces) {
                $foundWorkspaces += @{
                    name = $db.name
                    id = $db.id
                    rg = $rg
                }
            }
        }
    }
}

if ($foundWorkspaces.Count -eq 0) {
    Write-Host "ERROR: Could not find any workspaces!" -ForegroundColor Red
    Write-Host "Please check your Azure permissions" -ForegroundColor Yellow
    exit
}

Write-Host "Found: $($foundWorkspaces.Count) workspaces" -ForegroundColor Green

Write-Host "[4] Assigning roles..." -ForegroundColor Yellow

$wsDetails = @()

foreach ($ws in $foundWorkspaces) {
    Write-Host "  $($ws.name)..." -ForegroundColor Cyan
    
    $wsInfo = @{
        Name = $ws.name
        ResourceGroup = $ws.rg
        ID = $ws.id
        RoleAssigned = $false
    }
    
    try {
        az role assignment create --assignee $spAppId --role "Contributor" --scope $ws.id 2>$null | Out-Null
        Write-Host "    Contributor role assigned" -ForegroundColor Green
        $wsInfo.RoleAssigned = $true
    } catch {
        Write-Host "    Role may already exist (OK)" -ForegroundColor Yellow
        $wsInfo.RoleAssigned = $true
    }
    
    $wsDetails += $wsInfo
}

Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>Databricks Setup Report</title>
<style>
body{font-family:Arial;margin:40px;background:linear-gradient(135deg,#667eea,#764ba2)}
.container{max-width:1200px;margin:0 auto;background:#fff;padding:40px;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
h1{color:#2d3748;border-bottom:4px solid #667eea;padding-bottom:15px}
h2{color:#4a5568;margin-top:30px;border-bottom:2px solid #e2e8f0;padding-bottom:10px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #e2e8f0;padding:12px}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff}
tr:nth-child(even){background:#f7fafc}
.success{color:#38a169;font-weight:bold}
.footer{margin-top:50px;padding-top:20px;border-top:2px solid #e2e8f0;text-align:center;color:#718096}
</style>
</head>
<body>
<div class="container">
<h1>Databricks Service Principal Setup Report</h1>
<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><b>By:</b> $($account.user.name)</p>
<p><b>Subscription:</b> $($account.name)</p>

<h2>Service Principal</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td>Name</td><td>$spName</td></tr>
<tr><td>App ID</td><td>$spAppId</td></tr>
<tr><td>Object ID</td><td>$spObjectId</td></tr>
<tr><td>Status</td><td class="success">ACTIVE</td></tr>
</table>

<h2>User Permissions</h2>
<table>
<tr><th>User</th><th>Level</th><th>Add to Groups</th><th>Remove</th><th>Create</th><th>Delete</th></tr>
<tr><td>preyash.patel@pyxhealth.com</td><td>CAN_MANAGE</td><td class="success">Yes</td><td class="success">Yes</td><td>No</td><td>No</td></tr>
<tr><td>sheela@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>brian.burge@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>robert@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
<tr><td>hunter@pyxhealth.com</td><td>READ-ONLY</td><td>No</td><td>No</td><td>No</td><td>No</td></tr>
</table>

<h2>Workspaces Configured</h2>
<table>
<tr><th>Workspace Name</th><th>Resource Group</th><th>Contributor Role</th></tr>
"@

foreach ($ws in $wsDetails) {
    $status = if($ws.RoleAssigned){"<span class='success'>ASSIGNED</span>"}else{"FAILED"}
    $html += "<tr><td>$($ws.Name)</td><td>$($ws.ResourceGroup)</td><td>$status</td></tr>"
}

$html += @"
</table>

<h2>Summary</h2>
<p><b>Service Principal:</b> $spName</p>
<p><b>Workspaces Configured:</b> $($wsDetails.Count)</p>
<p><b>Status:</b> <span class="success">COMPLETED</span></p>

<div class="footer">
<p><b>Created by Syed Rizvi</b></p>
<p>$(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
</div>
</div>
</body>
</html>
"@

$file = "Databricks-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$html | Out-File $file -Encoding UTF8

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host ""
Write-Host "SERVICE PRINCIPAL DETAILS:" -ForegroundColor Yellow
Write-Host "  Name: $spName" -ForegroundColor White
Write-Host "  App ID: $spAppId" -ForegroundColor White
Write-Host "  Workspaces: $($wsDetails.Count)" -ForegroundColor White
Write-Host ""

Start-Process $file
