<#
.SYNOPSIS
Microsoft Entra ID Security Audit - FIXED VERSION
.DESCRIPTION
Complete audit of Entra ID tenant with HTML report
Fixed to use specific Graph modules to avoid function capacity error
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
    
    # Install SPECIFIC Graph modules to avoid function capacity error
    $modules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Users",
        "Microsoft.Graph.Groups",
        "Microsoft.Graph.Identity.DirectoryManagement",
        "Microsoft.Graph.Identity.SignIns",
        "Az.Accounts"
    )
    
    foreach ($mod in $modules) {
        if (!(Get-Module -ListAvailable -Name $mod)) {
            Write-Log "Installing $mod..." "WARNING"
            try {
                Install-Module -Name $mod -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-Log "Installed $mod" "SUCCESS"
            }
            catch {
                Write-Log "Failed to install $mod" "ERROR"
            }
        }
        
        # Import the module
        try {
            Import-Module $mod -Force -ErrorAction Stop
            Write-Log "Imported $mod" "SUCCESS"
        }
        catch {
            Write-Log "Failed to import $mod" "WARNING"
        }
    }
}

function Connect-Services {
    Write-Log "Connecting to services..." "INFO"
    try {
        # Connect to Microsoft Graph with specific scopes
        Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All","Policy.Read.All","Organization.Read.All" -NoWelcome -ErrorAction Stop
        Write-Log "Connected to Microsoft Graph" "SUCCESS"
        
        # Connect to Azure
        Connect-AzAccount -ErrorAction Stop | Out-Null
        Write-Log "Connected to Azure" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Connection failed: $_" "ERROR"
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
            Country = $org.Country
        }
        Write-Log "Tenant: $($org.DisplayName)" "SUCCESS"
    }
    catch {
        Write-Log "Failed to get tenant info: $_" "ERROR"
    }
}

function Get-UserStats {
    Write-Log "Analyzing users..." "INFO"
    try {
        $users = Get-MgUser -All -Property DisplayName,UserPrincipalName,AccountEnabled,UserType,AssignedLicenses
        
        $enabled = ($users | Where-Object {$_.AccountEnabled -eq $true}).Count
        $disabled = ($users | Where-Object {$_.AccountEnabled -eq $false}).Count
        $guests = ($users | Where-Object {$_.UserType -eq "Guest"}).Count
        $licensed = ($users | Where-Object {$_.AssignedLicenses.Count -gt 0}).Count
        
        $script:UserStats = @{
            Total = $users.Count
            Enabled = $enabled
            Disabled = $disabled
            Guests = $guests
            Licensed = $licensed
        }
        
        Write-Log "Users: Total=$($users.Count), Enabled=$enabled, Disabled=$disabled" "SUCCESS"
    }
    catch {
        Write-Log "Failed to analyze users: $_" "ERROR"
    }
}

function Get-GroupStats {
    Write-Log "Analyzing groups..." "INFO"
    try {
        $groups = Get-MgGroup -All -Property DisplayName,GroupTypes,SecurityEnabled
        
        $security = ($groups | Where-Object {$_.SecurityEnabled -eq $true}).Count
        $m365 = ($groups | Where-Object {$_.GroupTypes -contains "Unified"}).Count
        
        $script:GroupStats = @{
            Total = $groups.Count
            Security = $security
            Microsoft365 = $m365
        }
        
        Write-Log "Groups: Total=$($groups.Count), Security=$security, M365=$m365" "SUCCESS"
    }
    catch {
        Write-Log "Failed to analyze groups: $_" "ERROR"
    }
}

function Get-MFAStats {
    Write-Log "Checking MFA enrollment..." "INFO"
    try {
        $users = Get-MgUser -All -Property Id,UserPrincipalName
        $mfaEnabled = 0
        $mfaDisabled = 0
        
        # Check first 50 users (to avoid timeout)
        foreach ($user in $users | Select-Object -First 50) {
            try {
                $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue
                $hasMFA = $methods | Where-Object {$_.'@odata.type' -match 'phone|authenticator|fido'}
                if ($hasMFA) { $mfaEnabled++ } else { $mfaDisabled++ }
            }
            catch {
                # Skip this user
            }
        }
        
        $percentage = if (($mfaEnabled + $mfaDisabled) -gt 0) {
            [math]::Round(($mfaEnabled / ($mfaEnabled + $mfaDisabled)) * 100, 1)
        } else { 0 }
        
        $script:MFAStats = @{
            Enabled = $mfaEnabled
            Disabled = $mfaDisabled
            Percentage = $percentage
        }
        
        Write-Log "MFA: $percentage% enrolled (sampled 50 users)" "SUCCESS"
    }
    catch {
        Write-Log "Failed to check MFA: $_" "ERROR"
        $script:MFAStats = @{Enabled=0; Disabled=0; Percentage=0}
    }
}

function Get-CAInfo {
    Write-Log "Checking Conditional Access..." "INFO"
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        
        foreach ($p in $policies) {
            $script:CAResults += @{
                Name = $p.DisplayName
                State = $p.State
                Created = $p.CreatedDateTime
            }
        }
        
        $enabled = ($policies | Where-Object {$_.State -eq "enabled"}).Count
        Write-Log "CA Policies: Total=$($policies.Count), Enabled=$enabled" "SUCCESS"
        
        if ($policies.Count -eq 0) {
            $script:Findings.Critical += @{
                Title = "No Conditional Access Policies"
                Description = "No CA policies configured"
                Recommendation = "Implement CA policies immediately"
            }
        }
    }
    catch {
        Write-Log "Failed to check CA: $_" "ERROR"
    }
}

function Generate-Report {
    Write-Log "Generating report..." "INFO"
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $OutputPath "EntraAudit_$timestamp.html"
    
    $finalScore = [math]::Max(0, 100 + $script:SecurityScore)
    $scoreColor = if ($finalScore -ge 80) { "green" } elseif ($finalScore -ge 60) { "orange" } else { "red" }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Entra ID Security Audit</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
h2 { color: #2b579a; margin-top: 30px; }
.score { text-align: center; margin: 30px 0; }
.score-circle { display: inline-block; width: 150px; height: 150px; border-radius: 50%; background: $scoreColor; color: white; line-height: 150px; font-size: 48px; font-weight: bold; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
.stat { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
.stat-label { font-size: 14px; opacity: 0.9; }
.stat-value { font-size: 36px; font-weight: bold; margin-top: 10px; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; }
th { background: #0078d4; color: white; padding: 12px; text-align: left; }
td { padding: 10px; border-bottom: 1px solid #e1e1e1; }
tr:hover { background: #f8f9fa; }
.finding { margin: 15px 0; padding: 15px; border-left: 4px solid #dc3545; background: #f8d7da; border-radius: 4px; }
.info { background: #e3f2fd; border-left: 4px solid #2196f3; padding: 20px; border-radius: 5px; margin: 20px 0; }
</style>
</head>
<body>
<div class="container">
<h1>Microsoft Entra ID Security Audit</h1>
<p><strong>Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>

<div class="score">
<div class="score-circle">$finalScore</div>
<p style="margin-top: 10px; font-size: 20px;">Overall Security Score</p>
</div>

<h2>Tenant Information</h2>
<div class="info">
<p><strong>Tenant Name:</strong> $($script:TenantInfo.Name)</p>
<p><strong>Tenant ID:</strong> $($script:TenantInfo.ID)</p>
<p><strong>Primary Domain:</strong> $($script:TenantInfo.Domain)</p>
<p><strong>Country:</strong> $($script:TenantInfo.Country)</p>
</div>

<h2>User Statistics</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Users</div><div class="stat-value">$($script:UserStats.Total)</div></div>
<div class="stat"><div class="stat-label">Enabled</div><div class="stat-value">$($script:UserStats.Enabled)</div></div>
<div class="stat"><div class="stat-label">Disabled</div><div class="stat-value">$($script:UserStats.Disabled)</div></div>
<div class="stat"><div class="stat-label">Guests</div><div class="stat-value">$($script:UserStats.Guests)</div></div>
<div class="stat"><div class="stat-label">Licensed</div><div class="stat-value">$($script:UserStats.Licensed)</div></div>
</div>

<h2>MFA Enrollment</h2>
<div class="stats">
<div class="stat"><div class="stat-label">MFA Percentage</div><div class="stat-value">$($script:MFAStats.Percentage)%</div></div>
<div class="stat"><div class="stat-label">MFA Enabled</div><div class="stat-value">$($script:MFAStats.Enabled)</div></div>
<div class="stat"><div class="stat-label">MFA Disabled</div><div class="stat-value">$($script:MFAStats.Disabled)</div></div>
</div>

<h2>Groups</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Groups</div><div class="stat-value">$($script:GroupStats.Total)</div></div>
<div class="stat"><div class="stat-label">Security Groups</div><div class="stat-value">$($script:GroupStats.Security)</div></div>
<div class="stat"><div class="stat-label">M365 Groups</div><div class="stat-value">$($script:GroupStats.Microsoft365)</div></div>
</div>

<h2>Conditional Access Policies</h2>
"@

    if ($script:CAResults.Count -gt 0) {
        $html += "<table><tr><th>Policy Name</th><th>State</th><th>Created</th></tr>"
        foreach ($policy in $script:CAResults) {
            $html += "<tr><td>$($policy.Name)</td><td>$($policy.State)</td><td>$($policy.Created)</td></tr>"
        }
        $html += "</table>"
    } else {
        $html += "<p style='color: red; font-weight: bold;'>No Conditional Access policies found</p>"
    }

    $html += "<h2>Security Findings</h2>"
    
    if ($script:Findings.Critical.Count -gt 0) {
        foreach ($finding in $script:Findings.Critical) {
            $html += "<div class='finding'><strong>[CRITICAL] $($finding.Title)</strong><p>$($finding.Description)</p><p><em>Recommendation: $($finding.Recommendation)</em></p></div>"
        }
    } else {
        $html += "<p style='color: green; font-weight: bold;'>No critical security findings</p>"
    }

    $html += @"
<hr style="margin-top: 40px;">
<p style="text-align: center; color: #666;">Report generated by $env:USERNAME on $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
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
Write-Host "ENTRA ID SECURITY AUDIT - FIXED" -ForegroundColor Cyan
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
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "AUDIT COMPLETED!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Report: $report" -ForegroundColor Cyan
    Write-Host ""
    
    Start-Process $report
}
else {
    Write-Host "Failed to connect. Exiting." -ForegroundColor Red
}
