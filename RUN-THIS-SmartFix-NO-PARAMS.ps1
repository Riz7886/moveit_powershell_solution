$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host $msg -ForegroundColor Red }

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    SMART SECURITY FIX - FULLY AUTOMATED" -ForegroundColor Cyan
Write-Host "    Created by: Syed Rizvi" -ForegroundColor Cyan
Write-Host "    NO PARAMETERS NEEDED - JUST RUN IT" -ForegroundColor Cyan
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
$desktopPath = [Environment]::GetFolderPath("Desktop")
$reportPath = Join-Path $desktopPath "SmartFix_$timestamp"
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
Write-Host "STEP 1: AUTO-DISCOVERING VPN AND BASTION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Scanning ALL subscriptions automatically..."
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
                Write-Success "  FOUND VPN: $($vpn.Name)"
                
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
                        Subnet = $subnetPrefix
                    }
                }
            }
        }
    } catch {}
    
    try {
        $bastions = Get-AzBastion
        foreach ($bastion in $bastions) {
            Write-Success "  FOUND Bastion: $($bastion.Name)"
            
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
                    Subnet = $subnetPrefix
                }
            }
        }
    } catch {}
}

Write-Host ""
Write-Host "DISCOVERY:" -ForegroundColor Yellow
Write-Host "  VPN Gateways:    $($results.VPNGateways.Count)" -ForegroundColor $(if ($results.VPNGateways.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Azure Bastions:  $($results.AzureBastions.Count)" -ForegroundColor $(if ($results.AzureBastions.Count -gt 0) { "Green" } else { "Red" })
Write-Host ""

if ($results.VPNGateways.Count -eq 0 -and $results.AzureBastions.Count -eq 0) {
    Write-Fail "WARNING: NO VPN OR BASTION FOUND"
    Write-Fail "Cannot safely fix NSG rules without secure access"
    Write-Host ""
    
    $proceed = Read-Host "Proceed anyway? (yes/no)"
    if ($proceed -ne "yes") {
        Write-Info "Exiting"
        exit 0
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "STEP 2: AUTO-SCANNING DANGEROUS NSG RULES" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dangerousRules = @()
$dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")

foreach ($subscription in $subscriptions) {
    Write-Info "Scanning: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $nsgs = Get-AzNetworkSecurityGroup
        
        foreach ($nsg in $nsgs) {
            foreach ($rule in $nsg.SecurityRules) {
                if (($rule.SourceAddressPrefix -contains "*" -or $rule.SourceAddressPrefix -contains "0.0.0.0/0") -and 
                    $rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                    
                    $rulePorts = $rule.DestinationPortRange
                    
                    foreach ($port in $dangerousPorts) {
                        if ($rulePorts -contains $port -or $rulePorts -contains "*") {
                            Write-Fail "    FOUND: $($nsg.Name) - $($rule.Name) - Port $port"
                            
                            $dangerousRules += [PSCustomObject]@{
                                Subscription = $subscription.Name
                                SubscriptionId = $subscription.Id
                                NSG = $nsg.Name
                                RuleName = $rule.Name
                                Port = $port
                                ResourceGroup = $nsg.ResourceGroupName
                            }
                            break
                        }
                    }
                }
            }
        }
    } catch {}
}

Write-Host ""
Write-Success "Found $($dangerousRules.Count) dangerous NSG rules"
Write-Host ""

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "STEP 3: AUTO-SCANNING PUBLIC STORAGE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$publicContainers = @()

foreach ($subscription in $subscriptions) {
    Write-Info "Scanning: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $storageAccounts = Get-AzStorageAccount
        
        foreach ($sa in $storageAccounts) {
            try {
                $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
                $containers = Get-AzStorageContainer -Context $saContext -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off") {
                        Write-Fail "    PUBLIC: $($sa.StorageAccountName)/$($container.Name)"
                        
                        $publicContainers += [PSCustomObject]@{
                            Subscription = $subscription.Name
                            SubscriptionId = $subscription.Id
                            StorageAccount = $sa.StorageAccountName
                            Container = $container.Name
                            PublicAccess = $container.PublicAccess
                            ResourceGroup = $sa.ResourceGroupName
                            Context = $saContext
                        }
                    }
                }
            } catch {}
        }
    } catch {}
}

Write-Host ""
Write-Success "Found $($publicContainers.Count) public containers"
Write-Host ""

if ($dangerousRules.Count -eq 0) {
    Write-Success "No dangerous NSG rules - all good"
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "FIX NSG RULES" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Fail "FOUND $($dangerousRules.Count) DANGEROUS NSG RULES"
    Write-Host ""
    
    for ($i = 0; $i -lt $dangerousRules.Count; $i++) {
        $item = $dangerousRules[$i]
        Write-Host "  [$($i+1)] $($item.NSG) - $($item.RuleName) - Port $($item.Port)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    if ($vpnSubnets.Count -gt 0 -or $bastionSubnets.Count -gt 0) {
        Write-Success "VPN/Bastion detected - Will UPDATE rules (not delete)"
        Write-Host ""
        Write-Info "Will allow from:"
        foreach ($subnet in $vpnSubnets) {
            Write-Host "  - VPN: $subnet" -ForegroundColor Green
        }
        foreach ($subnet in $bastionSubnets) {
            Write-Host "  - Bastion: $subnet" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    Write-Host "[U] UPDATE rules to VPN/Bastion only (RECOMMENDED)" -ForegroundColor White
    Write-Host "[D] DELETE rules (DANGEROUS)" -ForegroundColor White
    Write-Host "[S] SKIP" -ForegroundColor White
    Write-Host ""
    
    $choice = ""
    while ($choice -ne "U" -and $choice -ne "D" -and $choice -ne "S") {
        $choice = (Read-Host "Choose U, D, or S").ToUpper()
    }
    
    Write-Host ""
    
    if ($choice -eq "U") {
        Write-Success "Updating rules..."
        Write-Host ""
        
        if ($vpnSubnets.Count -eq 0 -and $bastionSubnets.Count -eq 0) {
            Write-Warn "No VPN/Bastion - Enter company IP range:"
            $companyIP = Read-Host "IP range (e.g., 203.0.113.0/24)"
            $vpnSubnets += $companyIP
        }
        
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
                    
                    Write-Success "    UPDATED"
                    
                    $results.NSGRulesUpdated += [PSCustomObject]@{
                        Subscription = $item.Subscription
                        NSG = $item.NSG
                        RuleName = $item.RuleName
                        NewSource = $allowedSources -join ", "
                        Port = $item.Port
                    }
                }
            } catch {
                Write-Fail "    FAILED: $($_.Exception.Message)"
            }
        }
        
    } elseif ($choice -eq "D") {
        Write-Fail "Deleting rules..."
        
        $confirm = Read-Host "Type DELETE to confirm"
        if ($confirm -eq "DELETE") {
            foreach ($item in $dangerousRules) {
                try {
                    Write-Host "  Deleting: $($item.RuleName)..." -ForegroundColor Yellow
                    
                    Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
                    
                    $nsgToUpdate = Get-AzNetworkSecurityGroup -Name $item.NSG -ResourceGroupName $item.ResourceGroup
                    Remove-AzNetworkSecurityRuleConfig -Name $item.RuleName -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    
                    Write-Success "    DELETED"
                    $results.NSGRulesUpdated += $item
                } catch {
                    Write-Fail "    FAILED"
                }
            }
        }
    } else {
        Write-Host "Skipped" -ForegroundColor Gray
        $results.NSGRulesSkipped = $dangerousRules
    }
}

Write-Host ""
Write-Host "Press ENTER to continue..." -ForegroundColor Cyan
Read-Host

if ($publicContainers.Count -eq 0) {
    Write-Success "No public containers - all good"
} else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "FIX STORAGE" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Fail "FOUND $($publicContainers.Count) PUBLIC CONTAINERS"
    Write-Host ""
    
    for ($i = 0; $i -lt $publicContainers.Count; $i++) {
        $item = $publicContainers[$i]
        Write-Host "  [$($i+1)] $($item.StorageAccount)/$($item.Container)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[G] Generate SAS tokens THEN secure (RECOMMENDED)" -ForegroundColor White
    Write-Host "[S] Secure immediately (DANGEROUS)" -ForegroundColor White
    Write-Host "[K] SKIP" -ForegroundColor White
    Write-Host ""
    
    $choice = ""
    while ($choice -ne "G" -and $choice -ne "S" -and $choice -ne "K") {
        $choice = (Read-Host "Choose G, S, or K").ToUpper()
    }
    
    Write-Host ""
    
    if ($choice -eq "G") {
        Write-Success "Generating SAS tokens..."
        Write-Host ""
        
        Write-Info "Expiration:"
        Write-Host "  [1] 7 days"
        Write-Host "  [2] 30 days (recommended)"
        Write-Host "  [3] 90 days"
        $expiryChoice = Read-Host "Choose 1-3"
        
        $expiryDays = switch ($expiryChoice) {
            "1" { 7 }
            "2" { 30 }
            "3" { 90 }
            default { 30 }
        }
        
        $expiryTime = (Get-Date).AddDays($expiryDays)
        
        $sasTokenFile = Join-Path $reportPath "SAS_Tokens.txt"
        "SAS TOKENS FOR PUBLIC CONTAINERS" | Out-File -FilePath $sasTokenFile -Encoding UTF8
        "Generated: $(Get-Date)" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "Expires: $expiryTime" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
        
        foreach ($item in $publicContainers) {
            try {
                Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
                
                Write-Host "  Generating: $($item.StorageAccount)/$($item.Container)..." -ForegroundColor Yellow
                
                $sasToken = New-AzStorageContainerSASToken `
                    -Name $item.Container `
                    -Context $item.Context `
                    -Permission "rl" `
                    -ExpiryTime $expiryTime
                
                $sasUrl = "https://$($item.StorageAccount).blob.core.windows.net/$($item.Container)?$sasToken"
                
                Write-Success "    DONE"
                
                "Container: $($item.StorageAccount)/$($item.Container)" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "SAS URL: $sasUrl" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                "" | Out-File -FilePath $sasTokenFile -Append -Encoding UTF8
                
                $results.StorageSASTokens += [PSCustomObject]@{
                    Subscription = $item.Subscription
                    StorageAccount = $item.StorageAccount
                    Container = $item.Container
                    SASUrl = $sasUrl
                    ExpiresOn = $expiryTime
                }
            } catch {
                Write-Fail "    FAILED"
            }
        }
        
        Write-Host ""
        Write-Success "SAS tokens saved: $sasTokenFile"
        Write-Host ""
        
        $proceedToSecure = Read-Host "Secure containers NOW? (yes/no)"
        
        if ($proceedToSecure -eq "yes") {
            Write-Info "Securing..."
            
            $accountGroups = $publicContainers | Group-Object StorageAccount, SubscriptionId
            
            foreach ($group in $accountGroups) {
                $saName = $group.Group[0].StorageAccount
                $rgName = $group.Group[0].ResourceGroup
                $subId = $group.Group[0].SubscriptionId
                
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    
                    Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                    Write-Success "  $saName - SECURED"
                    
                    foreach ($item in $group.Group) {
                        $results.StorageFixed += $item
                    }
                } catch {
                    Write-Fail "  $saName - FAILED"
                }
            }
        } else {
            $results.StorageSkipped = $publicContainers
        }
        
    } elseif ($choice -eq "S") {
        Write-Fail "Securing immediately..."
        
        $confirm = Read-Host "Type SECURE to confirm"
        if ($confirm -eq "SECURE") {
            $accountGroups = $publicContainers | Group-Object StorageAccount, SubscriptionId
            
            foreach ($group in $accountGroups) {
                $saName = $group.Group[0].StorageAccount
                $rgName = $group.Group[0].ResourceGroup
                $subId = $group.Group[0].SubscriptionId
                
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    
                    Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                    Write-Success "  $saName - SECURED"
                    
                    foreach ($item in $group.Group) {
                        $results.StorageFixed += $item
                    }
                } catch {
                    Write-Fail "  $saName - FAILED"
                }
            }
        }
    } else {
        Write-Host "Skipped" -ForegroundColor Gray
        $results.StorageSkipped = $publicContainers
    }
}

Write-Host ""
Write-Info "Generating report..."

$htmlPath = Join-Path $reportPath "Report.html"
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Smart Security Fix Report</title>
    <style>
        body { font-family: Arial; margin: 0; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; }
        .header { background: #28a745; color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin: 0; }
        .content { padding: 30px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #28a745; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Smart Security Fix Report</h1>
            <p>Generated: $($results.Timestamp)</p>
            <p>Created by: Syed Rizvi</p>
        </div>
        <div class="content">
            <h2>Results</h2>
            <p>NSG Rules Updated: $($results.NSGRulesUpdated.Count)</p>
            <p>SAS Tokens Generated: $($results.StorageSASTokens.Count)</p>
            <p>Storage Secured: $($results.StorageFixed.Count)</p>
        </div>
    </div>
</body>
</html>
"@

$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "    COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Success "NSG Rules Updated:    $($results.NSGRulesUpdated.Count)"
Write-Success "SAS Tokens Generated: $($results.StorageSASTokens.Count)"
Write-Success "Storage Secured:      $($results.StorageFixed.Count)"
Write-Host ""
Write-Info "Report: $htmlPath"
if ($results.StorageSASTokens.Count -gt 0) {
    Write-Info "SAS Tokens: $(Join-Path $reportPath 'SAS_Tokens.txt')"
}
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Start-Process $htmlPath
}

Write-Host ""
Write-Success "Done"
Write-Host ""
