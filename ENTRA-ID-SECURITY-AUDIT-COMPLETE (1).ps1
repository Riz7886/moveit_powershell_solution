# ============================================================================
# MICROSOFT ENTRA ID COMPLETE SECURITY AUDIT
# ============================================================================
# Purpose: Complete Entra ID (Azure AD) security audit
# Author: Syed Rizvi  
# Date: February 13, 2026
# ============================================================================

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit",
    [switch]$SkipCostAnalysis,
    [switch]$IncludeDeletedUsers
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$script:StartTime = Get-Date
$script:AuditResults = @{
    TenantInfo = @{}
    SecurityScore = @{
        Overall = 0
        MaxScore = 100
        Categories = @{}
    }
    Statistics = @{
        Users = @{}
        Groups = @{}
        Applications = @{}
        Licenses = @{}
        Devices = @{}
        PrivilegedRoles = @{}
    }
    Findings = @{
        Critical = @()
        High = @()
        Medium = @()
        Low = @()
        Info = @()
    }
    ConditionalAccess = @()
    MFA = @{}
    PIM = @{}
    EnterpriseApps = @()
    Subscriptions = @()
    CostAnalysis = @{}
    Recommendations = @()
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-AuditLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "CRITICAL")]
        [string]$Type = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "SUCCESS"  { "Green" }
        "ERROR"    { "Red" }
        "WARNING"  { "Yellow" }
        "CRITICAL" { "Magenta" }
        default    { "Cyan" }
    }
    
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Add-Finding {
    param(
        [ValidateSet("Critical", "High", "Medium", "Low", "Info")]
        [string]$Severity,
        [string]$Category,
        [string]$Title,
        [string]$Description,
        [string]$Recommendation,
        [string]$Impact = "N/A",
        [array]$AffectedItems = @()
    )
    
    $finding = [PSCustomObject]@{
        Severity       = $Severity
        Category       = $Category
        Title          = $Title
        Description    = $Description
        Recommendation = $Recommendation
        Impact         = $Impact
        AffectedItems  = $AffectedItems
        Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $script:AuditResults.Findings[$Severity] += $finding
}

function Update-SecurityScore {
    param(
        [string]$Category,
        [int]$Points,
        [int]$MaxPoints
    )
    
    if (-not $script:AuditResults.SecurityScore.Categories.ContainsKey($Category)) {
        $script:AuditResults.SecurityScore.Categories[$Category] = @{
            Score = 0
            MaxScore = 0
        }
    }
    
    $script:AuditResults.SecurityScore.Categories[$Category].Score += $Points
    $script:AuditResults.SecurityScore.Categories[$Category].MaxScore += $MaxPoints
}

function Test-ModuleInstalled {
    param([string]$ModuleName)
    
    $module = Get-Module -ListAvailable -Name $ModuleName
    if ($module) {
        Write-AuditLog "Module '$ModuleName' is installed" -Type "SUCCESS"
        return $true
    } else {
        Write-AuditLog "Module '$ModuleName' is NOT installed" -Type "WARNING"
        return $false
    }
}

# ============================================================================
# MODULE INSTALLATION
# ============================================================================

function Install-RequiredModules {
    Write-AuditLog "Checking required PowerShell modules..." -Type "INFO"
    
    $requiredModules = @(
        "Microsoft.Graph",
        "Az.Accounts",
        "Az.Resources"
    )
    
    foreach ($moduleName in $requiredModules) {
        $installed = Get-Module -ListAvailable -Name $moduleName
        
        if (-not $installed) {
            Write-AuditLog "Installing module: $moduleName..." -Type "WARNING"
            try {
                Install-Module -Name $moduleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-AuditLog "Successfully installed $moduleName" -Type "SUCCESS"
            }
            catch {
                Write-AuditLog "Failed to install $moduleName : $_" -Type "ERROR"
            }
        } else {
            Write-AuditLog "Module $moduleName already installed" -Type "SUCCESS"
        }
    }
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

function Connect-EntraServices {
    Write-AuditLog "Connecting to Microsoft Entra ID and Azure services..." -Type "INFO"
    
    try {
        Write-AuditLog "Connecting to Microsoft Graph..." -Type "INFO"
        $graphScopes = @(
            "User.Read.All",
            "Group.Read.All",
            "Directory.Read.All",
            "AuditLog.Read.All",
            "Policy.Read.All",
            "Application.Read.All",
            "RoleManagement.Read.All"
        )
        
        Connect-MgGraph -Scopes $graphScopes -NoWelcome -ErrorAction Stop
        Write-AuditLog "Connected to Microsoft Graph successfully" -Type "SUCCESS"
        
        Write-AuditLog "Connecting to Azure..." -Type "INFO"
        Connect-AzAccount -ErrorAction Stop | Out-Null
        Write-AuditLog "Connected to Azure successfully" -Type "SUCCESS"
        
        return $true
    }
    catch {
        Write-AuditLog "Failed to connect to services: $_" -Type "ERROR"
        return $false
    }
}

# ============================================================================
# TENANT INFORMATION
# ============================================================================

function Get-TenantInformation {
    Write-AuditLog "Gathering tenant information..." -Type "INFO"
    
    try {
        $org = Get-MgOrganization
        
        $script:AuditResults.TenantInfo = @{
            TenantId = $org.Id
            DisplayName = $org.DisplayName
            TechnicalContact = ($org.TechnicalNotificationMails -join ", ")
            SecurityContact = ($org.SecurityComplianceNotificationMails -join ", ")
            CreatedDateTime = $org.CreatedDateTime
            Country = $org.Country
            PreferredLanguage = $org.PreferredLanguage
            DirectorySyncEnabled = $org.OnPremisesSyncEnabled
            VerifiedDomains = (($org.VerifiedDomains | Where-Object {$_.IsDefault}).Name)
            TotalDomains = $org.VerifiedDomains.Count
        }
        
        Write-AuditLog "Tenant: $($org.DisplayName)" -Type "SUCCESS"
        Write-AuditLog "Tenant ID: $($org.Id)" -Type "INFO"
        
        if ($org.OnPremisesSyncEnabled) {
            Add-Finding -Severity "Info" -Category "Configuration" `
                -Title "Directory Synchronization Enabled" `
                -Description "Directory sync is enabled for this tenant" `
                -Recommendation "Verify Azure AD Connect is configured correctly"
        } else {
            Write-AuditLog "This is a cloud-only tenant (no on-prem sync)" -Type "INFO"
        }
        
    }
    catch {
        Write-AuditLog "Failed to get tenant information: $_" -Type "ERROR"
    }
}

# ============================================================================
# USER AUDIT
# ============================================================================

function Get-UserAudit {
    Write-AuditLog "Auditing user accounts..." -Type "INFO"
    
    try {
        $users = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,LastPasswordChangeDateTime,PasswordPolicies,SignInActivity,AssignedLicenses,OnPremisesSyncEnabled,UserType,EmployeeId,Department,JobTitle
        
        Write-AuditLog "Total users found: $($users.Count)" -Type "INFO"
        
        $enabledUsers = $users | Where-Object {$_.AccountEnabled -eq $true}
        $disabledUsers = $users | Where-Object {$_.AccountEnabled -eq $false}
        $guestUsers = $users | Where-Object {$_.UserType -eq "Guest"}
        $syncedUsers = $users | Where-Object {$_.OnPremisesSyncEnabled -eq $true}
        $cloudOnlyUsers = $users | Where-Object {$_.OnPremisesSyncEnabled -ne $true}
        
        $inactiveThreshold = (Get-Date).AddDays(-90)
        $inactiveUsers = $users | Where-Object {
            $_.SignInActivity.LastSignInDateTime -and
            $_.SignInActivity.LastSignInDateTime -lt $inactiveThreshold
        }
        
        $noPasswordExpiry = $users | Where-Object {
            $_.PasswordPolicies -match "DisablePasswordExpiration"
        }
        
        $licensedUsers = $users | Where-Object {$_.AssignedLicenses.Count -gt 0}
        
        $script:AuditResults.Statistics.Users = @{
            Total = $users.Count
            Enabled = $enabledUsers.Count
            Disabled = $disabledUsers.Count
            Guest = $guestUsers.Count
            Synced = $syncedUsers.Count
            CloudOnly = $cloudOnlyUsers.Count
            Inactive90Days = $inactiveUsers.Count
            NoPasswordExpiry = $noPasswordExpiry.Count
            Licensed = $licensedUsers.Count
            Unlicensed = ($users.Count - $licensedUsers.Count)
        }
        
        if ($inactiveUsers.Count -gt 0) {
            Add-Finding -Severity "Medium" -Category "User Security" `
                -Title "Inactive User Accounts Detected" `
                -Description "Found $($inactiveUsers.Count) user accounts with no sign-in activity in the last 90 days" `
                -Recommendation "Review and disable or delete inactive user accounts" `
                -Impact "Inactive accounts increase attack surface" `
                -AffectedItems ($inactiveUsers | Select-Object -First 10 -ExpandProperty UserPrincipalName)
            
            Update-SecurityScore -Category "Users" -Points 0 -MaxPoints 10
        } else {
            Update-SecurityScore -Category "Users" -Points 10 -MaxPoints 10
        }
        
        if ($disabledUsers.Count -gt 0) {
            Add-Finding -Severity "Low" -Category "User Management" `
                -Title "Disabled User Accounts" `
                -Description "Found $($disabledUsers.Count) disabled user accounts" `
                -Recommendation "Review disabled accounts and remove if no longer needed" `
                -Impact "Clean up reduces license costs and clutter"
        }
        
        if ($noPasswordExpiry.Count -gt 0) {
            Add-Finding -Severity "High" -Category "Password Policy" `
                -Title "Users with Non-Expiring Passwords" `
                -Description "Found $($noPasswordExpiry.Count) users with passwords that never expire" `
                -Recommendation "Enable password expiration for all users unless there is a specific business reason" `
                -Impact "Non-expiring passwords increase security risk" `
                -AffectedItems ($noPasswordExpiry | Select-Object -First 10 -ExpandProperty UserPrincipalName)
            
            Update-SecurityScore -Category "Users" -Points 0 -MaxPoints 15
        } else {
            Update-SecurityScore -Category "Users" -Points 15 -MaxPoints 15
        }
        
        if ($guestUsers.Count -gt 0) {
            Add-Finding -Severity "Info" -Category "Guest Access" `
                -Title "Guest User Accounts" `
                -Description "Found $($guestUsers.Count) guest user accounts" `
                -Recommendation "Regularly review guest access and remove unnecessary accounts" `
                -Impact "Guest users should be monitored for security compliance"
        }
        
        Write-AuditLog "User audit completed: $($users.Count) users analyzed" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit users: $_" -Type "ERROR"
    }
}

# ============================================================================
# GROUP AUDIT
# ============================================================================

function Get-GroupAudit {
    Write-AuditLog "Auditing groups..." -Type "INFO"
    
    try {
        $groups = Get-MgGroup -All -Property DisplayName,Description,GroupTypes,Mail,SecurityEnabled,MembershipRule,OnPremisesSyncEnabled
        
        Write-AuditLog "Total groups found: $($groups.Count)" -Type "INFO"
        
        $securityGroups = $groups | Where-Object {$_.SecurityEnabled -eq $true}
        $m365Groups = $groups | Where-Object {$_.GroupTypes -contains "Unified"}
        $dynamicGroups = $groups | Where-Object {$_.GroupTypes -contains "DynamicMembership"}
        $syncedGroups = $groups | Where-Object {$_.OnPremisesSyncEnabled -eq $true}
        
        $emptyGroups = @()
        foreach ($group in $groups | Select-Object -First 100) {
            $members = Get-MgGroupMember -GroupId $group.Id -ErrorAction SilentlyContinue
            if ($null -eq $members -or $members.Count -eq 0) {
                $emptyGroups += $group
            }
        }
        
        $script:AuditResults.Statistics.Groups = @{
            Total = $groups.Count
            Security = $securityGroups.Count
            Microsoft365 = $m365Groups.Count
            Dynamic = $dynamicGroups.Count
            Synced = $syncedGroups.Count
            CloudOnly = ($groups.Count - $syncedGroups.Count)
            Empty = $emptyGroups.Count
        }
        
        if ($emptyGroups.Count -gt 0) {
            Add-Finding -Severity "Low" -Category "Group Management" `
                -Title "Empty Groups Detected" `
                -Description "Found $($emptyGroups.Count) groups with no members" `
                -Recommendation "Review and delete empty groups to reduce clutter" `
                -Impact "Empty groups can cause confusion"
        }
        
        Write-AuditLog "Group audit completed: $($groups.Count) groups analyzed" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit groups: $_" -Type "ERROR"
    }
}

# ============================================================================
# PRIVILEGED ROLES AUDIT
# ============================================================================

function Get-PrivilegedRolesAudit {
    Write-AuditLog "Auditing privileged roles..." -Type "INFO"
    
    try {
        $roles = Get-MgDirectoryRole -All
        
        $privilegedRoles = @()
        
        foreach ($role in $roles) {
            $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
            
            if ($members.Count -gt 0) {
                $privilegedRoles += [PSCustomObject]@{
                    RoleName = $role.DisplayName
                    RoleId = $role.Id
                    MemberCount = $members.Count
                    Members = ($members | ForEach-Object {
                        $user = Get-MgUser -UserId $_.Id -ErrorAction SilentlyContinue
                        if ($user) {
                            [PSCustomObject]@{
                                DisplayName = $user.DisplayName
                                UPN = $user.UserPrincipalName
                                AccountEnabled = $user.AccountEnabled
                            }
                        }
                    })
                }
            }
        }
        
        $script:AuditResults.Statistics.PrivilegedRoles = @{
            TotalRoles = $roles.Count
            RolesWithMembers = $privilegedRoles.Count
            TotalPrivilegedUsers = ($privilegedRoles | Measure-Object -Property MemberCount -Sum).Sum
        }
        
        $globalAdmins = $privilegedRoles | Where-Object {$_.RoleName -eq "Global Administrator"}
        if ($globalAdmins -and $globalAdmins.MemberCount -gt 5) {
            Add-Finding -Severity "High" -Category "Privileged Access" `
                -Title "Excessive Global Administrators" `
                -Description "Found $($globalAdmins.MemberCount) Global Administrators (Recommended: 2-5)" `
                -Recommendation "Reduce the number of Global Administrators to minimum necessary" `
                -Impact "Too many Global Admins increases security risk" `
                -AffectedItems ($globalAdmins.Members | Select-Object -First 10 -ExpandProperty UPN)
            
            Update-SecurityScore -Category "Privileged Access" -Points 0 -MaxPoints 20
        } else {
            Update-SecurityScore -Category "Privileged Access" -Points 20 -MaxPoints 20
        }
        
        Write-AuditLog "Privileged roles audit completed" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit privileged roles: $_" -Type "ERROR"
    }
}

# ============================================================================
# MFA AUDIT
# ============================================================================

function Get-MFAAudit {
    Write-AuditLog "Auditing MFA enrollment..." -Type "INFO"
    
    try {
        $users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName
        
        $mfaEnabled = 0
        $mfaDisabled = 0
        $usersWithoutMFA = @()
        
        foreach ($user in $users | Select-Object -First 200) {
            try {
                $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction SilentlyContinue
                
                $hasMFA = $authMethods | Where-Object {
                    $_.'@odata.type' -in @(
                        '#microsoft.graph.phoneAuthenticationMethod',
                        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod',
                        '#microsoft.graph.fido2AuthenticationMethod'
                    )
                }
                
                if ($hasMFA) {
                    $mfaEnabled++
                } else {
                    $mfaDisabled++
                    $usersWithoutMFA += $user.UserPrincipalName
                }
            }
            catch {
                # Silently continue
            }
        }
        
        $mfaPercentage = if ($users.Count -gt 0) { 
            [math]::Round(($mfaEnabled / $users.Count) * 100, 2) 
        } else { 
            0 
        }
        
        $script:AuditResults.MFA = @{
            TotalUsers = $users.Count
            MFAEnabled = $mfaEnabled
            MFADisabled = $mfaDisabled
            MFAPercentage = $mfaPercentage
            UsersWithoutMFA = $usersWithoutMFA
        }
        
        if ($mfaPercentage -lt 95) {
            Add-Finding -Severity "Critical" -Category "MFA" `
                -Title "Low MFA Enrollment Rate" `
                -Description "Only $mfaPercentage% of users have MFA enabled (Recommended: 100%)" `
                -Recommendation "Enforce MFA for all users through Conditional Access policies" `
                -Impact "Users without MFA are highly vulnerable to account compromise" `
                -AffectedItems ($usersWithoutMFA | Select-Object -First 20)
            
            Update-SecurityScore -Category "MFA" -Points ([math]::Round($mfaPercentage / 5)) -MaxPoints 20
        } else {
            Update-SecurityScore -Category "MFA" -Points 20 -MaxPoints 20
        }
        
        Write-AuditLog "MFA audit completed: $mfaPercentage% enrollment rate" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit MFA: $_" -Type "ERROR"
    }
}

# ============================================================================
# CONDITIONAL ACCESS POLICIES
# ============================================================================

function Get-ConditionalAccessAudit {
    Write-AuditLog "Auditing Conditional Access policies..." -Type "INFO"
    
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All
        
        Write-AuditLog "Found $($policies.Count) Conditional Access policies" -Type "INFO"
        
        $enabledPolicies = $policies | Where-Object {$_.State -eq "enabled"}
        $disabledPolicies = $policies | Where-Object {$_.State -eq "disabled"}
        $reportOnlyPolicies = $policies | Where-Object {$_.State -eq "enabledForReportingButNotEnforced"}
        
        foreach ($policy in $policies) {
            $script:AuditResults.ConditionalAccess += [PSCustomObject]@{
                DisplayName = $policy.DisplayName
                State = $policy.State
                CreatedDateTime = $policy.CreatedDateTime
                ModifiedDateTime = $policy.ModifiedDateTime
                GrantControls = ($policy.GrantControls.BuiltInControls -join ", ")
                Conditions = "Users: $($policy.Conditions.Users.IncludeUsers.Count), Apps: $($policy.Conditions.Applications.IncludeApplications.Count)"
            }
        }
        
        if ($policies.Count -eq 0) {
            Add-Finding -Severity "Critical" -Category "Conditional Access" `
                -Title "No Conditional Access Policies Configured" `
                -Description "No Conditional Access policies are configured for this tenant" `
                -Recommendation "Implement Conditional Access policies to enforce MFA, device compliance, and location-based access" `
                -Impact "Lack of Conditional Access increases security risk significantly"
            
            Update-SecurityScore -Category "Conditional Access" -Points 0 -MaxPoints 20
        } elseif ($enabledPolicies.Count -eq 0) {
            Add-Finding -Severity "Critical" -Category "Conditional Access" `
                -Title "No Active Conditional Access Policies" `
                -Description "Found $($policies.Count) policies but none are enabled" `
                -Recommendation "Enable at least one Conditional Access policy" `
                -Impact "Disabled policies provide no protection"
            
            Update-SecurityScore -Category "Conditional Access" -Points 0 -MaxPoints 20
        } else {
            Update-SecurityScore -Category "Conditional Access" -Points 20 -MaxPoints 20
            
            Add-Finding -Severity "Info" -Category "Conditional Access" `
                -Title "Conditional Access Policies Active" `
                -Description "Found $($enabledPolicies.Count) enabled policies" `
                -Recommendation "Regularly review and update policies" `
                -Impact "Good security posture"
        }
        
        Write-AuditLog "Conditional Access audit completed" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit Conditional Access: $_" -Type "ERROR"
    }
}

# ============================================================================
# ENTERPRISE APPLICATIONS AUDIT
# ============================================================================

function Get-EnterpriseAppsAudit {
    Write-AuditLog "Auditing Enterprise Applications..." -Type "INFO"
    
    try {
        $apps = Get-MgServicePrincipal -All -Property AppId,DisplayName,ServicePrincipalType,SignInAudience,AccountEnabled,Tags
        
        Write-AuditLog "Found $($apps.Count) Enterprise Applications" -Type "INFO"
        
        $enabledApps = $apps | Where-Object {$_.AccountEnabled -eq $true}
        $disabledApps = $apps | Where-Object {$_.AccountEnabled -eq $false}
        
        foreach ($app in $apps | Select-Object -First 100) {
            $script:AuditResults.EnterpriseApps += [PSCustomObject]@{
                DisplayName = $app.DisplayName
                AppId = $app.AppId
                Type = $app.ServicePrincipalType
                Enabled = $app.AccountEnabled
                SignInAudience = $app.SignInAudience
            }
        }
        
        $script:AuditResults.Statistics.Applications = @{
            Total = $apps.Count
            Enabled = $enabledApps.Count
            Disabled = $disabledApps.Count
        }
        
        Write-AuditLog "Enterprise Apps audit completed: $($apps.Count) applications" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit Enterprise Applications: $_" -Type "ERROR"
    }
}

# ============================================================================
# LICENSE AUDIT
# ============================================================================

function Get-LicenseAudit {
    Write-AuditLog "Auditing licenses..." -Type "INFO"
    
    try {
        $licenses = Get-MgSubscribedSku
        
        $totalLicenses = ($licenses | Measure-Object -Property ConsumedUnits -Sum).Sum
        $availableLicenses = ($licenses | ForEach-Object {$_.PrepaidUnits.Enabled - $_.ConsumedUnits} | Measure-Object -Sum).Sum
        
        $script:AuditResults.Statistics.Licenses = @{
            TotalSKUs = $licenses.Count
            TotalConsumed = $totalLicenses
            TotalAvailable = $availableLicenses
            Details = @()
        }
        
        foreach ($license in $licenses) {
            $script:AuditResults.Statistics.Licenses.Details += [PSCustomObject]@{
                SkuPartNumber = $license.SkuPartNumber
                Total = $license.PrepaidUnits.Enabled
                Consumed = $license.ConsumedUnits
                Available = ($license.PrepaidUnits.Enabled - $license.ConsumedUnits)
            }
        }
        
        if ($availableLicenses -gt 0) {
            $estimatedWaste = $availableLicenses * 10
            
            Add-Finding -Severity "Medium" -Category "Cost Optimization" `
                -Title "Unused License Capacity" `
                -Description "Found $availableLicenses unused licenses" `
                -Recommendation "Review license allocation and reduce quantity to save costs" `
                -Impact "Estimated monthly waste: `$$estimatedWaste"
        }
        
        Write-AuditLog "License audit completed: $totalLicenses licenses in use" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit licenses: $_" -Type "ERROR"
    }
}

# ============================================================================
# AZURE SUBSCRIPTIONS & RESOURCES
# ============================================================================

function Get-AzureSubscriptionsAudit {
    Write-AuditLog "Auditing Azure subscriptions..." -Type "INFO"
    
    try {
        $subscriptions = Get-AzSubscription
        
        Write-AuditLog "Found $($subscriptions.Count) Azure subscriptions" -Type "INFO"
        
        foreach ($sub in $subscriptions) {
            Set-AzContext -SubscriptionId $sub.Id | Out-Null
            
            $resources = Get-AzResource
            $resourceGroups = Get-AzResourceGroup
            
            $script:AuditResults.Subscriptions += [PSCustomObject]@{
                Name = $sub.Name
                Id = $sub.Id
                State = $sub.State
                TenantId = $sub.TenantId
                ResourceGroups = $resourceGroups.Count
                TotalResources = $resources.Count
                ResourceTypes = ($resources | Group-Object ResourceType | Select-Object Name, Count)
            }
            
            Write-AuditLog "Subscription: $($sub.Name) - $($resources.Count) resources" -Type "INFO"
        }
        
        Write-AuditLog "Azure subscriptions audit completed" -Type "SUCCESS"
    }
    catch {
        Write-AuditLog "Failed to audit Azure subscriptions: $_" -Type "ERROR"
    }
}

# ============================================================================
# SECURITY RECOMMENDATIONS
# ============================================================================

function Generate-Recommendations {
    Write-AuditLog "Generating security recommendations..." -Type "INFO"
    
    $recommendations = @()
    
    if ($script:AuditResults.MFA.MFAPercentage -lt 95) {
        $recommendations += "🔐 CRITICAL: Enforce MFA for all users through Conditional Access policies"
    }
    
    if ($script:AuditResults.ConditionalAccess.Count -eq 0) {
        $recommendations += "🛡️ CRITICAL: Implement Conditional Access policies immediately"
    }
    
    if ($script:AuditResults.Statistics.Users.Inactive90Days -gt 0) {
        $recommendations += "👤 HIGH: Review and disable $($script:AuditResults.Statistics.Users.Inactive90Days) inactive user accounts"
    }
    
    if ($script:AuditResults.Statistics.PrivilegedRoles.TotalPrivilegedUsers -gt 10) {
        $recommendations += "⚠️ HIGH: Review privileged role assignments and implement PIM"
    }
    
    if ($script:AuditResults.Statistics.Licenses.TotalAvailable -gt 0) {
        $recommendations += "💰 MEDIUM: Optimize license allocation to reduce costs"
    }
    
    $script:AuditResults.Recommendations = $recommendations
    
    Write-AuditLog "Generated $($recommendations.Count) recommendations" -Type "SUCCESS"
}

# ============================================================================
# CALCULATE FINAL SECURITY SCORE
# ============================================================================

function Calculate-SecurityScore {
    Write-AuditLog "Calculating overall security score..." -Type "INFO"
    
    $totalScore = 0
    $totalMaxScore = 0
    
    foreach ($category in $script:AuditResults.SecurityScore.Categories.Keys) {
        $totalScore += $script:AuditResults.SecurityScore.Categories[$category].Score
        $totalMaxScore += $script:AuditResults.SecurityScore.Categories[$category].MaxScore
    }
    
    $overallScore = if ($totalMaxScore -gt 0) {
        [math]::Round(($totalScore / $totalMaxScore) * 100, 2)
    } else {
        0
    }
    
    $script:AuditResults.SecurityScore.Overall = $overallScore
    $script:AuditResults.SecurityScore.MaxScore = 100
    
    $scoreColor = switch ($overallScore) {
        {$_ -ge 80} { "GREEN" }
        {$_ -ge 60} { "YELLOW" }
        {$_ -ge 40} { "ORANGE" }
        default { "RED" }
    }
    
    Write-AuditLog "Overall Security Score: $overallScore/100 ($scoreColor)" -Type "SUCCESS"
}

# ============================================================================
# HTML REPORT GENERATION
# ============================================================================

function Generate-HTMLReport {
    Write-AuditLog "Generating HTML report..." -Type "INFO"
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $OutputPath "EntraID_SecurityAudit_$timestamp.html"
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Build HTML sections without nested here-strings
    
    # Conditional Access Table
    $caTable = ""
    if ($script:AuditResults.ConditionalAccess.Count -gt 0) {
        $caTable = '<table class="findings-table"><thead><tr><th>Policy Name</th><th>State</th><th>Grant Controls</th><th>Last Modified</th></tr></thead><tbody>'
        foreach ($policy in $script:AuditResults.ConditionalAccess) {
            $stateBadge = switch ($policy.State) {
                "enabled" { '<span class="severity-badge severity-low">Enabled</span>' }
                "disabled" { '<span class="severity-badge severity-critical">Disabled</span>' }
                "enabledForReportingButNotEnforced" { '<span class="severity-badge severity-medium">Report-Only</span>' }
                default { $policy.State }
            }
            $caTable += "<tr><td>$($policy.DisplayName)</td><td>$stateBadge</td><td>$($policy.GrantControls)</td><td>$($policy.ModifiedDateTime)</td></tr>"
        }
        $caTable += '</tbody></table>'
    } else {
        $caTable = '<p style="color: red; font-weight: bold;">❌ No Conditional Access policies configured</p>'
    }
    
    # Findings Table
    $findingsTable = ""
    $allFindings = @()
    foreach ($severity in @("Critical", "High", "Medium", "Low", "Info")) {
        $allFindings += $script:AuditResults.Findings[$severity]
    }
    
    if ($allFindings.Count -gt 0) {
        $findingsTable = '<table class="findings-table"><thead><tr><th>Severity</th><th>Category</th><th>Title</th><th>Description</th><th>Recommendation</th></tr></thead><tbody>'
        foreach ($finding in $allFindings) {
            $findingsTable += "<tr><td><span class='severity-badge severity-$($finding.Severity.ToLower())'>$($finding.Severity)</span></td><td>$($finding.Category)</td><td>$($finding.Title)</td><td>$($finding.Description)</td><td>$($finding.Recommendation)</td></tr>"
        }
        $findingsTable += '</tbody></table>'
    } else {
        $findingsTable = '<p style="color: green; font-weight: bold;">✅ No critical security findings</p>'
    }
    
    # Recommendations
    $recommendationsHtml = ""
    if ($script:AuditResults.Recommendations.Count -gt 0) {
        $recommendationsHtml = '<div class="recommendations"><h3>💡 Key Recommendations</h3><ul>'
        foreach ($rec in $script:AuditResults.Recommendations) {
            $recommendationsHtml += "<li>$rec</li>"
        }
        $recommendationsHtml += '</ul></div>'
    }
    
    # Subscriptions Table
    $subscriptionsHtml = ""
    if ($script:AuditResults.Subscriptions.Count -gt 0) {
        $subscriptionsHtml = '<div class="section"><h2>☁️ Azure Subscriptions</h2><table class="findings-table"><thead><tr><th>Subscription Name</th><th>State</th><th>Resource Groups</th><th>Total Resources</th></tr></thead><tbody>'
        foreach ($sub in $script:AuditResults.Subscriptions) {
            $subscriptionsHtml += "<tr><td>$($sub.Name)</td><td>$($sub.State)</td><td>$($sub.ResourceGroups)</td><td>$($sub.TotalResources)</td></tr>"
        }
        $subscriptionsHtml += '</tbody></table></div>'
    }
    
    # Score rating
    $scoreRating = switch ($script:AuditResults.SecurityScore.Overall) {
        {$_ -ge 80} { "✅ Excellent Security Posture" }
        {$_ -ge 60} { "⚠️ Good but Needs Improvement" }
        {$_ -ge 40} { "⚠️ Fair - Action Required" }
        default { "❌ Poor - Immediate Action Required" }
    }
    
    # Directory sync status
    $dirSyncStatus = if ($script:AuditResults.TenantInfo.DirectorySyncEnabled) {"✅ Enabled"} else {"❌ Disabled (Cloud-Only)"}
    
    # Build the complete HTML
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Entra ID Security Audit Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; color: #333; }
        .container { max-width: 1400px; margin: 0 auto; background: white; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); overflow: hidden; }
        .header { background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: white; padding: 40px; text-align: center; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.2); }
        .header .subtitle { font-size: 1.2em; opacity: 0.9; }
        .score-section { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); padding: 40px; text-align: center; color: white; }
        .score-circle { width: 200px; height: 200px; border-radius: 50%; background: white; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center; box-shadow: 0 10px 30px rgba(0,0,0,0.2); }
        .score-number { font-size: 4em; font-weight: bold; color: #1e3c72; }
        .score-label { font-size: 1.5em; margin-top: 10px; }
        .content { padding: 40px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #1e3c72; border-bottom: 3px solid #667eea; padding-bottom: 10px; margin-bottom: 20px; font-size: 1.8em; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 25px; border-radius: 15px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); transition: transform 0.3s ease; }
        .stat-card:hover { transform: translateY(-5px); }
        .stat-label { font-size: 0.9em; opacity: 0.9; margin-bottom: 5px; }
        .stat-value { font-size: 2.5em; font-weight: bold; }
        .findings-table { width: 100%; border-collapse: collapse; margin-top: 20px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
        .findings-table th { background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: white; padding: 15px; text-align: left; font-weight: 600; }
        .findings-table td { padding: 15px; border-bottom: 1px solid #e0e0e0; }
        .findings-table tr:hover { background-color: #f5f5f5; }
        .severity-badge { display: inline-block; padding: 5px 15px; border-radius: 20px; font-weight: bold; font-size: 0.85em; }
        .severity-critical { background: #e74c3c; color: white; }
        .severity-high { background: #e67e22; color: white; }
        .severity-medium { background: #f39c12; color: white; }
        .severity-low { background: #3498db; color: white; }
        .severity-info { background: #95a5a6; color: white; }
        .recommendations { background: #fff3cd; border-left: 5px solid #ffc107; padding: 20px; border-radius: 5px; margin-top: 20px; }
        .recommendations h3 { color: #856404; margin-bottom: 15px; }
        .recommendations ul { list-style: none; }
        .recommendations li { padding: 10px 0; border-bottom: 1px solid #ffe8a1; }
        .recommendations li:last-child { border-bottom: none; }
        .footer { background: #f8f9fa; padding: 30px; text-align: center; color: #6c757d; border-top: 1px solid #dee2e6; }
        .tenant-info { background: #e3f2fd; border-left: 5px solid #2196f3; padding: 20px; border-radius: 5px; margin-bottom: 30px; }
        .tenant-info h3 { color: #1976d2; margin-bottom: 10px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin-top: 15px; }
        .info-item { padding: 10px; background: white; border-radius: 5px; }
        .info-label { font-weight: bold; color: #1976d2; margin-bottom: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Microsoft Entra ID Security Audit</h1>
            <div class="subtitle">Complete Security Assessment & Compliance Report</div>
            <div class="subtitle">Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</div>
        </div>
        
        <div class="score-section">
            <div class="score-circle">
                <div class="score-number">$($script:AuditResults.SecurityScore.Overall)</div>
            </div>
            <div class="score-label">Overall Security Score</div>
            <div style="margin-top: 20px; font-size: 1.1em;">$scoreRating</div>
        </div>
        
        <div class="content">
            <div class="tenant-info">
                <h3>📋 Tenant Information</h3>
                <div class="info-grid">
                    <div class="info-item"><div class="info-label">Tenant Name</div><div>$($script:AuditResults.TenantInfo.DisplayName)</div></div>
                    <div class="info-item"><div class="info-label">Tenant ID</div><div>$($script:AuditResults.TenantInfo.TenantId)</div></div>
                    <div class="info-item"><div class="info-label">Primary Domain</div><div>$($script:AuditResults.TenantInfo.VerifiedDomains)</div></div>
                    <div class="info-item"><div class="info-label">Directory Sync</div><div>$dirSyncStatus</div></div>
                </div>
            </div>
            
            <div class="section">
                <h2>👥 User Account Statistics</h2>
                <div class="stats-grid">
                    <div class="stat-card"><div class="stat-label">Total Users</div><div class="stat-value">$($script:AuditResults.Statistics.Users.Total)</div></div>
                    <div class="stat-card"><div class="stat-label">Active Users</div><div class="stat-value">$($script:AuditResults.Statistics.Users.Enabled)</div></div>
                    <div class="stat-card"><div class="stat-label">Inactive (90 days)</div><div class="stat-value">$($script:AuditResults.Statistics.Users.Inactive90Days)</div></div>
                    <div class="stat-card"><div class="stat-label">Guest Users</div><div class="stat-value">$($script:AuditResults.Statistics.Users.Guest)</div></div>
                    <div class="stat-card"><div class="stat-label">Licensed Users</div><div class="stat-value">$($script:AuditResults.Statistics.Users.Licensed)</div></div>
                    <div class="stat-card"><div class="stat-label">Cloud-Only Users</div><div class="stat-value">$($script:AuditResults.Statistics.Users.CloudOnly)</div></div>
                </div>
            </div>
            
            <div class="section">
                <h2>🔐 Multi-Factor Authentication</h2>
                <div class="stats-grid">
                    <div class="stat-card"><div class="stat-label">MFA Enrollment Rate</div><div class="stat-value">$($script:AuditResults.MFA.MFAPercentage)%</div></div>
                    <div class="stat-card"><div class="stat-label">MFA Enabled</div><div class="stat-value">$($script:AuditResults.MFA.MFAEnabled)</div></div>
                    <div class="stat-card"><div class="stat-label">MFA Not Enabled</div><div class="stat-value">$($script:AuditResults.MFA.MFADisabled)</div></div>
                </div>
            </div>
            
            <div class="section">
                <h2>👥 Groups</h2>
                <div class="stats-grid">
                    <div class="stat-card"><div class="stat-label">Total Groups</div><div class="stat-value">$($script:AuditResults.Statistics.Groups.Total)</div></div>
                    <div class="stat-card"><div class="stat-label">Security Groups</div><div class="stat-value">$($script:AuditResults.Statistics.Groups.Security)</div></div>
                    <div class="stat-card"><div class="stat-label">Microsoft 365 Groups</div><div class="stat-value">$($script:AuditResults.Statistics.Groups.Microsoft365)</div></div>
                    <div class="stat-card"><div class="stat-label">Dynamic Groups</div><div class="stat-value">$($script:AuditResults.Statistics.Groups.Dynamic)</div></div>
                </div>
            </div>
            
            <div class="section">
                <h2>🛡️ Conditional Access Policies</h2>
                $caTable
            </div>
            
            <div class="section">
                <h2>⚠️ Security Findings</h2>
                $findingsTable
            </div>
            
            $recommendationsHtml
            $subscriptionsHtml
        </div>
        
        <div class="footer">
            <p><strong>Microsoft Entra ID Security Audit Report</strong></p>
            <p>Generated by: $env:USERNAME | $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
            <p>Audit Duration: $([math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 2)) minutes</p>
        </div>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-AuditLog "HTML report generated: $reportPath" -Type "SUCCESS"
    
    return $reportPath
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Start-EntraIDAudit {
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host " MICROSOFT ENTRA ID COMPLETE SECURITY AUDIT" -ForegroundColor Cyan
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Install-RequiredModules
    
    $connected = Connect-EntraServices
    if (-not $connected) {
        Write-AuditLog "Failed to connect to required services. Exiting." -Type "ERROR"
        return
    }
    
    Get-TenantInformation
    Get-UserAudit
    Get-GroupAudit
    Get-PrivilegedRolesAudit
    Get-MFAAudit
    Get-ConditionalAccessAudit
    Get-EnterpriseAppsAudit
    Get-LicenseAudit
    Get-AzureSubscriptionsAudit
    
    Generate-Recommendations
    Calculate-SecurityScore
    
    $reportPath = Generate-HTMLReport
    
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host " AUDIT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Overall Security Score: " -NoNewline
    Write-Host "$($script:AuditResults.SecurityScore.Overall)/100" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📁 Report Location: " -NoNewline
    Write-Host "$reportPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚠️  Critical Findings: " -NoNewline
    Write-Host "$($script:AuditResults.Findings.Critical.Count)" -ForegroundColor Red
    Write-Host "⚠️  High Findings: " -NoNewline
    Write-Host "$($script:AuditResults.Findings.High.Count)" -ForegroundColor Magenta
    Write-Host "⚠️  Medium Findings: " -NoNewline
    Write-Host "$($script:AuditResults.Findings.Medium.Count)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Opening report in browser..." -ForegroundColor Cyan
    Start-Process $reportPath
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host ""
}

# Execute the audit
Start-EntraIDAudit
