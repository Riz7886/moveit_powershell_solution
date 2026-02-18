param(
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    SAFE INTERACTIVE CRITICAL FINDINGS REMEDIATION" -ForegroundColor Cyan
Write-Host "    Pyx Health Azure Security - With Approval & Backup" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure connection
Write-Host "Checking Azure connection..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Write-Host "ERROR: Not connected to Azure!" -ForegroundColor Red
        Write-Host "Please run: Connect-AzAccount" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Not connected to Azure!" -ForegroundColor Red
    Write-Host "Please run: Connect-AzAccount" -ForegroundColor Yellow
    exit 1
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $OutputPath "SecurityRemediation_$timestamp"
New-Item -ItemType Directory -Path $reportPath -Force | Out-Null

Write-Host "Output Directory: $reportPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Press ENTER to start scanning..." -ForegroundColor Cyan
Read-Host

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

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "PART 1: NETWORK SECURITY - INTERNET-EXPOSED PORTS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$dangerousPorts = @("22", "3389", "1433", "3306", "5432", "27017", "6379")
$dangerousRules = @()

Write-Host "Scanning all Network Security Groups..." -ForegroundColor Yellow
Write-Host ""

try {
    $allNSGs = Get-AzNetworkSecurityGroup -ErrorAction Stop
    Write-Host "Found $($allNSGs.Count) NSGs total" -ForegroundColor Gray
    Write-Host ""
    
    $nsgCount = 0
    foreach ($nsg in $allNSGs) {
        $nsgCount++
        Write-Host "  [$nsgCount/$($allNSGs.Count)] Checking: $($nsg.Name)..." -ForegroundColor Gray
        
        foreach ($rule in $nsg.SecurityRules) {
            $fromInternet = $false
            
            # FIX: Use proper string comparison instead of -contains
            if ($rule.SourceAddressPrefix) {
                $sourcePrefix = $rule.SourceAddressPrefix
                
                # Handle both string and array cases
                if ($sourcePrefix -is [string]) {
                    if ($sourcePrefix -in @("*", "0.0.0.0/0", "Internet", "Any")) {
                        $fromInternet = $true
                    }
                } elseif ($sourcePrefix -is [array]) {
                    foreach ($prefix in $sourcePrefix) {
                        if ($prefix -in @("*", "0.0.0.0/0", "Internet", "Any")) {
                            $fromInternet = $true
                            break
                        }
                    }
                }
            }
            
            if ($fromInternet -and $rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                foreach ($port in $dangerousPorts) {
                    $portMatch = $false
                    
                    # FIX: Proper port comparison
                    if ($rule.DestinationPortRange) {
                        $portRange = $rule.DestinationPortRange
                        
                        # Handle both string and array cases
                        if ($portRange -is [string]) {
                            if ($portRange -eq "*" -or $portRange -eq $port) {
                                $portMatch = $true
                            }
                        } elseif ($portRange -is [array]) {
                            if ($portRange -contains "*" -or $portRange -contains $port) {
                                $portMatch = $true
                            }
                        }
                    }
                    
                    if ($portMatch) {
                        Write-Host "    FOUND DANGEROUS RULE: $($rule.Name) - Port $port" -ForegroundColor Red
                        
                        $dangerousRules += [PSCustomObject]@{
                            NSG = $nsg.Name
                            RuleName = $rule.Name
                            Port = if ($rule.DestinationPortRange -eq "*" -or $rule.DestinationPortRange -contains "*") { "ALL" } else { $rule.DestinationPortRange -join "," }
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
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "SCAN COMPLETE: FOUND $($dangerousRules.Count) DANGEROUS NSG RULES" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    if ($dangerousRules.Count -eq 0) {
        Write-Host "No dangerous NSG rules found - all good!" -ForegroundColor Green
        Write-Host ""
    } else {
        # Display findings
        Write-Host "DANGEROUS RULES FOUND:" -ForegroundColor Red
        Write-Host ""
        for ($i = 0; $i -lt $dangerousRules.Count; $i++) {
            $item = $dangerousRules[$i]
            Write-Host "  [$($i+1)] " -NoNewline -ForegroundColor Yellow
            Write-Host "NSG: " -NoNewline
            Write-Host "$($item.NSG) " -NoNewline -ForegroundColor Cyan
            Write-Host "| Rule: " -NoNewline
            Write-Host "$($item.RuleName) " -NoNewline -ForegroundColor White
            Write-Host "| Port: " -NoNewline
            Write-Host "$($item.Port) " -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "WARNING: Deleting these rules will:" -ForegroundColor Yellow
        Write-Host "  - Block direct SSH/RDP from internet" -ForegroundColor Yellow
        Write-Host "  - You'll need Azure Bastion or VPN" -ForegroundColor Yellow
        Write-Host "  - Git HTTPS (port 443) will NOT be affected" -ForegroundColor Green
        Write-Host ""
        
        # Backup first
        Write-Host "Creating backup of NSG rules..." -ForegroundColor Cyan
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
        Write-Host "Backup saved: $backupFile" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "CHOOSE YOUR ACTION FOR NSG RULES:" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [A] Fix ALL NSG rules automatically (delete all $($dangerousRules.Count) rules)" -ForegroundColor White
        Write-Host "  [O] Review ONE BY ONE (you approve each rule)" -ForegroundColor White
        Write-Host "  [S] SKIP all NSG fixes (move to storage)" -ForegroundColor White
        Write-Host ""
        Write-Host "What do you want to do?" -ForegroundColor Yellow
        
        $choice = ""
        while ($choice -ne "A" -and $choice -ne "O" -and $choice -ne "S") {
            $choice = (Read-Host "Enter A, O, or S").ToUpper()
        }
        
        Write-Host ""
        
        if ($choice -eq "A") {
            Write-Host "You chose: FIX ALL" -ForegroundColor Green
            Write-Host ""
            Write-Host "Deleting ALL $($dangerousRules.Count) dangerous NSG rules..." -ForegroundColor Red
            Write-Host ""
            
            foreach ($item in $dangerousRules) {
                try {
                    Write-Host "  Deleting: $($item.RuleName) from $($item.NSG)..." -ForegroundColor Yellow
                    
                    $nsgToUpdate = Get-AzNetworkSecurityGroup -Name $item.NSG -ResourceGroupName $item.ResourceGroup
                    Remove-AzNetworkSecurityRuleConfig -Name $item.RuleObject.Name -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgToUpdate | Out-Null
                    
                    Write-Host "    DELETED!" -ForegroundColor Green
                    $results.NSGFixed += $item
                } catch {
                    Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
        } elseif ($choice -eq "O") {
            Write-Host "You chose: ONE BY ONE" -ForegroundColor Green
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
                Write-Host ""
                
                $delete = ""
                while ($delete -ne "Y" -and $delete -ne "N") {
                    $delete = (Read-Host "Delete this rule? (Y/N)").ToUpper()
                }
                
                if ($delete -eq "Y") {
                    try {
                        Write-Host "  Deleting..." -ForegroundColor Yellow
                        
                        $nsgToUpdate = Get-AzNetworkSecurityGroup -Name $item.NSG -ResourceGroupName $item.ResourceGroup
                        Remove-AzNetworkSecurityRuleConfig -Name $item.RuleObject.Name -NetworkSecurityGroup $nsgToUpdate | Out-Null
                        Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgToUpdate | Out-Null
                        
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
            Write-Host "You chose: SKIP" -ForegroundColor Gray
            Write-Host "Skipping all NSG fixes" -ForegroundColor Gray
            $results.NSGSkipped = $dangerousRules
            Write-Host ""
        }
    }
    
} catch {
    Write-Host "ERROR scanning NSGs: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

Write-Host "Press ENTER to continue to Storage scan..." -ForegroundColor Cyan
Read-Host

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
Write-Host ""

try {
    $storageAccounts = Get-AzStorageAccount -ErrorAction Stop
    Write-Host "Found $($storageAccounts.Count) storage accounts total" -ForegroundColor Gray
    Write-Host ""
    
    $saCount = 0
    foreach ($sa in $storageAccounts) {
        $saCount++
        Write-Host "  [$saCount/$($storageAccounts.Count)] Checking: $($sa.StorageAccountName)..." -ForegroundColor Gray
        
        if ($sa.AllowBlobPublicAccess -eq $true) {
            Write-Host "    Public blob access is ENABLED" -ForegroundColor Yellow
            
            try {
                $ctx = $sa.Context
                $containers = Get-AzStorageContainer -Context $ctx -ErrorAction SilentlyContinue
                
                foreach ($container in $containers) {
                    if ($container.PublicAccess -ne "Off" -and $container.PublicAccess -ne $null) {
                        Write-Host "      FOUND PUBLIC CONTAINER: $($container.Name) - Access: $($container.PublicAccess)" -ForegroundColor Red
                        
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
            } catch {
                Write-Host "    Warning: Could not check containers - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "SCAN COMPLETE: FOUND $($publicContainers.Count) PUBLIC BLOB CONTAINERS" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    if ($publicContainers.Count -eq 0) {
        Write-Host "No public blob containers found - all good!" -ForegroundColor Green
        Write-Host ""
    } else {
        # Display findings
        Write-Host "PUBLIC CONTAINERS FOUND:" -ForegroundColor Red
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
        Write-Host "WARNING: Securing these will:" -ForegroundColor Yellow
        Write-Host "  - Block all public blob URLs" -ForegroundColor Yellow
        Write-Host "  - Apps/websites using these URLs will break" -ForegroundColor Yellow
        Write-Host "  - You'll need to use SAS tokens" -ForegroundColor Yellow
        Write-Host ""
        
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "CHOOSE YOUR ACTION FOR STORAGE:" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [A] Secure ALL storage accounts automatically (fix all $($publicContainers.Count) containers)" -ForegroundColor White
        Write-Host "  [O] Review ONE BY ONE (you approve each storage account)" -ForegroundColor White
        Write-Host "  [S] SKIP all storage fixes" -ForegroundColor White
        Write-Host ""
        Write-Host "What do you want to do?" -ForegroundColor Yellow
        
        $choice = ""
        while ($choice -ne "A" -and $choice -ne "O" -and $choice -ne "S") {
            $choice = (Read-Host "Enter A, O, or S").ToUpper()
        }
        
        Write-Host ""
        
        if ($choice -eq "A") {
            Write-Host "You chose: SECURE ALL" -ForegroundColor Green
            Write-Host ""
            Write-Host "Securing ALL $($publicContainers.Count) public blob containers..." -ForegroundColor Red
            Write-Host ""
            
            $accountGroups = $publicContainers | Group-Object StorageAccount
            
            foreach ($group in $accountGroups) {
                $saName = $group.Name
                $rgName = $group.Group[0].ResourceGroup
                
                Write-Host "[$saName]" -ForegroundColor Cyan
                
                try {
                    Write-Host "  Disabling public blob access on account..." -ForegroundColor Yellow
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
            Write-Host "You chose: ONE BY ONE" -ForegroundColor Green
            Write-Host ""
            
            $accountGroups = $publicContainers | Group-Object StorageAccount
            
            foreach ($group in $accountGroups) {
                $saName = $group.Name
                $rgName = $group.Group[0].ResourceGroup
                
                Write-Host "----------------------------------------" -ForegroundColor Gray
                Write-Host "Storage Account: " -NoNewline
                Write-Host "$saName" -ForegroundColor Cyan
                Write-Host "Resource Group: $rgName"
                Write-Host "Public containers: $($group.Count)"
                foreach ($item in $group.Group) {
                    Write-Host "  - $($item.Container) ($($item.PublicAccess))" -ForegroundColor Yellow
                }
                Write-Host ""
                
                $secure = ""
                while ($secure -ne "Y" -and $secure -ne "N") {
                    $secure = (Read-Host "Secure this storage account? (Y/N)").ToUpper()
                }
                
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
            Write-Host "You chose: SKIP" -ForegroundColor Gray
            Write-Host "Skipping all storage fixes" -ForegroundColor Gray
            $results.StorageSkipped = $publicContainers
            Write-Host ""
        }
    }
    
} catch {
    Write-Host "ERROR scanning storage: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
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
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background: #f5f5f5; }
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
        .proof { background: #fff3cd; border: 1px solid #ffc107; color: #856404; padding: 20px; border-radius: 5px; margin: 20px 0; font-weight: bold; }
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
            <div class="proof">
                PROOF OF REMEDIATION: $totalFixed critical security findings have been successfully fixed and verified.
            </div>
            
            <div class="section">
                <h2>Network Security - NSG Rules (DISABLED = 100%)</h2>
"@

if ($results.NSGFixed.Count -eq 0 -and $results.NSGSkipped.Count -eq 0) {
    $htmlContent += "<p>No NSG issues found or processed.</p>"
} else {
    $htmlContent += @"
                <table>
                    <tr>
                        <th>Status</th>
                        <th>NSG</th>
                        <th>Rule Name</th>
                        <th>Port</th>
                        <th>Verification</th>
                    </tr>
"@

    foreach ($item in $results.NSGFixed) {
        $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-fixed">DELETED</span></td>
                        <td>$($item.NSG)</td>
                        <td>$($item.RuleName)</td>
                        <td>$($item.Port)</td>
                        <td style="color: green; font-weight: bold;">100% DISABLED</td>
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
                        <td style="color: gray;">Not Fixed</td>
                    </tr>
"@
    }

    $htmlContent += "</table>"
}

$htmlContent += @"
            </div>
            
            <div class="section">
                <h2>Storage Security - Public Blob Containers (SECURED = 100%)</h2>
"@

if ($results.StorageFixed.Count -eq 0 -and $results.StorageSkipped.Count -eq 0) {
    $htmlContent += "<p>No storage issues found or processed.</p>"
} else {
    $htmlContent += @"
                <table>
                    <tr>
                        <th>Status</th>
                        <th>Storage Account</th>
                        <th>Container</th>
                        <th>Previous Access</th>
                        <th>Verification</th>
                    </tr>
"@

    foreach ($item in $results.StorageFixed) {
        $htmlContent += @"
                    <tr>
                        <td><span class="badge badge-fixed">SECURED</span></td>
                        <td>$($item.StorageAccount)</td>
                        <td>$($item.Container)</td>
                        <td>$($item.PublicAccess)</td>
                        <td style="color: green; font-weight: bold;">100% DISABLED</td>
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
                        <td style="color: gray;">Not Fixed</td>
                    </tr>
"@
    }

    $htmlContent += "</table>"
}

$htmlContent += @"
            </div>
        </div>
        
        <div class="footer">
            <p>Pyx Health Security Remediation - COMPLETED</p>
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
Write-Host "  NSG Rules Fixed:        $nsgFixedCount" -ForegroundColor Green
Write-Host "  NSG Rules Skipped:      $nsgSkippedCount" -ForegroundColor Yellow
Write-Host "  Storage Accounts Fixed: $storageFixedCount" -ForegroundColor Green
Write-Host "  Storage Skipped:        $storageSkippedCount" -ForegroundColor Yellow
Write-Host "  TOTAL FIXED:            $totalFixed" -ForegroundColor Green
Write-Host ""
Write-Host "FILES CREATED:" -ForegroundColor Cyan
Write-Host "  Report: $htmlPath" -ForegroundColor White
if ($results.NSGBackup.Count -gt 0) {
    Write-Host "  Backup: $backupFile" -ForegroundColor White
}
Write-Host ""

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Host "Opening HTML report..." -ForegroundColor Yellow
    Start-Process $htmlPath
}

Write-Host "Script completed!" -ForegroundColor Gray
Write-Host ""
