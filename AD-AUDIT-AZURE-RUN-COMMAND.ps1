# ============================================================================
# AD SECURITY AUDIT - AZURE VM RUN COMMAND (NO RDP NEEDED!)
# ============================================================================
# Purpose: Run AD audit ON the DC using Azure VM Run Command
# This executes PowerShell DIRECTLY on the DC - NO network connectivity needed!
# Author: Syed Rizvi
# Date: February 13, 2026
# ============================================================================

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AD SECURITY AUDIT - AZURE VM RUN COMMAND" -ForegroundColor Cyan
Write-Host "  NO RDP, NO VPN, NO NETWORK ISSUES!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

# ============================================================================
# STEP 1: Find Domain Controllers
# ============================================================================

Write-Host "Finding Domain Controllers in Azure..." -ForegroundColor Cyan

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Logging into Azure..." -ForegroundColor Yellow
    az login | Out-Null
    $account = az account show | ConvertFrom-Json
}

Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host ""

$subscriptions = az account list --all 2>$null | ConvertFrom-Json
Write-Host "Scanning $($subscriptions.Count) subscriptions for Domain Controllers..." -ForegroundColor Cyan
Write-Host ""

$allDCs = @()

foreach ($subscription in $subscriptions) {
    if ($subscription.state -ne "Enabled") { continue }
    
    az account set --subscription $subscription.id 2>$null | Out-Null
    $vms = az vm list --subscription $subscription.id 2>$null | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        $isDC = $false
        
        foreach ($pattern in @("dc", "domaincontroller", "ad-", "adds-", "pdc", "bdc")) {
            if ($vm.name -like "*$pattern*") {
                $isDC = $true
                break
            }
        }
        
        if ($vm.tags.Role -eq "DomainController" -or $vm.tags.Type -eq "AD") {
            $isDC = $true
        }
        
        if ($isDC) {
            $allDCs += @{
                Name = $vm.name
                ResourceGroup = $vm.resourceGroup
                Subscription = $subscription.name
                SubscriptionId = $subscription.id
            }
            
            Write-Host "Found DC: $($vm.name) in $($vm.resourceGroup)" -ForegroundColor Green
        }
    }
}

if ($allDCs.Count -eq 0) {
    Write-Host "No Domain Controllers found!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Total Domain Controllers found: $($allDCs.Count)" -ForegroundColor Green
Write-Host ""

# Select first DC
$targetDC = $allDCs[0]

Write-Host "Using Domain Controller: $($targetDC.Name)" -ForegroundColor Cyan
Write-Host "Resource Group: $($targetDC.ResourceGroup)" -ForegroundColor Cyan
Write-Host ""

# Set subscription
az account set --subscription $targetDC.SubscriptionId 2>$null | Out-Null

# ============================================================================
# STEP 2: Create AD Audit Script to Run ON the DC
# ============================================================================

Write-Host "Preparing AD audit script to execute ON the DC..." -ForegroundColor Cyan

$adAuditScript = @'
# Import AD Module
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module GroupPolicy -ErrorAction SilentlyContinue

$output = @{}

try {
    # Get Domain Info
    $domain = Get-ADDomain
    $output.Domain = $domain.DNSRoot
    $output.DomainLevel = $domain.DomainMode
    
    # Get Forest Info
    $forest = Get-ADForest
    $output.ForestLevel = $forest.ForestMode
    
    # Get Password Policy
    $policy = Get-ADDefaultDomainPasswordPolicy
    $output.PasswordPolicy = @{
        MinLength = $policy.MinPasswordLength
        Complexity = $policy.ComplexityEnabled
        MaxAge = $policy.MaxPasswordAge.Days
        History = $policy.PasswordHistoryCount
        ReversibleEncryption = $policy.ReversibleEncryptionEnabled
        LockoutThreshold = $policy.LockoutThreshold
        LockoutDuration = $policy.LockoutDuration.Minutes
    }
    
    # Get All Users
    $allUsers = Get-ADUser -Filter * -Properties Enabled,LastLogonDate,PasswordNeverExpires,PasswordNotRequired
    $output.TotalUsers = $allUsers.Count
    $output.EnabledUsers = ($allUsers | Where-Object { $_.Enabled -eq $true }).Count
    $output.DisabledUsers = ($allUsers | Where-Object { $_.Enabled -eq $false }).Count
    
    # Inactive users (90+ days)
    $inactiveDate = (Get-Date).AddDays(-90)
    $inactiveUsers = $allUsers | Where-Object { 
        $_.Enabled -eq $true -and $_.LastLogonDate -and $_.LastLogonDate -lt $inactiveDate 
    }
    $output.InactiveUsers = $inactiveUsers.Count
    
    # Password never expires
    $neverExpireUsers = $allUsers | Where-Object { 
        $_.Enabled -eq $true -and $_.PasswordNeverExpires -eq $true 
    }
    $output.PasswordNeverExpires = $neverExpireUsers.Count
    
    # No password required
    $noPasswordUsers = $allUsers | Where-Object { 
        $_.Enabled -eq $true -and $_.PasswordNotRequired -eq $true 
    }
    $output.NoPasswordRequired = $noPasswordUsers.Count
    if ($noPasswordUsers.Count -gt 0) {
        $output.NoPasswordRequiredUsers = ($noPasswordUsers | Select-Object -First 5 | ForEach-Object { $_.SamAccountName }) -join ', '
    }
    
    # Get Privileged Users
    $output.PrivilegedUsers = @()
    
    foreach ($groupName in @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators")) {
        try {
            $group = Get-ADGroup -Filter "Name -eq '$groupName'"
            if ($group) {
                $members = Get-ADGroupMember -Identity $group
                $output.PrivilegedUsers += @{
                    Group = $groupName
                    Count = $members.Count
                    Members = ($members | ForEach-Object { $_.SamAccountName }) -join ', '
                }
            }
        } catch {}
    }
    
    # Get All Groups
    $allGroups = Get-ADGroup -Filter *
    $output.TotalGroups = $allGroups.Count
    
    # Empty groups (check first 100)
    $emptyGroupCount = 0
    foreach ($group in ($allGroups | Select-Object -First 100)) {
        $members = Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue
        if (-not $members -or $members.Count -eq 0) {
            $emptyGroupCount++
        }
    }
    $output.EmptyGroups = $emptyGroupCount
    
    # Get All GPOs
    try {
        $allGPOs = Get-GPO -All
        $output.TotalGPOs = $allGPOs.Count
    } catch {
        $output.TotalGPOs = 0
    }
    
    # Get Trusts
    try {
        $trusts = Get-ADTrust -Filter *
        if ($trusts) {
            $output.Trusts = @()
            foreach ($trust in $trusts) {
                $output.Trusts += @{
                    Name = $trust.Name
                    Direction = $trust.Direction
                    Type = $trust.TrustType
                }
            }
        } else {
            $output.Trusts = @()
        }
    } catch {
        $output.Trusts = @()
    }
    
    $output.Success = $true
    
} catch {
    $output.Success = $false
    $output.Error = $_.Exception.Message
}

# Return as JSON
$output | ConvertTo-Json -Depth 10
'@

# Save script to temp file
$tempScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
$adAuditScript | Out-File -FilePath $tempScriptPath -Encoding UTF8

Write-Host "Script created: $tempScriptPath" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 3: Execute Script ON the DC using Azure VM Run Command
# ============================================================================

Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  EXECUTING SCRIPT DIRECTLY ON THE DOMAIN CONTROLLER..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "This may take 30-60 seconds..." -ForegroundColor Cyan
Write-Host ""

try {
    $result = az vm run-command invoke `
        --name $targetDC.Name `
        --resource-group $targetDC.ResourceGroup `
        --command-id RunPowerShellScript `
        --scripts "@$tempScriptPath" `
        --output json 2>$null | ConvertFrom-Json
    
    # Remove temp script
    Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    
    if (-not $result) {
        Write-Host "Failed to execute command on DC!" -ForegroundColor Red
        exit 1
    }
    
    # Extract output
    $scriptOutput = $result.value[0].message
    
    # Parse JSON from output
    $jsonMatch = $scriptOutput | Select-String -Pattern '\{[\s\S]*\}' -AllMatches
    
    if ($jsonMatch.Matches.Count -gt 0) {
        $jsonString = $jsonMatch.Matches[0].Value
        $auditData = $jsonString | ConvertFrom-Json
        
        if ($auditData.Success -eq $false) {
            Write-Host "Error executing audit on DC: $($auditData.Error)" -ForegroundColor Red
            exit 1
        }
        
        # ====================================================================
        # STEP 4: Generate Beautiful HTML Report
        # ====================================================================
        
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  DATA RETRIEVED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "Domain: $($auditData.Domain)" -ForegroundColor Cyan
        Write-Host "Total Users: $($auditData.TotalUsers)" -ForegroundColor Cyan
        Write-Host "Total Groups: $($auditData.TotalGroups)" -ForegroundColor Cyan
        Write-Host "Total GPOs: $($auditData.TotalGPOs)" -ForegroundColor Cyan
        Write-Host ""
        
        # Calculate security score
        $totalChecks = 0
        $passedChecks = 0
        $findings = @{
            Critical = @()
            High = @()
            Medium = @()
            Low = @()
        }
        
        # Password Policy Checks
        $totalChecks++
        if ($auditData.PasswordPolicy.MinLength -ge 12) { $passedChecks++ } else {
            $findings.High += @{
                Title = "Weak Password Length"
                Description = "Minimum password length is $($auditData.PasswordPolicy.MinLength) (recommended: 12+)"
                Recommendation = "Increase minimum password length to 12 characters"
            }
        }
        
        $totalChecks++
        if ($auditData.PasswordPolicy.Complexity) { $passedChecks++ } else {
            $findings.Critical += @{
                Title = "Password Complexity Disabled"
                Description = "Password complexity is not enforced"
                Recommendation = "Enable password complexity immediately"
            }
        }
        
        $totalChecks++
        if ($auditData.PasswordPolicy.LockoutThreshold -gt 0) { $passedChecks++ } else {
            $findings.High += @{
                Title = "No Account Lockout Policy"
                Description = "Account lockout is not configured"
                Recommendation = "Set lockout threshold to 5-10 attempts"
            }
        }
        
        $totalChecks++
        if (-not $auditData.PasswordPolicy.ReversibleEncryption) { $passedChecks++ } else {
            $findings.Critical += @{
                Title = "Reversible Encryption Enabled"
                Description = "Passwords stored with reversible encryption"
                Recommendation = "DISABLE reversible encryption immediately"
            }
        }
        
        # User Checks
        $totalChecks++
        if ($auditData.InactiveUsers -eq 0) { $passedChecks++ } else {
            $findings.Medium += @{
                Title = "Inactive User Accounts"
                Description = "$($auditData.InactiveUsers) users inactive for 90+ days"
                Recommendation = "Disable inactive accounts"
            }
        }
        
        $totalChecks++
        if ($auditData.PasswordNeverExpires -eq 0) { $passedChecks++ } else {
            $findings.High += @{
                Title = "Passwords Never Expire"
                Description = "$($auditData.PasswordNeverExpires) users have non-expiring passwords"
                Recommendation = "Enforce password expiration"
            }
        }
        
        $totalChecks++
        if ($auditData.NoPasswordRequired -eq 0) { $passedChecks++ } else {
            $findings.Critical += @{
                Title = "No Password Required"
                Description = "$($auditData.NoPasswordRequired) users: $($auditData.NoPasswordRequiredUsers)"
                Recommendation = "IMMEDIATELY require passwords for all accounts"
            }
        }
        
        $totalChecks++
        if ($auditData.EmptyGroups -eq 0) { $passedChecks++ } else {
            $findings.Low += @{
                Title = "Empty Groups"
                Description = "$($auditData.EmptyGroups) groups have no members"
                Recommendation = "Remove unused groups"
            }
        }
        
        $securityScore = [math]::Round((($passedChecks / $totalChecks) * 100), 2)
        
        $scoreColor = if ($securityScore -ge 80) { "#27ae60" } 
                      elseif ($securityScore -ge 60) { "#f39c12" } 
                      else { "#e74c3c" }
        
        # Generate HTML Report
        $reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $reportFile = "AD-Security-Audit-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        $duration = (Get-Date) - $startTime
        
        $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Active Directory Security Audit Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-bottom: 2px solid #95a5a6; padding-bottom: 5px; }
        .summary-box { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin: 20px 0; }
        .score-box { background-color: $scoreColor; color: white; padding: 20px; border-radius: 10px; font-size: 48px; font-weight: bold; display: inline-block; margin: 20px 0; }
        .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .stat-box { background-color: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #3498db; }
        .stat-number { font-size: 36px; font-weight: bold; color: #2c3e50; }
        .stat-label { color: #7f8c8d; margin-top: 10px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background-color: #f5f5f5; }
        .finding { border-left: 5px solid; padding: 15px; margin: 15px 0; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .finding-critical { border-left-color: #c0392b; background-color: #fadbd8; }
        .finding-high { border-left-color: #e74c3c; background-color: #f8d7da; }
        .finding-medium { border-left-color: #f39c12; background-color: #fff3cd; }
        .finding-low { border-left-color: #3498db; background-color: #d1ecf1; }
        .badge { padding: 5px 10px; border-radius: 3px; color: white; font-weight: bold; }
        .badge-critical { background-color: #c0392b; }
        .badge-high { background-color: #e74c3c; }
        .badge-medium { background-color: #f39c12; }
        .badge-low { background-color: #3498db; }
        .badge-success { background-color: #27ae60; }
        .badge-warning { background-color: #f39c12; }
        .policy-box { background-color: #e8f5e9; padding: 15px; border-radius: 5px; margin: 10px 0; border-left: 4px solid #27ae60; }
        .timestamp { color: #95a5a6; text-align: right; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Active Directory Security Audit Report</h1>
        <div class="timestamp">Generated: $reportDate | Duration: $($duration.ToString('mm\:ss')) | Method: Azure VM Run Command</div>
        
        <div class="summary-box">
            <h2 style="color: white; border: none;">Executive Summary</h2>
            <div class="score-box">$securityScore%</div>
            <p style="font-size: 18px;">Security Score</p>
            <p><strong>Domain:</strong> $($auditData.Domain)</p>
            <p><strong>Forest Level:</strong> $($auditData.ForestLevel) | <strong>Domain Level:</strong> $($auditData.DomainLevel)</p>
            <p><strong>Total Checks:</strong> $totalChecks | <strong>Passed:</strong> $passedChecks</p>
        </div>
        
        <div class="stats-grid">
            <div class="stat-box">
                <div class="stat-number" style="color: #c0392b;">$($findings.Critical.Count)</div>
                <div class="stat-label">Critical</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #e74c3c;">$($findings.High.Count)</div>
                <div class="stat-label">High</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #f39c12;">$($findings.Medium.Count)</div>
                <div class="stat-label">Medium</div>
            </div>
            <div class="stat-box">
                <div class="stat-number" style="color: #3498db;">$($findings.Low.Count)</div>
                <div class="stat-label">Low</div>
            </div>
        </div>
        
        <h2>Domain Policies</h2>
        
        <h3>Password Policy</h3>
        <div class="policy-box">
            <table>
                <tr><th>Setting</th><th>Value</th><th>Recommended</th><th>Status</th></tr>
                <tr>
                    <td>Min Password Length</td>
                    <td>$($auditData.PasswordPolicy.MinLength) chars</td>
                    <td>12+ chars</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.MinLength -ge 12){'success'}else{'high'})">$(if($auditData.PasswordPolicy.MinLength -ge 12){'GOOD'}else{'WEAK'})</span></td>
                </tr>
                <tr>
                    <td>Complexity</td>
                    <td>$(if($auditData.PasswordPolicy.Complexity){'Enabled'}else{'Disabled'})</td>
                    <td>Enabled</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.Complexity){'success'}else{'critical'})">$(if($auditData.PasswordPolicy.Complexity){'GOOD'}else{'CRITICAL'})</span></td>
                </tr>
                <tr>
                    <td>Max Password Age</td>
                    <td>$($auditData.PasswordPolicy.MaxAge) days</td>
                    <td>60-90 days</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.MaxAge -ge 1 -and $auditData.PasswordPolicy.MaxAge -le 90){'success'}else{'medium'})">$(if($auditData.PasswordPolicy.MaxAge -ge 1 -and $auditData.PasswordPolicy.MaxAge -le 90){'GOOD'}else{'REVIEW'})</span></td>
                </tr>
                <tr>
                    <td>Password History</td>
                    <td>$($auditData.PasswordPolicy.History) passwords</td>
                    <td>12+ passwords</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.History -ge 12){'success'}else{'medium'})">$(if($auditData.PasswordPolicy.History -ge 12){'GOOD'}else{'REVIEW'})</span></td>
                </tr>
                <tr>
                    <td>Reversible Encryption</td>
                    <td>$(if($auditData.PasswordPolicy.ReversibleEncryption){'Enabled - BAD!'}else{'Disabled'})</td>
                    <td>Disabled</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.ReversibleEncryption){'critical'}else{'success'})">$(if($auditData.PasswordPolicy.ReversibleEncryption){'CRITICAL'}else{'GOOD'})</span></td>
                </tr>
            </table>
        </div>
        
        <h3>Account Lockout Policy</h3>
        <div class="policy-box">
            <table>
                <tr><th>Setting</th><th>Value</th><th>Recommended</th><th>Status</th></tr>
                <tr>
                    <td>Lockout Threshold</td>
                    <td>$(if($auditData.PasswordPolicy.LockoutThreshold -eq 0){'Not configured'}else{"$($auditData.PasswordPolicy.LockoutThreshold) attempts"})</td>
                    <td>5-10 attempts</td>
                    <td><span class="badge badge-$(if($auditData.PasswordPolicy.LockoutThreshold -gt 0){'success'}else{'high'})">$(if($auditData.PasswordPolicy.LockoutThreshold -gt 0){'GOOD'}else{'NOT CONFIGURED'})</span></td>
                </tr>
                <tr>
                    <td>Lockout Duration</td>
                    <td>$(if($auditData.PasswordPolicy.LockoutDuration){"$($auditData.PasswordPolicy.LockoutDuration) minutes"}else{"N/A"})</td>
                    <td>15-30 minutes</td>
                    <td><span class="badge badge-success">OK</span></td>
                </tr>
            </table>
        </div>
        
        <h2>User Statistics</h2>
        <table>
            <tr><th>Metric</th><th>Count</th><th>Status</th></tr>
            <tr><td>Total Users</td><td>$($auditData.TotalUsers)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Enabled Users</td><td>$($auditData.EnabledUsers)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Disabled Users</td><td>$($auditData.DisabledUsers)</td><td><span class="badge badge-success">OK</span></td></tr>
            <tr><td>Inactive (90+ days)</td><td>$($auditData.InactiveUsers)</td><td><span class="badge badge-$(if($auditData.InactiveUsers -gt 0){'medium'}else{'success'})">$(if($auditData.InactiveUsers -gt 0){'WARNING'}else{'OK'})</span></td></tr>
            <tr><td>Password Never Expires</td><td>$($auditData.PasswordNeverExpires)</td><td><span class="badge badge-$(if($auditData.PasswordNeverExpires -gt 0){'high'}else{'success'})">$(if($auditData.PasswordNeverExpires -gt 0){'RISK'}else{'OK'})</span></td></tr>
            <tr><td>No Password Required</td><td>$($auditData.NoPasswordRequired)</td><td><span class="badge badge-$(if($auditData.NoPasswordRequired -gt 0){'critical'}else{'success'})">$(if($auditData.NoPasswordRequired -gt 0){'CRITICAL'}else{'OK'})</span></td></tr>
        </table>
        
        <h2>Privileged Users</h2>
        <table>
            <tr><th>Group</th><th>Members</th><th>Count</th></tr>
"@
        
        foreach ($priv in $auditData.PrivilegedUsers) {
            $htmlReport += "            <tr><td>$($priv.Group)</td><td>$($priv.Members)</td><td>$($priv.Count)</td></tr>`n"
        }
        
        $htmlReport += @"
        </table>
        
        <h2>Groups & GPOs</h2>
        <table>
            <tr><th>Metric</th><th>Count</th></tr>
            <tr><td>Total Groups</td><td>$($auditData.TotalGroups)</td></tr>
            <tr><td>Empty Groups</td><td>$($auditData.EmptyGroups)</td></tr>
            <tr><td>Total GPOs</td><td>$($auditData.TotalGPOs)</td></tr>
        </table>
        
        <h2>Trust Relationships</h2>
"@
        
        if ($auditData.Trusts.Count -gt 0) {
            $htmlReport += "        <table>`n            <tr><th>Name</th><th>Direction</th><th>Type</th></tr>`n"
            foreach ($trust in $auditData.Trusts) {
                $htmlReport += "            <tr><td>$($trust.Name)</td><td>$($trust.Direction)</td><td>$($trust.Type)</td></tr>`n"
            }
            $htmlReport += "        </table>`n"
        } else {
            $htmlReport += "        <p>No trust relationships found.</p>`n"
        }
        
        $htmlReport += @"
        
        <h2>Security Findings</h2>
"@
        
        # Critical Findings
        foreach ($finding in $findings.Critical) {
            $htmlReport += @"
        <div class="finding finding-critical">
            <div><span class="badge badge-critical">CRITICAL</span> <strong>$($finding.Title)</strong></div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
        }
        
        # High Findings
        foreach ($finding in $findings.High) {
            $htmlReport += @"
        <div class="finding finding-high">
            <div><span class="badge badge-high">HIGH</span> <strong>$($finding.Title)</strong></div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
        }
        
        # Medium Findings
        foreach ($finding in $findings.Medium) {
            $htmlReport += @"
        <div class="finding finding-medium">
            <div><span class="badge badge-medium">MEDIUM</span> <strong>$($finding.Title)</strong></div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
        }
        
        # Low Findings
        foreach ($finding in $findings.Low) {
            $htmlReport += @"
        <div class="finding finding-low">
            <div><span class="badge badge-low">LOW</span> <strong>$($finding.Title)</strong></div>
            <div>$($finding.Description)</div>
            <div><strong>Recommendation:</strong> $($finding.Recommendation)</div>
        </div>
"@
        }
        
        if (($findings.Critical.Count + $findings.High.Count + $findings.Medium.Count + $findings.Low.Count) -eq 0) {
            $htmlReport += "        <p style='color: green; font-weight: bold; font-size: 18px;'>No security findings! AD environment is healthy!</p>`n"
        }
        
        $htmlReport += @"
        
        <h2>Recommendations</h2>
        <ol>
            <li>Address Critical findings immediately (within 24 hours)</li>
            <li>Review High priority findings (within 1 week)</li>
            <li>Plan remediation for Medium/Low findings</li>
            <li>Run monthly security audits</li>
            <li>Enable MFA for all privileged accounts</li>
            <li>Review and limit privileged group membership (max 3-5 members)</li>
            <li>Disable inactive accounts (90+ days)</li>
            <li>Enforce strong password policies (12+ chars, complexity, expiration)</li>
        </ol>
        
        <div style="background-color: #ecf0f1; padding: 20px; margin-top: 30px; border-radius: 5px;">
            <h3>Audit Summary</h3>
            <p><strong>Domain:</strong> $($auditData.Domain)</p>
            <p><strong>Forest Level:</strong> $($auditData.ForestLevel)</p>
            <p><strong>Domain Level:</strong> $($auditData.DomainLevel)</p>
            <p><strong>Security Score:</strong> <span style="color: $scoreColor; font-weight: bold; font-size: 24px;">$securityScore%</span></p>
            <p><strong>Total Checks:</strong> $totalChecks | <strong>Passed:</strong> $passedChecks</p>
            <p><strong>Duration:</strong> $($duration.ToString('mm\:ss'))</p>
            <p><strong>Method:</strong> Azure VM Run Command (no RDP/VPN required)</p>
        </div>
    </div>
</body>
</html>
"@
        
        # Save HTML report
        $reportPath = Join-Path (Get-Location) $reportFile
        $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8
        
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  AUDIT COMPLETE - MIND BLOWN!" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Security Score: $securityScore%" -ForegroundColor $(if($securityScore -ge 80){"Green"}elseif($securityScore -ge 60){"Yellow"}else{"Red"})
        Write-Host "Critical: $($findings.Critical.Count) | High: $($findings.High.Count) | Medium: $($findings.Medium.Count) | Low: $($findings.Low.Count)" -ForegroundColor White
        Write-Host ""
        Write-Host "Report saved: $reportFile" -ForegroundColor Cyan
        Write-Host "Opening report in browser..." -ForegroundColor Cyan
        Write-Host ""
        
        # Open report
        Start-Process $reportPath
        
    } else {
        Write-Host "Could not parse output from DC!" -ForegroundColor Red
        Write-Host "Raw output:" -ForegroundColor Yellow
        Write-Host $scriptOutput -ForegroundColor White
    }
    
} catch {
    Write-Host "Error executing command on DC: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  DONE - NO RDP, NO VPN, JUST PURE MAGIC!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
