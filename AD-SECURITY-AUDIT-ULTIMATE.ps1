# ============================================================================
# ACTIVE DIRECTORY SECURITY AUDIT - ULTIMATE EDITION
# ============================================================================
# Purpose: Scan all 13 Azure subscriptions, find ALL Domain Controllers,
#          run comprehensive AD security audit, generate detailed HTML report
# Author: Syed Rizvi
# Date: February 13, 2026
# ============================================================================

$ErrorActionPreference = "Continue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$AuditResults = @{
    SecurityScore = 0
    TotalChecks = 0
    PassedChecks = 0
    Findings = @{
        Critical = @()
        High = @()
        Medium = @()
        Low = @()
        Info = @()
    }
    DomainControllers = @()
    Users = @{
        Total = 0
        Enabled = 0
        Disabled = 0
        Inactive = 0
        NeverExpire = 0
        Duplicates = @()
        Privileged = @()
        NoPasswordRequired = @()
    }
    Groups = @{
        Total = 0
        Empty = 0
        Privileged = @()
        Nested = @()
    }
    GPOs = @{
        Total = 0
        Linked = 0
        Unlinked = 0
        Empty = @()
    }
    Certificates = @{
        Total = 0
        Expired = @()
        Expiring = @()
        Weak = @()
    }
    Permissions = @()
    RecentChanges = @()
    Trusts = @()
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "CRITICAL" { "Magenta" }
        default { "Cyan" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Title,
        [string]$Description,
        [string]$Recommendation,
        [string]$Impact = "N/A"
    )
    
    $finding = @{
        Severity = $Severity
        Category = $Category
        Title = $Title
        Description = $Description
        Recommendation = $Recommendation
        Impact = $Impact
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $AuditResults.Findings[$Severity] += $finding
    $AuditResults.TotalChecks++
}

function Test-ADModule {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-AuditLog "Installing Active Directory module..." "WARNING"
        try {
            Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature
            Import-Module ActiveDirectory
        } catch {
            Write-AuditLog "Failed to install AD module. Install RSAT tools manually." "ERROR"
            return $false
        }
    }
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    return $true
}

# ============================================================================
# MAIN EXECUTION - 100% AUTOMATED
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ACTIVE DIRECTORY SECURITY AUDIT - ULTIMATE EDITION" -ForegroundColor Cyan
Write-Host "  Scanning ALL 13 Subscriptions - 100% Automated" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

# STEP 1: Check Azure login
Write-AuditLog "Step 1: Checking Azure authentication..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-AuditLog "Logging in to Azure..." "WARNING"
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-AuditLog "Logged in as: $($account.user.name)" "SUCCESS"
Write-Host ""

# STEP 2: Get all subscriptions
Write-AuditLog "Step 2: Finding all Azure subscriptions..."
$subscriptions = az account list --all 2>$null | ConvertFrom-Json

Write-AuditLog "Found $($subscriptions.Count) subscriptions" "SUCCESS"
foreach ($sub in $subscriptions) {
    Write-Host "  - $($sub.name) [$($sub.state)]" -ForegroundColor White
}
Write-Host ""

# STEP 3: Find all Domain Controllers across all subscriptions
Write-AuditLog "Step 3: Scanning for Domain Controllers across all subscriptions..."

$allDomainControllers = @()

foreach ($subscription in $subscriptions) {
    if ($subscription.state -ne "Enabled") {
        Write-AuditLog "Skipping disabled subscription: $($subscription.name)" "WARNING"
        continue
    }
    
    Write-AuditLog "Scanning subscription: $($subscription.name)" "INFO"
    az account set --subscription $subscription.id 2>$null | Out-Null
    
    # Get all VMs in subscription
    $vms = az vm list --subscription $subscription.id 2>$null | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        # Check if VM is a Domain Controller
        try {
            $vmDetails = az vm show --ids $vm.id --subscription $subscription.id 2>$null | ConvertFrom-Json
            
            # Check VM name patterns common for DCs
            $isDC = $false
            $dcPatterns = @("dc", "domaincontroller", "ad-", "adds-")
            
            foreach ($pattern in $dcPatterns) {
                if ($vm.name -like "*$pattern*") {
                    $isDC = $true
                    break
                }
            }
            
            # Also check tags
            if ($vm.tags.Role -eq "DomainController" -or $vm.tags.Type -eq "AD") {
                $isDC = $true
            }
            
            if ($isDC) {
                $dcInfo = @{
                    Name = $vm.name
                    ResourceGroup = $vm.resourceGroup
                    Subscription = $subscription.name
                    SubscriptionId = $subscription.id
                    Location = $vm.location
                    PowerState = $vm.powerState
                    PrivateIP = $null
                    PublicIP = $null
                }
                
                # Get IP addresses
                try {
                    $nics = az vm nic list --vm-name $vm.name --resource-group $vm.resourceGroup --subscription $subscription.id 2>$null | ConvertFrom-Json
                    if ($nics -and $nics.Count -gt 0) {
                        $nicId = $nics[0].id
                        $nicDetails = az network nic show --ids $nicId --subscription $subscription.id 2>$null | ConvertFrom-Json
                        if ($nicDetails.ipConfigurations -and $nicDetails.ipConfigurations.Count -gt 0) {
                            $dcInfo.PrivateIP = $nicDetails.ipConfigurations[0].privateIPAddress
                        }
                    }
                } catch {
                    Write-AuditLog "Could not get IP for $($vm.name)" "WARNING"
                }
                
                $allDomainControllers += $dcInfo
                Write-AuditLog "Found Domain Controller: $($vm.name) in $($subscription.name)" "SUCCESS"
            }
            
        } catch {
            Write-AuditLog "Error checking VM $($vm.name): $($_.Exception.Message)" "WARNING"
        }
    }
}

$AuditResults.DomainControllers = $allDomainControllers

Write-Host ""
Write-AuditLog "Total Domain Controllers found: $($allDomainControllers.Count)" "SUCCESS"
Write-Host ""

if ($allDomainControllers.Count -eq 0) {
    Write-AuditLog "No Domain Controllers found. Exiting." "ERROR"
    exit 1
}

# STEP 4: Check if AD module is available
Write-AuditLog "Step 4: Checking Active Directory PowerShell module..."
if (-not (Test-ADModule)) {
    Write-AuditLog "AD PowerShell module not available. Some checks will be skipped." "WARNING"
    $hasADModule = $false
} else {
    Write-AuditLog "AD PowerShell module loaded successfully" "SUCCESS"
    $hasADModule = $true
}
Write-Host ""

# STEP 5: Run comprehensive AD security audits
Write-AuditLog "Step 5: Running comprehensive Active Directory security audit..."
Write-Host ""

if ($hasADModule) {
    try {
        # Get AD Domain info
        Write-AuditLog "Gathering Active Directory information..." "INFO"
        $domain = Get-ADDomain
        $forest = Get-ADForest
        
        Write-AuditLog "Domain: $($domain.DNSRoot)" "SUCCESS"
        Write-AuditLog "Forest Functional Level: $($forest.ForestMode)" "INFO"
        Write-AuditLog "Domain Functional Level: $($domain.DomainMode)" "INFO"
        Write-Host ""
        
        # ====================================================================
        # USER AUDITS
        # ====================================================================
        
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        Write-AuditLog "AUDITING USERS" "INFO"
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        
        $allUsers = Get-ADUser -Filter * -Properties *
        $AuditResults.Users.Total = $allUsers.Count
        
        Write-AuditLog "Total users: $($allUsers.Count)" "INFO"
        
        # Enabled vs Disabled users
        $enabledUsers = $allUsers | Where-Object { $_.Enabled -eq $true }
        $disabledUsers = $allUsers | Where-Object { $_.Enabled -eq $false }
        
        $AuditResults.Users.Enabled = $enabledUsers.Count
        $AuditResults.Users.Disabled = $disabledUsers.Count
        
        Write-AuditLog "Enabled users: $($enabledUsers.Count)" "SUCCESS"
        Write-AuditLog "Disabled users: $($disabledUsers.Count)" "WARNING"
        
        # Inactive users (not logged in for 90 days)
        $inactiveDate = (Get-Date).AddDays(-90)
        $inactiveUsers = $enabledUsers | Where-Object { 
            $_.LastLogonDate -and $_.LastLogonDate -lt $inactiveDate 
        }
        
        $AuditResults.Users.Inactive = $inactiveUsers.Count
        
        if ($inactiveUsers.Count -gt 0) {
            Add-Finding -Severity "Medium" -Category "Users" `
                -Title "Inactive User Accounts Found" `
                -Description "$($inactiveUsers.Count) enabled user accounts have not logged in for 90+ days" `
                -Recommendation "Review and disable/remove inactive accounts: $($inactiveUsers.SamAccountName -join ', ')" `
                -Impact "Security Risk - Inactive accounts can be compromised"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # Users with passwords that never expire
        $neverExpireUsers = $enabledUsers | Where-Object { $_.PasswordNeverExpires -eq $true }
        $AuditResults.Users.NeverExpire = $neverExpireUsers.Count
        
        if ($neverExpireUsers.Count -gt 0) {
            Add-Finding -Severity "High" -Category "Users" `
                -Title "Users with Non-Expiring Passwords" `
                -Description "$($neverExpireUsers.Count) users have passwords set to never expire" `
                -Recommendation "Enforce password expiration policy for: $($neverExpireUsers.SamAccountName -join ', ')" `
                -Impact "Security Risk - Passwords should be rotated regularly"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # Users with no password required
        $noPasswordUsers = $enabledUsers | Where-Object { $_.PasswordNotRequired -eq $true }
        $AuditResults.Users.NoPasswordRequired = $noPasswordUsers
        
        if ($noPasswordUsers.Count -gt 0) {
            Add-Finding -Severity "Critical" -Category "Users" `
                -Title "Users with No Password Required" `
                -Description "$($noPasswordUsers.Count) users do not require a password" `
                -Recommendation "IMMEDIATELY require passwords for: $($noPasswordUsers.SamAccountName -join ', ')" `
                -Impact "CRITICAL - Accounts can be accessed without authentication"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # Duplicate users (same display name)
        $duplicateNames = $allUsers | Group-Object DisplayName | Where-Object { $_.Count -gt 1 }
        if ($duplicateNames) {
            $AuditResults.Users.Duplicates = $duplicateNames | ForEach-Object {
                @{
                    DisplayName = $_.Name
                    Count = $_.Count
                    Users = ($_.Group | ForEach-Object { $_.SamAccountName }) -join ', '
                }
            }
            
            Add-Finding -Severity "Low" -Category "Users" `
                -Title "Duplicate User Display Names Found" `
                -Description "$($duplicateNames.Count) display names are used by multiple accounts" `
                -Recommendation "Review and rename duplicate accounts to ensure uniqueness" `
                -Impact "Confusion - May cause identity confusion"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # ====================================================================
        # PRIVILEGED USER AUDITS
        # ====================================================================
        
        Write-AuditLog "Auditing privileged users..." "INFO"
        
        $privilegedGroups = @(
            "Domain Admins",
            "Enterprise Admins",
            "Schema Admins",
            "Administrators",
            "Account Operators",
            "Backup Operators",
            "Server Operators",
            "Print Operators"
        )
        
        foreach ($groupName in $privilegedGroups) {
            try {
                $group = Get-ADGroup -Filter "Name -eq '$groupName'" -Properties Members
                if ($group) {
                    $members = Get-ADGroupMember -Identity $group
                    if ($members.Count -gt 0) {
                        $AuditResults.Users.Privileged += @{
                            Group = $groupName
                            MemberCount = $members.Count
                            Members = ($members | ForEach-Object { $_.SamAccountName }) -join ', '
                        }
                        
                        if ($members.Count -gt 5) {
                            Add-Finding -Severity "Medium" -Category "Privileged Access" `
                                -Title "Excessive Privileged Group Membership" `
                                -Description "$groupName has $($members.Count) members (recommended: <= 5)" `
                                -Recommendation "Review and remove unnecessary members from $groupName" `
                                -Impact "Security Risk - Too many privileged accounts increase attack surface"
                        }
                    }
                }
            } catch {
                Write-AuditLog "Could not audit group: $groupName" "WARNING"
            }
        }
        
        # ====================================================================
        # GROUP AUDITS
        # ====================================================================
        
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        Write-AuditLog "AUDITING GROUPS" "INFO"
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        
        $allGroups = Get-ADGroup -Filter * -Properties *
        $AuditResults.Groups.Total = $allGroups.Count
        
        Write-AuditLog "Total groups: $($allGroups.Count)" "INFO"
        
        # Empty groups
        $emptyGroups = $allGroups | Where-Object {
            $members = Get-ADGroupMember -Identity $_ -ErrorAction SilentlyContinue
            $members.Count -eq 0
        }
        
        $AuditResults.Groups.Empty = $emptyGroups.Count
        
        if ($emptyGroups.Count -gt 0) {
            Add-Finding -Severity "Low" -Category "Groups" `
                -Title "Empty Groups Found" `
                -Description "$($emptyGroups.Count) groups have no members" `
                -Recommendation "Review and remove unused groups: $($emptyGroups.Name -join ', ')" `
                -Impact "Cleanup - Improves AD organization"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # ====================================================================
        # GPO AUDITS
        # ====================================================================
        
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        Write-AuditLog "AUDITING GROUP POLICY OBJECTS" "INFO"
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        
        try {
            $allGPOs = Get-GPO -All
            $AuditResults.GPOs.Total = $allGPOs.Count
            
            Write-AuditLog "Total GPOs: $($allGPOs.Count)" "INFO"
            
            # Unlinked GPOs
            $unlinkedGPOs = @()
            foreach ($gpo in $allGPOs) {
                $links = $gpo | Get-GPOReport -ReportType XML | Select-String "LinksTo"
                if (-not $links) {
                    $unlinkedGPOs += $gpo
                }
            }
            
            $AuditResults.GPOs.Unlinked = $unlinkedGPOs.Count
            $AuditResults.GPOs.Linked = $allGPOs.Count - $unlinkedGPOs.Count
            
            if ($unlinkedGPOs.Count -gt 0) {
                Add-Finding -Severity "Low" -Category "GPO" `
                    -Title "Unlinked GPOs Found" `
                    -Description "$($unlinkedGPOs.Count) GPOs are not linked to any OU" `
                    -Recommendation "Review and remove unlinked GPOs: $($unlinkedGPOs.DisplayName -join ', ')" `
                    -Impact "Cleanup - Unlinked GPOs serve no purpose"
            } else {
                $AuditResults.PassedChecks++
            }
            
        } catch {
            Write-AuditLog "Could not audit GPOs: $($_.Exception.Message)" "WARNING"
        }
        
        # ====================================================================
        # TRUST RELATIONSHIPS
        # ====================================================================
        
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        Write-AuditLog "AUDITING TRUST RELATIONSHIPS" "INFO"
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        
        try {
            $trusts = Get-ADTrust -Filter *
            
            if ($trusts) {
                foreach ($trust in $trusts) {
                    $AuditResults.Trusts += @{
                        Name = $trust.Name
                        Direction = $trust.Direction
                        TrustType = $trust.TrustType
                        ForestTransitive = $trust.ForestTransitive
                    }
                }
                
                Write-AuditLog "Found $($trusts.Count) trust relationship(s)" "INFO"
                
                # Check for external trusts
                $externalTrusts = $trusts | Where-Object { $_.TrustType -eq "External" }
                if ($externalTrusts) {
                    Add-Finding -Severity "Medium" -Category "Trusts" `
                        -Title "External Trust Relationships Detected" `
                        -Description "Found $($externalTrusts.Count) external trust(s)" `
                        -Recommendation "Review external trusts and ensure they are necessary and properly secured" `
                        -Impact "Security Risk - External trusts can be exploited"
                }
            } else {
                Write-AuditLog "No trust relationships found" "INFO"
                $AuditResults.PassedChecks++
            }
        } catch {
            Write-AuditLog "Could not audit trusts: $($_.Exception.Message)" "WARNING"
        }
        
        # ====================================================================
        # RECENT CHANGES (Last 30 days)
        # ====================================================================
        
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        Write-AuditLog "AUDITING RECENT CHANGES (Last 30 Days)" "INFO"
        Write-AuditLog "═══════════════════════════════════════════════════" "INFO"
        
        $since = (Get-Date).AddDays(-30)
        
        # Recently created users
        $recentUsers = $allUsers | Where-Object { $_.Created -gt $since }
        if ($recentUsers) {
            $AuditResults.RecentChanges += @{
                Type = "User Created"
                Count = $recentUsers.Count
                Items = ($recentUsers | ForEach-Object { "$($_.SamAccountName) ($($_.Created))" }) -join ', '
            }
            Write-AuditLog "Recently created users: $($recentUsers.Count)" "INFO"
        }
        
        # Recently modified users
        $recentModified = $allUsers | Where-Object { $_.Modified -gt $since }
        if ($recentModified) {
            $AuditResults.RecentChanges += @{
                Type = "User Modified"
                Count = $recentModified.Count
                Items = ($recentModified | Select-Object -First 10 | ForEach-Object { "$($_.SamAccountName) ($($_.Modified))" }) -join ', '
            }
            Write-AuditLog "Recently modified users: $($recentModified.Count)" "INFO"
        }
        
        # Recently created groups
        $recentGroups = $allGroups | Where-Object { $_.Created -gt $since }
        if ($recentGroups) {
            $AuditResults.RecentChanges += @{
                Type = "Group Created"
                Count = $recentGroups.Count
                Items = ($recentGroups | ForEach-Object { "$($_.Name) ($($_.Created))" }) -join ', '
            }
            Write-AuditLog "Recently created groups: $($recentGroups.Count)" "INFO"
        }
        
    } catch {
        Write-AuditLog "Error during AD audit: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-AuditLog "Skipping detailed AD audits - AD module not available" "WARNING"
}

# ====================================================================
# CALCULATE SECURITY SCORE
# ====================================================================

Write-Host ""
Write-AuditLog "Calculating security score..." "INFO"

$totalFindings = $AuditResults.Findings.Critical.Count + 
                 $AuditResults.Findings.High.Count + 
                 $AuditResults.Findings.Medium.Count + 
                 $AuditResults.Findings.Low.Count

if ($AuditResults.TotalChecks -gt 0) {
    $AuditResults.SecurityScore = [math]::Round((($AuditResults.PassedChecks / $AuditResults.TotalChecks) * 100), 2)
} else {
    $AuditResults.SecurityScore = 0
}

Write-AuditLog "Security Score: $($AuditResults.SecurityScore)%" $(if($AuditResults.SecurityScore -ge 80){"SUCCESS"}elseif($AuditResults.SecurityScore -ge 60){"WARNING"}else{"ERROR"})
Write-AuditLog "Total Checks: $($AuditResults.TotalChecks)" "INFO"
Write-AuditLog "Passed: $($AuditResults.PassedChecks)" "SUCCESS"
Write-AuditLog "Critical Findings: $($AuditResults.Findings.Critical.Count)" $(if($AuditResults.Findings.Critical.Count -gt 0){"CRITICAL"}else{"SUCCESS"})
Write-AuditLog "High Findings: $($AuditResults.Findings.High.Count)" $(if($AuditResults.Findings.High.Count -gt 0){"ERROR"}else{"SUCCESS"})
Write-AuditLog "Medium Findings: $($AuditResults.Findings.Medium.Count)" $(if($AuditResults.Findings.Medium.Count -gt 0){"WARNING"}else{"SUCCESS"})
Write-AuditLog "Low Findings: $($AuditResults.Findings.Low.Count)" "INFO"

Write-Host ""

# ============================================================================
# GENERATE HTML REPORT
# ============================================================================

Write-AuditLog "Generating comprehensive HTML report..." "INFO"

$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportFile = "AD-Security-Audit-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
$duration = (Get-Date) - $startTime

$scoreColor = if ($AuditResults.SecurityScore -ge 80) { "#27ae60" } 
              elseif ($AuditResults.SecurityScore -ge 60) { "#f39c12" } 
              else { "#e74c3c" }

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Active Directory Security Audit Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 4px solid #3498db;
            padding-bottom: 15px;
            margin-bottom: 20px;
        }
        h2 {
            color: #34495e;
            margin-top: 40px;
            border-bottom: 2px solid #95a5a6;
            padding-bottom: 10px;
        }
        h3 {
            color: #7f8c8d;
            margin-top: 25px;
        }
        .executive-summary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin: 30px 0;
        }
        .score-box {
            display: inline-block;
            background-color: $scoreColor;
            color: white;
            padding: 20px 40px;
            border-radius: 10px;
            font-size: 48px;
            font-weight: bold;
            margin: 20px 0;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .stat-box {
            background-color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            border-left: 4px solid #3498db;
        }
        .stat-number {
            font-size: 36px;
            font-weight: bold;
            color: #2c3e50;
        }
        .stat-label {
            color: #7f8c8d;
            margin-top: 10px;
        }
        .finding {
            background-color: white;
            border-left: 5px solid;
            padding: 20px;
            margin: 15px 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .finding-critical {
            border-left-color: #c0392b;
            background-color: #fadbd8;
        }
        .finding-high {
            border-left-color: #e74c3c;
            background-color: #f8d7da;
        }
        .finding-medium {
            border-left-color: #f39c12;
            background-color: #fff3cd;
        }
        .finding-low {
            border-left-color: #3498db;
            background-color: #d1ecf1;
        }
        .finding-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .finding-description {
            margin: 10px 0;
        }
        .finding-recommendation {
            background-color: rgba(255,255,255,0.7);
            padding: 10px;
            border-radius: 5px;
            margin-top: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        th {
            background-color: #34495e;
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #ecf0f1;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        .severity-badge {
            padding: 5px 15px;
            border-radius: 20px;
            color: white;
            font-weight: bold;
            display: inline-block;
        }
        .badge-critical { background-color: #c0392b; }
        .badge-high { background-color: #e74c3c; }
        .badge-medium { background-color: #f39c12; }
        .badge-low { background-color: #3498db; }
        .badge-success { background-color: #27ae60; }
        .badge-warning { background-color: #f39c12; }
        .badge-danger { background-color: #e74c3c; }
        .timestamp {
            color: #95a5a6;
            font-size: 0.9em;
            text-align: right;
            margin-bottom: 20px;
        }
        .dc-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .dc-card {
            background-color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #27ae60;
        }
        .dc-name {
            font-size: 18px;
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .dc-info {
            color: #7f8c8d;
            margin: 5px 0;
        }
        @media print {
            body {
                background-color: white;
            }
            .container {
                box-shadow: none;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ Active Directory Security Audit Report</h1>
        <div class="timestamp">Generated: $reportDate | Duration: $($duration.ToString('mm\:ss'))</div>
        
        <div class="executive-summary">
            <h2 style="color: white; border: none;">Executive Summary</h2>
            <div class="score-box">$($AuditResults.SecurityScore)%</div>
            <p style="font-size: 18px; margin-top: 20px;">Security Score</p>
            <p>This comprehensive audit scanned <strong>$($subscriptions.Count) Azure subscriptions</strong> and found <strong>$($allDomainControllers.Count) Domain Controller(s)</strong>.</p>
            <p>Total Checks Performed: <strong>$($AuditResults.TotalChecks)</strong> | Passed: <strong>$($AuditResults.PassedChecks)</strong></p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-box">
                <div class="stat-number" style="color: #c0392b;">$($AuditResults.Findings.Critical.Count)</div>
                <div class="stat-label">Critical Findings</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #e74c3c;">$($AuditResults.Findings.High.Count)</div>
                <div class="stat-label">High Findings</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #f39c12;">$($AuditResults.Findings.Medium.Count)</div>
                <div class="stat-label">Medium Findings</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #3498db;">$($AuditResults.Findings.Low.Count)</div>
                <div class="stat-label">Low Findings</div>
            </div>
        </div>
        
        <h2>🖥️ Domain Controllers</h2>
        <div class="dc-grid">
"@

foreach ($dc in $allDomainControllers) {
    $htmlReport += @"
            <div class="dc-card">
                <div class="dc-name">$($dc.Name)</div>
                <div class="dc-info"><strong>Subscription:</strong> $($dc.Subscription)</div>
                <div class="dc-info"><strong>Resource Group:</strong> $($dc.ResourceGroup)</div>
                <div class="dc-info"><strong>Location:</strong> $($dc.Location)</div>
                <div class="dc-info"><strong>Private IP:</strong> $($dc.PrivateIP)</div>
            </div>
"@
}

$htmlReport += @"
        </div>
        
        <h2>👥 User Statistics</h2>
        <table>
            <tr>
                <th>Metric</th>
                <th>Count</th>
                <th>Status</th>
            </tr>
            <tr>
                <td>Total Users</td>
                <td>$($AuditResults.Users.Total)</td>
                <td><span class="severity-badge badge-success">✓</span></td>
            </tr>
            <tr>
                <td>Enabled Users</td>
                <td>$($AuditResults.Users.Enabled)</td>
                <td><span class="severity-badge badge-success">✓</span></td>
            </tr>
            <tr>
                <td>Disabled Users</td>
                <td>$($AuditResults.Users.Disabled)</td>
                <td><span class="severity-badge badge-warning">⚠</span></td>
            </tr>
            <tr>
                <td>Inactive Users (90+ days)</td>
                <td>$($AuditResults.Users.Inactive)</td>
                <td><span class="severity-badge badge-$(if($AuditResults.Users.Inactive -gt 0){'warning'}else{'success'})">$(if($AuditResults.Users.Inactive -gt 0){'⚠'}else{'✓'})</span></td>
            </tr>
            <tr>
                <td>Password Never Expires</td>
                <td>$($AuditResults.Users.NeverExpire)</td>
                <td><span class="severity-badge badge-$(if($AuditResults.Users.NeverExpire -gt 0){'danger'}else{'success'})">$(if($AuditResults.Users.NeverExpire -gt 0){'✗'}else{'✓'})</span></td>
            </tr>
            <tr>
                <td>No Password Required</td>
                <td>$($AuditResults.Users.NoPasswordRequired.Count)</td>
                <td><span class="severity-badge badge-$(if($AuditResults.Users.NoPasswordRequired.Count -gt 0){'danger'}else{'success'})">$(if($AuditResults.Users.NoPasswordRequired.Count -gt 0){'✗'}else{'✓'})</span></td>
            </tr>
        </table>
        
        <h2>👤 Privileged Users</h2>
        <table>
            <tr>
                <th>Privileged Group</th>
                <th>Member Count</th>
                <th>Members</th>
            </tr>
"@

foreach ($privGroup in $AuditResults.Users.Privileged) {
    $htmlReport += @"
            <tr>
                <td><strong>$($privGroup.Group)</strong></td>
                <td>$($privGroup.MemberCount)</td>
                <td>$($privGroup.Members)</td>
            </tr>
"@
}

$htmlReport += @"
        </table>
        
        <h2>📁 Group Statistics</h2>
        <table>
            <tr>
                <th>Metric</th>
                <th>Count</th>
                <th>Status</th>
            </tr>
            <tr>
                <td>Total Groups</td>
                <td>$($AuditResults.Groups.Total)</td>
                <td><span class="severity-badge badge-success">✓</span></td>
            </tr>
            <tr>
                <td>Empty Groups</td>
                <td>$($AuditResults.Groups.Empty)</td>
                <td><span class="severity-badge badge-$(if($AuditResults.Groups.Empty -gt 0){'warning'}else{'success'})">$(if($AuditResults.Groups.Empty -gt 0){'⚠'}else{'✓'})</span></td>
            </tr>
        </table>
        
        <h2>📋 GPO Statistics</h2>
        <table>
            <tr>
                <th>Metric</th>
                <th>Count</th>
                <th>Status</th>
            </tr>
            <tr>
                <td>Total GPOs</td>
                <td>$($AuditResults.GPOs.Total)</td>
                <td><span class="severity-badge badge-success">✓</span></td>
            </tr>
            <tr>
                <td>Linked GPOs</td>
                <td>$($AuditResults.GPOs.Linked)</td>
                <td><span class="severity-badge badge-success">✓</span></td>
            </tr>
            <tr>
                <td>Unlinked GPOs</td>
                <td>$($AuditResults.GPOs.Unlinked)</td>
                <td><span class="severity-badge badge-$(if($AuditResults.GPOs.Unlinked -gt 0){'warning'}else{'success'})">$(if($AuditResults.GPOs.Unlinked -gt 0){'⚠'}else{'✓'})</span></td>
            </tr>
        </table>
        
        <h2>🔗 Trust Relationships</h2>
"@

if ($AuditResults.Trusts.Count -gt 0) {
    $htmlReport += @"
        <table>
            <tr>
                <th>Trust Name</th>
                <th>Direction</th>
                <th>Type</th>
                <th>Forest Transitive</th>
            </tr>
"@
    foreach ($trust in $AuditResults.Trusts) {
        $htmlReport += @"
            <tr>
                <td>$($trust.Name)</td>
                <td>$($trust.Direction)</td>
                <td>$($trust.TrustType)</td>
                <td>$($trust.ForestTransitive)</td>
            </tr>
"@
    }
    $htmlReport += "        </table>`n"
} else {
    $htmlReport += "        <p>No trust relationships found.</p>`n"
}

$htmlReport += @"
        
        <h2>📅 Recent Changes (Last 30 Days)</h2>
"@

if ($AuditResults.RecentChanges.Count -gt 0) {
    $htmlReport += @"
        <table>
            <tr>
                <th>Change Type</th>
                <th>Count</th>
                <th>Items</th>
            </tr>
"@
    foreach ($change in $AuditResults.RecentChanges) {
        $htmlReport += @"
            <tr>
                <td>$($change.Type)</td>
                <td>$($change.Count)</td>
                <td>$($change.Items)</td>
            </tr>
"@
    }
    $htmlReport += "        </table>`n"
} else {
    $htmlReport += "        <p>No recent changes detected.</p>`n"
}

$htmlReport += @"
        
        <h2>🚨 Security Findings</h2>
"@

# Critical Findings
if ($AuditResults.Findings.Critical.Count -gt 0) {
    $htmlReport += "        <h3>Critical Findings</h3>`n"
    foreach ($finding in $AuditResults.Findings.Critical) {
        $htmlReport += @"
        <div class="finding finding-critical">
            <div class="finding-title"><span class="severity-badge badge-critical">CRITICAL</span> $($finding.Title)</div>
            <div class="finding-description"><strong>Description:</strong> $($finding.Description)</div>
            <div class="finding-description"><strong>Impact:</strong> $($finding.Impact)</div>
            <div class="finding-recommendation"><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
    }
}

# High Findings
if ($AuditResults.Findings.High.Count -gt 0) {
    $htmlReport += "        <h3>High Priority Findings</h3>`n"
    foreach ($finding in $AuditResults.Findings.High) {
        $htmlReport += @"
        <div class="finding finding-high">
            <div class="finding-title"><span class="severity-badge badge-high">HIGH</span> $($finding.Title)</div>
            <div class="finding-description"><strong>Description:</strong> $($finding.Description)</div>
            <div class="finding-description"><strong>Impact:</strong> $($finding.Impact)</div>
            <div class="finding-recommendation"><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
    }
}

# Medium Findings
if ($AuditResults.Findings.Medium.Count -gt 0) {
    $htmlReport += "        <h3>Medium Priority Findings</h3>`n"
    foreach ($finding in $AuditResults.Findings.Medium) {
        $htmlReport += @"
        <div class="finding finding-medium">
            <div class="finding-title"><span class="severity-badge badge-medium">MEDIUM</span> $($finding.Title)</div>
            <div class="finding-description"><strong>Description:</strong> $($finding.Description)</div>
            <div class="finding-description"><strong>Impact:</strong> $($finding.Impact)</div>
            <div class="finding-recommendation"><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
    }
}

# Low Findings
if ($AuditResults.Findings.Low.Count -gt 0) {
    $htmlReport += "        <h3>Low Priority Findings</h3>`n"
    foreach ($finding in $AuditResults.Findings.Low) {
        $htmlReport += @"
        <div class="finding finding-low">
            <div class="finding-title"><span class="severity-badge badge-low">LOW</span> $($finding.Title)</div>
            <div class="finding-description"><strong>Description:</strong> $($finding.Description)</div>
            <div class="finding-description"><strong>Impact:</strong> $($finding.Impact)</div>
            <div class="finding-recommendation"><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
    }
}

if ($totalFindings -eq 0) {
    $htmlReport += "        <p style='color: green; font-size: 18px; font-weight: bold;'>✅ No security findings detected. Active Directory environment is in good health!</p>`n"
}

$htmlReport += @"
        
        <h2>✅ Recommendations</h2>
        <ol>
            <li><strong>Address Critical Findings Immediately:</strong> Critical findings pose immediate security risks and should be resolved within 24 hours.</li>
            <li><strong>Review High Priority Findings:</strong> High priority findings should be addressed within 1 week.</li>
            <li><strong>Plan Remediation for Medium/Low Findings:</strong> Schedule remediation activities for medium and low findings in the next maintenance window.</li>
            <li><strong>Regular Audits:</strong> Run this audit monthly to maintain security posture.</li>
            <li><strong>Enable Multi-Factor Authentication (MFA):</strong> Enforce MFA for all privileged accounts.</li>
            <li><strong>Review Privileged Access:</strong> Limit Domain Admins and Enterprise Admins to essential personnel only.</li>
            <li><strong>Monitor Inactive Accounts:</strong> Disable accounts that have been inactive for 90+ days.</li>
            <li><strong>Password Policy:</strong> Ensure strong password policies are enforced (complexity, length, rotation).</li>
            <li><strong>Audit Logs:</strong> Enable and monitor AD audit logs for suspicious activities.</li>
            <li><strong>Backup Domain Controllers:</strong> Ensure regular backups of all domain controllers.</li>
        </ol>
        
        <div style="background-color: #ecf0f1; padding: 20px; border-radius: 8px; margin-top: 40px;">
            <h3>📊 Audit Summary</h3>
            <p><strong>Total Subscriptions Scanned:</strong> $($subscriptions.Count)</p>
            <p><strong>Domain Controllers Found:</strong> $($allDomainControllers.Count)</p>
            <p><strong>Security Score:</strong> <span style="color: $scoreColor; font-weight: bold; font-size: 24px;">$($AuditResults.SecurityScore)%</span></p>
            <p><strong>Total Checks Performed:</strong> $($AuditResults.TotalChecks)</p>
            <p><strong>Checks Passed:</strong> $($AuditResults.PassedChecks)</p>
            <p><strong>Audit Duration:</strong> $($duration.ToString('mm\:ss'))</p>
            <p><strong>Generated:</strong> $reportDate</p>
        </div>
    </div>
</body>
</html>
"@

# Save HTML report
$reportPath = Join-Path (Get-Location) $reportFile
$htmlReport | Out-File -FilePath $reportPath -Encoding UTF8

$endTime = Get-Date
$totalDuration = $endTime - $startTime

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Security Score: $($AuditResults.SecurityScore)%" -ForegroundColor $(if($AuditResults.SecurityScore -ge 80){"Green"}elseif($AuditResults.SecurityScore -ge 60){"Yellow"}else{"Red"})
Write-Host "  Total Duration: $($totalDuration.ToString('mm\:ss'))" -ForegroundColor White
Write-Host "  Report File: $reportFile" -ForegroundColor White
Write-Host "  Location: $reportPath" -ForegroundColor White
Write-Host ""
Write-Host "  Opening report in browser..." -ForegroundColor Cyan

# Open the report
Start-Process $reportPath

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ALL DONE! 100% AUTOMATED AD SECURITY AUDIT COMPLETE!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
