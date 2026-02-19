$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PASSWORD NEVER EXPIRES - USER EXPORT" -ForegroundColor Cyan
Write-Host "  For: Tony Schlak" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$env:USERPROFILE\Desktop\PasswordNeverExpires_$timestamp.csv"

Write-Host "Step 1: Connecting to Azure AD..." -ForegroundColor Yellow
Write-Host "  A browser window will open - sign in with your account" -ForegroundColor Gray
Write-Host ""

try {
    Connect-MgGraph -Scopes "User.Read.All" -ErrorAction Stop
    Write-Host "  Connected successfully" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "  ERROR: Failed to connect" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Step 2: Getting all users from Azure AD..." -ForegroundColor Yellow
Write-Host "  Please wait..." -ForegroundColor Gray
Write-Host ""

try {
    $allUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,AccountEnabled,PasswordPolicies,Department,JobTitle,CreatedDateTime,Id
    Write-Host "  Found $($allUsers.Count) total users" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "  ERROR: Failed to get users" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

Write-Host "Step 3: Filtering for DisablePasswordExpiration..." -ForegroundColor Yellow

$filtered = $allUsers | Where-Object {$_.PasswordPolicies -like "*DisablePasswordExpiration*"}

Write-Host "  Found $($filtered.Count) users with password expiration disabled" -ForegroundColor Green
Write-Host ""

if ($filtered.Count -eq 0) {
    Write-Host "No users found with DisablePasswordExpiration" -ForegroundColor Yellow
    Disconnect-MgGraph
    exit 0
}

Write-Host "Step 4: Creating CSV file..." -ForegroundColor Yellow

$results = @()
foreach ($user in $filtered) {
    $results += [PSCustomObject]@{
        'Display Name' = $user.DisplayName
        'User Principal Name' = $user.UserPrincipalName
        'Email' = $user.Mail
        'Account Enabled' = $user.AccountEnabled
        'Password Policy' = $user.PasswordPolicies
        'Department' = $user.Department
        'Job Title' = $user.JobTitle
        'Created' = $user.CreatedDateTime
        'User ID' = $user.Id
    }
}

$results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

Write-Host "  CSV created: $csvFile" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph | Out-Null

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total users with password expiration disabled: $($filtered.Count)" -ForegroundColor White
Write-Host ""
Write-Host "CSV saved to: $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "Opening CSV file..." -ForegroundColor Green
Write-Host ""
Write-Host "Send this file to Tony Schlak" -ForegroundColor Cyan
Write-Host ""
Write-Host "DONE" -ForegroundColor Green
