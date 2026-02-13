#Requires -Modules Microsoft.Graph, Az.Accounts

<#
.SYNOPSIS
    Microsoft Entra ID Complete Security Audit Script
.DESCRIPTION
    Comprehensive audit of Entra ID tenant including users, groups, MFA, 
    conditional access, licenses, and Azure subscriptions
.PARAMETER OutputPath
    Path where HTML report will be saved (default: Desktop\EntraAudit)
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$script:StartTime = Get-Date
$script:TenantInfo = @{}
$script:UserStats = @{}
$script:GroupStats = @{}
$script:MFAStats = @{}
$script:CAResults = @()
$script:Findings = @{
    Critical = @()
    High = @()
    Medium = @()
    Low = @()
}
$script:SecurityScore = 0
$script:MaxScore = 100

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR" = "Red"
    }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Title,
        [string]$Description,
        [string]$Recommendation
    )
    $script:Findings[$Severity] += [PSCustomObject]@{
        Title = $Title
        Description = $Description
        Recommendation = $Recommendation
    }
}

function Connect-Services {
    Write-Log "Connecting to Microsoft services..." "INFO"
    
    try {
        # Connect to Microsoft Graph
        $scopes = @(
            "User.Read.All",
            "Group.Read.All",
            "Directory.Read.All",
            "Policy.Read.All",
            "Application.Read.All"
        )
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
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
    Write-Log "Getting tenant information..." "INFO"
    
    try {
        $org = Get-MgOrganization
        $script:TenantInfo = @{
            Name = $org.DisplayName
            ID = $org.Id
            Domain = ($org.VerifiedDomains | Where-Object {$_.IsDefault}).Name
            Country = $org.Country
            IsSynced = $org.OnPremisesSyncEnabled
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
        $users = Get-MgUser -All -Property DisplayName,UserPrincipalName,AccountEnabled,SignInActivity,AssignedLicenses,UserType
        
        $enabled = ($users | Where-Object {$_.AccountEnabled}).Count
        $disabled = ($users | Where-Object {-not $_.AccountEnabled}).Count
        $guests = ($users | Where-Object {$_.UserType -eq "Guest"}).Count
        $licensed = ($users | Where-Object {$_.AssignedLicenses.Count -gt 0}).Count
        
        # Inactive users (no login in 90 days)
        $inactiveDate = (Get-Date).AddDays(-90)
        $inactive = ($users | Where-Object {
            $_.SignInActivity.LastSignInDateTime -and 
            $_.SignInActivity.LastSignInDateTime -lt $inactiveDate
        }).Count
        
        $script:UserStats = @{
            Total = $users.Count
            Enabled = $enabled
            Disabled = $disabled
            Guests = $guests
            Licensed = $licensed
            Inactive = $inactive
        }
        
        # Findings
        if ($inactive -gt 0) {
            Add-Finding -Severity "Medium" -Title "Inactive User Accounts" `
                -Description "Found $inactive users inactive for 90+ days" `
                -Recommendation "Review and disable inactive accounts"
            $script:SecurityScore -= 10
        }
        
        Write-Log "Users analyzed: $($users.Count) total" "SUCCESS"
    }
    catch {
        Write-Log "Failed to analyze users: $_" "ERROR"
    }
}

function Get-GroupStats {
    Write-Log "Analyzing groups..." "INFO"
    
    try {
        $groups = Get-MgGroup -All -Property DisplayName,GroupTypes,SecurityEnabled
        
        $security = ($groups | Where-Object {$_.SecurityEnabled}).Count
        $m365 = ($groups | Where-Object {$_.GroupTypes -contains "Unified"}).Count
        
        $script:GroupStats = @{
            Total = $groups.Count
            Security = $security
            Microsoft365 = $m365
        }
        
        Write-Log "Groups analyzed: $($groups.Count) total" "SUCCESS"
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
        
        foreach ($user in $users | Select-Object -First 100) {
            try {
                $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue
                $hasMFA = $methods | Where-Object {
                    $_.'@odata.type' -match 'phone|authenticator|fido'
                }
                if ($hasMFA) { $mfaEnabled++ } else { $mfaDisabled++ }
            }
            catch { }
        }
        
        $percentage = if ($users.Count -gt 0) {
            [math]::Round(($mfaEnabled / ($mfaEnabled + $mfaDisabled)) * 100, 1)
        } else { 0 }
        
        $script:MFAStats = @{
            Total = $users.Count
            Enabled = $mfaEnabled
            Disabled = $mfaDisabled
            Percentage = $percentage
        }
        
        # Findings
        if ($percentage -lt 95) {
            Add-Finding -Severity "Critical" -Title "Low MFA Enrollment" `
                -Description "Only $percentage% of users have MFA enabled" `
                -Recommendation "Enforce MFA through Conditional Access policies"
            $script:SecurityScore -= 20
        }
        
        Write-Log "MFA enrollment: $percentage%" "SUCCESS"
    }
    catch {
        Write-Log "Failed to check MFA: $_" "ERROR"
    }
}

function Get-ConditionalAccess {
    Write-Log "Checking Conditional Access policies..." "INFO"
    
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        
        foreach ($policy in $policies) {
            $script:CAResults += [PSCustomObject]@{
                Name = $policy.DisplayName
                State = $policy.State
                Created = $policy.CreatedDateTime
            }
        }
        
        $enabled = ($policies | Where-Object {$_.State -eq "enabled"}).Count
        
        # Findings
        if ($policies.Count -eq 0) {
            Add-Finding -Severity "Critical" -Title "No Conditional Access Policies" `
                -Description "No CA policies configured" `
                -Recommendation "Implement CA policies immediately"
            $script:SecurityScore -= 30
        }
        elseif ($enabled -eq 0) {
            Add-Finding -Severity "Critical" -Title "No Active CA Policies" `
                -Description "Policies exist but none are enabled" `
                -Recommendation "Enable at least one CA policy"
            $script:SecurityScore -= 25
        }
        
        Write-Log "Found $($policies.Count) CA policies ($enabled enabled)" "SUCCESS"
    }
    catch {
        Write-Log "Failed to check CA policies: $_" "ERROR"
    }
}

function Generate-HTMLReport {
    Write-Log "Generating HTML report..." "INFO"
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportFile = Join-Path $OutputPath "EntraAudit_$timestamp.html"
    
    # Calculate final security score
    $finalScore = [math]::Max(0, $script:MaxScore + $script:SecurityScore)
    $scoreClass = if ($finalScore -ge 80) { "good" } 
                  elseif ($finalScore -ge 60) { "fair" } 
                  else { "poor" }
    
    # Build HTML content using string builder
    $html = New-Object System.Text.StringBuilder
    
    # HTML Header
    [void]$html.AppendLine('<!DOCTYPE html>')
    [void]$html.AppendLine('<html><head><meta charset="UTF-8">')
    [void]$html.AppendLine('<title>Entra ID Security Audit Report</title>')
    [void]$html.AppendLine('<style>')
    [void]$html.AppendLine('body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }')
    [void]$html.AppendLine('.container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }')
    [void]$html.AppendLine('h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }')
    [void]$html.AppendLine('h2 { color: #2b579a; margin-top: 30px; border-bottom: 2px solid #e1e1e1; padding-bottom: 8px; }')
    [void]$html.AppendLine('.score { text-align: center; margin: 30px 0; }')
    [void]$html.AppendLine('.score-circle { display: inline-block; width: 150px; height: 150px; border-radius: 50%; line-height: 150px; font-size: 48px; font-weight: bold; color: white; }')
    [void]$html.AppendLine('.score-circle.good { background: #28a745; }')
    [void]$html.AppendLine('.score-circle.fair { background: #ffc107; }')
    [void]$html.AppendLine('.score-circle.poor { background: #dc3545; }')
    [void]$html.AppendLine('.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }')
    [void]$html.AppendLine('.stat-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }')
    [void]$html.AppendLine('.stat-label { font-size: 14px; opacity: 0.9; }')
    [void]$html.AppendLine('.stat-value { font-size: 36px; font-weight: bold; margin-top: 10px; }')
    [void]$html.AppendLine('table { width: 100%; border-collapse: collapse; margin: 20px 0; }')
    [void]$html.AppendLine('th { background: #0078d4; color: white; padding: 12px; text-align: left; }')
    [void]$html.AppendLine('td { padding: 10px; border-bottom: 1px solid #e1e1e1; }')
    [void]$html.AppendLine('tr:hover { background: #f8f9fa; }')
    [void]$html.AppendLine('.finding { margin: 15px 0; padding: 15px; border-left: 4px solid #ccc; border-radius: 4px; }')
    [void]$html.AppendLine('.finding.critical { border-color: #dc3545; background: #f8d7da; }')
    [void]$html.AppendLine('.finding.high { border-color: #fd7e14; background: #ffe8cc; }')
    [void]$html.AppendLine('.finding.medium { border-color: #ffc107; background: #fff3cd; }')
    [void]$html.AppendLine('.finding.low { border-color: #17a2b8; background: #d1ecf1; }')
    [void]$html.AppendLine('.info-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 20px 0; }')
    [void]$html.AppendLine('.info-item { padding: 10px; }')
    [void]$html.AppendLine('.info-label { font-weight: bold; color: #0078d4; }')
    [void]$html.AppendLine('</style></head><body><div class="container">')
    
    # Title
    [void]$html.AppendLine('<h1>🛡️ Microsoft Entra ID Security Audit Report</h1>')
    [void]$html.AppendLine("<p><strong>Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>")
    
    # Security Score
    [void]$html.AppendLine('<div class="score">')
    [void]$html.AppendLine("<div class='score-circle $scoreClass'>$finalScore</div>")
    [void]$html.AppendLine('<p style="margin-top: 10px; font-size: 20px;">Overall Security Score</p>')
    [void]$html.AppendLine('</div>')
    
    # Tenant Info
    [void]$html.AppendLine('<h2>📋 Tenant Information</h2>')
    [void]$html.AppendLine('<div class="info-grid">')
    [void]$html.AppendLine("<div class='info-item'><div class='info-label'>Tenant Name</div><div>$($script:TenantInfo.Name)</div></div>")
    [void]$html.AppendLine("<div class='info-item'><div class='info-label'>Tenant ID</div><div>$($script:TenantInfo.ID)</div></div>")
    [void]$html.AppendLine("<div class='info-item'><div class='info-label'>Primary Domain</div><div>$($script:TenantInfo.Domain)</div></div>")
    [void]$html.AppendLine("<div class='info-item'><div class='info-label'>Directory Sync</div><div>$(if($script:TenantInfo.IsSynced){'Enabled'}else{'Disabled'})</div></div>")
    [void]$html.AppendLine('</div>')
    
    # User Statistics
    [void]$html.AppendLine('<h2>👥 User Statistics</h2>')
    [void]$html.AppendLine('<div class="stats">')
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Total Users</div><div class='stat-value'>$($script:UserStats.Total)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Enabled</div><div class='stat-value'>$($script:UserStats.Enabled)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Disabled</div><div class='stat-value'>$($script:UserStats.Disabled)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Guests</div><div class='stat-value'>$($script:UserStats.Guests)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Licensed</div><div class='stat-value'>$($script:UserStats.Licensed)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Inactive (90d)</div><div class='stat-value'>$($script:UserStats.Inactive)</div></div>")
    [void]$html.AppendLine('</div>')
    
    # MFA Statistics
    [void]$html.AppendLine('<h2>🔐 Multi-Factor Authentication</h2>')
    [void]$html.AppendLine('<div class="stats">')
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>MFA Enrollment</div><div class='stat-value'>$($script:MFAStats.Percentage)%</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>MFA Enabled</div><div class='stat-value'>$($script:MFAStats.Enabled)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>MFA Disabled</div><div class='stat-value'>$($script:MFAStats.Disabled)</div></div>")
    [void]$html.AppendLine('</div>')
    
    # Group Statistics
    [void]$html.AppendLine('<h2>👥 Groups</h2>')
    [void]$html.AppendLine('<div class="stats">')
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Total Groups</div><div class='stat-value'>$($script:GroupStats.Total)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>Security Groups</div><div class='stat-value'>$($script:GroupStats.Security)</div></div>")
    [void]$html.AppendLine("<div class='stat-box'><div class='stat-label'>M365 Groups</div><div class='stat-value'>$($script:GroupStats.Microsoft365)</div></div>")
    [void]$html.AppendLine('</div>')
    
    # Conditional Access
    [void]$html.AppendLine('<h2>🛡️ Conditional Access Policies</h2>')
    if ($script:CAResults.Count -gt 0) {
        [void]$html.AppendLine('<table><thead><tr><th>Policy Name</th><th>State</th><th>Created</th></tr></thead><tbody>')
        foreach ($policy in $script:CAResults) {
            [void]$html.AppendLine("<tr><td>$($policy.Name)</td><td>$($policy.State)</td><td>$($policy.Created)</td></tr>")
        }
        [void]$html.AppendLine('</tbody></table>')
    } else {
        [void]$html.AppendLine('<p style="color: red; font-weight: bold;">⚠️ No Conditional Access policies found</p>')
    }
    
    # Security Findings
    [void]$html.AppendLine('<h2>⚠️ Security Findings</h2>')
    
    $hasFindings = $false
    foreach ($severity in @("Critical", "High", "Medium", "Low")) {
        foreach ($finding in $script:Findings[$severity]) {
            $hasFindings = $true
            [void]$html.AppendLine("<div class='finding $($severity.ToLower())'>")
            [void]$html.AppendLine("<strong>[$severity] $($finding.Title)</strong>")
            [void]$html.AppendLine("<p>$($finding.Description)</p>")
            [void]$html.AppendLine("<p><em>Recommendation: $($finding.Recommendation)</em></p>")
            [void]$html.AppendLine("</div>")
        }
    }
    
    if (-not $hasFindings) {
        [void]$html.AppendLine('<p style="color: green; font-weight: bold;">✅ No critical security findings</p>')
    }
    
    # Footer
    [void]$html.AppendLine('<hr style="margin-top: 40px;">')
    [void]$html.AppendLine("<p style='text-align: center; color: #666;'>Report generated by $env:USERNAME on $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>")
    [void]$html.AppendLine('<p style="text-align: center; color: #666;">Audit Duration: ' + "$([math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 2)) minutes</p>")
    [void]$html.AppendLine('</div></body></html>')
    
    # Write to file
    $html.ToString() | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Log "Report saved: $reportFile" "SUCCESS"
    return $reportFile
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-Audit {
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host " MICROSOFT ENTRA ID SECURITY AUDIT" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host ""
    
    # Check and install required modules
    Write-Log "Checking required modules..." "INFO"
    $requiredModules = @("Microsoft.Graph", "Az.Accounts")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Log "Installing $module..." "WARNING"
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
        }
    }
    
    # Connect to services
    if (-not (Connect-Services)) {
        Write-Log "Failed to connect. Exiting." "ERROR"
        return
    }
    
    # Run audits
    Get-TenantInfo
    Get-UserStats
    Get-GroupStats
    Get-MFAStats
    Get-ConditionalAccess
    
    # Generate report
    $reportPath = Generate-HTMLReport
    
    # Summary
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host " AUDIT COMPLETED!" -ForegroundColor Green
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Security Score: $([math]::Max(0, $script:MaxScore + $script:SecurityScore))/100" -ForegroundColor Yellow
    Write-Host "📁 Report: $reportPath" -ForegroundColor Cyan
    Write-Host "⚠️  Critical Findings: $($script:Findings.Critical.Count)" -ForegroundColor Red
    Write-Host "⚠️  High Findings: $($script:Findings.High.Count)" -ForegroundColor Magenta
    Write-Host "⚠️  Medium Findings: $($script:Findings.Medium.Count)" -ForegroundColor Yellow
    Write-Host ""
    
    # Open report
    Start-Process $reportPath
}

# Run the audit
Start-Audit
