# AZURE AD AUTHENTICATION DIAGNOSTIC AND FIX TOOL
# Diagnoses and fixes repeated login prompts across PyxHealth subscriptions
# Author: Syed Rizvi
# Date: February 26, 2026

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [switch]$DiagnoseOnly,
    [switch]$AutoFix
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$LogFolder = "C:\Temp\Auth_Fix"
$LogFile = "$LogFolder\Auth_Diagnostic_$timestamp.txt"
$ReportFile = "$LogFolder\Auth_Fix_Report_$timestamp.html"

if (!(Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param($Message, $Color = "White")
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "[$ts] $Message" -ForegroundColor $Color
}

$issues = @()
$fixes = @()

Write-Host ""
Write-Host "======================================================================"
Write-Host "AZURE AD AUTHENTICATION DIAGNOSTIC TOOL"
Write-Host "User: $UserEmail"
Write-Host "======================================================================"
Write-Host ""

# ==============================================================================
# STEP 1: GET USER OBJECT FROM AZURE AD
# ==============================================================================

Write-Log "STEP 1: Retrieving user account information..." "Cyan"

try {
    $user = Get-AzADUser -UserPrincipalName $UserEmail
    
    if (!$user) {
        Write-Log "ERROR: User not found in Azure AD" "Red"
        exit
    }
    
    Write-Log "  User found: $($user.DisplayName)" "Green"
    Write-Log "  User ID: $($user.Id)" "White"
    Write-Log "  Account Enabled: $($user.AccountEnabled)" "White"
    
    if (!$user.AccountEnabled) {
        $issues += "User account is disabled"
    }
    
} catch {
    Write-Log "ERROR: Failed to retrieve user - $($_.Exception.Message)" "Red"
    exit
}

# ==============================================================================
# STEP 2: CHECK MANAGER ATTRIBUTE (Known Issue from Brian's message)
# ==============================================================================

Write-Log ""
Write-Log "STEP 2: Checking manager attribute..." "Cyan"

try {
    $manager = Get-AzADUser -ObjectId $user.Id | Select-Object -ExpandProperty Manager -ErrorAction SilentlyContinue
    
    if ($manager) {
        Write-Log "  Manager set to: $manager" "Green"
    } else {
        Write-Log "  WARNING: Manager attribute is not set" "Yellow"
        $issues += "Manager attribute not configured (can cause authentication loops)"
        
        if ($AutoFix) {
            Write-Log "  Attempting to set manager attribute..." "Yellow"
            # This would need the actual manager's ID
            Write-Log "  Manual action required: Set manager in Azure AD portal" "Yellow"
            $fixes += "Manager attribute needs manual configuration in Azure AD"
        }
    }
} catch {
    Write-Log "  WARNING: Could not retrieve manager attribute" "Yellow"
}

# ==============================================================================
# STEP 3: CHECK USER SIGN-IN ACTIVITY
# ==============================================================================

Write-Log ""
Write-Log "STEP 3: Checking recent sign-in activity..." "Cyan"

try {
    # Get sign-in logs for the user (last 24 hours)
    $signIns = Get-AzureADAuditSignInLogs -Filter "userPrincipalName eq '$UserEmail'" -Top 50 -ErrorAction SilentlyContinue
    
    if ($signIns) {
        $failedSignIns = $signIns | Where-Object { $_.Status.ErrorCode -ne 0 }
        $successfulSignIns = $signIns | Where-Object { $_.Status.ErrorCode -eq 0 }
        
        Write-Log "  Total sign-ins (last 50): $($signIns.Count)" "White"
        Write-Log "  Successful: $($successfulSignIns.Count)" "Green"
        Write-Log "  Failed: $($failedSignIns.Count)" "Yellow"
        
        if ($failedSignIns.Count -gt 0) {
            Write-Log "  Recent failure reasons:" "Yellow"
            $failedSignIns | Select-Object -First 5 | ForEach-Object {
                Write-Log "    - $($_.Status.FailureReason)" "Yellow"
            }
            $issues += "Multiple failed sign-in attempts detected"
        }
        
        # Check for excessive sign-in frequency (authentication loop)
        $recentSignIns = $signIns | Where-Object { $_.CreatedDateTime -gt (Get-Date).AddHours(-1) }
        if ($recentSignIns.Count -gt 20) {
            Write-Log "  WARNING: Excessive sign-ins detected ($($recentSignIns.Count) in last hour)" "Red"
            $issues += "Authentication loop detected - user signing in repeatedly"
        }
    }
} catch {
    Write-Log "  Note: Sign-in logs require Azure AD Premium license" "Yellow"
}

# ==============================================================================
# STEP 4: CHECK CONDITIONAL ACCESS POLICY VIOLATIONS
# ==============================================================================

Write-Log ""
Write-Log "STEP 4: Checking Conditional Access policies..." "Cyan"

try {
    $caPolicies = Get-AzureADMSConditionalAccessPolicy -ErrorAction SilentlyContinue
    
    if ($caPolicies) {
        Write-Log "  Total Conditional Access policies: $($caPolicies.Count)" "White"
        
        $enabledPolicies = $caPolicies | Where-Object { $_.State -eq "enabled" }
        Write-Log "  Enabled policies: $($enabledPolicies.Count)" "White"
        
        # Check if user is in scope for policies requiring MFA
        $mfaPolicies = $enabledPolicies | Where-Object { 
            $_.GrantControls.BuiltInControls -contains "mfa" 
        }
        
        if ($mfaPolicies.Count -gt 0) {
            Write-Log "  MFA-requiring policies: $($mfaPolicies.Count)" "Yellow"
            $issues += "$($mfaPolicies.Count) Conditional Access policies require MFA"
        }
    }
} catch {
    Write-Log "  Note: Could not retrieve Conditional Access policies" "Yellow"
}

# ==============================================================================
# STEP 5: CHECK MFA STATUS
# ==============================================================================

Write-Log ""
Write-Log "STEP 5: Checking MFA configuration..." "Cyan"

try {
    # Check MFA registration status
    $mfaStatus = Get-MsolUser -UserPrincipalName $UserEmail -ErrorAction SilentlyContinue | 
        Select-Object StrongAuthenticationRequirements, StrongAuthenticationMethods
    
    if ($mfaStatus) {
        if ($mfaStatus.StrongAuthenticationRequirements.Count -gt 0) {
            Write-Log "  MFA Status: Enabled and enforced" "Green"
        } else {
            Write-Log "  MFA Status: Not enforced (may be enforced via Conditional Access)" "Yellow"
        }
        
        if ($mfaStatus.StrongAuthenticationMethods.Count -gt 0) {
            Write-Log "  MFA Methods registered: $($mfaStatus.StrongAuthenticationMethods.Count)" "Green"
        } else {
            Write-Log "  WARNING: No MFA methods registered" "Red"
            $issues += "No MFA authentication methods registered"
        }
    }
} catch {
    Write-Log "  Note: MFA status check requires MSOnline module" "Yellow"
}

# ==============================================================================
# STEP 6: CHECK TOKEN/SESSION ISSUES
# ==============================================================================

Write-Log ""
Write-Log "STEP 6: Checking for token/session issues..." "Cyan"

# Check for common token issues
$tokenIssues = @()

# Check token lifetime policies
try {
    $tokenPolicies = Get-AzureADPolicy -ErrorAction SilentlyContinue | 
        Where-Object { $_.Type -eq "TokenLifetimePolicy" }
    
    if ($tokenPolicies.Count -gt 0) {
        Write-Log "  Token lifetime policies found: $($tokenPolicies.Count)" "White"
        foreach ($policy in $tokenPolicies) {
            $definition = $policy.Definition | ConvertFrom-Json
            Write-Log "    Policy: $($policy.DisplayName)" "Gray"
        }
    }
} catch {
    Write-Log "  Could not retrieve token policies" "Yellow"
}

# ==============================================================================
# STEP 7: CHECK APP REGISTRATIONS AND SERVICE PRINCIPALS
# ==============================================================================

Write-Log ""
Write-Log "STEP 7: Checking application assignments..." "Cyan"

try {
    # Get app role assignments for user
    $appAssignments = Get-AzureADUserAppRoleAssignment -ObjectId $user.Id -ErrorAction SilentlyContinue
    
    if ($appAssignments) {
        Write-Log "  Application assignments: $($appAssignments.Count)" "White"
        
        # Check for expired or invalid assignments
        foreach ($assignment in $appAssignments) {
            try {
                $sp = Get-AzureADServicePrincipal -ObjectId $assignment.ResourceId -ErrorAction SilentlyContinue
                if (!$sp) {
                    Write-Log "  WARNING: Assignment to deleted/invalid app: $($assignment.ResourceId)" "Yellow"
                    $issues += "User has assignment to deleted or invalid application"
                }
            } catch {
                # Service principal might be deleted
            }
        }
    }
} catch {
    Write-Log "  Could not retrieve application assignments" "Yellow"
}

# ==============================================================================
# STEP 8: CHECK DATABRICKS SPECIFIC ISSUES
# ==============================================================================

Write-Log ""
Write-Log "STEP 8: Checking Databricks authentication..." "Cyan"

# Databricks often has token/PAT issues
Write-Log "  Checking Databricks workspaces across subscriptions..." "White"

$allSubscriptions = Get-AzSubscription
$databricksWorkspaces = @()

foreach ($sub in $allSubscriptions) {
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    $workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces" -ErrorAction SilentlyContinue
    
    if ($workspaces) {
        $databricksWorkspaces += $workspaces
    }
}

if ($databricksWorkspaces.Count -gt 0) {
    Write-Log "  Databricks workspaces found: $($databricksWorkspaces.Count)" "White"
    Write-Log "  Note: Databricks uses separate authentication tokens" "Yellow"
    $issues += "Databricks requires workspace-specific authentication tokens (PATs)"
}

# ==============================================================================
# STEP 9: RECOMMENDED FIXES
# ==============================================================================

Write-Log ""
Write-Log "======================================================================"
Write-Log "DIAGNOSIS COMPLETE"
Write-Log "======================================================================"
Write-Log ""

if ($issues.Count -eq 0) {
    Write-Log "No issues detected. Authentication should be working normally." "Green"
} else {
    Write-Log "ISSUES DETECTED: $($issues.Count)" "Yellow"
    Write-Log ""
    
    foreach ($issue in $issues) {
        Write-Log "  - $issue" "Yellow"
    }
}

# ==============================================================================
# AUTOMATIC FIXES (if enabled)
# ==============================================================================

if ($AutoFix -and $issues.Count -gt 0) {
    Write-Log ""
    Write-Log "======================================================================"
    Write-Log "APPLYING AUTOMATIC FIXES"
    Write-Log "======================================================================"
    Write-Log ""
    
    # Fix 1: Clear cached credentials
    Write-Log "FIX 1: Clearing cached credentials..." "Cyan"
    try {
        # Clear Azure credential cache
        $azContext = Get-AzContext
        if ($azContext) {
            Clear-AzContext -Force
            Write-Log "  Azure credential cache cleared" "Green"
            $fixes += "Cleared Azure credential cache"
        }
        
        # Clear Windows Credential Manager entries
        cmdkey /list | Select-String "azure|databricks|microsoft" | ForEach-Object {
            $target = $_.Line.Split(" ")[1]
            cmdkey /delete:$target
            Write-Log "  Cleared credential: $target" "Green"
        }
        
    } catch {
        Write-Log "  Could not clear all credentials: $($_.Exception.Message)" "Yellow"
    }
    
    # Fix 2: Force token refresh
    Write-Log ""
    Write-Log "FIX 2: Forcing token refresh..." "Cyan"
    try {
        Disconnect-AzAccount -ErrorAction SilentlyContinue
        Write-Log "  User should re-authenticate on next login" "Green"
        $fixes += "Forced token refresh by clearing session"
    } catch {
        Write-Log "  Note: Token refresh will occur on next login" "Yellow"
    }
    
    # Fix 3: Provide instructions for Databricks
    if ($databricksWorkspaces.Count -gt 0) {
        Write-Log ""
        Write-Log "FIX 3: Databricks authentication fix..." "Cyan"
        Write-Log "  User needs to generate Personal Access Tokens (PATs) for each workspace" "Yellow"
        $fixes += "User should generate new Databricks PATs for each workspace"
    }
}

# ==============================================================================
# GENERATE HTML REPORT
# ==============================================================================

Write-Log ""
Write-Log "Generating diagnostic report..." "Cyan"

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Authentication Diagnostic Report</title>
    <style>
        body { font-family: Calibri, Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #0078d4; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background: #d9d9d9; padding: 10px; text-align: left; border: 1px solid #000; }
        td { padding: 8px; border: 1px solid #000; }
        .issue { background: #fff3cd; padding: 10px; margin: 10px 0; border-left: 4px solid #ffc107; }
        .fix { background: #d4edda; padding: 10px; margin: 10px 0; border-left: 4px solid #28a745; }
        .info { background: #e7f3ff; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>Azure AD Authentication Diagnostic Report</h1>
    <p><strong>User:</strong> $UserEmail</p>
    <p><strong>Report Date:</strong> $timestamp</p>
    <p><strong>Technician:</strong> Syed Rizvi</p>
    
    <h2>User Account Information</h2>
    <table>
        <tr><td>Display Name</td><td>$($user.DisplayName)</td></tr>
        <tr><td>User Principal Name</td><td>$($user.UserPrincipalName)</td></tr>
        <tr><td>Account Enabled</td><td>$($user.AccountEnabled)</td></tr>
        <tr><td>User ID</td><td>$($user.Id)</td></tr>
    </table>
    
    <h2>Issues Detected</h2>
"@

if ($issues.Count -gt 0) {
    foreach ($issue in $issues) {
        $html += "<div class='issue'>$issue</div>"
    }
} else {
    $html += "<div class='info'>No issues detected</div>"
}

$html += "<h2>Recommended Actions</h2>"

$recommendations = @(
    "Clear browser cache and cookies for Azure Portal, Databricks, and Outlook",
    "Sign out completely from all Microsoft services and sign back in",
    "Verify MFA methods are registered and working (https://aka.ms/mfasetup)",
    "For Databricks: Generate new Personal Access Tokens (PATs) in each workspace",
    "Clear Windows Credential Manager entries for Azure and Databricks",
    "Verify manager attribute is set correctly in Azure AD",
    "Contact IT if issue persists after following these steps"
)

foreach ($rec in $recommendations) {
    $html += "<div class='info'>$rec</div>"
}

if ($fixes.Count -gt 0) {
    $html += "<h2>Fixes Applied</h2>"
    foreach ($fix in $fixes) {
        $html += "<div class='fix'>$fix</div>"
    }
}

$html += @"
    <h2>Next Steps for User</h2>
    <ol>
        <li>Close all browser windows</li>
        <li>Clear browser cache (Ctrl+Shift+Delete)</li>
        <li>Restart browser</li>
        <li>Navigate to portal.azure.com and sign in</li>
        <li>Test Databricks Dev and Prod access</li>
        <li>Test Outlook and Data Factory</li>
    </ol>
    
    <p><strong>Support Contact:</strong> Syed Rizvi - IT Infrastructure Team</p>
</body>
</html>
"@

$html | Out-File -FilePath $ReportFile -Encoding UTF8

Write-Log "Report saved: $ReportFile" "Green"
Write-Log ""
Write-Log "======================================================================"
Write-Log "INSTRUCTIONS FOR USER: $UserEmail"
Write-Log "======================================================================"
Write-Log ""
Write-Log "1. Close all browser windows" "Yellow"
Write-Log "2. Clear browser cache (Ctrl+Shift+Delete in Chrome/Edge)" "Yellow"
Write-Log "3. Open Windows Credential Manager (Control Panel)" "Yellow"
Write-Log "4. Remove any Azure/Databricks/Microsoft credentials" "Yellow"
Write-Log "5. Restart your computer" "Yellow"
Write-Log "6. Sign in to Azure Portal fresh" "Yellow"
Write-Log "7. For Databricks, generate new Personal Access Tokens" "Yellow"
Write-Log ""
Write-Log "Report location: $ReportFile" "Green"
Write-Log "Opening report..." "Cyan"

Start-Process $ReportFile

Write-Log ""
Write-Log "Diagnostic complete" "Green"
