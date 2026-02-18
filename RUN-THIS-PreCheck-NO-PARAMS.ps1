$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host $msg -ForegroundColor Red }

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    PRE-CHECK: IMPACT ANALYSIS - FULLY AUTOMATED" -ForegroundColor Cyan
Write-Host "    Created by: Syed Rizvi" -ForegroundColor Cyan
Write-Host "    NO PARAMETERS NEEDED - JUST RUN IT" -ForegroundColor Cyan
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
$desktopPath = [Environment]::GetFolderPath("Desktop")
$reportPath = Join-Path $desktopPath "ImpactAnalysis_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-Info "Output Directory: $reportPath"
Write-Host ""

Write-Info "Discovering ALL Subscriptions automatically..."
$subscriptions = Get-AzSubscription
Write-Success "Found $($subscriptions.Count) subscription(s)"
Write-Host ""
foreach ($sub in $subscriptions) {
    Write-Host "  - $($sub.Name)" -ForegroundColor Gray
}
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
Write-Host "SCANNING ALL SUBSCRIPTIONS FOR VPN AND BASTION" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

foreach ($subscription in $subscriptions) {
    Write-Info "Checking subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    try {
        $vpnGateways = Get-AzVirtualNetworkGateway
        foreach ($vpn in $vpnGateways) {
            if ($vpn.GatewayType -eq "Vpn") {
                Write-Success "  FOUND VPN Gateway: $($vpn.Name)"
                
                $impactReport.VPNGateways += [PSCustomObject]@{
                    Subscription = $subscription.Name
                    Name = $vpn.Name
                    ResourceGroup = $vpn.ResourceGroupName
                }
            }
        }
    } catch {}
    
    try {
        $bastions = Get-AzBastion
        foreach ($bastion in $bastions) {
            Write-Success "  FOUND Azure Bastion: $($bastion.Name)"
            
            $impactReport.AzureBastions += [PSCustomObject]@{
                Subscription = $subscription.Name
                Name = $bastion.Name
                ResourceGroup = $bastion.ResourceGroupName
            }
        }
    } catch {}
}

Write-Host ""
Write-Success "VPN Gateways: $($impactReport.VPNGateways.Count)"
Write-Success "Azure Bastions: $($impactReport.AzureBastions.Count)"
Write-Host ""

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "SCANNING ALL SUBSCRIPTIONS FOR PUBLIC STORAGE" -ForegroundColor Cyan
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
                        Write-Fail "  PUBLIC: $($sa.StorageAccountName)/$($container.Name)"
                        
                        $blobCount = 0
                        try {
                            $blobCount = (Get-AzStorageBlob -Container $container.Name -Context $saContext -ErrorAction SilentlyContinue).Count
                        } catch {}
                        
                        $impactReport.PublicStorageContainers += [PSCustomObject]@{
                            Subscription = $subscription.Name
                            StorageAccount = $sa.StorageAccountName
                            Container = $container.Name
                            ResourceGroup = $sa.ResourceGroupName
                            PublicAccess = $container.PublicAccess
                            BlobCount = $blobCount
                        }
                    }
                }
            } catch {}
        }
    } catch {}
}

Write-Host ""
Write-Success "Public Containers: $($impactReport.PublicStorageContainers.Count)"
Write-Host ""

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "SCANNING ALL SUBSCRIPTIONS FOR DANGEROUS NSG RULES" -ForegroundColor Cyan
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
                            Write-Fail "  DANGEROUS: $($nsg.Name) - $($rule.Name) - Port $port"
                            
                            $portName = switch ($port) {
                                "22" { "SSH" }
                                "3389" { "RDP" }
                                "1433" { "SQL" }
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
Write-Success "Dangerous NSG Rules: $($impactReport.DangerousNSGRules.Count)"
Write-Host ""

Write-Host ""
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host "SCAN COMPLETE" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "FINDINGS:" -ForegroundColor Cyan
Write-Host "  VPN Gateways:               $($impactReport.VPNGateways.Count)" -ForegroundColor $(if ($impactReport.VPNGateways.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Azure Bastions:             $($impactReport.AzureBastions.Count)" -ForegroundColor $(if ($impactReport.AzureBastions.Count -gt 0) { "Green" } else { "Red" })
Write-Host "  Public Storage Containers:  $($impactReport.PublicStorageContainers.Count)" -ForegroundColor $(if ($impactReport.PublicStorageContainers.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Dangerous NSG Rules:        $($impactReport.DangerousNSGRules.Count)" -ForegroundColor $(if ($impactReport.DangerousNSGRules.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Impact Analysis Report</title>
    <style>
        body { font-family: Arial; margin: 0; padding: 0; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; }
        .header { background: #dc3545; color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin: 0; }
        .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; padding: 30px; }
        .stat-box { background: white; padding: 20px; border: 2px solid #ffc107; text-align: center; }
        .stat-box h3 { font-size: 32px; margin: 10px 0; color: #dc3545; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #333; border-bottom: 3px solid #dc3545; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #dc3545; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Security Impact Analysis</h1>
            <p>Generated: $(Get-Date)</p>
            <p>Created by: Syed Rizvi</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3>$($impactReport.VPNGateways.Count)</h3>
                <p>VPN Gateways</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.AzureBastions.Count)</h3>
                <p>Azure Bastions</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.PublicStorageContainers.Count)</h3>
                <p>Public Containers</p>
            </div>
            <div class="stat-box">
                <h3>$($impactReport.DangerousNSGRules.Count)</h3>
                <p>Dangerous Rules</p>
            </div>
        </div>
        
        <div class="content">
"@

if ($impactReport.VPNGateways.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>VPN Gateways Found</h2><table><tr><th>Subscription</th><th>Name</th><th>Resource Group</th></tr>'
    foreach ($vpn in $impactReport.VPNGateways) {
        $htmlContent += "<tr><td>$($vpn.Subscription)</td><td>$($vpn.Name)</td><td>$($vpn.ResourceGroup)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

if ($impactReport.AzureBastions.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Azure Bastions Found</h2><table><tr><th>Subscription</th><th>Name</th><th>Resource Group</th></tr>'
    foreach ($bastion in $impactReport.AzureBastions) {
        $htmlContent += "<tr><td>$($bastion.Subscription)</td><td>$($bastion.Name)</td><td>$($bastion.ResourceGroup)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

if ($impactReport.PublicStorageContainers.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Public Storage Containers</h2><table><tr><th>Subscription</th><th>Storage Account</th><th>Container</th><th>Access Level</th><th>Blob Count</th></tr>'
    foreach ($container in $impactReport.PublicStorageContainers) {
        $htmlContent += "<tr><td>$($container.Subscription)</td><td>$($container.StorageAccount)</td><td>$($container.Container)</td><td>$($container.PublicAccess)</td><td>$($container.BlobCount)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

if ($impactReport.DangerousNSGRules.Count -gt 0) {
    $htmlContent += '<div class="section"><h2>Dangerous NSG Rules</h2><table><tr><th>Subscription</th><th>NSG</th><th>Rule Name</th><th>Port</th><th>Service</th></tr>'
    foreach ($rule in $impactReport.DangerousNSGRules) {
        $htmlContent += "<tr><td>$($rule.Subscription)</td><td>$($rule.NSG)</td><td>$($rule.RuleName)</td><td>$($rule.Port)</td><td>$($rule.PortName)</td></tr>"
    }
    $htmlContent += '</table></div>'
}

$htmlContent += @"
        </div>
    </div>
</body>
</html>
"@

$htmlPath = Join-Path $reportPath "ImpactAnalysis.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

$impactReport.VPNGateways | Export-Csv -Path (Join-Path $reportPath "VPNGateways.csv") -NoTypeInformation
$impactReport.AzureBastions | Export-Csv -Path (Join-Path $reportPath "AzureBastions.csv") -NoTypeInformation
$impactReport.PublicStorageContainers | Export-Csv -Path (Join-Path $reportPath "PublicStorageContainers.csv") -NoTypeInformation
$impactReport.DangerousNSGRules | Export-Csv -Path (Join-Path $reportPath "DangerousNSGRules.csv") -NoTypeInformation

Write-Host "REPORT SAVED:" -ForegroundColor Cyan
Write-Host "  HTML: $htmlPath" -ForegroundColor White
Write-Host "  CSVs: $reportPath" -ForegroundColor White
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Info "Opening report..."
    Start-Process $htmlPath
}

Write-Host ""
Write-Success "Analysis complete"
Write-Host ""
