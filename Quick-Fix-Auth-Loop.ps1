# QUICK FIX: Azure Authentication Loop Issue
# Immediate fix for repeated login prompts
# Author: Syed Rizvi
# Date: February 26, 2026

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail
)

Write-Host ""
Write-Host "======================================================================"
Write-Host "QUICK FIX: Authentication Loop Issue"
Write-Host "User: $UserEmail"
Write-Host "======================================================================"
Write-Host ""

$fixesApplied = 0

# Fix 1: Clear Azure PowerShell context
Write-Host "Fix 1: Clearing Azure PowerShell cached credentials..." -ForegroundColor Cyan
try {
    Clear-AzContext -Force -ErrorAction SilentlyContinue
    Disconnect-AzAccount -ErrorAction SilentlyContinue
    Write-Host "  SUCCESS: Azure credentials cleared" -ForegroundColor Green
    $fixesApplied++
} catch {
    Write-Host "  SKIP: No Azure credentials to clear" -ForegroundColor Yellow
}

# Fix 2: Clear Azure CLI tokens
Write-Host ""
Write-Host "Fix 2: Clearing Azure CLI tokens..." -ForegroundColor Cyan
try {
    az logout 2>$null
    az account clear 2>$null
    Write-Host "  SUCCESS: Azure CLI tokens cleared" -ForegroundColor Green
    $fixesApplied++
} catch {
    Write-Host "  SKIP: Azure CLI not installed or no tokens" -ForegroundColor Yellow
}

# Fix 3: Clear Windows Credential Manager
Write-Host ""
Write-Host "Fix 3: Clearing Windows Credential Manager..." -ForegroundColor Cyan

$credentialsCleared = 0
try {
    # Get list of credentials
    $creds = cmdkey /list | Select-String "Target:"
    
    foreach ($cred in $creds) {
        $targetLine = $cred.Line
        
        # Check if it's Azure/Microsoft/Databricks related
        if ($targetLine -match "azure|microsoft|databricks|login\.windows\.net|graph\.windows\.net") {
            # Extract the target name
            $target = ($targetLine -split "Target: ")[1].Trim()
            
            # Delete the credential
            $result = cmdkey /delete:$target 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Cleared: $target" -ForegroundColor Gray
                $credentialsCleared++
            }
        }
    }
    
    if ($credentialsCleared -gt 0) {
        Write-Host "  SUCCESS: Cleared $credentialsCleared cached credentials" -ForegroundColor Green
        $fixesApplied++
    } else {
        Write-Host "  INFO: No Azure credentials found in Credential Manager" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARNING: Could not clear Credential Manager" -ForegroundColor Yellow
}

# Fix 4: Clear browser cache instructions
Write-Host ""
Write-Host "Fix 4: Browser cache clearing required..." -ForegroundColor Cyan
Write-Host "  USER ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "  1. Close ALL browser windows (Chrome, Edge, Firefox)" -ForegroundColor White
Write-Host "  2. Press Ctrl+Shift+Delete to open Clear browsing data" -ForegroundColor White
Write-Host "  3. Select 'All time' for time range" -ForegroundColor White
Write-Host "  4. Check: Cookies, Cached images and files" -ForegroundColor White
Write-Host "  5. Click 'Clear data'" -ForegroundColor White

# Fix 5: Token refresh
Write-Host ""
Write-Host "Fix 5: Force token refresh on next login..." -ForegroundColor Cyan
Write-Host "  INFO: User will need to re-authenticate completely" -ForegroundColor Yellow
Write-Host "  This is normal and expected" -ForegroundColor Yellow

Write-Host ""
Write-Host "======================================================================"
Write-Host "FIXES APPLIED: $fixesApplied"
Write-Host "======================================================================"
Write-Host ""

# Instructions for Brian
Write-Host "NEXT STEPS FOR: $UserEmail" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMMEDIATE ACTIONS:" -ForegroundColor Yellow
Write-Host "1. Close all applications (Outlook, browsers, Azure Data Studio, etc.)" -ForegroundColor White
Write-Host "2. Clear browser cache (see instructions above)" -ForegroundColor White
Write-Host "3. Restart your computer" -ForegroundColor White
Write-Host ""
Write-Host "AFTER RESTART:" -ForegroundColor Yellow
Write-Host "1. Open browser and go to portal.azure.com" -ForegroundColor White
Write-Host "2. Sign in with: $UserEmail" -ForegroundColor White
Write-Host "3. Complete MFA if prompted" -ForegroundColor White
Write-Host "4. Test each application:" -ForegroundColor White
Write-Host "   - Azure Portal" -ForegroundColor Gray
Write-Host "   - Azure Data Factory" -ForegroundColor Gray
Write-Host "   - Databricks Dev" -ForegroundColor Gray
Write-Host "   - Databricks Prod" -ForegroundColor Gray
Write-Host "   - Outlook" -ForegroundColor Gray
Write-Host ""
Write-Host "DATABRICKS SPECIFIC:" -ForegroundColor Yellow
Write-Host "If Databricks still prompts for login repeatedly:" -ForegroundColor White
Write-Host "1. Go to Databricks workspace" -ForegroundColor White
Write-Host "2. Click your user icon (top right)" -ForegroundColor White
Write-Host "3. Select 'User Settings'" -ForegroundColor White
Write-Host "4. Go to 'Access Tokens' tab" -ForegroundColor White
Write-Host "5. Revoke all old tokens" -ForegroundColor White
Write-Host "6. Generate new Personal Access Token (PAT)" -ForegroundColor White
Write-Host "7. Save the token securely" -ForegroundColor White
Write-Host ""
Write-Host "If issue persists after these steps, run:" -ForegroundColor Yellow
Write-Host "  .\Fix-Azure-Auth-Issue.ps1 -UserEmail $UserEmail -AutoFix" -ForegroundColor White
Write-Host ""
Write-Host "Fix completed. User should follow the steps above." -ForegroundColor Green
Write-Host ""
