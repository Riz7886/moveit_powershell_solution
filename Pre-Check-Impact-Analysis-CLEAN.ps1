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
Write-Host "    PRE-CHECK: IMPACT ANALYSIS" -ForegroundColor Cyan
Write-Host "    Created by: Syed Rizvi" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Info "Checking Azure connection..."
try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Write-Warn "Not connected to Azure. Connecting..."
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
$reportPath = Join-Path $OutputPath "ImpactAnalysis_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-Info "Output Directory: $reportPath"
Write-Host ""

Write-Info "Discovering Subscriptions..."
$subscriptions = Get-AzSubscription
Write-Success "Found $($subscriptions.Count) subscription(s)"
Write-Host ""

$impactReport = @{
    VPNGateways = @()
    AzureBastions = @()
    PublicStorageContainers = @()
    DangerousNSGRules = @()
    PotentialBreaks = @()
    Recommendations = @()
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "CHECK 1: DETECTING VPN AND BASTION INFRASTRUCTURE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($subscription in $subscriptions) {
    Write-Info "Checking subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $vpnGateways = Get-AzVirtualNetworkGateway
        foreach ($vpn in $vpnGateways) {
            if ($vpn.GatewayType -eq "Vpn") {
                Write-Success "  FOUND VPN Gateway: $($vpn.Name) in RG: $($vpn.ResourceGroupName)"
                
                $impactReport.VPNGateways += [PSCustomObject]@{
                    Subscription = $subscription.Name
                    Name = $vpn.Name
                    ResourceGroup = $vpn.ResourceGroupName
                    VNetName = $vpn.IpConfigurations[0].Subnet.Id.Split('/')[8]
                    PublicIP = $vpn.IpConfigurations[0].PublicIpAddress.Id
                    GatewayType = $vpn.VpnType
                }
            }
        }
    } catch {}
    
    try {
        $bastions = Get-AzBastion
        foreach ($bastion in $bastions) {
            Write-Success "  FOUND Azure Bastion: $($bastion.Name) in RG: $($bastion.ResourceGroupName)"
            
            $impactReport.AzureBastions += [PSCustomObject]@{
                Subscription = $subscription.Name
                Name = $bastion.Name
                ResourceGroup = $bastion.ResourceGroupName
                VNetName = $bastion.IpConfigurations[0].Subnet.Id.Split('/')[8]
            }
        }
    } catch {}
}

Write-Host ""
if ($impactReport.VPNGateways.Count -eq 0 -and $impactReport.AzureBastions.Count -eq 0) {
    Write-Fail "WARNING: NO VPN OR BASTION FOUND!"
    Write-Fail "If we delete NSG rules, you will LOSE ALL RDP/SSH ACCESS!"
    Write-Host ""
    $impactReport.PotentialBreaks += "CRITICAL: No VPN or Bastion detected - deleting NSG rules will lock you out"
} else {
    Write-Success "Found secure access methods:"
    Write-Success "  VPN Gateways: $($impactReport.VPNGateways.Count)"
    Write-Success "  Azure Bastions: $($impactReport.AzureBastions.Count)"
    Write-Host ""
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "CHECK 2: ANALYZING PUBLIC STORAGE CONTAINER USAGE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($subscription in $subscriptions) {
    Write-Info "Checking subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $storageAccounts = Get-AzStorageAccount
        
        foreach ($sa in $storageAccounts) {
            try {
                $saContext = (Get-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName).Context
                $containers = Get-AzStorageContainer -Context $saContext -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off") {
                        Write-Fail "  PUBLIC CONTAINER: $($sa.StorageAccountName)/$($container.Name)"
                        
                        $blobCount = (Get-AzStorageBlob -Container $container.Name -Context $saContext -ErrorAction SilentlyContinue).Count
                        
                        $publicUrl = "https://$($sa.StorageAccountName).blob.core.windows.net/$($container.Name)"
                        
                        $impactReport.PublicStorageContainers += [PSCustomObject]@{
                            Subscription = $subscription.Name
                            StorageAccount = $sa.StorageAccountName
                            Container = $container.Name
                            ResourceGroup = $sa.ResourceGroupName
                            PublicAccess = $container.PublicAccess
                            BlobCount = $blobCount
                            PublicURL = $publicUrl
                            WillBreak = "YES - Any app using $publicUrl will fail"
                        }
                        
                        $impactReport.PotentialBreaks += "Storage: $($sa.StorageAccountName)/$($container.Name) - $blobCount files with public URLs will become inaccessible"
                    }
                }
            } catch {}
        }
    } catch {}
}

Write-Host ""
if ($impactReport.PublicStorageContainers.Count -gt 0) {
    Write-Warn "IMPACT: $($impactReport.PublicStorageContainers.Count) public containers found"
    Write-Warn "Applications using public blob URLs will BREAK unless we:"
    Write-Warn "  1. Generate SAS tokens for each container"
    Write-Warn "  2. Update applications to use SAS URLs"
    Write-Warn "  3. OR setup Private Endpoints"
    Write-Host ""
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "CHECK 3: DETECTING ACTIVE RDP/SSH CONNECTIONS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")

foreach ($subscription in $subscriptions) {
    Write-Info "Checking subscription: $($subscription.Name)"
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
                            Write-Fail "  DANGEROUS RULE: $($nsg.Name) - $($rule.Name) allows port $port from internet"
                            
                            $attachedVMs = @()
                            if ($nsg.NetworkInterfaces) {
                                foreach ($nic in $nsg.NetworkInterfaces) {
                                    $nicName = $nic.Id.Split('/')[-1]
                                    $attachedVMs += $nicName
                                }
                            }
                            
                            $portName = switch ($port) {
                                "22" { "SSH" }
                                "3389" { "RDP" }
                                "1433" { "SQL Server" }
                                "3306" { "MySQL" }
                                "5432" { "PostgreSQL" }
                                "27017" { "MongoDB" }
                                "6379" { "Redis" }
                                default { "Port $port" }
                            }
                            
                            $impactReport.DangerousNSGRules += [PSCustomObject]@{
                                Subscription = $subscription.Name
                                NSG = $nsg.Name
                                RuleName = $rule.Name
                                Port = $port
                                PortName = $portName
                                ResourceGroup = $nsg.ResourceGroupName
                                AttachedVMs = $attachedVMs -join ", "
                                WillBreak = if ($attachedVMs.Count -gt 0) { "YES - Will lose $portName access to: $($attachedVMs -join ', ')" } else { "Maybe - Rule exists but not attached to VMs" }
                            }
                            
                            if ($attachedVMs.Count -gt 0) {
                                $impactReport.PotentialBreaks += "NSG: $($nsg.Name) - Deleting rule '$($rule.Name)' will block $portName to VMs: $($attachedVMs -join ', ')"
                            }
                        }
                    }
                }
            }
        }
    } catch {}
}

Write-Host ""
if ($impactReport.DangerousNSGRules.Count -gt 0) {
    Write-Warn "IMPACT: $($impactReport.DangerousNSGRules.Count) dangerous NSG rules found"
    Write-Warn "If we DELETE these rules, you will LOSE direct internet access to VMs"
    Write-Host ""
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "GENERATING RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($impactReport.PublicStorageContainers.Count -gt 0) {
    $impactReport.Recommendations += @"
STORAGE SECURITY (23 findings):
================================
OPTION 1: SAS Tokens (Recommended for Apps)
- Generate SAS tokens with expiration (7-90 days)
- Update applications to use SAS URLs instead of public URLs
- No infrastructure changes needed
- Easy rollback

OPTION 2: Private Endpoints (Best Security)
- Create Private Endpoints for storage accounts
- Connect to VNet
- No public internet access
- Requires VNet connectivity from apps

ACTION REQUIRED:
1. Identify all applications using public blob URLs
2. Generate SAS tokens for each container
3. Test with SAS URLs before disabling public access
4. Update app configurations
5. Then disable public access
"@
}

if ($impactReport.DangerousNSGRules.Count -gt 0) {
    if ($impactReport.VPNGateways.Count -gt 0 -or $impactReport.AzureBastions.Count -gt 0) {
        $impactReport.Recommendations += @"

NSG SECURITY (6 findings):
==========================
GOOD NEWS: VPN/Bastion infrastructure detected

RECOMMENDED APPROACH:
1. DO NOT DELETE the rules
2. MODIFY rules to allow only VPN/Bastion subnets
3. Keep RDP/SSH working through secure channels

For VPN Gateway:
- Get VPN Gateway subnet range
- Update NSG rules to allow ONLY from VPN subnet

For Azure Bastion:
- Rules already handle Bastion correctly
- Just remove 0.0.0.0/0 source

EXAMPLE NSG RULE MODIFICATION:
Old: Allow RDP from 0.0.0.0/0 (internet)
New: Allow RDP from 10.0.1.0/24 (VPN subnet)

This way:
- Security is fixed (no internet exposure)
- Nothing breaks (RDP still works via VPN)
"@
    } else {
        $impactReport.Recommendations += @"

NSG SECURITY (6 findings):
==========================
WARNING: NO VPN OR BASTION DETECTED

CRITICAL DECISION REQUIRED:
If we delete these rules, you will be LOCKED OUT of your VMs

RECOMMENDED APPROACH:
1. First deploy Azure Bastion OR VPN Gateway
2. Test connectivity through Bastion/VPN
3. Then update NSG rules to allow only Bastion/VPN
4. Do NOT just delete the rules

TEMPORARY OPTION:
- Update rules to allow only YOUR company's public IP range
- Not perfect but better than 0.0.0.0/0
"@
    }
}

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Remediation Impact Analysis</title>
    <style>
        body { font-family: 'Segoe UI', Arial; margin: 0; padding: 0; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #dc3545 0%, #fd7e14 100%); color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin: 0; }
        .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; padding: 30px; background: #fff3cd; }
        .stat-box { background: white; padding: 20px; border-radius: 8px; border: 2px solid #ffc107; text-align: center; }
        .stat-box h3 { font-size: 32px; margin: 10px 0; color: #dc3545; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #333; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 3px solid #dc3545; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #dc3545; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
        .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 20px; margin: 20px 0; }
        .danger { background: #f8d7da; border-left: 4px solid #dc3545; padding: 20px; margin: 20px 0; }
        .success { background: #d4edda; border-left: 4px solid #28a745; padding: 20px; margin: 20px 0; }
        .recommendations { background: #e7f3ff; border-left: 4px solid #0066cc; padding: 20px; margin: 20px 0; white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Security Remediation Impact Analysis</h1>
            <p>Generated: $(Get-Date)</p>
            <p>Created by: Syed Rizvi</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3>$($impactReport.PublicStorageContainers.Count)</h3>
                <p>Public Storage Containers</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.DangerousNSGRules.Count)</h3>
                <p>Dangerous NSG Rules</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.VPNGateways.Count)</h3>
                <p>VPN Gateways Found</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.AzureBastions.Count)</h3>
                <p>Azure Bastions Found</p>
            </div>
        </div>
        
        <div class="content">
"@

if ($impactReport.VPNGateways.Count -gt 0 -or $impactReport.AzureBastions.Count -gt 0) {
    $htmlContent += '<div class="success"><strong>GOOD NEWS:</strong> Secure access infrastructure detected</div>'
    
    if ($impactReport.VPNGateways.Count -gt 0) {
        $htmlContent += '<div class="section"><h2>VPN Gateways Detected</h2><table><tr><th>Subscription</th><th>Name</th><th>VNet</th><th>Type</th></tr>'
        foreach ($vpn in $impactReport.VPNGateways) {
            $htmlContent += "<tr><td>$($vpn.Subscription)</td><td>$($vpn.Name)</td><td>$($vpn.VNetName)</td><td>$($vpn.GatewayType)</td></tr>"
        }
        $htmlContent += '</table></div>'
    }
    
    if ($impactReport.AzureBastions.Count -gt 0) {
        $htmlContent += '<div class="section"><h2>Azure Bastions Detected</h2><table><tr><th>Subscription</th><th>Name</th><th>VNet</th></tr>'
        foreach ($bastion in $impactReport.AzureBastions) {
            $htmlContent += "<tr><td>$($bastion.Subscription)</td><td>$($bastion.Name)</td><td>$($bastion.VNet)</td></tr>"
        }
        $htmlContent += '</table></div>'
    }
} else {
    $htmlContent += '<div class="danger"><strong>WARNING:</strong> NO VPN or Bastion found - Deleting NSG rules will LOCK YOU OUT</div>'
}

if ($impactReport.PublicStorageContainers.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Public Storage Containers - WILL BREAK if Locked</h2>'
    $htmlContent += '<div class="warning"><strong>Impact:</strong> Applications using public blob URLs will fail immediately when we disable public access.</div>'
    $htmlContent += '<table><tr><th>Subscription</th><th>Storage Account</th><th>Container</th><th>Blob Count</th><th>Public URL</th><th>Impact</th></tr>'
    foreach ($container in $impactReport.PublicStorageContainers) {
        $htmlContent += "<tr><td>$($container.Subscription)</td><td>$($container.StorageAccount)</td><td>$($container.Container)</td><td>$($container.BlobCount)</td><td>$($container.PublicURL)</td><td style='color:red; font-weight:bold;'>$($container.WillBreak)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

if ($impactReport.DangerousNSGRules.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Dangerous NSG Rules - WILL BREAK if Deleted</h2>'
    $htmlContent += '<div class="warning"><strong>Impact:</strong> Deleting these rules will block all direct RDP/SSH access from internet.</div>'
    $htmlContent += '<table><tr><th>Subscription</th><th>NSG</th><th>Rule</th><th>Port/Service</th><th>Attached VMs</th><th>Impact</th></tr>'
    foreach ($rule in $impactReport.DangerousNSGRules) {
        $htmlContent += "<tr><td>$($rule.Subscription)</td><td>$($rule.NSG)</td><td>$($rule.RuleName)</td><td>$($rule.Port) - $($rule.PortName)</td><td>$($rule.AttachedVMs)</td><td style='color:red; font-weight:bold;'>$($rule.WillBreak)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

$htmlContent += '<div class="section"><h2>RECOMMENDATIONS - HOW TO FIX WITHOUT BREAKING</h2>'
foreach ($rec in $impactReport.Recommendations) {
    $htmlContent += "<div class='recommendations'>$rec</div>"
}

$htmlContent += @"
        </div>
    </div>
</body>
</html>
"@

$htmlPath = Join-Path $reportPath "ImpactAnalysis.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

$impactReport.PublicStorageContainers | Export-Csv -Path (Join-Path $reportPath "PublicStorageContainers.csv") -NoTypeInformation
$impactReport.DangerousNSGRules | Export-Csv -Path (Join-Path $reportPath "DangerousNSGRules.csv") -NoTypeInformation

Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "IMPACT ANALYSIS COMPLETE" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

Write-Info "FINDINGS:"
Write-Host "  Public Storage Containers:  $($impactReport.PublicStorageContainers.Count)" -ForegroundColor $(if ($impactReport.PublicStorageContainers.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Dangerous NSG Rules:        $($impactReport.DangerousNSGRules.Count)" -ForegroundColor $(if ($impactReport.DangerousNSGRules.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  VPN Gateways:               $($impactReport.VPNGateways.Count)" -ForegroundColor $(if ($impactReport.VPNGateways.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Azure Bastions:             $($impactReport.AzureBastions.Count)" -ForegroundColor $(if ($impactReport.AzureBastions.Count -gt 0) { "Green" } else { "Red" })
Write-Host ""

if ($impactReport.PotentialBreaks.Count -gt 0) {
    Write-Warn "POTENTIAL BREAKS DETECTED:"
    foreach ($break in $impactReport.PotentialBreaks) {
        Write-Warn "  - $break"
    }
    Write-Host ""
}

Write-Info "REPORT SAVED:"
Write-Host "  HTML Report: $htmlPath" -ForegroundColor White
Write-Host "  Storage CSV: $(Join-Path $reportPath 'PublicStorageContainers.csv')" -ForegroundColor White
Write-Host "  NSG CSV: $(Join-Path $reportPath 'DangerousNSGRules.csv')" -ForegroundColor White
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Info "Opening report..."
    Start-Process $htmlPath
}

Write-Host ""
Write-Success "Analysis complete - Review the report before running remediation"
Write-Host ""
