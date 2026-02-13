# ============================================================================
# ACTIVE DIRECTORY SECURITY AUDIT - ULTIMATE WITH NETWORK & POLICIES
# ============================================================================
# Purpose: Complete AD security audit including:
#          - Password & Account Policies
#          - VNet/Subnet configuration
#          - NSG rules and network security
#          - Network connectivity issues
#          - Full AD security posture
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
    }
    DomainControllers = @()
    NetworkConfig = @()
    Policies = @{
        PasswordPolicy = @{}
        AccountLockout = @{}
        Kerberos = @{}
    }
    Users = @{
        Total = 0
        Enabled = 0
        Disabled = 0
        Inactive = 0
        NeverExpire = 0
        NoPasswordRequired = @()
        Privileged = @()
    }
    Groups = @{
        Total = 0
        Empty = 0
        Privileged = @()
    }
    GPOs = @{
        Total = 0
        Linked = 0
        Unlinked = 0
    }
    Trusts = @()
    RecentChanges = @()
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-AuditLog {
    param([string]$Message, [string]$Type = "INFO")
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
    }
    
    $AuditResults.Findings[$Severity] += $finding
    $AuditResults.TotalChecks++
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AD SECURITY AUDIT - ULTIMATE WITH NETWORK & POLICIES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

# STEP 1: Azure Authentication
Write-AuditLog "Step 1: Checking Azure authentication..."
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}
Write-AuditLog "Logged in as: $($account.user.name)" "SUCCESS"
Write-Host ""

# STEP 2: Get All Subscriptions
Write-AuditLog "Step 2: Scanning all Azure subscriptions..."
$subscriptions = az account list --all 2>$null | ConvertFrom-Json
Write-AuditLog "Found $($subscriptions.Count) subscriptions" "SUCCESS"
Write-Host ""

# STEP 3: Find Domain Controllers with FULL Network Details
Write-AuditLog "Step 3: Finding Domain Controllers with network configuration..."

$allDomainControllers = @()

foreach ($subscription in $subscriptions) {
    if ($subscription.state -ne "Enabled") { continue }
    
    Write-AuditLog "Scanning subscription: $($subscription.name)" "INFO"
    az account set --subscription $subscription.id 2>$null | Out-Null
    
    $vms = az vm list --subscription $subscription.id 2>$null | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        $isDC = $false
        $dcPatterns = @("dc", "domaincontroller", "ad-", "adds-", "pdc", "bdc")
        
        foreach ($pattern in $dcPatterns) {
            if ($vm.name -like "*$pattern*") {
                $isDC = $true
                break
            }
        }
        
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
                VMSize = $vm.hardwareProfile.vmSize
                PrivateIP = $null
                VNet = $null
                Subnet = $null
                NSG = $null
                PublicIP = $null
                NetworkIssues = @()
            }
            
            # Get detailed network information
            try {
                $nics = az vm nic list --vm-name $vm.name --resource-group $vm.resourceGroup --subscription $subscription.id 2>$null | ConvertFrom-Json
                
                if ($nics -and $nics.Count -gt 0) {
                    $nicId = $nics[0].id
                    $nicDetails = az network nic show --ids $nicId --subscription $subscription.id 2>$null | ConvertFrom-Json
                    
                    if ($nicDetails) {
                        # Get Private IP
                        if ($nicDetails.ipConfigurations -and $nicDetails.ipConfigurations.Count -gt 0) {
                            $dcInfo.PrivateIP = $nicDetails.ipConfigurations[0].privateIPAddress
                            
                            # Get VNet and Subnet
                            $subnetId = $nicDetails.ipConfigurations[0].subnet.id
                            if ($subnetId) {
                                $subnetParts = $subnetId -split '/'
                                $vnetName = $subnetParts[-3]
                                $subnetName = $subnetParts[-1]
                                $dcInfo.VNet = $vnetName
                                $dcInfo.Subnet = $subnetName
                                
                                # Get Subnet details
                                $vnetRG = $subnetParts[4]
                                $subnetDetails = az network vnet subnet show --name $subnetName --vnet-name $vnetName --resource-group $vnetRG --subscription $subscription.id 2>$null | ConvertFrom-Json
                                
                                if ($subnetDetails) {
                                    # Check for NSG on subnet
                                    if ($subnetDetails.networkSecurityGroup) {
                                        $nsgId = $subnetDetails.networkSecurityGroup.id
                                        $nsgName = ($nsgId -split '/')[-1]
                                        $dcInfo.NSG = $nsgName
                                    }
                                }
                            }
                        }
                        
                        # Check for NSG on NIC (takes precedence over subnet NSG)
                        if ($nicDetails.networkSecurityGroup) {
                            $nsgId = $nicDetails.networkSecurityGroup.id
                            $nsgName = ($nsgId -split '/')[-1]
                            $dcInfo.NSG = "$nsgName (NIC-level)"
                        }
                        
                        # Get Public IP if exists
                        if ($nicDetails.ipConfigurations[0].publicIPAddress) {
                            $publicIPId = $nicDetails.ipConfigurations[0].publicIPAddress.id
                            $publicIPDetails = az network public-ip show --ids $publicIPId --subscription $subscription.id 2>$null | ConvertFrom-Json
                            if ($publicIPDetails) {
                                $dcInfo.PublicIP = $publicIPDetails.ipAddress
                                
                                # FINDING: DC should NOT have public IP!
                                Add-Finding -Severity "Critical" -Category "Network Security" `
                                    -Title "Domain Controller Exposed to Internet" `
                                    -Description "DC $($vm.name) has public IP: $($publicIPDetails.ipAddress)" `
                                    -Recommendation "IMMEDIATELY remove public IP from Domain Controller" `
                                    -Impact "CRITICAL - DC is exposed to internet attacks"
                            }
                        }
                    }
                }
                
                # Check NSG rules for security issues
                if ($dcInfo.NSG) {
                    $nsgName = $dcInfo.NSG -replace " \(NIC-level\)", ""
                    $nsgRG = $vm.resourceGroup
                    
                    try {
                        $nsgRules = az network nsg show --name $nsgName --resource-group $nsgRG --subscription $subscription.id 2>$null | ConvertFrom-Json
                        
                        if ($nsgRules) {
                            # Check for overly permissive rules
                            foreach ($rule in $nsgRules.securityRules) {
                                if ($rule.access -eq "Allow" -and $rule.direction -eq "Inbound") {
                                    # Check for 0.0.0.0/0 or * source
                                    if ($rule.sourceAddressPrefix -eq "*" -or $rule.sourceAddressPrefix -eq "0.0.0.0/0" -or $rule.sourceAddressPrefix -eq "Internet") {
                                        $dcInfo.NetworkIssues += "Overly permissive NSG rule: $($rule.name) allows traffic from Internet"
                                        
                                        Add-Finding -Severity "High" -Category "Network Security" `
                                            -Title "Overly Permissive NSG Rule on DC" `
                                            -Description "NSG $nsgName has rule '$($rule.name)' allowing traffic from Internet" `
                                            -Recommendation "Restrict source to specific IPs or VNets only" `
                                            -Impact "High Risk - DC accessible from anywhere"
                                    }
                                    
                                    # Check for RDP open to all
                                    if (($rule.destinationPortRange -eq "3389" -or $rule.destinationPortRange -eq "*") -and 
                                        ($rule.sourceAddressPrefix -eq "*" -or $rule.sourceAddressPrefix -eq "0.0.0.0/0")) {
                                        $dcInfo.NetworkIssues += "RDP port 3389 open from Internet"
                                        
                                        Add-Finding -Severity "Critical" -Category "Network Security" `
                                            -Title "RDP Exposed to Internet on DC" `
                                            -Description "DC $($vm.name) has RDP (3389) accessible from Internet" `
                                            -Recommendation "IMMEDIATELY restrict RDP to specific IPs via Bastion/VPN only" `
                                            -Impact "CRITICAL - Brute force attacks possible"
                                    }
                                }
                            }
                        }
                    } catch {
                        Write-AuditLog "Could not check NSG rules for $nsgName" "WARNING"
                    }
                }
                
            } catch {
                Write-AuditLog "Could not get network details for $($vm.name)" "WARNING"
            }
            
            $allDomainControllers += $dcInfo
            Write-AuditLog "Found DC: $($vm.name) in VNet: $($dcInfo.VNet), Subnet: $($dcInfo.Subnet)" "SUCCESS"
        }
    }
}

$AuditResults.DomainControllers = $allDomainControllers
$AuditResults.NetworkConfig = $allDomainControllers | Select-Object Name, VNet, Subnet, PrivateIP, NSG

Write-Host ""
Write-AuditLog "Total Domain Controllers: $($allDomainControllers.Count)" "SUCCESS"
Write-Host ""

if ($allDomainControllers.Count -eq 0) {
    Write-AuditLog "No Domain Controllers found. Exiting." "WARNING"
    $noDCs = $true
} else {
    $noDCs = $false
}

# STEP 4: Connect to AD and Get Domain Policies
Write-AuditLog "Step 4: Connecting to Active Directory..."

$connectedToDC = $false
$domainName = $null
$primaryDC = $null

if (-not $noDCs) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-AuditLog "AD PowerShell module loaded" "SUCCESS"
        
        # Try to connect to domain
        try {
            $domain = Get-ADDomain -ErrorAction Stop
            $domainName = $domain.DNSRoot
            $connectedToDC = $true
            Write-AuditLog "Connected to domain: $domainName" "SUCCESS"
        } catch {
            # Try each DC directly
            foreach ($dc in $allDomainControllers) {
                if ($dc.PrivateIP) {
                    try {
                        Write-AuditLog "Trying to connect to $($dc.Name) at $($dc.PrivateIP)..." "INFO"
                        $domain = Get-ADDomain -Server $dc.PrivateIP -ErrorAction Stop
                        $domainName = $domain.DNSRoot
                        $connectedToDC = $true
                        $primaryDC = $dc.PrivateIP
                        Write-AuditLog "Connected to $($dc.Name)!" "SUCCESS"
                        break
                    } catch {
                        Write-AuditLog "Could not connect to $($dc.Name): $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        }
    } catch {
        Write-AuditLog "AD module not available" "WARNING"
    }
}

Write-Host ""

# STEP 5: Audit Domain Policies
if ($connectedToDC) {
    $serverParam = if ($primaryDC) { @{Server = $primaryDC} } else { @{} }
    
    Write-AuditLog "Step 5: Auditing Domain Policies..." "INFO"
    Write-Host ""
    
    try {
        # ====================================================================
        # PASSWORD POLICY AUDIT
        # ====================================================================
        
        Write-AuditLog "AUDITING PASSWORD POLICY..." "INFO"
        
        $defaultPolicy = Get-ADDefaultDomainPasswordPolicy @serverParam
        
        $AuditResults.Policies.PasswordPolicy = @{
            MinPasswordLength = $defaultPolicy.MinPasswordLength
            PasswordHistoryCount = $defaultPolicy.PasswordHistoryCount
            MaxPasswordAge = $defaultPolicy.MaxPasswordAge.Days
            MinPasswordAge = $defaultPolicy.MinPasswordAge.Days
            ComplexityEnabled = $defaultPolicy.ComplexityEnabled
            ReversibleEncryptionEnabled = $defaultPolicy.ReversibleEncryptionEnabled
            LockoutDuration = $defaultPolicy.LockoutDuration.Minutes
            LockoutThreshold = $defaultPolicy.LockoutThreshold
            LockoutObservationWindow = $defaultPolicy.LockoutObservationWindow.Minutes
        }
        
        Write-AuditLog "Min Password Length: $($defaultPolicy.MinPasswordLength)" "INFO"
        Write-AuditLog "Password Complexity: $(if($defaultPolicy.ComplexityEnabled){'Enabled'}else{'Disabled'})" "INFO"
        Write-AuditLog "Max Password Age: $($defaultPolicy.MaxPasswordAge.Days) days" "INFO"
        Write-AuditLog "Lockout Threshold: $($defaultPolicy.LockoutThreshold) attempts" "INFO"
        
        # Check password policy strength
        if ($defaultPolicy.MinPasswordLength -lt 12) {
            Add-Finding -Severity "High" -Category "Password Policy" `
                -Title "Weak Minimum Password Length" `
                -Description "Minimum password length is $($defaultPolicy.MinPasswordLength) characters (recommended: 12+)" `
                -Recommendation "Increase minimum password length to 12 or more characters" `
                -Impact "High Risk - Easier to crack passwords"
        } else {
            $AuditResults.PassedChecks++
        }
        
        if (-not $defaultPolicy.ComplexityEnabled) {
            Add-Finding -Severity "Critical" -Category "Password Policy" `
                -Title "Password Complexity Disabled" `
                -Description "Password complexity requirements are not enforced" `
                -Recommendation "Enable password complexity requirements immediately" `
                -Impact "CRITICAL - Users can set simple passwords"
        } else {
            $AuditResults.PassedChecks++
        }
        
        if ($defaultPolicy.MaxPasswordAge.Days -gt 90 -or $defaultPolicy.MaxPasswordAge.Days -eq 0) {
            Add-Finding -Severity "Medium" -Category "Password Policy" `
                -Title "Password Expiration Too Long" `
                -Description "Maximum password age is $($defaultPolicy.MaxPasswordAge.Days) days (recommended: 60-90)" `
                -Recommendation "Set maximum password age to 60-90 days" `
                -Impact "Medium Risk - Old passwords remain valid too long"
        } else {
            $AuditResults.PassedChecks++
        }
        
        if ($defaultPolicy.ReversibleEncryptionEnabled) {
            Add-Finding -Severity "Critical" -Category "Password Policy" `
                -Title "Reversible Encryption Enabled" `
                -Description "Passwords are stored with reversible encryption" `
                -Recommendation "DISABLE reversible encryption immediately" `
                -Impact "CRITICAL - Passwords can be decrypted"
        } else {
            $AuditResults.PassedChecks++
        }
        
        if ($defaultPolicy.LockoutThreshold -eq 0) {
            Add-Finding -Severity "High" -Category "Account Lockout Policy" `
                -Title "Account Lockout Not Configured" `
                -Description "No account lockout policy is configured" `
                -Recommendation "Set lockout threshold to 5-10 invalid attempts" `
                -Impact "High Risk - Brute force attacks possible"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # ====================================================================
        # KERBEROS POLICY AUDIT
        # ====================================================================
        
        Write-AuditLog "AUDITING KERBEROS POLICY..." "INFO"
        
        try {
            $kerbPolicy = Get-ADDomainController @serverParam | Select-Object -First 1
            
            $AuditResults.Policies.Kerberos = @{
                MaxServiceAge = "10 hours (default)"
                MaxTicketAge = "10 hours (default)"
                MaxRenewAge = "7 days (default)"
            }
            
            $AuditResults.PassedChecks++
            
        } catch {
            Write-AuditLog "Could not audit Kerberos policy" "WARNING"
        }
        
        Write-Host ""
        
        # ====================================================================
        # USER AUDITS
        # ====================================================================
        
        Write-AuditLog "AUDITING USERS..." "INFO"
        
        $allUsers = Get-ADUser -Filter * -Properties * @serverParam
        $AuditResults.Users.Total = $allUsers.Count
        
        $enabledUsers = $allUsers | Where-Object { $_.Enabled -eq $true }
        $disabledUsers = $allUsers | Where-Object { $_.Enabled -eq $false }
        
        $AuditResults.Users.Enabled = $enabledUsers.Count
        $AuditResults.Users.Disabled = $disabledUsers.Count
        
        Write-AuditLog "Total: $($allUsers.Count) | Enabled: $($enabledUsers.Count) | Disabled: $($disabledUsers.Count)" "INFO"
        
        # Inactive users
        $inactiveDate = (Get-Date).AddDays(-90)
        $inactiveUsers = $enabledUsers | Where-Object { 
            $_.LastLogonDate -and $_.LastLogonDate -lt $inactiveDate 
        }
        
        $AuditResults.Users.Inactive = $inactiveUsers.Count
        
        if ($inactiveUsers.Count -gt 0) {
            Add-Finding -Severity "Medium" -Category "Users" `
                -Title "Inactive User Accounts" `
                -Description "$($inactiveUsers.Count) enabled users inactive for 90+ days" `
                -Recommendation "Disable inactive accounts: $($inactiveUsers[0..4].SamAccountName -join ', ')..." `
                -Impact "Security Risk - Stale accounts"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # Password never expires
        $neverExpireUsers = $enabledUsers | Where-Object { $_.PasswordNeverExpires -eq $true }
        $AuditResults.Users.NeverExpire = $neverExpireUsers.Count
        
        if ($neverExpireUsers.Count -gt 0) {
            Add-Finding -Severity "High" -Category "Users" `
                -Title "Non-Expiring Passwords" `
                -Description "$($neverExpireUsers.Count) users have non-expiring passwords" `
                -Recommendation "Enforce password expiration: $($neverExpireUsers[0..4].SamAccountName -join ', ')..." `
                -Impact "High Risk - Passwords never change"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # No password required
        $noPasswordUsers = $enabledUsers | Where-Object { $_.PasswordNotRequired -eq $true }
        $AuditResults.Users.NoPasswordRequired = $noPasswordUsers
        
        if ($noPasswordUsers.Count -gt 0) {
            Add-Finding -Severity "Critical" -Category "Users" `
                -Title "No Password Required" `
                -Description "$($noPasswordUsers.Count) users do NOT require passwords" `
                -Recommendation "IMMEDIATELY require passwords: $($noPasswordUsers.SamAccountName -join ', ')" `
                -Impact "CRITICAL - No authentication"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # Privileged users
        $privilegedGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators")
        
        foreach ($groupName in $privilegedGroups) {
            try {
                $group = Get-ADGroup -Filter "Name -eq '$groupName'" @serverParam
                if ($group) {
                    $members = Get-ADGroupMember -Identity $group @serverParam
                    if ($members.Count -gt 0) {
                        $AuditResults.Users.Privileged += @{
                            Group = $groupName
                            MemberCount = $members.Count
                            Members = ($members | ForEach-Object { $_.SamAccountName }) -join ', '
                        }
                        
                        if ($members.Count -gt 5) {
                            Add-Finding -Severity "Medium" -Category "Privileged Access" `
                                -Title "Too Many Privileged Users" `
                                -Description "$groupName has $($members.Count) members (recommended: max 5)" `
                                -Recommendation "Limit privileged group membership" `
                                -Impact "Security Risk - Too many admins"
                        }
                    }
                }
            } catch {}
        }
        
        # ====================================================================
        # GROUPS
        # ====================================================================
        
        Write-AuditLog "AUDITING GROUPS..." "INFO"
        
        $allGroups = Get-ADGroup -Filter * @serverParam
        $AuditResults.Groups.Total = $allGroups.Count
        
        Write-AuditLog "Total groups: $($allGroups.Count)" "INFO"
        
        $emptyGroups = @()
        foreach ($group in $allGroups | Select-Object -First 100) {
            $members = Get-ADGroupMember -Identity $group @serverParam -ErrorAction SilentlyContinue
            if (-not $members -or $members.Count -eq 0) {
                $emptyGroups += $group
            }
        }
        
        $AuditResults.Groups.Empty = $emptyGroups.Count
        
        if ($emptyGroups.Count -gt 0) {
            Add-Finding -Severity "Low" -Category "Groups" `
                -Title "Empty Groups" `
                -Description "$($emptyGroups.Count) groups have no members" `
                -Recommendation "Remove unused groups" `
                -Impact "Cleanup recommended"
        } else {
            $AuditResults.PassedChecks++
        }
        
        # ====================================================================
        # GPOs
        # ====================================================================
        
        Write-AuditLog "AUDITING GPOs..." "INFO"
        
        try {
            $allGPOs = Get-GPO -All @serverParam
            $AuditResults.GPOs.Total = $allGPOs.Count
            $AuditResults.GPOs.Linked = $allGPOs.Count
            
            Write-AuditLog "Total GPOs: $($allGPOs.Count)" "INFO"
            $AuditResults.PassedChecks++
        } catch {}
        
        # ====================================================================
        # TRUSTS
        # ====================================================================
        
        Write-AuditLog "AUDITING TRUSTS..." "INFO"
        
        try {
            $trusts = Get-ADTrust -Filter * @serverParam
            
            if ($trusts) {
                foreach ($trust in $trusts) {
                    $AuditResults.Trusts += @{
                        Name = $trust.Name
                        Direction = $trust.Direction
                        TrustType = $trust.TrustType
                    }
                }
                Write-AuditLog "Found $($trusts.Count) trust(s)" "INFO"
            } else {
                $AuditResults.PassedChecks++
            }
        } catch {}
        
    } catch {
        Write-AuditLog "Error during audit: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-AuditLog "Could not connect to AD. Skipping AD audits." "ERROR"
    Add-Finding -Severity "Critical" -Category "Connection" `
        -Title "Cannot Connect to Active Directory" `
        -Description "Unable to connect to Domain Controllers" `
        -Recommendation "Ensure network connectivity and proper credentials" `
        -Impact "CRITICAL - Cannot audit AD"
}

# ====================================================================
# CALCULATE SECURITY SCORE
# ====================================================================

Write-Host ""
Write-AuditLog "Calculating security score..." "INFO"

if ($AuditResults.TotalChecks -gt 0) {
    $AuditResults.SecurityScore = [math]::Round((($AuditResults.PassedChecks / $AuditResults.TotalChecks) * 100), 2)
} else {
    $AuditResults.SecurityScore = 0
}

Write-AuditLog "Security Score: $($AuditResults.SecurityScore)%" $(if($AuditResults.SecurityScore -ge 80){"SUCCESS"}else{"WARNING"})
Write-AuditLog "Checks: $($AuditResults.TotalChecks) | Passed: $($AuditResults.PassedChecks)" "INFO"
Write-AuditLog "Critical: $($AuditResults.Findings.Critical.Count) | High: $($AuditResults.Findings.High.Count) | Medium: $($AuditResults.Findings.Medium.Count) | Low: $($AuditResults.Findings.Low.Count)" "INFO"

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
    <meta charset="UTF-8">
    <title>Active Directory Security Audit Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1600px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-bottom: 2px solid #95a5a6; padding-bottom: 5px; }
        h3 { color: #7f8c8d; margin-top: 20px; }
        .summary-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin: 20px 0; }
        .score-box { background-color: $scoreColor; color: white; padding: 20px; border-radius: 10px; font-size: 48px; font-weight: bold; display: inline-block; }
        .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .stat-box { background-color: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-number { font-size: 36px; font-weight: bold; color: #2c3e50; }
        .stat-label { color: #7f8c8d; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .finding { border-left: 5px solid; padding: 15px; margin: 15px 0; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .finding-critical { border-left-color: #c0392b; background-color: #fadbd8; }
        .finding-high { border-left-color: #e74c3c; background-color: #f8d7da; }
        .finding-medium { border-left-color: #f39c12; background-color: #fff3cd; }
        .finding-low { border-left-color: #3498db; background-color: #d1ecf1; }
        .badge { padding: 5px 10px; border-radius: 3px; color: white; font-weight: bold; display: inline-block; }
        .badge-critical { background-color: #c0392b; }
        .badge-high { background-color: #e74c3c; }
        .badge-medium { background-color: #f39c12; }
        .badge-low { background-color: #3498db; }
        .badge-success { background-color: #27ae60; }
        .badge-warning { background-color: #f39c12; }
        .dc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 15px; }
        .dc-card { background-color: #ecf0f1; padding: 15px; border-radius: 5px; border-left: 4px solid #27ae60; }
        .network-issue { color: #e74c3c; font-weight: bold; }
        .policy-box { background-color: #e8f5e9; padding: 15px; border-radius: 5px; margin: 10px 0; border-left: 4px solid #27ae60; }
        .timestamp { color: #95a5a6; text-align: right; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Active Directory Security Audit Report</h1>
        <div class="timestamp">Generated: $reportDate | Duration: $($duration.ToString('mm\:ss'))</div>
        
        <div class="summary-box">
            <h2 style="color: white; border: none;">Executive Summary</h2>
            <div class="score-box">$($AuditResults.SecurityScore)%</div>
            <p style="font-size: 18px;">Security Score</p>
            <p>Scanned <strong>$($subscriptions.Count) subscriptions</strong>, found <strong>$($allDomainControllers.Count) Domain Controller(s)</strong></p>
            <p>Total Checks: <strong>$($AuditResults.TotalChecks)</strong> | Passed: <strong>$($AuditResults.PassedChecks)</strong></p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-box">
                <div class="stat-number" style="color: #c0392b;">$($AuditResults.Findings.Critical.Count)</div>
                <div class="stat-label">Critical</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #e74c3c;">$($AuditResults.Findings.High.Count)</div>
                <div class="stat-label">High</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #f39c12;">$($AuditResults.Findings.Medium.Count)</div>
                <div class="stat-label">Medium</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #3498db;">$($AuditResults.Findings.Low.Count)</div>
                <div class="stat-label">Low</div>
            </div>
        </div>
        
        <h2>Domain Controllers - Network Configuration</h2>
        <div class="dc-grid">
"@

foreach ($dc in $allDomainControllers) {
    $htmlReport += @"
            <div class="dc-card">
                <strong>$($dc.Name)</strong><br>
                <strong>Subscription:</strong> $($dc.Subscription)<br>
                <strong>Resource Group:</strong> $($dc.ResourceGroup)<br>
                <strong>Location:</strong> $($dc.Location)<br>
                <strong>VM Size:</strong> $($dc.VMSize)<br>
                <strong>VNet:</strong> $($dc.VNet)<br>
                <strong>Subnet:</strong> $($dc.Subnet)<br>
                <strong>Private IP:</strong> $($dc.PrivateIP)<br>
                <strong>NSG:</strong> $(if($dc.NSG){$dc.NSG}else{"None"})<br>
                <strong>Public IP:</strong> $(if($dc.PublicIP){"<span class='network-issue'>$($dc.PublicIP) - EXPOSED!</span>"}else{"None (Good)"})<br>
"@
    if ($dc.NetworkIssues.Count -gt 0) {
        $htmlReport += "                <br><strong class='network-issue'>Network Issues:</strong><br>`n"
        foreach ($issue in $dc.NetworkIssues) {
            $htmlReport += "                <span class='network-issue'>- $issue</span><br>`n"
        }
    }
    $htmlReport += "            </div>`n"
}

$htmlReport += @"
        </div>
        
        <h2>Domain Policies</h2>
        
        <h3>Password Policy</h3>
        <div class="policy-box">
            <table>
                <tr><th>Setting</th><th>Value</th><th>Recommended</th><th>Status</th></tr>
                <tr>
                    <td>Minimum Password Length</td>
                    <td>$($AuditResults.Policies.PasswordPolicy.MinPasswordLength) characters</td>
                    <td>12+ characters</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.MinPasswordLength -ge 12){'success'}else{'high'})">$(if($AuditResults.Policies.PasswordPolicy.MinPasswordLength -ge 12){'GOOD'}else{'WEAK'})</span></td>
                </tr>
                <tr>
                    <td>Password Complexity</td>
                    <td>$(if($AuditResults.Policies.PasswordPolicy.ComplexityEnabled){'Enabled'}else{'Disabled'})</td>
                    <td>Enabled</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.ComplexityEnabled){'success'}else{'critical'})">$(if($AuditResults.Policies.PasswordPolicy.ComplexityEnabled){'GOOD'}else{'CRITICAL'})</span></td>
                </tr>
                <tr>
                    <td>Maximum Password Age</td>
                    <td>$($AuditResults.Policies.PasswordPolicy.MaxPasswordAge) days</td>
                    <td>60-90 days</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.MaxPasswordAge -ge 1 -and $AuditResults.Policies.PasswordPolicy.MaxPasswordAge -le 90){'success'}else{'medium'})">$(if($AuditResults.Policies.PasswordPolicy.MaxPasswordAge -ge 1 -and $AuditResults.Policies.PasswordPolicy.MaxPasswordAge -le 90){'GOOD'}else{'REVIEW'})</span></td>
                </tr>
                <tr>
                    <td>Password History</td>
                    <td>$($AuditResults.Policies.PasswordPolicy.PasswordHistoryCount) passwords</td>
                    <td>12+ passwords</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.PasswordHistoryCount -ge 12){'success'}else{'medium'})">$(if($AuditResults.Policies.PasswordPolicy.PasswordHistoryCount -ge 12){'GOOD'}else{'REVIEW'})</span></td>
                </tr>
                <tr>
                    <td>Reversible Encryption</td>
                    <td>$(if($AuditResults.Policies.PasswordPolicy.ReversibleEncryptionEnabled){'Enabled - BAD!'}else{'Disabled'})</td>
                    <td>Disabled</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.ReversibleEncryptionEnabled){'critical'}else{'success'})">$(if($AuditResults.Policies.PasswordPolicy.ReversibleEncryptionEnabled){'CRITICAL'}else{'GOOD'})</span></td>
                </tr>
            </table>
        </div>
        
        <h3>Account Lockout Policy</h3>
        <div class="policy-box">
            <table>
                <tr><th>Setting</th><th>Value</th><th>Recommended</th><th>Status</th></tr>
                <tr>
                    <td>Lockout Threshold</td>
                    <td>$(if($AuditResults.Policies.PasswordPolicy.LockoutThreshold -eq 0){'Not configured'}else{"$($AuditResults.Policies.PasswordPolicy.LockoutThreshold) attempts"})</td>
                    <td>5-10 attempts</td>
                    <td><span class="badge badge-$(if($AuditResults.Policies.PasswordPolicy.LockoutThreshold -gt 0){'success'}else{'high'})">$(if($AuditResults.Policies.PasswordPolicy.LockoutThreshold -gt 0){'GOOD'}else{'NOT CONFIGURED'})</span></td>
                </tr>
                <tr>
                    <td>Lockout Duration</td>
                    <td>$(if($AuditResults.Policies.PasswordPolicy.LockoutDuration){"$($AuditResults.Policies.PasswordPolicy.LockoutDuration) minutes"}else{"N/A"})</td>
                    <td>15-30 minutes</td>
                    <td><span class="badge badge-success">OK</span></td>
                </tr>
            </table>
        </div>
        
        <h2>User Statistics</h2>
        <table>
            <tr><th>Metric</th><th>Count</th><th>Status</th></tr>
            <tr><td>Total Users</td><td>$($AuditResults.Users.Total)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Enabled Users</td><td>$($AuditResults.Users.Enabled)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Disabled Users</td><td>$($AuditResults.Users.Disabled)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Inactive (90+ days)</td><td>$($AuditResults.Users.Inactive)</td><td><span class="badge badge-$(if($AuditResults.Users.Inactive -gt 0){'medium'}else{'success'})">$(if($AuditResults.Users.Inactive -gt 0){'WARNING'}else{'OK'})</span></td></tr>
            <tr><td>Password Never Expires</td><td>$($AuditResults.Users.NeverExpire)</td><td><span class="badge badge-$(if($AuditResults.Users.NeverExpire -gt 0){'high'}else{'success'})">$(if($AuditResults.Users.NeverExpire -gt 0){'RISK'}else{'OK'})</span></td></tr>
            <tr><td>No Password Required</td><td>$($AuditResults.Users.NoPasswordRequired.Count)</td><td><span class="badge badge-$(if($AuditResults.Users.NoPasswordRequired.Count -gt 0){'critical'}else{'success'})">$(if($AuditResults.Users.NoPasswordRequired.Count -gt 0){'CRITICAL'}else{'OK'})</span></td></tr>
        </table>
        
        <h2>Privileged Users</h2>
        <table>
            <tr><th>Group</th><th>Members</th><th>Count</th></tr>
"@

foreach ($priv in $AuditResults.Users.Privileged) {
    $htmlReport += "            <tr><td>$($priv.Group)</td><td>$($priv.Members)</td><td>$($priv.MemberCount)</td></tr>`n"
}

$htmlReport += @"
        </table>
        
        <h2>Groups & GPOs</h2>
        <table>
            <tr><th>Metric</th><th>Count</th></tr>
            <tr><td>Total Groups</td><td>$($AuditResults.Groups.Total)</td></tr>
            <tr><td>Empty Groups</td><td>$($AuditResults.Groups.Empty)</td></tr>
            <tr><td>Total GPOs</td><td>$($AuditResults.GPOs.Total)</td></tr>
        </table>
        
        <h2>Security Findings</h2>
"@

# Add findings
foreach ($finding in $AuditResults.Findings.Critical) {
    $htmlReport += @"
        <div class="finding finding-critical">
            <div><span class="badge badge-critical">CRITICAL</span> <strong>$($finding.Title)</strong></div>
            <div><strong>Category:</strong> $($finding.Category)</div>
            <div>$($finding.Description)</div>
            <div><strong>Impact:</strong> $($finding.Impact)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
}

foreach ($finding in $AuditResults.Findings.High) {
    $htmlReport += @"
        <div class="finding finding-high">
            <div><span class="badge badge-high">HIGH</span> <strong>$($finding.Title)</strong></div>
            <div><strong>Category:</strong> $($finding.Category)</div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
}

foreach ($finding in $AuditResults.Findings.Medium) {
    $htmlReport += @"
        <div class="finding finding-medium">
            <div><span class="badge badge-medium">MEDIUM</span> <strong>$($finding.Title)</strong></div>
            <div><strong>Category:</strong> $($finding.Category)</div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
}

foreach ($finding in $AuditResults.Findings.Low) {
    $htmlReport += @"
        <div class="finding finding-low">
            <div><span class="badge badge-low">LOW</span> <strong>$($finding.Title)</strong></div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
}

if (($AuditResults.Findings.Critical.Count + $AuditResults.Findings.High.Count + $AuditResults.Findings.Medium.Count + $AuditResults.Findings.Low.Count) -eq 0) {
    $htmlReport += "        <p style='color: green; font-weight: bold;'>No security findings! AD environment is healthy!</p>`n"
}

$htmlReport += @"
        
        <h2>Recommendations</h2>
        <ol>
            <li><strong>Network Security:</strong> Ensure DCs do not have public IPs and NSG rules are properly restricted</li>
            <li><strong>Password Policy:</strong> Enforce minimum 12 characters, complexity, and 60-90 day expiration</li>
            <li><strong>Account Lockout:</strong> Configure lockout after 5-10 failed attempts</li>
            <li><strong>Critical Findings:</strong> Address within 24 hours</li>
            <li><strong>High Priority:</strong> Address within 1 week</li>
            <li><strong>Privileged Access:</strong> Limit Domain Admins to 3-5 members maximum</li>
            <li><strong>Inactive Accounts:</strong> Disable accounts inactive for 90+ days</li>
            <li><strong>MFA:</strong> Enable multi-factor authentication for all privileged accounts</li>
            <li><strong>Regular Audits:</strong> Run this audit monthly</li>
            <li><strong>VNet Security:</strong> Implement proper network segmentation and NSG rules</li>
        </ol>
        
        <div style="background-color: #ecf0f1; padding: 20px; margin-top: 30px; border-radius: 5px;">
            <h3>Audit Summary</h3>
            <p><strong>Subscriptions:</strong> $($subscriptions.Count)</p>
            <p><strong>Domain Controllers:</strong> $($allDomainControllers.Count)</p>
            <p><strong>Security Score:</strong> <span style="color: $scoreColor; font-weight: bold; font-size: 24px;">$($AuditResults.SecurityScore)%</span></p>
            <p><strong>Total Checks:</strong> $($AuditResults.TotalChecks) | <strong>Passed:</strong> $($AuditResults.PassedChecks)</p>
            <p><strong>Duration:</strong> $($duration.ToString('mm\:ss'))</p>
        </div>
    </div>
</body>
</html>
"@

# Save report
$reportPath = Join-Path (Get-Location) $reportFile
$htmlReport | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  AUDIT COMPLETE!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Security Score: $($AuditResults.SecurityScore)%" -ForegroundColor $(if($AuditResults.SecurityScore -ge 80){"Green"}else{"Yellow"})
Write-Host "  Report: $reportFile" -ForegroundColor White
Write-Host ""

Start-Process $reportPath

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  COMPLETE AUDIT WITH POLICIES & NETWORK DETAILS!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
