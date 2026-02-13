<#
.SYNOPSIS
BULLETPROOF Entra ID Security Audit
.DESCRIPTION
Works on PowerShell 5.1 and 7+ - Minimal dependencies
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit"
)

$ErrorActionPreference = "Continue"

$results = @{
    TenantInfo = @{}
    Users = @{}
    Groups = @{}
    CA = @()
}

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Connect-EntraID {
    Write-Status "Connecting to Entra ID..." "Yellow"
    
    try {
        Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All" -NoWelcome -ErrorAction Stop
        Write-Status "Connected successfully" "Green"
        return $true
    }
    catch {
        Write-Status "Connection failed" "Red"
        return $false
    }
}

function Get-EntraData {
    Write-Status "Gathering data..." "Yellow"
    
    try {
        $org = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization"
        $results.TenantInfo = @{
            Name = $org.value[0].displayName
            ID = $org.value[0].id
        }
        
        $users = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$count=true&`$top=999" -Headers @{ConsistencyLevel="eventual"}
        $allUsers = $users.value
        
        $results.Users = @{
            Total = $allUsers.Count
            Enabled = ($allUsers | Where-Object {$_.accountEnabled -eq $true}).Count
            Disabled = ($allUsers | Where-Object {$_.accountEnabled -eq $false}).Count
        }
        
        $groups = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$count=true&`$top=999" -Headers @{ConsistencyLevel="eventual"}
        $results.Groups = @{
            Total = $groups.value.Count
        }
        
        try {
            $ca = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
            foreach ($p in $ca.value) {
                $results.CA += @{Name=$p.displayName; State=$p.state}
            }
        }
        catch {
            Write-Status "CA policies not accessible" "Yellow"
        }
        
        Write-Status "Data collected" "Green"
    }
    catch {
        Write-Status "Error: $_" "Red"
    }
}

function Generate-Report {
    Write-Status "Generating report..." "Yellow"
    
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $OutputPath "EntraAudit_$timestamp.html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Entra ID Audit</title>
<style>
body { font-family: Arial; background: linear-gradient(135deg, #667eea, #764ba2); padding: 20px; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 15px; }
h1 { color: #0078d4; font-size: 2.5em; }
h2 { color: #2b579a; margin-top: 30px; }
.info { background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 30px; border-radius: 10px; margin: 20px 0; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
.stat { background: linear-gradient(135deg, #f093fb, #f5576c); color: white; padding: 25px; border-radius: 10px; text-align: center; }
.stat-value { font-size: 3em; font-weight: bold; }
.stat-label { font-size: 0.9em; opacity: 0.9; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; }
th { background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 15px; }
td { padding: 12px; border-bottom: 1px solid #ddd; }
</style>
</head>
<body>
<div class="container">
<h1>Microsoft Entra ID Security Audit</h1>

<div class="info">
<h3>Tenant Information</h3>
<p><strong>Name:</strong> $($results.TenantInfo.Name)</p>
<p><strong>ID:</strong> $($results.TenantInfo.ID)</p>
<p><strong>Generated:</strong> $(Get-Date)</p>
</div>

<h2>User Statistics</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total</div><div class="stat-value">$($results.Users.Total)</div></div>
<div class="stat"><div class="stat-label">Enabled</div><div class="stat-value">$($results.Users.Enabled)</div></div>
<div class="stat"><div class="stat-label">Disabled</div><div class="stat-value">$($results.Users.Disabled)</div></div>
</div>

<h2>Groups</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Groups</div><div class="stat-value">$($results.Groups.Total)</div></div>
</div>

<h2>Conditional Access</h2>
"@

    if ($results.CA.Count -gt 0) {
        $html += "<table><tr><th>Policy</th><th>State</th></tr>"
        foreach ($p in $results.CA) {
            $html += "<tr><td>$($p.Name)</td><td>$($p.State)</td></tr>"
        }
        $html += "</table>"
    }
    else {
        $html += "<p>No CA policies or insufficient permissions</p>"
    }

    $html += "</div></body></html>"
    
    $html | Out-File -FilePath $file -Encoding UTF8
    Write-Status "Report: $file" "Green"
    return $file
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "ENTRA ID AUDIT" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

Write-Status "Installing Microsoft.Graph..." "Yellow"
Install-Module Microsoft.Graph -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Authentication -Force

if (Connect-EntraID) {
    Get-EntraData
    $report = Generate-Report
    Write-Host ""
    Write-Host "COMPLETED!" -ForegroundColor Green
    Write-Host "Report: $report" -ForegroundColor Cyan
    Write-Host ""
    Start-Process $report
}
else {
    Write-Host "FAILED TO CONNECT" -ForegroundColor Red
}

Disconnect-MgGraph -ErrorAction SilentlyContinue
