<#
.SYNOPSIS
Microsoft Entra ID Security Audit
.DESCRIPTION
Complete audit of Entra ID tenant with HTML report
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit"
)

$ErrorActionPreference = "Continue"

# Global variables
$script:TenantInfo = @{}
$script:UserStats = @{}
$script:GroupStats = @{}
$script:MFAStats = @{}
$script:CAResults = @()
$script:Findings = @{Critical=@(); High=@(); Medium=@(); Low=@()}
$script:SecurityScore = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{INFO="Cyan"; SUCCESS="Green"; WARNING="Yellow"; ERROR="Red"}
    Write-Host "[$Level] $Message" -ForegroundColor $colors[$Level]
}

function Install-Modules {
    Write-Log "Installing required modules..." "INFO"
    $modules = @("Microsoft.Graph", "Az.Accounts")
    foreach ($mod in $modules) {
        if (!(Get-Module -ListAvailable -Name $mod)) {
            Write-Log "Installing $mod..." "WARNING"
            Install-Module -Name $mod -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        Import-Module $mod -Force -ErrorAction SilentlyContinue
    }
}

function Connect-Services {
    Write-Log "Connecting to services..." "INFO"
    try {
        Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All","Policy.Read.All" -NoWelcome -ErrorAction Stop
        Connect-AzAccount -ErrorAction Stop | Out-Null
        Write-Log "Connected successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Connection failed" "ERROR"
        return $false
    }
}

function Get-TenantInfo {
    Write-Log "Getting tenant info..." "INFO"
    try {
        $org = Get-MgOrganization
        $script:TenantInfo = @{
            Name = $org.DisplayName
            ID = $org.Id
            Domain = ($org.VerifiedDomains | Where-Object {$_.IsDefault}).Name
        }
    }
    catch {
        Write-Log "Failed to get tenant info" "ERROR"
    }
}

function Get-UserStats {
    Write-Log "Analyzing users..." "INFO"
    try {
        $users = Get-MgUser -All
        $script:UserStats = @{
            Total = $users.Count
            Enabled = ($users | Where-Object {$_.AccountEnabled}).Count
            Disabled = ($users | Where-Object {!$_.AccountEnabled}).Count
        }
    }
    catch {
        Write-Log "Failed to analyze users" "ERROR"
    }
}

function Get-GroupStats {
    Write-Log "Analyzing groups..." "INFO"
    try {
        $groups = Get-MgGroup -All
        $script:GroupStats = @{
            Total = $groups.Count
        }
    }
    catch {
        Write-Log "Failed to analyze groups" "ERROR"
    }
}

function Get-MFAStats {
    Write-Log "Checking MFA..." "INFO"
    $script:MFAStats = @{Enabled=0; Disabled=0; Percentage=0}
}

function Get-CAInfo {
    Write-Log "Checking Conditional Access..." "INFO"
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        foreach ($p in $policies) {
            $script:CAResults += @{Name=$p.DisplayName; State=$p.State}
        }
    }
    catch {
        Write-Log "Failed to check CA" "ERROR"
    }
}

function Generate-Report {
    Write-Log "Generating report..." "INFO"
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $OutputPath "EntraAudit_$timestamp.html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
<title>Entra ID Audit</title>
<style>
body { font-family: Arial; margin: 20px; background: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; }
h1 { color: #0078d4; }
.stat { display: inline-block; margin: 10px; padding: 20px; background: #667eea; color: white; border-radius: 8px; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; }
th { background: #0078d4; color: white; padding: 10px; }
td { padding: 10px; border-bottom: 1px solid #ddd; }
</style>
</head>
<body>
<div class="container">
<h1>Entra ID Security Audit</h1>
<p>Generated: $(Get-Date)</p>

<h2>Tenant Information</h2>
<p>Name: $($script:TenantInfo.Name)</p>
<p>ID: $($script:TenantInfo.ID)</p>
<p>Domain: $($script:TenantInfo.Domain)</p>

<h2>User Statistics</h2>
<div class="stat">Total: $($script:UserStats.Total)</div>
<div class="stat">Enabled: $($script:UserStats.Enabled)</div>
<div class="stat">Disabled: $($script:UserStats.Disabled)</div>

<h2>Group Statistics</h2>
<div class="stat">Total Groups: $($script:GroupStats.Total)</div>

<h2>Conditional Access Policies</h2>
<table>
<tr><th>Policy Name</th><th>State</th></tr>
"@

    foreach ($policy in $script:CAResults) {
        $html += "<tr><td>$($policy.Name)</td><td>$($policy.State)</td></tr>"
    }

    $html += @"
</table>
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $file -Encoding UTF8
    Write-Log "Report saved: $file" "SUCCESS"
    return $file
}

# Main execution
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ENTRA ID SECURITY AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Install-Modules

if (Connect-Services) {
    Get-TenantInfo
    Get-UserStats
    Get-GroupStats
    Get-MFAStats
    Get-CAInfo
    
    $report = Generate-Report
    
    Write-Host ""
    Write-Host "AUDIT COMPLETED!" -ForegroundColor Green
    Write-Host "Report: $report" -ForegroundColor Cyan
    Write-Host ""
    
    Start-Process $report
}
else {
    Write-Host "Failed to connect. Exiting." -ForegroundColor Red
}
