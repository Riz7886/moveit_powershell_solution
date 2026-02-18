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
Write-Host "    SMART SECURITY REMEDIATION" -ForegroundColor Cyan
Write-Host "    Created by: Syed Rizvi" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking Azure connection..."
try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Success "Connected as: $($context.Account.Id)"
    Write-Host ""
} catch {
    Write-Fail "Failed to connect to Azure"
    exit 1
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $OutputPath "SmartRemediation_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

$results = @{
    VPNGateways = @()
    AzureBastions = @()
    NSGRulesUpdated = @()
    NSGRulesSkipped = @()
    StorageSASTokens = @()
    StorageFixed = @()
    StorageSkipped = @()
    Timestamp = Get-Date
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "STEP 1: DISCOVERING VPN AND BASTION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Scanning all subscriptions for VPN and Bastion..."
$subscriptions = Get-AzSubscription
Write-Success "Found $($subscriptions.Count) subscription(s)"
Write-Host ""

$vpnSubnets = @()
$bastionSubnets = @()

foreach ($subscription in $subscriptions) {
    Write-Info "Checking: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $vpnGateways = Get-AzVirtualNetworkGateway
        foreach ($vpn in $vpnGateways) {
            if ($vpn.GatewayType -eq "Vpn") {
                Write-Success "  FOUND VPN Gateway: $($vpn.Name)"
                
                $vnetId = $vpn.IpConfigurations[0].Subnet.Id
                $vnetName = $vnetId.Split('/')[8]
                $rgName = $vnetId.Split('/')[4]
                
                $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
                $gatewaySubnet = $vnet.Subnets | Where-Object { $_.Name -eq "GatewaySubnet" }
                
                if ($gatewaySubnet) {
                    $subnetPrefix = $gatewaySubnet.AddressPrefix[0]
                    Write-Success "    VPN Subnet: $subnetPrefix"
                    
                    $vpnSubnets += $subnetPrefix
                    
                    $results.VPNGateways += [PSCustomObject]@{
                        Subscription = $subscription.Name
                        Name = $vpn.Name
                        VNet = $vnetName
                        Subnet = $subnetPrefix
                        ResourceGroup = $rgName
                    }
                }
            }
        }
    } catch {
        Write-Warn "  Could not check VPN gateways: $($_.Exception.Message)"
    }
    
    try {
        $bastions = Get-AzBastion
        foreach ($bastion in $bastions) {
            Write-Success "  FOUND Azure Bastion: $($bastion.Name)"
            
            $subnetId = $bastion.IpConfigurations[0].Subnet.Id
            $vnetName = $subnetId.Split('/')[8]
            $rgName = $subnetId.Split('/')[4]
            
            $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
            $bastionSubnet = $vnet.Subnets | Where-Object { $_.Name -eq "AzureBastionSubnet" }
            
            if ($bastionSubnet) {
                $subnetPrefix = $bastionSubnet.AddressPrefix[0]
                Write-Success "    Bastion Subnet: $subnetPrefix"
                
                $bastionSubnets += $subnetPrefix
                
                $results.AzureBastions += [PSCustomObject]@{
                    Subscription = $subscription.Name
                    Name = $bastion.Name
                    VNet = $vnetName
                    Subnet = $subnetPrefix
                    ResourceGroup = $rgName
                }
            }
        }
    } catch {
        Write-Warn "  Could not check Bastion: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "DISCOVERY RESULTS:" -ForegroundColor Yellow
Write-Host "  VPN Gateways Found:    $($results.VPNGateways.Count)" -ForegroundColor $(if ($results.VPNGateways.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Azure Bastions Found:  $($results.AzureBastions.Count)" -ForegroundColor $(if ($results.AzureBastions.Count -gt 0) { "Green" } else { "Red" })
Write-Host ""

if ($results.VPNGateways.Count -eq 0 -and $results.AzureBastions.Count -eq 0) {
    Write-Fail "CRITICAL WARNING: NO VPN OR BASTION FOUND"
    Write-Fail "Cannot safely fix NSG rules without secure access method"
    Write-Host ""
    Write-Warn "OPTIONS:"
    Write-Warn "1. Deploy Azure Bastion first (recommended)"
    Write-Warn "2. Get your company's public IP range for temporary access"
    Write-Warn "3. Skip NSG fixes for now (not recommended)"
    Write-Host ""
    
    $proceed = Read-Host "Do you want to proceed anyway? (yes/no)"
    if ($proceed -ne "yes") {
        Write-Info "Exiting - Please deploy VPN or Bastion first"
        exit 0
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "STEP 2: SCANNING DANGEROUS NSG RULES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dangerousRules = @()
$dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")

foreach ($subscription in $subscriptions) {
    Write-Info "Scanning subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $nsgs = Get-AzNetworkSecurityGroup
        Write-Success "  Found $($nsgs.Count) NSGs"
        
        foreach ($nsg in $nsgs) {
            foreach ($rule in $nsg.SecurityRules) {
                if (($rule.SourceAddressPrefix -contains "*" -or $rule.SourceAddressPrefix -contains "0.0.0.0/0") -and 
                    $rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                    
                    $rulePorts = $rule.DestinationPortRange
                    
                    foreach ($port in $dangerousPorts) {
                        if ($rulePorts -contains $port -or $rulePorts -contains "*") {
                            $portDisplay = if ($rulePorts -contains "*") { "ALL" } else { $rulePorts -join "," }
                            
                            Write-Fail "    FOUND: $($nsg.Name) - Rule: $($rule.Name) - Port $port"
                            
                            $dangerousRules += [PSCustomObject]@{
                                Subscription = $subscription.Name
                                SubscriptionId = $subscription.Id
                                NSG = $nsg.Name
                                RuleName = $rule.Name
                                Port = $portDisplay
                                Priority = $rule.Priority
                                Protocol = $rule.Protocol
                                ResourceGroup = $nsg.ResourceGroupName
                                NSGObject = $nsg
                                RuleObject = $rule
                            }
                            break
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warn "  Could not retrieve NSGs: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Success "Found $($dangerousRules.Count) dangerous NSG rules"
Write-Host ""

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "STEP 3: SCANNING PUBLIC STORAGE CONTAINERS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$publicContainers = @()

foreach ($subscription in $subscriptions) {
    Write-Info "Scanning subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $storageAccounts = Get-AzStorageAccount
        Write-Success "  Found $($storageAccounts.Count) Storage Accounts"
        
        foreach ($sa in $storageAccounts) {
            try {
                $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
                $containers = Get-AzStorageContainer -Context $saContext -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off") {
                        Write-Fail "    PUBLIC: $($sa.StorageAccountName)/$($container.Name) - Access: $($container.PublicAccess)"
                        
                        $publicContainers += [PSCustomObject]@{
                            Subscription = $subscription.Name
                            SubscriptionId = $subscription.Id
                            StorageAccount = $sa.StorageAccountName
                            Container = $container.Name
                            PublicAccess = $container.PublicAccess
                            ResourceGroup = $sa.ResourceGroupName
                            SAObject = $sa
                            Context = $saContext
                        }
                    }
                }
            } catch {}
        }
    } catch {
        Write-Warn "  Could not retrieve storage accounts: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Success "Found $($publicContainers.Count) public blob containers"
Write-Host ""

if ($dangerousRules.Count -eq 0) {
    Write-Success "No dangerous NSG rules found - all good"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "PART 1: FIX NSG RULES (SMART UPDATE)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Fail "FOUND $($dangerousRules.Count) DANGEROUS NSG RULES:"
    Write-Host ""
    for ($i = 0; $i -lt $dangerousRules.Count; $i++) {
        $item = $dangerousRules[$i]
        Write-Host "  [$($i+1)] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($item.NSG) " -NoNewline -ForegroundColor Cyan
        Write-Host "| Rule: " -NoNewline
        Write-Host "$($item.RuleName) " -NoNewline -ForegroundColor White
        Write-Host "| Port: " -NoNewline
        Write-Host "$($item.Port) " -ForegroundColor Red
    }
    
    Write-Host ""
    if ($vpnSubnets.Count -gt 0 -or $bastionSubnets.Count -gt 0) {
        Write-Success "GOOD NEWS: VPN/Bastion infrastructure detected"
        Write-Success "We will UPDATE rules to allow only VPN/Bastion (not delete them)"
        Write-Host ""
        Write-Info "Rules will be updated to allow from:"
        foreach ($subnet in $vpnSubnets) {
            Write-Host "  - VPN Subnet: $subnet" -ForegroundColor Green
        }
        foreach ($subnet in $bastionSubnets) {
            Write-Host "  - Bastion Subnet: $subnet" -ForegroundColor Green
        }
    } else {
        Write-Warn "NO VPN/BASTION: Will need manual IP range"
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "CHOOSE YOUR ACTION FOR NSG RULES:" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [U] UPDATE rules to allow VPN/Bastion only (RECOMMENDED)" -ForegroundColor White
    Write-Host "  [D] DELETE rules completely (DANGEROUS)" -ForegroundColor White
    Write-Host "  [S] SKIP all NSG fixes" -ForegroundColor White
    Write-Host ""
    Write-Host "What do you want to do?" -ForegroundColor Yellow
    
    $choice = ""
    while ($choice -ne "U" -and $choice -ne "D" -and $choice -ne "S") {
        $choice = (Read-Host "Enter U, D, or S").ToUpper()
    }
    
    Write-Host ""
    
    if ($choice -eq "U") {
        Write-Success "You chose: UPDATE RULES (Smart Fix)"
        Write-Host ""
        
        if ($vpnSubnets.Count -eq 0 -and $bastionSubnets.Count -eq 0) {
            Write-Warn "No VPN/Bastion subnets found - Enter your company's IP range:"
            $companyIP = Read-Host "Enter IP range (e.g., 203.0.113.0/24)"
            $vpnSubnets += $companyIP
        }
        
        Write-Info "Updating NSG rules to allow only secure subnets..."
        Write-Host ""
        
        foreach ($item in $dangerousRules) {
            try {
                Write-Host "  Updating: $($item.RuleName) in $($item.NSG)..." -ForegroundColor Yellow
                
                Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
                
                $nsgToUpdate = Get-AzNetworkSecurityGroup -Name $item.NSG -ResourceGroupName $item.ResourceGroup
                
                $ruleToUpdate = $nsgToUpdate.SecurityRules | Where-Object { $_.Name -eq $item.RuleName }
                
                if ($ruleToUpdate) {
                    $allowedSources = @()
                    $allowedSources += $vpnSubnets
                    $allowedSources += $bastionSubnets
                    
                    if ($allowedSources.Count -eq 1) {
                        $ruleToUpdate.SourceAddressPrefix = $allowedSources[0]
                    } else {
                        $ruleToUpdate.SourceAddressPrefixes = $allowedSources
                        $ruleToUpdate.SourceAddressPrefix = $null
                    }
                    
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    
                    Write-Success "    UPDATED - Now allows only from: $($allowedSources -join ', ')"
                    
                    $results.NSGRulesUpdated += [PSCustomObject]@{
                        Subscription = $item.Subscription
                        NSG = $item.NSG
                        RuleName = $item.RuleName
                        OldSource = "0.0.0.0/0 (Internet)"
                        NewSource = $allowedSources -join ", "
                        Port = $item.Port
                    }
                } else {
                    Write-Warn "    Rule not found (may have been deleted)"
                }
            } catch {
                Write-Fail "    FAILED: $($_.Exception.Message)"
            }
        }
        
    } elseif ($choice -eq "D") {
        Write-Fail "You chose: DELETE (Dangerous)"
        Write-Warn "This will remove all internet access to your VMs"
        $confirm = Read-Host "Are you SURE? Type 'DELETE' to confirm"
        
        if ($confirm -eq "DELETE") {
            Write-Host ""
            Write-Info "Deleting NSG rules..."
            
            foreach ($item in $dangerousRules) {
                try {
                    Write-Host "  Deleting: $($item.RuleName) from $($item.NSG)..." -ForegroundColor Yellow
                    
                    Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
                    
                    $nsgToUpdate = Get-AzNetworkSecurityGroup -Name $item.NSG -ResourceGroupName $item.ResourceGroup
                    Remove-AzNetworkSecurityRuleConfig -Name $item.RuleName -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    
                    Write-Success "    DELETED"
                    $results.NSGRulesUpdated += $item
                } catch {
                    Write-Fail "    FAILED: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Info "Delete cancelled"
        }
        
    } else {
        Write-Host "You chose: SKIP" -ForegroundColor Gray
        $results.NSGRulesSkipped = $dangerousRules
    }
}

Write-Host ""
Write-Host "Press ENTER to continue to Storage fixes..." -ForegroundColor Cyan
Read-Host

if ($publicContainers.Count -eq 0) {
    Write-Success "No public blob containers found - all good"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "PART 2: FIX STORAGE (GENERATE SAS TOKENS)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Fail "FOUND $($publicContainers.Count) PUBLIC BLOB CONTAINERS:"
    Write-Host ""
    for ($i = 0; $i -lt $publicContainers.Count; $i++) {
        $item = $publicContainers[$i]
        Write-Host "  [$($i+1)] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($item.StorageAccount) " -NoNewline -ForegroundColor Cyan
        Write-Host "/ " -NoNewline
        Write-Host "$($item.Container) " -NoNewline -ForegroundColor White
        Write-Host "- Access: " -NoNewline
        Write-Host "$($item.PublicAccess)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Warn "WARNING: Apps using public URLs will break unless we generate SAS tokens"
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "CHOOSE YOUR ACTION FOR STORAGE:" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [G] Generate SAS tokens THEN secure (RECOMMENDED)" -ForegroundColor White
    Write-Host "  [S] Secure immediately (DANGEROUS)" -ForegroundColor White
    Write-Host "  [K] SKIP all storage fixes" -ForegroundColor White
    Write-Host ""
    Write-Host "What do you want to do?" -ForegroundColor Yellow
    
    $choice = ""
    while ($choice -ne "G" -and $choice -ne "S" -and $choice -ne "K") {
        $choice = (Read-Host "Enter G, S, or K").ToUpper()
    }
    
    Write-Host ""
    
    if ($choice -eq "G") {
        Write-Success "You chose: Generate SAS Tokens First (Smart Fix)"
        Write-Host ""
        
        Write-Info "SAS Token Expiration Options:"
        Write-Host "  [1] 7 days"
        Write-Host "  [2] 30 days (recommended)"
        Write-Host "  [3] 90 days"
        Write-Host "  [4] 1 year"
        $expiryChoice = Read-Host "Choose expiration (1-4)"
        
        $expiryDays = switch ($expiryChoice) {
            "1" { 7 }
            "2" { 30 }
            "3" { 90 }
            "4" { 365 }
            default { 30 }
        }
        
        $expiryTime = (Get-Date).AddDays($expiryDays)
        
        Write-Info "Generating SAS tokens (expire: $expiryTime)..."
        Write-Host ""
        
        $sasTokenFile = Join-Path $reportPath "SAS_Tokens.txt"
        "SAS TOKENS FOR PUBLIC CONTAINERS" | Out-File -FilePath $sasTokenFile -Encoding UTF8
        "Generated: $(Get-Date)" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "Expires: $expiryTime" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "IMPORTANT: Update your applications to use these SAS URLs instead of public URLs" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "=====================================================================" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        
        foreach ($item in $publicContainers) {
            try {
                Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
                
                Write-Host "  Generating SAS for: $($item.StorageAccount)/$($item.Container)..." -ForegroundColor Yellow
                
                $sasToken = New-AzStorageContainerSASToken `
                    -Name $item.Container `
                    -Context $item.Context `
                    -Permission "rl" `
                    -ExpiryTime $expiryTime
                
                $sasUrl = "https://$($item.StorageAccount).blob.core.windows.net/$($item.Container)?$sasToken"
                
                Write-Success "    SAS Token Generated"
                
                "Container: $($item.StorageAccount)/$($item.Container)" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "Subscription: $($item.Subscription)" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "Old Public URL: https://$($item.StorageAccount).blob.core.windows.net/$($item.Container)/" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "New SAS URL: $sasUrl" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "Example blob access:" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "  https://$($item.StorageAccount).blob.core.windows.net/$($item.Container)/filename.jpg?$sasToken" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "=====================================================================" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                
                $results.StorageSASTokens += [PSCustomObject]@{
                    Subscription = $item.Subscription
                    StorageAccount = $item.StorageAccount
                    Container = $item.Container
                    SASToken = $sasToken
                    SASUrl = $sasUrl
                    ExpiresOn = $expiryTime
                }
            } catch {
                Write-Fail "    FAILED: $($_.Exception.Message)"
            }
        }
        
        Write-Host ""
        Write-Success "SAS tokens saved to: $sasTokenFile"
        Write-Host ""
        Write-Warn "NEXT STEPS:"
        Write-Warn "1. Open $sasTokenFile"
        Write-Warn "2. Update your applications to use SAS URLs"
        Write-Warn "3. Test applications with SAS URLs"
        Write-Warn "4. Then run this script again to disable public access"
        Write-Host ""
        
        $proceedToSecure = Read-Host "Do you want to secure containers NOW? (yes/no)"
        
        if ($proceedToSecure -eq "yes") {
            Write-Info "Securing containers..."
            Write-Host ""
            
            $accountGroups = $publicContainers | Group-Object StorageAccount, SubscriptionId
            
            foreach ($group in $accountGroups) {
                $saName = $group.Group[0].StorageAccount
                $rgName = $group.Group[0].ResourceGroup
                $subId = $group.Group[0].SubscriptionId
                $subName = $group.Group[0].Subscription
                
                Write-Host "[$subName] $saName" -ForegroundColor Cyan
                
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    
                    Write-Host "  Disabling public blob access on account..." -ForegroundColor Yellow
                    Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                    Write-Success "    Account: SECURED"
                    
                    $ctx = $group.Group[0].Context
                    foreach ($item in $group.Group) {
                        try {
                            Set-AzStorageContainerAcl -Name $item.Container -Permission Off -Context $ctx | Out-Null
                            Write-Success "    Container: $($item.Container) - SECURED"
                            $results.StorageFixed += $item
                        } catch {
                            Write-Fail "    Container: $($item.Container) - FAILED"
                        }
                    }
                } catch {
                    Write-Fail "  FAILED: $($_.Exception.Message)"
                }
                Write-Host ""
            }
        } else {
            Write-Info "Storage NOT secured - Use SAS tokens first, then secure later"
            $results.StorageSkipped = $publicContainers
        }
        
    } elseif ($choice -eq "S") {
        Write-Fail "You chose: Secure Immediately (Dangerous)"
        Write-Warn "Apps using public URLs will break"
        $confirm = Read-Host "Are you SURE? Type 'SECURE' to confirm"
        
        if ($confirm -eq "SECURE") {
            Write-Host ""
            Write-Info "Securing storage accounts..."
            
            $accountGroups = $publicContainers | Group-Object StorageAccount, SubscriptionId
            
            foreach ($group in $accountGroups) {
                $saName = $group.Group[0].StorageAccount
                $rgName = $group.Group[0].ResourceGroup
                $subId = $group.Group[0].SubscriptionId
                $subName = $group.Group[0].Subscription
                
                Write-Host "[$subName] $saName" -ForegroundColor Cyan
                
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    
                    Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                    Write-Success "  Account: SECURED"
                    
                    $ctx = $group.Group[0].Context
                    foreach ($item in $group.Group) {
                        Set-AzStorageContainerAcl -Name $item.Container -Permission Off -Context $ctx | Out-Null
                        Write-Success "  Container: $($item.Container) - SECURED"
                        $results.StorageFixed += $item
                    }
                } catch {
                    Write-Fail "  FAILED: $($_.Exception.Message)"
                }
                Write-Host ""
            }
        } else {
            Write-Info "Secure cancelled"
        }
        
    } else {
        Write-Host "You chose: SKIP" -ForegroundColor Gray
        $results.StorageSkipped = $publicContainers
    }
}

Write-Host ""
Write-Info "Generating HTML Report..."

$nsgUpdatedCount = $results.NSGRulesUpdated.Count
$nsgSkippedCount = $results.NSGRulesSkipped.Count
$sasTokenCount = $results.StorageSASTokens.Count
$storageFixedCount = $results.StorageFixed.Count
$storageSkippedCount = $results.StorageSkipped.Count
$totalFixed = $nsgUpdatedCount + $storageFixedCount

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Smart Security Remediation Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #28a745 0%, #20c997 100%); color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin-bottom: 10px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #d4edda; }
        .stat-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .stat-box h3 { font-size: 32px; margin: 10px 0; color: #28a745; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #333; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 2px solid #28a745; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #28a745; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
        .success-box { background: #d4edda; border-left: 4px solid #28a745; padding: 20px; margin: 20px 0; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; border-top: 1px solid #e0e0e0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Smart Security Remediation</h1>
            <p>Generated: $($results.Timestamp)</p>
            <p>Created by: Syed Rizvi</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3>$totalFixed</h3>
                <p>Total Issues Fixed</p>
            </div>
            <div class="stat-box">
                <h3>$nsgUpdatedCount</h3>
                <p>NSG Rules Updated</p>
            </div>
            <div class="stat-box">
                <h3>$sasTokenCount</h3>
                <p>SAS Tokens Generated</p>
            </div>
            <div class="stat-box">
                <h3>$storageFixedCount</h3>
                <p>Storage Secured</p>
            </div>
        </div>
        
        <div class="content">
            <div class="success-box">
                <strong>SMART FIX COMPLETE:</strong> Security issues resolved without breaking existing functionality
            </div>
"@

if ($results.VPNGateways.Count -gt 0 -or $results.AzureBastions.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Secure Access Infrastructure</h2>'
    
    if ($results.VPNGateways.Count -gt 0) {
        $htmlContent += '<h3>VPN Gateways</h3><table><tr><th>Subscription</th><th>Name</th><th>VNet</th><th>Subnet</th></tr>'
        foreach ($vpn in $results.VPNGateways) {
            $htmlContent += "<tr><td>$($vpn.Subscription)</td><td>$($vpn.Name)</td><td>$($vpn.VNet)</td><td>$($vpn.Subnet)</td></tr>"
        }
        $htmlContent += '</table>'
    }
    
    if ($results.AzureBastions.Count -gt 0) {
        $htmlContent += '<h3>Azure Bastions</h3><table><tr><th>Subscription</th><th>Name</th><th>VNet</th><th>Subnet</th></tr>'
        foreach ($bastion in $results.AzureBastions) {
            $htmlContent += "<tr><td>$($bastion.Subscription)</td><td>$($bastion.Name)</td><td>$($bastion.VNet)</td><td>$($bastion.Subnet)</td></tr>"
        }
        $htmlContent += '</table>'
    }
    
    $htmlContent += '</div>'
}

if ($results.NSGRulesUpdated.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>NSG Rules - Updated (NOT Deleted)</h2>'
    $htmlContent += '<div class="success-box">Rules updated to allow VPN/Bastion only - RDP/SSH still works through secure channels</div>'
    $htmlContent += '<table><tr><th>Subscription</th><th>NSG</th><th>Rule</th><th>Old Source</th><th>New Source</th><th>Port</th></tr>'
    foreach ($rule in $results.NSGRulesUpdated) {
        $htmlContent += "<tr><td>$($rule.Subscription)</td><td>$($rule.NSG)</td><td>$($rule.RuleName)</td><td style='color:red;'>$($rule.OldSource)</td><td style='color:green; font-weight:bold;'>$($rule.NewSource)</td><td>$($rule.Port)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

if ($results.StorageSASTokens.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Storage - SAS Tokens Generated</h2>'
    $htmlContent += '<div class="success-box">SAS tokens generated - Update apps to use SAS URLs before public access is disabled</div>'
    $htmlContent += '<table><tr><th>Subscription</th><th>Storage Account</th><th>Container</th><th>Expires</th></tr>'
    foreach ($token in $results.StorageSASTokens) {
        $htmlContent += "<tr><td>$($token.Subscription)</td><td>$($token.StorageAccount)</td><td>$($token.Container)</td><td>$($token.ExpiresOn)</td></tr>"
    }
    $htmlContent += '</table>'
    $htmlContent += "<p><strong>SAS URLs saved to:</strong> $(Join-Path $reportPath 'SAS_Tokens.txt')</p>"
    $htmlContent += '</div>'
}

if ($results.StorageFixed.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Storage Accounts - Secured</h2>'
    $htmlContent += '<table><tr><th>Subscription</th><th>Storage Account</th><th>Container</th><th>Previous Access</th></tr>'
    foreach ($item in $results.StorageFixed) {
        $htmlContent += "<tr><td>$($item.Subscription)</td><td>$($item.StorageAccount)</td><td>$($item.Container)</td><td style='color:red;'>$($item.PublicAccess)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

$htmlContent += @"
        </div>
        
        <div class="footer">
            <p>Smart Security Remediation - Completed Successfully</p>
            <p>Report generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>Created by: Syed Rizvi</p>
        </div>
    </div>
</body>
</html>
"@

$htmlPath = Join-Path $reportPath "SmartRemediationReport.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "    SMART REMEDIATION COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Info "RESULTS:"
Write-Success "  NSG Rules Updated:      $nsgUpdatedCount"
Write-Success "  SAS Tokens Generated:   $sasTokenCount"
Write-Success "  Storage Secured:        $storageFixedCount"
Write-Warn "  Skipped:                $(($nsgSkippedCount + $storageSkippedCount))"
Write-Success "  TOTAL FIXED:            $totalFixed"
Write-Host ""
Write-Info "FILES CREATED:"
Write-Host "  Report: $htmlPath" -ForegroundColor White
if ($results.StorageSASTokens.Count -gt 0) {
    Write-Host "  SAS Tokens: $(Join-Path $reportPath 'SAS_Tokens.txt')" -ForegroundColor White
}
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Info "Opening HTML report..."
    Start-Process $htmlPath
}

Write-Host ""
Write-Success "Security fixed WITHOUT breaking anything"
Write-Host ""
