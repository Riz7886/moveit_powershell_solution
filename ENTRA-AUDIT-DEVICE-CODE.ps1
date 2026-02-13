<#
.SYNOPSIS
Entra ID Audit - Uses Device Code Authentication (NO WAM ISSUES)
#>

param([string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit")

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "ENTRA ID AUDIT - DEVICE CODE AUTH" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Install module if needed
if (!(Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "Installing Microsoft.Graph..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Authentication -Force -Scope CurrentUser -AllowClobber
}

Import-Module Microsoft.Graph.Authentication

# Connect using DEVICE CODE (avoids WAM issues)
Write-Host "Connecting to Entra ID..." -ForegroundColor Yellow
Write-Host "A code will appear - copy it and go to https://microsoft.com/devicelogin" -ForegroundColor Yellow
Write-Host ""

try {
    Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All","Organization.Read.All" -UseDeviceCode -NoWelcome
    Write-Host "Connected!" -ForegroundColor Green
}
catch {
    Write-Host "Connection failed: $_" -ForegroundColor Red
    exit
}

# Collect data
Write-Host "Collecting data..." -ForegroundColor Cyan

$data = @{
    Tenant = @{}
    Users = @{}
    Groups = @{}
    CA = @()
}

# Get tenant
try {
    $org = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization"
    $data.Tenant = @{
        Name = $org.value[0].displayName
        ID = $org.value[0].id
        Domain = ($org.value[0].verifiedDomains | Where-Object {$_.isDefault}).name
    }
}
catch { Write-Host "Error getting tenant: $_" -ForegroundColor Red }

# Get users
try {
    $users = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users?`$top=999&`$count=true" -Headers @{ConsistencyLevel="eventual"}
    $data.Users = @{
        Total = $users.value.Count
        Enabled = ($users.value | Where-Object {$_.accountEnabled}).Count
        Disabled = ($users.value | Where-Object {!$_.accountEnabled}).Count
        Guests = ($users.value | Where-Object {$_.userType -eq "Guest"}).Count
    }
}
catch { Write-Host "Error getting users: $_" -ForegroundColor Red }

# Get groups
try {
    $groups = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/groups?`$top=999"
    $data.Groups.Total = $groups.value.Count
}
catch { Write-Host "Error getting groups: $_" -ForegroundColor Red }

# Get CA policies
try {
    $ca = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
    foreach ($p in $ca.value) {
        $data.CA += @{Name=$p.displayName; State=$p.state}
    }
}
catch { }

Write-Host "Data collected!" -ForegroundColor Green

# Generate report
if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$reportFile = Join-Path $OutputPath "EntraAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

@"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Entra ID Audit</title>
<style>
body{font-family:Arial;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px}
.container{max-width:1200px;margin:0 auto;background:white;padding:40px;border-radius:15px}
h1{color:#0078d4;font-size:2.5em}
.info{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:30px;border-radius:10px;margin:20px 0}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:20px 0}
.stat{background:linear-gradient(135deg,#f093fb,#f5576c);color:white;padding:25px;border-radius:10px;text-align:center}
.stat-value{font-size:3em;font-weight:bold}
.stat-label{font-size:0.9em}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#0078d4;color:white;padding:15px}
td{padding:12px;border-bottom:1px solid #ddd}
</style></head><body>
<div class="container">
<h1>Microsoft Entra ID Audit</h1>

<div class="info">
<h3>Tenant Information</h3>
<p><b>Name:</b> $($data.Tenant.Name)</p>
<p><b>ID:</b> $($data.Tenant.ID)</p>
<p><b>Domain:</b> $($data.Tenant.Domain)</p>
<p><b>Generated:</b> $(Get-Date)</p>
</div>

<h2>User Statistics</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total</div><div class="stat-value">$($data.Users.Total)</div></div>
<div class="stat"><div class="stat-label">Enabled</div><div class="stat-value">$($data.Users.Enabled)</div></div>
<div class="stat"><div class="stat-label">Disabled</div><div class="stat-value">$($data.Users.Disabled)</div></div>
<div class="stat"><div class="stat-label">Guests</div><div class="stat-value">$($data.Users.Guests)</div></div>
</div>

<h2>Groups</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Groups</div><div class="stat-value">$($data.Groups.Total)</div></div>
</div>

<h2>Conditional Access Policies</h2>
$(if($data.CA.Count -gt 0){"<table><tr><th>Policy</th><th>State</th></tr>"+($data.CA|ForEach-Object{"<tr><td>$($_.Name)</td><td>$($_.State)</td></tr>"})+"</table>"}else{"<p>No CA policies found</p>"})

</div></body></html>
"@ | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "COMPLETED!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile
Disconnect-MgGraph
