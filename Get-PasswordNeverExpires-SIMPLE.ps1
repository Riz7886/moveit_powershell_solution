$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  EXPORT USERS WITH PASSWORD EXPIRATION DISABLED" -ForegroundColor Cyan
Write-Host "  For: Tony Schlak" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$desktop = [Environment]::GetFolderPath("Desktop")
$csvFile = Join-Path $desktop "PasswordNeverExpires_Users_$timestamp.csv"

Write-Host "Getting all users from Azure AD..." -ForegroundColor Cyan
Write-Host ""

try {
    $allUsers = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,PasswordPolicies,Department,JobTitle,CreatedDateTime
    Write-Host "Retrieved $($allUsers.Count) total users" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Not connected to Azure AD" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run this first:" -ForegroundColor Yellow
    Write-Host "  Connect-MgGraph -Scopes User.Read.All" -ForegroundColor White
    Write-Host ""
    Write-Host "Then run this script again" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Filtering users with DisablePasswordExpiration..." -ForegroundColor Cyan

$usersWithNoExpiry = $allUsers | Where-Object {
    $_.PasswordPolicies -ne $null -and $_.PasswordPolicies -like "*DisablePasswordExpiration*"
}

Write-Host "Found $($usersWithNoExpiry.Count) users with password expiration disabled" -ForegroundColor Green
Write-Host ""

if ($usersWithNoExpiry.Count -eq 0) {
    Write-Host "No users found!" -ForegroundColor Yellow
    exit 0
}

Write-Host "Creating CSV..." -ForegroundColor Cyan

$results = @()

foreach ($user in $usersWithNoExpiry) {
    $results += [PSCustomObject]@{
        'Display Name' = $user.DisplayName
        'User Principal Name' = $user.UserPrincipalName
        'Email' = $user.Mail
        'Account Enabled' = $user.AccountEnabled
        'Password Policy' = $user.PasswordPolicies
        'Department' = $user.Department
        'Job Title' = $user.JobTitle
        'Account Created' = $user.CreatedDateTime
        'User ID' = $user.Id
    }
}

$results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total users: $($usersWithNoExpiry.Count)" -ForegroundColor White
Write-Host ""
Write-Host "CSV file: $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "DONE - Send this CSV to Tony" -ForegroundColor Green
Write-Host ""
