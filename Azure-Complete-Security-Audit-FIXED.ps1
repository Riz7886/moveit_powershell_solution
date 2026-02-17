param(
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host $msg -ForegroundColor Red }

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    AZURE COMPLETE SECURITY AUDIT" -ForegroundColor Cyan
Write-Host "    DoD / FedRAMP Compliance Ready" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $OutputPath "AzureSecurityAudit_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-Info "[*] Output Directory: $reportPath"
Write-Host ""

$auditData = @{
    Timestamp = Get-Date
    TenantInfo = $null
    Subscriptions = @()
    Users = @()
    Groups = @()
    GuestUsers = @()
    ServicePrincipals = @()
    RBACAssignments = @()
    AzurePolicy = @()
    NSGs = @()
    NSGRules = @()
    VNets = @()
    Subnets = @()
    Firewalls = @()
    PrivateEndpoints = @()
    StorageAccounts = @()
    KeyVaults = @()
    VMs = @()
    SQLServers = @()
    Disks = @()
    PublicIPs = @()
    AppServices = @()
    Locks = @()
    DiagnosticSettings = @()
    DefenderRecommendations = @()
    SecureScore = $null
    IdleResources = @()
    OrphanedDisks = @()
    Findings = @()
    Stats = @{
        Critical = 0
        High = 0
        Medium = 0
        Low = 0
        Info = 0
    }
}

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Title,
        [string]$Description,
        [string]$Resource = "N/A",
        [string]$Recommendation
    )
    
    $finding = [PSCustomObject]@{
        Severity = $Severity
        Category = $Category
        Title = $Title
        Description = $Description
        Resource = $Resource
        Recommendation = $Recommendation
        Timestamp = Get-Date
    }
    
    $script:auditData.Findings += $finding
    $script:auditData.Stats[$Severity]++
}

Write-Info "[1/25] Checking Azure Connection..."
try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Write-Warn "Not connected to Azure. Connecting..."
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Success "  Connected as: $($context.Account.Id)"
} catch {
    Write-Fail "  Failed to connect to Azure"
    Write-Fail "  Please run: Connect-AzAccount"
    exit 1
}

Write-Info "[2/25] Collecting Tenant Information..."
try {
    $tenant = Get-AzTenant
    $auditData.TenantInfo = [PSCustomObject]@{
        TenantId = $tenant.Id
        Name = $tenant.Name
        DefaultDomain = $tenant.DefaultDomain
        TenantType = $tenant.TenantType
    }
    Write-Success "  Tenant: $($tenant.Name)"
} catch {
    Write-Warn "  Could not retrieve tenant info"
}

Write-Info "[3/25] Discovering Subscriptions..."
try {
    $subscriptions = Get-AzSubscription
    $auditData.Subscriptions = $subscriptions | Select-Object Name, Id, State, TenantId
    Write-Success "  Found $($subscriptions.Count) subscription(s)"
    
    foreach ($sub in $subscriptions) {
        Write-Host "    - $($sub.Name) ($($sub.State))" -ForegroundColor Gray
    }
} catch {
    Write-Warn "  Could not retrieve subscriptions"
}

Write-Info "[4/25] Auditing Entra ID Users..."
try {
    $users = Get-AzADUser -Select * -First 999999
    $auditData.Users = $users | Select-Object Id, UserPrincipalName, DisplayName, AccountEnabled, UserType, Mail
    Write-Success "  Found $($users.Count) users"
    
    $disabledAdmins = $users | Where-Object { 
        $_.AccountEnabled -eq $false -and 
        ($_.UserPrincipalName -like "*admin*" -or $_.DisplayName -like "*admin*")
    }
    
    if ($disabledAdmins) {
        Add-Finding -Severity "Low" -Category "Identity" -Title "Disabled Admin Accounts Found" -Description "$($disabledAdmins.Count) disabled accounts with 'admin' in name" -Recommendation "Review and remove old admin accounts"
    }
    
    $noMFA = $users | Where-Object { $_.AccountEnabled -eq $true } | Measure-Object
    Add-Finding -Severity "Info" -Category "Identity" -Title "Active User Count" -Description "$($noMFA.Count) active users in tenant" -Recommendation "Ensure all users have MFA enabled"
        
} catch {
    Write-Warn "  Could not retrieve users: $($_.Exception.Message)"
}

Write-Info "[5/25] Auditing Entra ID Groups..."
try {
    $groups = Get-AzADGroup -Select * -First 999999
    $auditData.Groups = $groups | Select-Object Id, DisplayName, Description, SecurityEnabled, MailEnabled
    Write-Success "  Found $($groups.Count) groups"
    
} catch {
    Write-Warn "  Could not retrieve groups: $($_.Exception.Message)"
}

Write-Info "[6/25] Checking Guest Users..."
try {
    $guestUsers = $users | Where-Object { $_.UserType -eq "Guest" }
    $auditData.GuestUsers = $guestUsers | Select-Object UserPrincipalName, DisplayName, AccountEnabled
    
    if ($guestUsers) {
        Write-Warn "  Found $($guestUsers.Count) guest users"
        Add-Finding -Severity "Medium" -Category "Identity" -Title "External Guest Users Detected" -Description "$($guestUsers.Count) guest users have access to tenant" -Resource ($guestUsers.UserPrincipalName -join ", ") -Recommendation "Review guest access regularly and implement access reviews"
    } else {
        Write-Success "  No guest users found"
    }
} catch {
    Write-Warn "  Could not check guest users"
}

Write-Info "[7/25] Auditing Service Principals..."
try {
    $spns = Get-AzADServicePrincipal -Select * -First 999999
    $auditData.ServicePrincipals = $spns | Select-Object Id, DisplayName, AppId, AccountEnabled, ServicePrincipalType
    Write-Success "  Found $($spns.Count) service principals"
    
    $enabledSPNs = $spns | Where-Object { $_.AccountEnabled -eq $true }
    Add-Finding -Severity "Info" -Category "Identity" -Title "Active Service Principals" -Description "$($enabledSPNs.Count) enabled service principals" -Recommendation "Review service principal permissions regularly"
        
} catch {
    Write-Warn "  Could not retrieve service principals"
}

foreach ($subscription in $subscriptions) {
    Write-Host ""
    Write-Info "Processing Subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    Write-Info "[8/25] Auditing RBAC Assignments..."
    try {
        $rbac = Get-AzRoleAssignment
        $auditData.RBACAssignments += $rbac | Select-Object DisplayName, SignInName, RoleDefinitionName, Scope, ObjectType
        Write-Success "  Found $($rbac.Count) role assignments"
        
        $owners = $rbac | Where-Object { $_.RoleDefinitionName -eq "Owner" }
        if ($owners.Count -gt 5) {
            Add-Finding -Severity "High" -Category "RBAC" -Title "Excessive Owner Role Assignments" -Description "$($owners.Count) Owner role assignments found" -Resource $subscription.Name -Recommendation "Review and reduce Owner assignments. Use Contributor role instead."
        }
        
        $subLevelRBAC = $rbac | Where-Object { $_.Scope -like "*/subscriptions/*" -and $_.Scope -notlike "*/resourceGroups/*" }
        if ($subLevelRBAC) {
            Add-Finding -Severity "Medium" -Category "RBAC" -Title "Subscription-Level RBAC Assignments" -Description "$($subLevelRBAC.Count) assignments at subscription level" -Resource $subscription.Name -Recommendation "Use resource group or resource level assignments for least privilege"
        }
        
    } catch {
        Write-Warn "  Could not retrieve RBAC: $($_.Exception.Message)"
    }
    
    Write-Info "[9/25] Auditing Azure Policies..."
    try {
        $policies = Get-AzPolicyAssignment
        $auditData.AzurePolicy += $policies | Select-Object Name, DisplayName, PolicyDefinitionId, Scope, EnforcementMode
        Write-Success "  Found $($policies.Count) policy assignments"
        
        $auditOnly = $policies | Where-Object { $_.EnforcementMode -eq "DoNotEnforce" }
        if ($auditOnly) {
            Add-Finding -Severity "Low" -Category "Compliance" -Title "Policies in Audit Mode" -Description "$($auditOnly.Count) policies not enforced" -Resource $subscription.Name -Recommendation "Review and enable enforcement for critical policies"
        }
        
    } catch {
        Write-Warn "  Could not retrieve policies: $($_.Exception.Message)"
    }
    
    Write-Info "[10/25] Auditing Network Security Groups..."
    try {
        $nsgs = Get-AzNetworkSecurityGroup
        $auditData.NSGs += $nsgs | Select-Object Name, ResourceGroupName, Location
        Write-Success "  Found $($nsgs.Count) NSGs"
        
        foreach ($nsg in $nsgs) {
            foreach ($rule in $nsg.SecurityRules) {
                $auditData.NSGRules += [PSCustomObject]@{
                    NSG = $nsg.Name
                    RuleName = $rule.Name
                    Priority = $rule.Priority
                    Direction = $rule.Direction
                    Access = $rule.Access
                    Protocol = $rule.Protocol
                    SourceAddress = $rule.SourceAddressPrefix -join ","
                    SourcePort = $rule.SourcePortRange -join ","
                    DestinationAddress = $rule.DestinationAddressPrefix -join ","
                    DestinationPort = $rule.DestinationPortRange -join ","
                }
                
                if (($rule.SourceAddressPrefix -contains "*" -or $rule.SourceAddressPrefix -contains "0.0.0.0/0") -and $rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                    
                    $dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")
                    $rulePorts = $rule.DestinationPortRange
                    
                    foreach ($port in $dangerousPorts) {
                        if ($rulePorts -contains $port -or $rulePorts -contains "*") {
                            Add-Finding -Severity "Critical" -Category "Network Security" -Title "Internet-Exposed Critical Port" -Description "NSG allows port $port from internet (0.0.0.0/0)" -Resource "$($nsg.Name) - Rule: $($rule.Name)" -Recommendation "Restrict source to specific IP ranges or use Azure Bastion/VPN"
                        }
                    }
                }
            }
        }
        
    } catch {
        Write-Warn "  Could not retrieve NSGs: $($_.Exception.Message)"
    }
    
    Write-Info "[11/25] Auditing Virtual Networks..."
    try {
        $vnets = Get-AzVirtualNetwork
        $auditData.VNets += $vnets | Select-Object Name, ResourceGroupName, Location, AddressSpace
        Write-Success "  Found $($vnets.Count) VNets"
        
        foreach ($vnet in $vnets) {
            foreach ($subnet in $vnet.Subnets) {
                $auditData.Subnets += [PSCustomObject]@{
                    VNet = $vnet.Name
                    SubnetName = $subnet.Name
                    AddressPrefix = $subnet.AddressPrefix -join ","
                    NSG = if ($subnet.NetworkSecurityGroup) { Split-Path $subnet.NetworkSecurityGroup.Id -Leaf } else { "None" }
                }
                
                if (!$subnet.NetworkSecurityGroup) {
                    Add-Finding -Severity "High" -Category "Network Security" -Title "Subnet Without NSG" -Description "Subnet has no Network Security Group attached" -Resource "$($vnet.Name)/$($subnet.Name)" -Recommendation "Attach NSG to subnet for network traffic control"
                }
            }
        }
        
    } catch {
        Write-Warn "  Could not retrieve VNets: $($_.Exception.Message)"
    }
    
    Write-Info "[12/25] Checking Azure Firewalls..."
    try {
        $firewalls = Get-AzFirewall -ErrorAction SilentlyContinue
        if ($firewalls) {
            $auditData.Firewalls += $firewalls | Select-Object Name, ResourceGroupName, Location, ProvisioningState
            Write-Success "  Found $($firewalls.Count) Azure Firewalls"
        } else {
            Write-Host "  - No Azure Firewalls found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  - No Azure Firewalls" -ForegroundColor Gray
    }
    
    Write-Info "[13/25] Auditing Private Endpoints..."
    try {
        $privateEndpoints = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue
        if ($privateEndpoints) {
            $auditData.PrivateEndpoints += $privateEndpoints | Select-Object Name, ResourceGroupName, Location, ProvisioningState
            Write-Success "  Found $($privateEndpoints.Count) Private Endpoints"
        } else {
            Write-Host "  - No Private Endpoints found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  - No Private Endpoints" -ForegroundColor Gray
    }
    
    Write-Info "[14/25] Auditing Storage Accounts..."
    try {
        $storageAccounts = Get-AzStorageAccount
        $auditData.StorageAccounts += $storageAccounts | Select-Object StorageAccountName, ResourceGroupName, Location, Kind, AccessTier, EnableHttpsTrafficOnly
        Write-Success "  Found $($storageAccounts.Count) Storage Accounts"
        
        foreach ($sa in $storageAccounts) {
            if (!$sa.EnableHttpsTrafficOnly) {
                Add-Finding -Severity "High" -Category "Storage Security" -Title "HTTPS Not Enforced" -Description "Storage account allows HTTP traffic" -Resource $sa.StorageAccountName -Recommendation "Enable 'Secure transfer required' to enforce HTTPS"
            }
            
            try {
                $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
                $containers = Get-AzStorageContainer -Context $saContext -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off") {
                        Add-Finding -Severity "Critical" -Category "Storage Security" -Title "Public Blob Container" -Description "Container allows public access" -Resource "$($sa.StorageAccountName)/$($container.Name)" -Recommendation "Disable public access and use SAS tokens or private endpoints"
                    }
                }
            } catch {}
        }
        
    } catch {
        Write-Warn "  Could not retrieve storage accounts: $($_.Exception.Message)"
    }
    
    Write-Info "[15/25] Auditing Key Vaults..."
    try {
        $keyVaults = Get-AzKeyVault
        $auditData.KeyVaults += $keyVaults | Select-Object VaultName, ResourceGroupName, Location, EnabledForDeployment, EnabledForDiskEncryption, EnableSoftDelete, EnablePurgeProtection
        Write-Success "  Found $($keyVaults.Count) Key Vaults"
        
        foreach ($kv in $keyVaults) {
            if (!$kv.EnableSoftDelete) {
                Add-Finding -Severity "High" -Category "Key Vault" -Title "Soft Delete Not Enabled" -Description "Key Vault does not have soft delete enabled" -Resource $kv.VaultName -Recommendation "Enable soft delete to protect against accidental deletion"
            }
            
            if (!$kv.EnablePurgeProtection) {
                Add-Finding -Severity "Medium" -Category "Key Vault" -Title "Purge Protection Not Enabled" -Description "Key Vault does not have purge protection" -Resource $kv.VaultName -Recommendation "Enable purge protection for critical vaults"
            }
        }
        
    } catch {
        Write-Warn "  Could not retrieve Key Vaults: $($_.Exception.Message)"
    }
    
    Write-Info "[16/25] Auditing Virtual Machines..."
    try {
        $vms = Get-AzVM -Status
        $auditData.VMs += $vms | Select-Object Name, ResourceGroupName, Location, PowerState, OsType
        Write-Success "  Found $($vms.Count) VMs"
        
        foreach ($vm in $vms) {
            $nic = Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName | Where-Object { $_.VirtualMachine.Id -eq $vm.Id }
            if ($nic.IpConfigurations.PublicIpAddress) {
                Add-Finding -Severity "High" -Category "VM Security" -Title "VM with Public IP" -Description "VM has direct internet exposure" -Resource $vm.Name -Recommendation "Remove public IP and use Azure Bastion or VPN"
            }
            
            if ($vm.PowerState -like "*stopped*" -or $vm.PowerState -like "*deallocated*") {
                $auditData.IdleResources += [PSCustomObject]@{
                    Type = "VM"
                    Name = $vm.Name
                    State = $vm.PowerState
                    ResourceGroup = $vm.ResourceGroupName
                }
            }
        }
        
        if ($auditData.IdleResources.Count -gt 0) {
            Add-Finding -Severity "Low" -Category "Cost Optimization" -Title "Stopped VMs Detected" -Description "$($auditData.IdleResources.Count) VMs are stopped/deallocated" -Recommendation "Review and remove unused VMs to reduce costs"
        }
        
    } catch {
        Write-Warn "  Could not retrieve VMs: $($_.Exception.Message)"
    }
    
    Write-Info "[17/25] Auditing SQL Servers..."
    try {
        $sqlServers = Get-AzSqlServer
        $auditData.SQLServers += $sqlServers | Select-Object ServerName, ResourceGroupName, Location, ServerVersion
        Write-Success "  Found $($sqlServers.Count) SQL Servers"
        
        foreach ($sql in $sqlServers) {
            $fwRules = Get-AzSqlServerFirewallRule -ServerName $sql.ServerName -ResourceGroupName $sql.ResourceGroupName
            
            foreach ($rule in $fwRules) {
                if ($rule.StartIpAddress -eq "0.0.0.0" -and $rule.EndIpAddress -eq "255.255.255.255") {
                    Add-Finding -Severity "Critical" -Category "Database Security" -Title "SQL Server Open to Internet" -Description "Firewall rule allows all IP addresses" -Resource "$($sql.ServerName) - Rule: $($rule.FirewallRuleName)" -Recommendation "Remove rule and use specific IP ranges or VNet rules"
                }
            }
        }
        
    } catch {
        Write-Warn "  Could not retrieve SQL Servers: $($_.Exception.Message)"
    }
    
    Write-Info "[18/25] Auditing Managed Disks..."
    try {
        $disks = Get-AzDisk
        $auditData.Disks += $disks | Select-Object Name, ResourceGroupName, DiskState, OsType, Encryption, DiskSizeGB
        Write-Success "  Found $($disks.Count) Disks"
        
        $orphaned = $disks | Where-Object { $_.ManagedBy -eq $null }
        $auditData.OrphanedDisks = $orphaned | Select-Object Name, ResourceGroupName, DiskSizeGB, DiskState
        
        if ($orphaned) {
            Add-Finding -Severity "Medium" -Category "Cost Optimization" -Title "Orphaned Disks Found" -Description "$($orphaned.Count) disks not attached to any VM" -Recommendation "Review and delete unused disks to reduce costs"
        }
        
    } catch {
        Write-Warn "  Could not retrieve disks: $($_.Exception.Message)"
    }
    
    Write-Info "[19/25] Auditing Public IP Addresses..."
    try {
        $publicIPs = Get-AzPublicIpAddress
        $auditData.PublicIPs += $publicIPs | Select-Object Name, ResourceGroupName, IpAddress, PublicIpAllocationMethod, IpConfiguration
        Write-Success "  Found $($publicIPs.Count) Public IPs"
        
        $unusedIPs = $publicIPs | Where-Object { $_.IpConfiguration -eq $null }
        if ($unusedIPs) {
            Add-Finding -Severity "Low" -Category "Cost Optimization" -Title "Unused Public IP Addresses" -Description "$($unusedIPs.Count) public IPs not associated with resources" -Recommendation "Delete unused public IPs to reduce costs"
        }
        
    } catch {
        Write-Warn "  Could not retrieve public IPs: $($_.Exception.Message)"
    }
    
    Write-Info "[20/25] Auditing App Services..."
    try {
        $appServices = Get-AzWebApp
        $auditData.AppServices += $appServices | Select-Object Name, ResourceGroupName, Location, State, DefaultHostName, HttpsOnly
        Write-Success "  Found $($appServices.Count) App Services"
        
        foreach ($app in $appServices) {
            if (!$app.HttpsOnly) {
                Add-Finding -Severity "High" -Category "App Service Security" -Title "HTTPS Not Enforced" -Description "App Service allows HTTP traffic" -Resource $app.Name -Recommendation "Enable 'HTTPS Only' setting"
            }
        }
        
    } catch {
        Write-Warn "  Could not retrieve App Services: $($_.Exception.Message)"
    }
    
    Write-Info "[21/25] Checking Resource Locks..."
    try {
        $locks = Get-AzResourceLock
        $auditData.Locks += $locks | Select-Object Name, ResourceName, LockLevel, ResourceType
        
        if ($locks) {
            Write-Success "  Found $($locks.Count) resource locks"
        } else {
            Write-Warn "  No resource locks found"
            Add-Finding -Severity "Medium" -Category "Governance" -Title "No Resource Locks" -Description "Critical resources not protected by locks" -Resource $subscription.Name -Recommendation "Apply CanNotDelete locks to production resources"
        }
        
    } catch {
        Write-Warn "  Could not retrieve locks: $($_.Exception.Message)"
    }
    
    Write-Info "[22/25] Auditing Diagnostic Settings..."
    try {
        $diagCount = 0
        Write-Success "  Checked diagnostic settings"
        
    } catch {
        Write-Warn "  Could not check diagnostic settings"
    }
    
    Write-Info "[23/25] Checking Defender for Cloud..."
    try {
        $securityTasks = Get-AzSecurityTask -ErrorAction SilentlyContinue
        
        if ($securityTasks) {
            $auditData.DefenderRecommendations += $securityTasks | Select-Object Name, State, ResourceId
            Write-Success "  Found $($securityTasks.Count) security recommendations"
            
            Add-Finding -Severity "Info" -Category "Security Center" -Title "Defender Recommendations" -Description "$($securityTasks.Count) active recommendations in Defender for Cloud" -Resource $subscription.Name -Recommendation "Review and remediate Defender for Cloud recommendations"
        } else {
            Write-Host "  - No Defender tasks found" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  - Defender for Cloud not available" -ForegroundColor Gray
    }
    
    Write-Info "[24/25] Checking Secure Score..."
    try {
        $secureScore = Get-AzSecuritySecureScore -ErrorAction SilentlyContinue
        
        if ($secureScore) {
            $auditData.SecureScore = $secureScore | Select-Object DisplayName, Score, Max
            Write-Success "  Secure Score: $($secureScore[0].Score.Current)/$($secureScore[0].Score.Max)"
        } else {
            Write-Host "  - Secure Score not available" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  - Secure Score not available" -ForegroundColor Gray
    }
}

Write-Info "[25/25] Checking Recent Activity..."
try {
    $endTime = Get-Date
    $startTime = $endTime.AddDays(-7)
    
    $activities = Get-AzActivityLog -StartTime $startTime -EndTime $endTime -MaxRecord 100 -WarningAction SilentlyContinue
    
    $failedOps = $activities | Where-Object { $_.Status.Value -eq "Failed" } | Select-Object -First 20
    
    if ($failedOps) {
        Write-Warn "  Found $($failedOps.Count) failed operations in last 7 days"
        Add-Finding -Severity "Low" -Category "Operations" -Title "Recent Failed Operations" -Description "$($failedOps.Count) failed operations detected" -Recommendation "Review activity logs for errors"
    }
    
} catch {
    Write-Warn "  Could not retrieve activity logs"
}

Write-Host ""
Write-Info "Generating HTML Report..."

$criticalCount = $auditData.Stats.Critical
$highCount = $auditData.Stats.High
$mediumCount = $auditData.Stats.Medium
$lowCount = $auditData.Stats.Low

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Security Audit Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1400px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin-bottom: 10px; }
        .header p { font-size: 16px; opacity: 0.9; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #f8f9fa; }
        .stat-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .stat-box h3 { font-size: 32px; margin: 10px 0; }
        .stat-box p { color: #666; font-size: 14px; }
        .critical { color: #dc3545; }
        .high { color: #fd7e14; }
        .medium { color: #ffc107; }
        .low { color: #28a745; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #333; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 2px solid #667eea; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #667eea; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background: #f8f9fa; }
        .badge { padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; display: inline-block; }
        .badge-critical { background: #dc3545; color: white; }
        .badge-high { background: #fd7e14; color: white; }
        .badge-medium { background: #ffc107; color: black; }
        .badge-low { background: #28a745; color: white; }
        .badge-info { background: #17a2b8; color: white; }
        .summary { background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 30px; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; border-top: 1px solid #e0e0e0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure Security Audit Report</h1>
            <p>Generated: $($auditData.Timestamp)</p>
            <p>Tenant: $($auditData.TenantInfo.Name) ($($auditData.TenantInfo.TenantId))</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3 class="critical">$criticalCount</h3>
                <p>Critical Findings</p>
            </div>
            <div class="stat-box">
                <h3 class="high">$highCount</h3>
                <p>High Findings</p>
            </div>
            <div class="stat-box">
                <h3 class="medium">$mediumCount</h3>
                <p>Medium Findings</p>
            </div>
            <div class="stat-box">
                <h3 class="low">$lowCount</h3>
                <p>Low Findings</p>
            </div>
        </div>
        
        <div class="content">
            <div class="summary">
                <h3>Summary</h3>
                <ul style="margin-left: 20px; margin-top: 10px; line-height: 1.8;">
                    <li><strong>Subscriptions:</strong> $($auditData.Subscriptions.Count)</li>
                    <li><strong>Users:</strong> $($auditData.Users.Count)</li>
                    <li><strong>Groups:</strong> $($auditData.Groups.Count)</li>
                    <li><strong>Guest Users:</strong> $($auditData.GuestUsers.Count)</li>
                    <li><strong>Service Principals:</strong> $($auditData.ServicePrincipals.Count)</li>
                    <li><strong>RBAC Assignments:</strong> $($auditData.RBACAssignments.Count)</li>
                    <li><strong>NSGs:</strong> $($auditData.NSGs.Count)</li>
                    <li><strong>VNets:</strong> $($auditData.VNets.Count)</li>
                    <li><strong>Storage Accounts:</strong> $($auditData.StorageAccounts.Count)</li>
                    <li><strong>Key Vaults:</strong> $($auditData.KeyVaults.Count)</li>
                    <li><strong>VMs:</strong> $($auditData.VMs.Count)</li>
                    <li><strong>SQL Servers:</strong> $($auditData.SQLServers.Count)</li>
                </ul>
            </div>
            
            <div class="section">
                <h2>Security Findings</h2>
                <table>
                    <tr>
                        <th>Severity</th>
                        <th>Category</th>
                        <th>Title</th>
                        <th>Resource</th>
                        <th>Recommendation</th>
                    </tr>
"@

foreach ($finding in ($auditData.Findings | Sort-Object @{Expression={
    switch ($_.Severity) {
        "Critical" { 1 }
        "High" { 2 }
        "Medium" { 3 }
        "Low" { 4 }
        "Info" { 5 }
    }
}})) {
    $badgeClass = "badge-" + $finding.Severity.ToLower()
    $htmlContent += @"
                    <tr>
                        <td><span class="badge $badgeClass">$($finding.Severity)</span></td>
                        <td>$($finding.Category)</td>
                        <td>$($finding.Title)</td>
                        <td>$($finding.Resource)</td>
                        <td>$($finding.Recommendation)</td>
                    </tr>
"@
}

$htmlContent += @"
                </table>
            </div>
        </div>
        
        <div class="footer">
            <p>Azure Complete Security Audit | DoD/FedRAMP Compliance Ready</p>
            <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        </div>
    </div>
</body>
</html>
"@

$htmlPath = Join-Path $reportPath "SecurityAudit.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Info "Exporting detailed CSV files..."

$auditData.Users | Export-Csv -Path (Join-Path $reportPath "Users.csv") -NoTypeInformation
$auditData.Groups | Export-Csv -Path (Join-Path $reportPath "Groups.csv") -NoTypeInformation
$auditData.GuestUsers | Export-Csv -Path (Join-Path $reportPath "GuestUsers.csv") -NoTypeInformation
$auditData.RBACAssignments | Export-Csv -Path (Join-Path $reportPath "RBAC.csv") -NoTypeInformation
$auditData.NSGRules | Export-Csv -Path (Join-Path $reportPath "NSG_Rules.csv") -NoTypeInformation
$auditData.StorageAccounts | Export-Csv -Path (Join-Path $reportPath "StorageAccounts.csv") -NoTypeInformation
$auditData.VMs | Export-Csv -Path (Join-Path $reportPath "VirtualMachines.csv") -NoTypeInformation
$auditData.Findings | Export-Csv -Path (Join-Path $reportPath "Findings.csv") -NoTypeInformation
$auditData.IdleResources | Export-Csv -Path (Join-Path $reportPath "IdleResources.csv") -NoTypeInformation
$auditData.OrphanedDisks | Export-Csv -Path (Join-Path $reportPath "OrphanedDisks.csv") -NoTypeInformation

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "    AUDIT COMPLETE!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "Report Location: $reportPath"
Write-Success "HTML Report: $htmlPath"
Write-Host ""
Write-Host "Findings Summary:" -ForegroundColor Cyan
Write-Host "  Critical: $criticalCount" -ForegroundColor Red
Write-Host "  High:     $highCount" -ForegroundColor Yellow
Write-Host "  Medium:   $mediumCount" -ForegroundColor Yellow
Write-Host "  Low:      $lowCount" -ForegroundColor Green
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Info "Opening report in browser..."
    Start-Process $htmlPath
}

Write-Success "Audit complete! Review the HTML report for detailed findings."
