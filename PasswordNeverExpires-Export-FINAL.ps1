Import-Module AzureAD

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PASSWORD EXPIRATION DISABLED - USER EXPORT" -ForegroundColor Cyan
Write-Host "  For: Tony Schlak" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "C:\Users\$env:USERNAME\Desktop\PasswordNeverExpires_$timestamp.csv"

Write-Host "Connecting to Azure AD..." -ForegroundColor Yellow

try {
    $connection = Connect-AzureAD -ErrorAction Stop
    Write-Host "  Connected to tenant: $($connection.TenantDomain)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "  ERROR: Failed to connect" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Retrieving all users from Azure AD..." -ForegroundColor Yellow
Write-Host "  This may take 1-2 minutes..." -ForegroundColor Gray
Write-Host ""

$allUsers = Get-AzureADUser -All $true

Write-Host "  Retrieved $($allUsers.Count) total users" -ForegroundColor Green
Write-Host ""

Write-Host "Filtering for users with password expiration disabled..." -ForegroundColor Yellow

$filteredUsers = @()

foreach ($user in $allUsers) {
    if ($user.PasswordPolicies) {
        if ($user.PasswordPolicies.ToString() -match "DisablePasswordExpiration") {
            $filteredUsers += $user
        }
    }
}

Write-Host "  Found $($filteredUsers.Count) users with password never expires" -ForegroundColor Green
Write-Host ""

if ($filteredUsers.Count -eq 0) {
    Write-Host "ERROR: No users found with DisablePasswordExpiration!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host "  1. No users have this setting enabled" -ForegroundColor White
    Write-Host "  2. Policy name might be different in your tenant" -ForegroundColor White
    Write-Host ""
    
    Write-Host "Exporting first 10 users with their PasswordPolicies for review:" -ForegroundColor Yellow
    $allUsers | Select-Object -First 10 DisplayName,UserPrincipalName,PasswordPolicies | Format-Table -AutoSize
    
    exit 1
}

Write-Host "Creating CSV export..." -ForegroundColor Yellow

$results = @()

foreach ($user in $filteredUsers) {
    $results += [PSCustomObject]@{
        'Display Name' = $user.DisplayName
        'User Principal Name' = $user.UserPrincipalName
        'Email' = $user.Mail
        'Account Enabled' = $user.AccountEnabled
        'Password Policies' = $user.PasswordPolicies
        'Department' = $user.Department
        'Job Title' = $user.JobTitle
        'Object ID' = $user.ObjectId
    }
}

$results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

Write-Host "  CSV file created" -ForegroundColor Green
Write-Host ""

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Users with password never expires: $($filteredUsers.Count)" -ForegroundColor White
Write-Host ""
Write-Host "CSV file saved to:" -ForegroundColor Yellow
Write-Host "  $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "Opening CSV file..." -ForegroundColor Green
Write-Host ""
Write-Host "Send this file to Tony Schlak" -ForegroundColor Cyan
Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host ""
