$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SMART SECURITY FIX - CISCO ANYCONNECT COMPATIBLE" -ForegroundColor Cyan
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
$outputFolder = Join-Path $desktop "SmartFix_$timestamp"
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

$results = @{
    VPNRanges = @()
    NSGFixed = @()
    StorageSAS = @()
    StorageFixed = @()
}

Write-Host "Detecting Cisco VPN IP ranges from NSG rules..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription
$vpnRanges = @()

foreach ($sub in $subscriptions) {
    Write-Host "  $($sub.Name)" -ForegroundColor Gray
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
                            Write-Host "    Found VPN range: $src" -ForegroundColor Green
                        }
                    }
                }
            }
        }
    }
}

Write-Host ""
Write-Host "VPN IP Ranges Found: $($vpnRanges.Count)" -ForegroundColor $(if($vpnRanges.Count -gt 0){"Green"}else{"Yellow"})

if ($vpnRanges.Count -eq 0) {
    Write-Host ""
    Write-Host "Cisco AnyConnect VPN is not an Azure resource" -ForegroundColor Yellow
    Write-Host "Please provide your VPN IP range manually" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Example formats:" -ForegroundColor Cyan
    Write-Host "  10.0.0.0/8" -ForegroundColor Gray
    Write-Host "  172.16.0.0/12" -ForegroundColor Gray
    Write-Host "  192.168.1.0/24" -ForegroundColor Gray
    Write-Host ""
    
    $manual = Read-Host "Enter Cisco VPN IP range (or press ENTER to skip NSG fixes)"
    if ($manual) {
        $vpnRanges += $manual
        Write-Host "Using VPN range: $manual" -ForegroundColor Green
    } else {
        Write-Host "Skipping NSG fixes" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    foreach ($r in $vpnRanges) {
        Write-Host "  - $r" -ForegroundColor Green
    }
}

$results.VPNRanges = $vpnRanges

Write-Host ""
Write-Host "Scanning for dangerous NSG rules..." -ForegroundColor Cyan
$dangerPorts = @("22","3389","1433","3306","5432")
$badRules = @()

foreach ($sub in $subscriptions) {
    Write-Host "  $($sub.Name)" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $nsgs = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue
    foreach ($nsg in $nsgs) {
        foreach ($rule in $nsg.SecurityRules) {
            $src = $rule.SourceAddressPrefix
            if (($src -eq "*" -or $src -eq "0.0.0.0/0" -or $src -eq "Internet") -and 
                $rule.Direction -eq "Inbound" -and 
                $rule.Access -eq "Allow") {
                
                $ports = $rule.DestinationPortRange
                foreach ($port in $dangerPorts) {
                    if ($ports -contains $port -or $ports -contains "*") {
                        Write-Host "    FOUND: $($nsg.Name) - $($rule.Name)" -ForegroundColor Red
                        
                        $badRules += [PSCustomObject]@{
                            SubId = $sub.Id
                            SubName = $sub.Name
                            NSG = $nsg.Name
                            Rule = $rule.Name
                            Port = $port
                            RG = $nsg.ResourceGroupName
                        }
                        break
                    }
                }
            }
        }
    }
}

Write-Host ""
Write-Host "Dangerous Rules: $($badRules.Count)" -ForegroundColor $(if($badRules.Count -gt 0){"Red"}else{"Green"})
Write-Host ""

if ($badRules.Count -gt 0 -and $vpnRanges.Count -gt 0) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "FIX NSG RULES" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i=0; $i -lt $badRules.Count; $i++) {
        Write-Host "  [$($i+1)] $($badRules[$i].NSG) - $($badRules[$i].Rule) - Port $($badRules[$i].Port)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Will UPDATE rules to allow Cisco VPN only:" -ForegroundColor Green
    foreach ($r in $vpnRanges) {
        Write-Host "  - $r" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "[U] UPDATE rules (recommended)" -ForegroundColor White
    Write-Host "[D] DELETE rules (dangerous)" -ForegroundColor White
    Write-Host "[S] SKIP" -ForegroundColor White
    Write-Host ""
    
    $choice = ""
    while ($choice -ne "U" -and $choice -ne "D" -and $choice -ne "S") {
        $choice = (Read-Host "Choose").ToUpper()
    }
    
    if ($choice -eq "U") {
        Write-Host ""
        Write-Host "Updating rules..." -ForegroundColor Yellow
        
        foreach ($r in $badRules) {
            try {
                Write-Host "  $($r.NSG) - $($r.Rule)..." -ForegroundColor Yellow
                
                Set-AzContext -SubscriptionId $r.SubId | Out-Null
                $nsg = Get-AzNetworkSecurityGroup -Name $r.NSG -ResourceGroupName $r.RG
                $rule = $nsg.SecurityRules | Where-Object {$_.Name -eq $r.Rule}
                
                if ($rule) {
                    if ($vpnRanges.Count -eq 1) {
                        $rule.SourceAddressPrefix = $vpnRanges[0]
                    } else {
                        $rule.SourceAddressPrefixes = $vpnRanges
                        $rule.SourceAddressPrefix = $null
                    }
                    
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null
                    Write-Host "    UPDATED" -ForegroundColor Green
                    
                    $results.NSGFixed += $r
                }
            } catch {
                Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    elseif ($choice -eq "D") {
        $conf = Read-Host "Type DELETE to confirm"
        if ($conf -eq "DELETE") {
            Write-Host ""
            foreach ($r in $badRules) {
                try {
                    Write-Host "  Deleting $($r.NSG) - $($r.Rule)..." -ForegroundColor Yellow
                    
                    Set-AzContext -SubscriptionId $r.SubId | Out-Null
                    $nsg = Get-AzNetworkSecurityGroup -Name $r.NSG -ResourceGroupName $r.RG
                    Remove-AzNetworkSecurityRuleConfig -Name $r.Rule -NetworkSecurityGroup $nsg | Out-Null
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null
                    
                    Write-Host "    DELETED" -ForegroundColor Green
                    $results.NSGFixed += $r
                } catch {
                    Write-Host "    FAILED" -ForegroundColor Red
                }
            }
        }
    }
}
elseif ($badRules.Count -gt 0 -and $vpnRanges.Count -eq 0) {
    Write-Host "Cannot fix NSG rules - No VPN IP range available" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press ENTER to continue..." -ForegroundColor Cyan
Read-Host

Write-Host "Scanning for public storage..." -ForegroundColor Cyan
$publicContainers = @()

foreach ($sub in $subscriptions) {
    Write-Host "  $($sub.Name)" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $sas = Get-AzStorageAccount -ErrorAction SilentlyContinue
    foreach ($sa in $sas) {
        try {
            $ctx = $sa.Context
            $containers = Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue
            
            foreach ($c in $containers) {
                if ($c.PublicAccess -ne "Off") {
                    Write-Host "    PUBLIC: $($sa.StorageAccountName)/$($c.Name)" -ForegroundColor Red
                    
                    $publicContainers += [PSCustomObject]@{
                        SubId = $sub.Id
                        SubName = $sub.Name
                        SA = $sa.StorageAccountName
                        Container = $c.Name
                        Access = $c.PublicAccess
                        RG = $sa.ResourceGroupName
                        Context = $ctx
                    }
                }
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "Public Containers: $($publicContainers.Count)" -ForegroundColor $(if($publicContainers.Count -gt 0){"Red"}else{"Green"})
Write-Host ""

if ($publicContainers.Count -gt 0) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "FIX STORAGE" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i=0; $i -lt $publicContainers.Count; $i++) {
        Write-Host "  [$($i+1)] $($publicContainers[$i].SA)/$($publicContainers[$i].Container)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[G] Generate SAS tokens first (recommended)" -ForegroundColor White
    Write-Host "[S] Secure immediately (dangerous)" -ForegroundColor White
    Write-Host "[K] SKIP" -ForegroundColor White
    Write-Host ""
    
    $choice = ""
    while ($choice -ne "G" -and $choice -ne "S" -and $choice -ne "K") {
        $choice = (Read-Host "Choose").ToUpper()
    }
    
    if ($choice -eq "G") {
        Write-Host ""
        Write-Host "Expiration: [1] 7 days  [2] 30 days  [3] 90 days" -ForegroundColor Cyan
        $exp = Read-Host "Choose"
        $days = switch($exp) { "1" {7} "2" {30} "3" {90} default {30} }
        $expiry = (Get-Date).AddDays($days)
        
        Write-Host ""
        Write-Host "Generating SAS tokens..." -ForegroundColor Yellow
        
        $sasFile = Join-Path $outputFolder "SAS_Tokens.txt"
        "SAS TOKENS FOR PYX HEALTH STORAGE" | Out-File -FilePath $sasFile -Encoding UTF8
        "Generated: $(Get-Date)" | Out-File -FilePath $sasFile -Append
        "Expires: $expiry" | Out-File -FilePath $sasFile -Append
        "" | Out-File -FilePath $sasFile -Append
        
        foreach ($c in $publicContainers) {
            try {
                Set-AzContext -SubscriptionId $c.SubId | Out-Null
                
                Write-Host "  $($c.SA)/$($c.Container)..." -ForegroundColor Yellow
                
                $sas = New-AzStorageContainerSASToken -Name $c.Container -Context $c.Context -Permission "rl" -ExpiryTime $expiry
                $url = "https://$($c.SA).blob.core.windows.net/$($c.Container)?$sas"
                
                Write-Host "    DONE" -ForegroundColor Green
                
                "$($c.SA)/$($c.Container)" | Out-File -FilePath $sasFile -Append
                "URL: $url" | Out-File -FilePath $sasFile -Append
                "" | Out-File -FilePath $sasFile -Append
                
                $results.StorageSAS += $c
            } catch {
                Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Write-Host "SAS tokens saved: $sasFile" -ForegroundColor Green
        Write-Host ""
        
        $secure = Read-Host "Secure containers now? (yes/no)"
        if ($secure -eq "yes") {
            Write-Host ""
            $groups = $publicContainers | Group-Object SA,SubId
            foreach ($g in $groups) {
                $sa = $g.Group[0].SA
                $rg = $g.Group[0].RG
                $sid = $g.Group[0].SubId
                
                try {
                    Set-AzContext -SubscriptionId $sid | Out-Null
                    Set-AzStorageAccount -ResourceGroupName $rg -Name $sa -AllowBlobPublicAccess $false | Out-Null
                    Write-Host "  $sa - SECURED" -ForegroundColor Green
                    
                    foreach ($c in $g.Group) {
                        $results.StorageFixed += $c
                    }
                } catch {
                    Write-Host "  $sa - FAILED" -ForegroundColor Red
                }
            }
        }
    }
    elseif ($choice -eq "S") {
        $conf = Read-Host "Type SECURE to confirm"
        if ($conf -eq "SECURE") {
            Write-Host ""
            $groups = $publicContainers | Group-Object SA,SubId
            foreach ($g in $groups) {
                $sa = $g.Group[0].SA
                $rg = $g.Group[0].RG
                $sid = $g.Group[0].SubId
                
                try {
                    Set-AzContext -SubscriptionId $sid | Out-Null
                    Set-AzStorageAccount -ResourceGroupName $rg -Name $sa -AllowBlobPublicAccess $false | Out-Null
                    Write-Host "  $sa - SECURED" -ForegroundColor Green
                    
                    foreach ($c in $g.Group) {
                        $results.StorageFixed += $c
                    }
                } catch {
                    Write-Host "  $sa - FAILED" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "VPN Ranges Used: $($results.VPNRanges.Count)" -ForegroundColor Green
Write-Host "NSG Rules Fixed: $($results.NSGFixed.Count)" -ForegroundColor Green
Write-Host "SAS Tokens: $($results.StorageSAS.Count)" -ForegroundColor Green
Write-Host "Storage Secured: $($results.StorageFixed.Count)" -ForegroundColor Green
Write-Host ""

$html = @"
<html>
<head><title>Smart Fix Report</title>
<style>body{font-family:Arial;margin:20px}h1{color:#28a745}</style>
</head>
<body>
<h1>Smart Security Fix Report</h1>
<p>Generated: $(Get-Date)</p>
<p>By: Syed Rizvi</p>
<h2>Cisco AnyConnect VPN Compatibility</h2>
<p>VPN IP Ranges Used: $($results.VPNRanges.Count)</p>
<h2>Results</h2>
<p>NSG Rules Fixed: $($results.NSGFixed.Count)</p>
<p>SAS Tokens Generated: $($results.StorageSAS.Count)</p>
<p>Storage Secured: $($results.StorageFixed.Count)</p>
</body>
</html>
"@

$htmlFile = Join-Path $outputFolder "Report.html"
$html | Out-File -FilePath $htmlFile -Encoding UTF8

Write-Host "Report: $htmlFile" -ForegroundColor Green
Write-Host ""

Start-Process $htmlFile

Write-Host "DONE" -ForegroundColor Green
