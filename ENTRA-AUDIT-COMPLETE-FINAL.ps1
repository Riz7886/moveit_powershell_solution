param([string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit")

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "ENTRA ID COMPLETE SECURITY AUDIT" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$az = Get-Command az -ErrorAction SilentlyContinue
if (!$az) {
    Write-Host "Installing Azure CLI..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
}

Write-Host "Logging in..." -ForegroundColor Yellow
az login --allow-no-subscriptions | Out-Null

Write-Host "Collecting comprehensive data..." -ForegroundColor Cyan

# Tenant
Write-Host "  - Tenant info" -ForegroundColor Gray
$tenant = az account show | ConvertFrom-Json

# Users
Write-Host "  - Users" -ForegroundColor Gray
$users = az ad user list | ConvertFrom-Json

# Groups
Write-Host "  - Groups" -ForegroundColor Gray
$groups = az ad group list | ConvertFrom-Json

# Apps
Write-Host "  - Applications" -ForegroundColor Gray
$apps = az ad app list | ConvertFrom-Json

# Service Principals
Write-Host "  - Service Principals" -ForegroundColor Gray
$sps = az ad sp list --all | ConvertFrom-Json

# Role Assignments
Write-Host "  - Role Assignments" -ForegroundColor Gray
$roles = az role assignment list | ConvertFrom-Json

# Subscriptions
Write-Host "  - Subscriptions" -ForegroundColor Gray
$subs = az account list | ConvertFrom-Json

# Resources (for each subscription)
Write-Host "  - Resources" -ForegroundColor Gray
$allResources = @()
$allVMs = @()
$allNetworks = @()

foreach ($sub in $subs) {
    az account set --subscription $sub.id | Out-Null
    
    $resources = az resource list | ConvertFrom-Json
    $allResources += $resources
    
    $vms = az vm list -d | ConvertFrom-Json
    $allVMs += $vms
    
    $vnets = az network vnet list | ConvertFrom-Json
    $allNetworks += $vnets
}

# Build data structure
$data = @{
    Tenant = @{
        Name = $tenant.name
        ID = $tenant.tenantId
        User = $tenant.user.name
    }
    Users = @{
        Total = $users.Count
        Enabled = ($users | Where-Object {$_.accountEnabled}).Count
        Disabled = ($users | Where-Object {!$_.accountEnabled}).Count
        Guests = ($users | Where-Object {$_.userType -eq "Guest"}).Count
        Members = ($users | Where-Object {$_.userType -eq "Member"}).Count
    }
    Groups = @{
        Total = $groups.Count
        Security = ($groups | Where-Object {$_.securityEnabled}).Count
        M365 = ($groups | Where-Object {$_.groupTypes -contains "Unified"}).Count
    }
    Apps = @{
        Total = $apps.Count
    }
    ServicePrincipals = @{
        Total = $sps.Count
    }
    Roles = @{
        Total = $roles.Count
        Owners = ($roles | Where-Object {$_.roleDefinitionName -eq "Owner"}).Count
        Contributors = ($roles | Where-Object {$_.roleDefinitionName -eq "Contributor"}).Count
    }
    Subscriptions = @{
        Total = $subs.Count
        Active = ($subs | Where-Object {$_.state -eq "Enabled"}).Count
    }
    Resources = @{
        Total = $allResources.Count
        VMs = $allVMs.Count
        Networks = $allNetworks.Count
        ByType = ($allResources | Group-Object type | Sort-Object Count -Descending | Select-Object -First 10)
    }
}

Write-Host "Data collected!" -ForegroundColor Green

# Generate comprehensive HTML
if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$file = Join-Path $OutputPath "EntraAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

$resourceTypesHtml = ""
foreach ($rt in $data.Resources.ByType) {
    $resourceTypesHtml += "<tr><td>$($rt.Name)</td><td>$($rt.Count)</td></tr>"
}

$topRolesHtml = ""
$topRoles = $roles | Group-Object roleDefinitionName | Sort-Object Count -Descending | Select-Object -First 10
foreach ($r in $topRoles) {
    $topRolesHtml += "<tr><td>$($r.Name)</td><td>$($r.Count)</td></tr>"
}

$vmListHtml = ""
foreach ($vm in $allVMs | Select-Object -First 20) {
    $vmListHtml += "<tr><td>$($vm.name)</td><td>$($vm.powerState)</td><td>$($vm.location)</td><td>$($vm.hardwareProfile.vmSize)</td></tr>"
}

@"
<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<title>Entra ID Complete Security Audit</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px}
.container{max-width:1400px;margin:0 auto;background:white;padding:40px;border-radius:15px;box-shadow:0 20px 60px rgba(0,0,0,0.3)}
h1{color:#0078d4;font-size:2.5em;margin-bottom:10px}
.subtitle{color:#666;margin-bottom:30px;font-size:1.1em}
h2{color:#2b579a;font-size:1.8em;margin:40px 0 20px 0;border-bottom:3px solid #e1e1e1;padding-bottom:10px}
.header-box{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:30px;border-radius:10px;margin:20px 0}
.header-box h3{margin-bottom:15px}
.header-box p{margin:8px 0;font-size:1.1em}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:25px 0}
.stat{background:linear-gradient(135deg,#f093fb,#f5576c);color:white;padding:25px;border-radius:12px;text-align:center;box-shadow:0 5px 15px rgba(0,0,0,0.2);transition:transform 0.3s}
.stat:hover{transform:translateY(-5px)}
.stat-label{font-size:0.9em;opacity:0.95;margin-bottom:10px;text-transform:uppercase}
.stat-value{font-size:3.5em;font-weight:bold}
table{width:100%;border-collapse:collapse;margin:20px 0;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:15px;text-align:left}
td{padding:12px 15px;border-bottom:1px solid #e1e1e1}
tr:hover{background:#f8f9fa}
.section{margin:40px 0}
.badge{display:inline-block;padding:5px 15px;border-radius:20px;font-size:0.85em;font-weight:bold;margin:5px}
.badge-success{background:#28a745;color:white}
.badge-warning{background:#ffc107;color:#333}
.badge-danger{background:#dc3545;color:white}
.footer{margin-top:50px;padding-top:30px;border-top:2px solid #e1e1e1;text-align:center;color:#666}
</style></head><body>
<div class="container">

<h1>🛡️ Microsoft Entra ID Complete Security Audit</h1>
<div class="subtitle">Comprehensive Tenant Security Assessment</div>

<div class="header-box">
<h3>📋 Tenant Information</h3>
<p><strong>Tenant:</strong> $($data.Tenant.Name)</p>
<p><strong>Tenant ID:</strong> $($data.Tenant.ID)</p>
<p><strong>Audited By:</strong> $($data.Tenant.User)</p>
<p><strong>Report Date:</strong> $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
</div>

<div class="section">
<h2>👥 User Accounts</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Users</div><div class="stat-value">$($data.Users.Total)</div></div>
<div class="stat"><div class="stat-label">Enabled</div><div class="stat-value">$($data.Users.Enabled)</div></div>
<div class="stat"><div class="stat-label">Disabled</div><div class="stat-value">$($data.Users.Disabled)</div></div>
<div class="stat"><div class="stat-label">Guest Users</div><div class="stat-value">$($data.Users.Guests)</div></div>
<div class="stat"><div class="stat-label">Member Users</div><div class="stat-value">$($data.Users.Members)</div></div>
</div>
</div>

<div class="section">
<h2>👥 Groups & Security</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Groups</div><div class="stat-value">$($data.Groups.Total)</div></div>
<div class="stat"><div class="stat-label">Security Groups</div><div class="stat-value">$($data.Groups.Security)</div></div>
<div class="stat"><div class="stat-label">M365 Groups</div><div class="stat-value">$($data.Groups.M365)</div></div>
</div>
</div>

<div class="section">
<h2>📱 Applications & Service Principals</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Applications</div><div class="stat-value">$($data.Apps.Total)</div></div>
<div class="stat"><div class="stat-label">Service Principals</div><div class="stat-value">$($data.ServicePrincipals.Total)</div></div>
</div>
</div>

<div class="section">
<h2>🔐 Role Assignments</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Assignments</div><div class="stat-value">$($data.Roles.Total)</div></div>
<div class="stat"><div class="stat-label">Owners</div><div class="stat-value">$($data.Roles.Owners)</div></div>
<div class="stat"><div class="stat-label">Contributors</div><div class="stat-value">$($data.Roles.Contributors)</div></div>
</div>

<h3>Top Role Assignments</h3>
<table>
<thead><tr><th>Role</th><th>Assignments</th></tr></thead>
<tbody>$topRolesHtml</tbody>
</table>
</div>

<div class="section">
<h2>☁️ Azure Subscriptions</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Subscriptions</div><div class="stat-value">$($data.Subscriptions.Total)</div></div>
<div class="stat"><div class="stat-label">Active</div><div class="stat-value">$($data.Subscriptions.Active)</div></div>
</div>
</div>

<div class="section">
<h2>🖥️ Azure Resources</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Resources</div><div class="stat-value">$($data.Resources.Total)</div></div>
<div class="stat"><div class="stat-label">Virtual Machines</div><div class="stat-value">$($data.Resources.VMs)</div></div>
<div class="stat"><div class="stat-label">Virtual Networks</div><div class="stat-value">$($data.Resources.Networks)</div></div>
</div>

<h3>Top Resource Types</h3>
<table>
<thead><tr><th>Resource Type</th><th>Count</th></tr></thead>
<tbody>$resourceTypesHtml</tbody>
</table>
</div>

$(if ($allVMs.Count -gt 0) {
"<div class='section'>
<h2>💻 Virtual Machines</h2>
<table>
<thead><tr><th>VM Name</th><th>Power State</th><th>Location</th><th>Size</th></tr></thead>
<tbody>$vmListHtml</tbody>
</table>
</div>"
})

<div class="section">
<h2>📊 Security Summary</h2>
<table>
<thead><tr><th>Category</th><th>Count</th><th>Status</th></tr></thead>
<tbody>
<tr><td>Total Users</td><td>$($data.Users.Total)</td><td><span class="badge badge-success">✓</span></td></tr>
<tr><td>Guest Users</td><td>$($data.Users.Guests)</td><td><span class="badge badge-warning">Review</span></td></tr>
<tr><td>Applications</td><td>$($data.Apps.Total)</td><td><span class="badge badge-success">✓</span></td></tr>
<tr><td>Service Principals</td><td>$($data.ServicePrincipals.Total)</td><td><span class="badge badge-success">✓</span></td></tr>
<tr><td>Role Assignments</td><td>$($data.Roles.Total)</td><td><span class="badge badge-warning">Review</span></td></tr>
<tr><td>Azure Resources</td><td>$($data.Resources.Total)</td><td><span class="badge badge-success">✓</span></td></tr>
</tbody>
</table>
</div>

<div class="footer">
<p><strong>Microsoft Entra ID Complete Security Audit</strong></p>
<p>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss") | By: $env:USERNAME</p>
<p style="margin-top:10px;font-size:0.9em">Powered by Azure CLI | Comprehensive Tenant Assessment</p>
</div>

</div></body></html>
"@ | Out-File -FilePath $file -Encoding UTF8

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "✅ COMPREHENSIVE AUDIT COMPLETED!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Report includes:" -ForegroundColor Yellow
Write-Host "   - Users ($($data.Users.Total) total)" -ForegroundColor White
Write-Host "   - Groups ($($data.Groups.Total) total)" -ForegroundColor White
Write-Host "   - Applications ($($data.Apps.Total) total)" -ForegroundColor White
Write-Host "   - Service Principals ($($data.ServicePrincipals.Total) total)" -ForegroundColor White
Write-Host "   - Role Assignments ($($data.Roles.Total) total)" -ForegroundColor White
Write-Host "   - Subscriptions ($($data.Subscriptions.Total) total)" -ForegroundColor White
Write-Host "   - Azure Resources ($($data.Resources.Total) total)" -ForegroundColor White
Write-Host "   - Virtual Machines ($($data.Resources.VMs) total)" -ForegroundColor White
Write-Host ""
Write-Host "📁 Report: $file" -ForegroundColor Cyan
Write-Host ""

Start-Process $file
