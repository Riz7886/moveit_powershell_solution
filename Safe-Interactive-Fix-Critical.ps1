param(
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    SAFE INTERACTIVE CRITICAL FINDINGS REMEDIATION" -ForegroundColor Cyan
Write-Host "    Pyx Health Azure Security - With Approval & Backup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $OutputPath "SecurityRemediation_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-Host "Output Directory: $reportPath" -ForegroundColor Gray
Write-Host ""

# Results tracking
$results = @{
    NSGBackup = @()
    NSGFixed = @()
    NSGSkipped = @()
    StorageFixed = @()
    StorageSkipped = @()
    Timestamp = Get-Date
}

# ================================================================
# PART 1: NETWORK SECURITY - NSG RULES
# ================================================================

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PART 1: NETWORK SECURITY - INTERNET-EXPOSED PORTS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")
$dangerousRules = @()

Write-Host "Scanning all Network Security Groups..." -ForegroundColor Yellow

try {
    $allNSGs = Get-AzNetworkSecurityGroup
    
    foreach ($nsg in $allNSGs) {
        foreach ($rule in $nsg.SecurityRules) {
            $fromInternet = ($rule.SourceAddressPrefix -contains "*" -or 
                            $rule.SourceAddressPrefix -contains "0.0.0.0/0" -or
                            $rule.SourceAddressPrefix -contains "Internet")
            
            if ($fromInternet -and $rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                foreach ($port in $dangerousPorts) {
                    if ($rule.DestinationPortRange -contains $port -or $rule.DestinationPortRange -contains "*") {
                        $dangerousRules += [PSCustomObject]@{
                            NSG = $nsg.Name
                            RuleName = $rule.Name
                            Port = if ($rule.DestinationPortRange -contains "*") { "ALL" } else { $rule.DestinationPortRange -join "," }
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
    
    Write-Host ""
    Write-Host "FOUND $($dangerousRules.Count) DANGEROUS NSG RULES:" -ForegroundColor Red
    Write-Host ""
    
    if ($dangerousRules.Count -gt 0) {
        # Display findings
        for ($i = 0; $i -lt $dangerousRules.Count; $i++) {
            $item = $dangerousRules[$i]
            Write-Host "[$($i+1)/$($dangerousRules.Count)] " -NoNewline -ForegroundColor Yellow
            Write-Host "$($item.NSG) " -NoNewline -ForegroundColor Cyan
            Write-Host "- Rule: " -NoNewline
            Write-Host "$($item.RuleName) " -NoNewline -ForegroundColor White
            Write-Host "- Port: " -NoNewline
            Write-Host "$($item.Port) " -NoNewline -ForegroundColor Red
            Write-Host "($($item.Protocol))"
        }
        
        Write-Host ""
        Write-Host "WARNING: Deleting these rules will:" -ForegroundColor Yellow
        Write-Host "  - Block direct SSH/RDP from internet" -ForegroundColor Yellow
        Write-Host "  - You'll need Azure Bastion or VPN for server access" -ForegroundColor Yellow
        Write-Host "  - HTTPS/HTTP (ports 80/443) will NOT be affected" -ForegroundColor Green
        Write-Host ""
        
        # Backup first
        Write-Host "Step 1: Creating backup of NSG rules..." -ForegroundColor Cyan
        foreach ($item in $dangerousRules) {
            $results.NSGBackup += [PSCustomObject]@{
                NSG = $item.NSG
                RuleName = $item.RuleName
                SourceAddressPrefix = $item.RuleObject.SourceAddressPrefix -join ","
                SourcePortRange = $item.RuleObject.SourcePortRange -join ","
                DestinationAddressPrefix = $item.RuleObject.DestinationAddressPrefix -join ","
                DestinationPortRange = $item.RuleObject.DestinationPortRange -join ","
                Protocol = $item.Protocol
                Direction = $item.RuleObject.Direction
                Priority = $item.Priority
                Access = $item.RuleObject.Access
                ResourceGroup = $item.ResourceGroup
            }
        }
        
        $backupFile = Join-Path $reportPath "NSG_Rules_Backup.csv"
        $results.NSGBackup | Export-Csv -Path $backupFile -NoTypeInformation
        Write-Host "  Backup saved to: $backupFile" -ForegroundColor Green
        Write-Host ""
        
        # Ask for approval
        Write-Host "OPTIONS:" -ForegroundColor Cyan
        Write-Host "  [A] Fix ALL NSG rules automatically" -ForegroundColor White
        Write-Host "  [O] Review and approve ONE BY ONE" -ForegroundColor White
        Write-Host "  [S] SKIP all NSG fixes (move to storage)" -ForegroundColor White
        Write-Host ""
        
        $choice = Read-Host "Enter choice (A/O/S)"
        
        if ($choice -eq "A") {
            Write-Host ""
            Write-Host "Deleting ALL dangerous NSG rules..." -ForegroundColor Red
            Write-Host ""
            
            foreach ($item in $dangerousRules) {
                try {
                    Write-Host "  Deleting: $($item.RuleName) from $($item.NSG)..." -ForegroundColor Yellow
                    Remove-AzNetworkSecurityRuleConfig -Name $item.RuleObject.Name -NetworkSecurityGroup $item.NSGObject | Out-Null
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $item.NSGObject | Out-Null
                    Write-Host "    DELETED!" -ForegroundColor Green
                    
                    $results.NSGFixed += $item
                } catch {
                    Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
        } elseif ($choice -eq "O") {
            Write-Host ""
            Write-Host "Reviewing rules one by one..." -ForegroundColor Cyan
            Write-Host ""
            
            foreach ($item in $dangerousRules) {
                Write-Host "----------------------------------------" -ForegroundColor Gray
                Write-Host "NSG: " -NoNewline
                Write-Host "$($item.NSG)" -ForegroundColor Cyan
                Write-Host "Rule: " -NoNewline
                Write-Host "$($item.RuleName)" -ForegroundColor White
                Write-Host "Port: " -NoNewline
                Write-Host "$($item.Port) " -NoNewline -ForegroundColor Red
                Write-Host "($($item.Protocol))"
                Write-Host "Priority: $($item.Priority)"
                Write-Host ""
                
                $delete = Read-Host "Delete this rule? (Y/N)"
                
                if ($delete -eq "Y") {
                    try {
                        Write-Host "  Deleting..." -ForegroundColor Yellow
                        Remove-AzNetworkSecurityRuleConfig -Name $item.RuleObject.Name -NetworkSecurityGroup $item.NSGObject | Out-Null
                        Set-AzNetworkSecurityGroup -NetworkSecurityGroup $item.NSGObject | Out-Null
                        Write-Host "  DELETED!" -ForegroundColor Green
                        
                        $results.NSGFixed += $item
                    } catch {
                        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  Skipped" -ForegroundColor Gray
                    $results.NSGSkipped += $item
                }
                Write-Host ""
            }
            
        } else {
            Write-Host ""
            Write-Host "Skipping all NSG fixes" -ForegroundColor Gray
            $results.NSGSkipped = $dangerousRules
        }
        
    } else {
        Write-Host "No dangerous NSG rules found!" -ForegroundColor Green
    }
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# ================================================================
# PART 2: STORAGE SECURITY - PUBLIC BLOB CONTAINERS
# ================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PART 2: STORAGE SECURITY - PUBLIC BLOB CONTAINERS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$publicContainers = @()

Write-Host "Scanning all Storage Accounts..." -ForegroundColor Yellow

try {
    $storageAccounts = Get-AzStorageAccount
    
    foreach ($sa in $storageAccounts) {
        Write-Host "  Checking: $($sa.StorageAccountName)..." -ForegroundColor Gray
        
        if ($sa.AllowBlobPublicAccess -eq $true) {
            try {
                $ctx = $sa.Context
                $containers = Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off") {
                        $publicContainers += [PSCustomObject]@{
                            StorageAccount = $sa.StorageAccountName
                            Container = $container.Name
                            PublicAccess = $container.PublicAccess
                            ResourceGroup = $sa.ResourceGroupName
                            SAObject = $sa
                            Context = $ctx
                        }
                    }
                }
            } catch {}
        }
    }
    
    Write-Host ""
    Write-Host "FOUND $($publicContainers.Count) PUBLIC BLOB CONTAINERS:" -ForegroundColor Red
    Write-Host ""
    
    if ($publicContainers.Count -gt 0) {
        # Display findings
        for ($i = 0; $i -lt $publicContainers.Count; $i++) {
            $item = $publicContainers[$i]
            Write-Host "[$($i+1)/$($publicContainers.Count)] " -NoNewline -ForegroundColor Yellow
            Write-Host "$($item.StorageAccount) " -NoNewline -ForegroundColor Cyan
            Write-Host "/ " -NoNewline
            Write-Host "$($item.Container) " -NoNewline -ForegroundColor White
            Write-Host "- Access: " -NoNewline
            Write-Host "$($item.PublicAccess)" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "WARNING: Securing these will:" -ForegroundColor Yellow
        Write-Host "  - Block all public blob URLs" -ForegroundColor Yellow
        Write-Host "  - Apps/websites using these URLs will break" -ForegroundColor Yellow
        Write-Host "  - You'll need to use SAS tokens instead" -ForegroundColor Yellow
        Write-Host ""
        
        # Ask for approval
        Write-Host "OPTIONS:" -ForegroundColor Cyan
        Write-Host "  [A] Secure ALL storage accounts automatically" -ForegroundColor White
        Write-Host "  [O] Review and approve ONE BY ONE" -ForegroundColor White
        Write-Host "  [S] SKIP all storage fixes" -ForegroundColor White
        Write-Host ""
        
        $choice = Read-Host "Enter choice (A/O/S)"
        
        if ($choice -eq "A") {
            Write-Host ""
            Write-Host "Securing ALL public blob containers..." -ForegroundColor Red
            Write-Host ""
            
            $accountGroups = $publicContainers | Group-Object StorageAccount
            
            foreach ($group in $accountGroups) {
                $saName = $group.Name
                $rgName = $group.Group[0].ResourceGroup
                
                Write-Host "[$saName]" -ForegroundColor Cyan
                
                try {
                    Write-Host "  Disabling public blob access..." -ForegroundColor Yellow
                    Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                    Write-Host "    Account: SECURED" -ForegroundColor Green
                    
                    $ctx = $group.Group[0].Context
                    foreach ($item in $group.Group) {
                        try {
                            Set-AzStorageContainerAcl -Name $item.Container -Permission Off -Context $ctx | Out-Null
                            Write-Host "    Container: $($item.Container) - SECURED" -ForegroundColor Green
                            $results.StorageFixed += $item
                        } catch {
                            Write-Host "    Container: $($item.Container) - FAILED" -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
                Write-Host ""
            }
            
        } elseif ($choice -eq "O") {
            Write-Host ""
            Write-Host "Reviewing storage accounts one by one..." -ForegroundColor Cyan
            Write-Host ""
            
            $accountGroups = $publicContainers | Group-Object StorageAccount
            
            foreach ($group in $accountGroups) {
                $saName = $group.Name
                $rgName = $group.Group[0].ResourceGroup
                
                Write-Host "----------------------------------------" -ForegroundColor Gray
                Write-Host "Storage Account: " -NoNewline
                Write-Host "$saName" -ForegroundColor Cyan
                Write-Host "Containers with public access: $($group.Count)"
                foreach ($item in $group.Group) {
                    Write-Host "  - $($item.Container) ($($item.PublicAccess))" -ForegroundColor Yellow
                }
                Write-Host ""
                
                $secure = Read-Host "Secure this storage account? (Y/N)"
                
                if ($secure -eq "Y") {
                    try {
                        Write-Host "  Securing..." -ForegroundColor Yellow
                        Set-AzStorageAccount -ResourceGroupName $rgName -Name $saName -AllowBlobPublicAccess $false | Out-Null
                        Write-Host "  Account: SECURED" -ForegroundColor Green
                        
                        $ctx = $group.Group[0].Context
                        foreach ($item in $group.Group) {
                            Set-AzStorageContainerAcl -Name $item.Container -Permission Off -Context $ctx | Out-Null
                            Write-Host "  Container: $($item.Container) - SECURED" -ForegroundColor Green
                            $results.StorageFixed += $item
                        }
                    } catch {
                        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  Skipped" -ForegroundColor Gray
                    foreach ($item in $group.Group) {
                        $results.StorageSkipped += $item
                    }
                }
                Write-Host ""
            }
            
        } else {
            Write-Host ""
            Write-Host "Skipping all storage fixes" -ForegroundColor Gray
            $results.StorageSkipped = $publicContainers
        }
        
    } else {
        Write-Host "No public blob containers found!" -ForegroundColor Green
    }
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# ================================================================
# GENERATE HTML REPORT
# ================================================================

Write-Host ""
Write-Host "Generating HTML Report..." -ForegroundColor Cyan

$nsgFixedCount = $results.NSGFixed.Count
$nsgSkippedCount = $results.NSGSkipped.Count
$storageFixedCount = $results.StorageFixed.Count
$storageSkippedCount = $results.StorageSkipped.Count
$totalFixed = $nsgFixedCount + $storageFixedCount

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Remediation Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%); color: white; padding: 40px; }
        .header h1 { font-size: 36px; margin-bottom: 10px; }
        .header p { font-size: 16px; opacity: 0.9; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; padding: 30px; background: #f8f9fa; }
        .stat-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .stat-box h3 { font-size: 32px; margin: 10px 0; color: #28a745; }
        .stat-box p { color: #666; font-size: 14px; }
        .content { padding: 30px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #333; margin-bottom: 20px; padding-bottom: 10px; border-bottom: 2px solid #11998e; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #11998e; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 12px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background: #f8f9fa; }
        .badge { padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; display: inline-block; }
        .badge-fixed { background: #28a745; color: white; }
        .badge-skipped { background: #6c757d; color: white; }
        .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; border-top: 1px solid #e0e0e0; }
        .success-msg { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Security Remediation Report</h1>
            <p>Generated: $($results.Timestamp)</p>
            <p>Pyx Health - Critical Findings Remediation</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3>$totalFixed</h3>
                <p>Total Issues Fixed</p>
            </div>
            <div class="stat-box">
                <h3>$nsgFixedCount</h3>
                <p>NSG Rules Deleted</p>
            </div>
            <div class="stat-box">
                <h3>$storageFixedCount</h3>
                <p>Storage Accounts Secured</p>
            </div>
            <div class="stat-box">
                <h3>$($nsgSkippedCount + $storageSkippedCount)</h3>
                <p>Issues Skipped</p>
            </div>
        </div>
        
        <div class="content">
            <div class="success-msg">
                <strong>SUCCESS!</strong> All selected critical findings have been remediated. Your environment is now more secure!
            </div>
            
            <div class="section">
                <h2>Network Security - NSG Rules</h2>
                <table>
                    <tr>
                        <th>Status</th>
                        <th>NSG</th>
                        <th>Rule Name</th>
                        <th>Port</th>
                        <th>Protocol</th>
                    </tr>
"@

foreach ($item in $results.NSGFixed) {
    $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-fixed">FIXED</span></td>
                        <td>$($item.NSG)</td>
                        <td>$($item.RuleName)</td>
                        <td>$($item.Port)</td>
                        <td>$($item.Protocol)</td>
                    </tr>
"@
}

foreach ($item in $results.NSGSkipped) {
    $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-skipped">SKIPPED</span></td>
                        <td>$($item.NSG)</td>
                        <td>$($item.RuleName)</td>
                        <td>$($item.Port)</td>
                        <td>$($item.Protocol)</td>
                    </tr>
"@
}

$htmlContent += @"
                </table>
            </div>
            
            <div class="section">
                <h2>Storage Security - Public Blob Containers</h2>
                <table>
                    <tr>
                        <th>Status</th>
                        <th>Storage Account</th>
                        <th>Container</th>
                        <th>Previous Access</th>
                    </tr>
"@

foreach ($item in $results.StorageFixed) {
    $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-fixed">SECURED</span></td>
                        <td>$($item.StorageAccount)</td>
                        <td>$($item.Container)</td>
                        <td>$($item.PublicAccess)</td>
                    </tr>
"@
}

foreach ($item in $results.StorageSkipped) {
    $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-skipped">SKIPPED</span></td>
                        <td>$($item.StorageAccount)</td>
                        <td>$($item.Container)</td>
                        <td>$($item.PublicAccess)</td>
                    </tr>
"@
}

$htmlContent += @"
                </table>
            </div>
            
            <div class="section">
                <h2>Next Steps</h2>
                <ul style="line-height: 2; margin-left: 20px;">
                    <li><strong>For NSG Rules:</strong> Use Azure Bastion or VPN for server access</li>
                    <li><strong>For Storage:</strong> Generate SAS tokens for applications</li>
                    <li><strong>Backup File:</strong> NSG_Rules_Backup.csv (in output folder)</li>
                    <li><strong>Re-run Audit:</strong> Verify all critical findings are resolved</li>
                </ul>
            </div>
        </div>
        
        <div class="footer">
            <p>Pyx Health Security Remediation</p>
            <p>Report generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        </div>
    </div>
</body>
</html>
"@

$htmlPath = Join-Path $reportPath "RemediationReport.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

# ================================================================
# SUMMARY
# ================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "    REMEDIATION COMPLETE!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "RESULTS:" -ForegroundColor Cyan
Write-Host "  NSG Rules Fixed:       $nsgFixedCount" -ForegroundColor Green
Write-Host "  NSG Rules Skipped:     $nsgSkippedCount" -ForegroundColor Yellow
Write-Host "  Storage Accounts Fixed: $storageFixedCount" -ForegroundColor Green
Write-Host "  Storage Skipped:        $storageSkippedCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "FILES CREATED:" -ForegroundColor Cyan
Write-Host "  HTML Report: $htmlPath" -ForegroundColor White
if ($results.NSGBackup.Count -gt 0) {
    Write-Host "  NSG Backup:  $backupFile" -ForegroundColor White
}
Write-Host ""

# Open report
if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Host "Opening HTML report..." -ForegroundColor Yellow
    Start-Process $htmlPath
}

Write-Host "Remediation completed at: $(Get-Date)" -ForegroundColor Gray
Write-Host ""
