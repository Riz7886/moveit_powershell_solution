$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AZURE SECURITY AUDIT - CISCO ANYCONNECT COMPATIBLE" -ForegroundColor Cyan
Write-Host "  Created by: Syed Rizvi" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Write-Host "Connecting to Azure..." -ForegroundColor Yellow
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot connect to Azure" -ForegroundColor Red
    exit 1
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$desktop = [Environment]::GetFolderPath("Desktop")
$outputFolder = Join-Path $desktop "SecurityAudit_$timestamp"
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

Write-Host "Output: $outputFolder" -ForegroundColor Cyan
Write-Host ""

$subscriptions = Get-AzSubscription
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

Write-Host "NOTE: Cisco AnyConnect/Secure Client is NOT an Azure resource" -ForegroundColor Yellow
Write-Host "We will detect the VPN IP range from existing NSG rules" -ForegroundColor Yellow
Write-Host ""

$vpnRanges = @()
$publicStorage = @()
$badNSG = @()

Write-Host "Scanning NSG rules to find Cisco VPN IP ranges..." -ForegroundColor Cyan
$dangerPorts = @("22","3389","1433","3306","5432")

foreach ($sub in $subscriptions) {
    Write-Host "  Checking: $($sub.Name)" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $nsgs = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue
    foreach ($nsg in $nsgs) {
        foreach ($rule in $nsg.SecurityRules) {
            $src = $rule.SourceAddressPrefix
            
            if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                if ($src -ne "*" -and $src -ne "0.0.0.0/0" -and $src -ne "Internet" -and $src -ne "VirtualNetwork") {
                    if ($src -match '^\d+\.\d+\.\d+\.\d+/\d+$') {
                        if ($vpnRanges -notcontains $src) {
                            $vpnRanges += $src
                            Write-Host "    Found IP range in NSG: $src" -ForegroundColor Green
                        }
                    }
                }
            }
            
            if (($src -eq "*" -or $src -eq "0.0.0.0/0" -or $src -eq "Internet") -and 
                $rule.Direction -eq "Inbound" -and 
                $rule.Access -eq "Allow") {
                
                $ports = $rule.DestinationPortRange
                foreach ($port in $dangerPorts) {
                    if ($ports -contains $port -or $ports -contains "*") {
                        Write-Host "    DANGEROUS: $($nsg.Name) - $($rule.Name) - Port $port" -ForegroundColor Red
                        
                        $badNSG += [PSCustomObject]@{
                            Subscription = $sub.Name
                            NSG = $nsg.Name
                            Rule = $rule.Name
                            Port = $port
                            ResourceGroup = $nsg.ResourceGroupName
                        }
                        break
                    }
                }
            }
        }
    }
}

Write-Host ""
Write-Host "VPN IP Ranges Found: $($vpnRanges.Count)" -ForegroundColor $(if($vpnRanges.Count -gt 0){"Green"}else{"Yellow"})
if ($vpnRanges.Count -gt 0) {
    foreach ($r in $vpnRanges) {
        Write-Host "  - $r" -ForegroundColor Green
    }
}
Write-Host "Dangerous Rules: $($badNSG.Count)" -ForegroundColor $(if($badNSG.Count -gt 0){"Red"}else{"Green"})
Write-Host ""

Write-Host "Scanning for public storage..." -ForegroundColor Cyan
foreach ($sub in $subscriptions) {
    Write-Host "  Checking: $($sub.Name)" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $storageAccounts = Get-AzStorageAccount -ErrorAction SilentlyContinue
    foreach ($sa in $storageAccounts) {
        try {
            $ctx = $sa.Context
            $containers = Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue
            
            foreach ($c in $containers) {
                if ($c.PublicAccess -ne "Off") {
                    Write-Host "    PUBLIC: $($sa.StorageAccountName)/$($c.Name)" -ForegroundColor Red
                    
                    $publicStorage += [PSCustomObject]@{
                        Subscription = $sub.Name
                        StorageAccount = $sa.StorageAccountName
                        Container = $c.Name
                        Access = $c.PublicAccess
                        ResourceGroup = $sa.ResourceGroupName
                    }
                }
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "Public Containers: $($publicStorage.Count)" -ForegroundColor $(if($publicStorage.Count -gt 0){"Red"}else{"Green"})
Write-Host ""

Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "SUMMARY" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "VPN IP Ranges:    $($vpnRanges.Count)" -ForegroundColor $(if($vpnRanges.Count -gt 0){"Green"}else{"Yellow"})
Write-Host "Public Storage:   $($publicStorage.Count)" -ForegroundColor $(if($publicStorage.Count -gt 0){"Red"}else{"Green"})
Write-Host "Bad NSG Rules:    $($badNSG.Count)" -ForegroundColor $(if($badNSG.Count -gt 0){"Red"}else{"Green"})
Write-Host ""

if ($vpnRanges.Count -eq 0) {
    Write-Host "NOTE: No VPN IP ranges detected in NSG rules" -ForegroundColor Yellow
    Write-Host "You may need to provide your Cisco VPN IP range manually" -ForegroundColor Yellow
    Write-Host ""
}

$vpnRanges | ForEach-Object { 
    [PSCustomObject]@{IPRange = $_} 
} | Export-Csv -Path (Join-Path $outputFolder "VPN_IP_Ranges.csv") -NoTypeInformation

$publicStorage | Export-Csv -Path (Join-Path $outputFolder "Public_Storage.csv") -NoTypeInformation
$badNSG | Export-Csv -Path (Join-Path $outputFolder "Dangerous_NSG_Rules.csv") -NoTypeInformation

$html = @"
<html>
<head><title>Security Audit</title>
<style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1200px;margin:0 auto;background:white;padding:30px}
.header{background:#dc3545;color:white;padding:30px;margin:-30px -30px 30px -30px}
h1{margin:0;font-size:32px}
.stat{display:inline-block;width:200px;padding:20px;margin:10px;background:#f8f9fa;border-left:4px solid #007bff;text-align:center}
.stat h2{font-size:36px;margin:10px 0;color:#dc3545}
.good{border-left-color:#28a745!important}
.good h2{color:#28a745!important}
.warn{border-left-color:#ffc107!important}
.warn h2{color:#ffc107!important}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#343a40;color:white;padding:12px;text-align:left}
td{padding:12px;border-bottom:1px solid #dee2e6}
tr:nth-child(even){background:#f8f9fa}
.note{background:#fff3cd;padding:15px;margin:20px 0;border-left:4px solid:#ffc107}
</style>
</head>
<body>
<div class="container">
<div class="header"><h1>Azure Security Audit</h1><p>Generated: $(Get-Date)</p><p>By: Syed Rizvi</p></div>
<div class="note"><strong>NOTE:</strong> Using Cisco AnyConnect/Secure Client VPN - IP ranges detected from existing NSG rules</div>
<div class="stat $(if($vpnRanges.Count -gt 0){'good'}else{'warn'})"><h2>$($vpnRanges.Count)</h2><p>VPN IP Ranges</p></div>
<div class="stat"><h2>$($publicStorage.Count)</h2><p>Public Storage</p></div>
<div class="stat"><h2>$($badNSG.Count)</h2><p>Bad NSG Rules</p></div>
"@

if ($vpnRanges.Count -gt 0) {
    $html += "<h2>VPN IP Ranges Detected</h2><table><tr><th>IP Range</th></tr>"
    foreach ($r in $vpnRanges) {
        $html += "<tr><td>$r</td></tr>"
    }
    $html += "</table>"
} else {
    $html += "<div class='note'><strong>No VPN IP ranges detected</strong><br>Cisco AnyConnect VPN is not an Azure resource. You may need to provide the VPN IP range manually when fixing NSG rules.</div>"
}

if ($publicStorage.Count -gt 0) {
    $html += "<h2>Public Storage Containers</h2><table><tr><th>Subscription</th><th>Storage</th><th>Container</th></tr>"
    foreach ($s in $publicStorage) {
        $html += "<tr><td>$($s.Subscription)</td><td>$($s.StorageAccount)</td><td>$($s.Container)</td></tr>"
    }
    $html += "</table>"
}

if ($badNSG.Count -gt 0) {
    $html += "<h2>Dangerous NSG Rules</h2><table><tr><th>Subscription</th><th>NSG</th><th>Rule</th><th>Port</th></tr>"
    foreach ($n in $badNSG) {
        $html += "<tr><td>$($n.Subscription)</td><td>$($n.NSG)</td><td>$($n.Rule)</td><td>$($n.Port)</td></tr>"
    }
    $html += "</table>"
}

$html += "</div></body></html>"

$htmlFile = Join-Path $outputFolder "Report.html"
$html | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host "Report saved: $htmlFile" -ForegroundColor Green
Write-Host ""

Start-Process $htmlFile

Write-Host "DONE" -ForegroundColor Green
Write-Host ""
