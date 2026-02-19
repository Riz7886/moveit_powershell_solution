$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PASSWORD NEVER EXPIRES - USER EXPORT" -ForegroundColor Cyan
Write-Host "  For: Tony Schlak" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$env:USERPROFILE\Desktop\PasswordNeverExpires_$timestamp.csv"

Write-Host "Connecting to Azure AD..." -ForegroundColor Yellow
Write-Host ""
Write-Host "INSTRUCTIONS:" -ForegroundColor Cyan
Write-Host "1. A code will appear below" -ForegroundColor White
Write-Host "2. Open browser and go to: https://microsoft.com/devicelogin" -ForegroundColor White
Write-Host "3. Enter the code" -ForegroundColor White
Write-Host "4. Sign in with your Pyx Health account" -ForegroundColor White
Write-Host ""
Write-Host "Waiting for authentication..." -ForegroundColor Yellow
Write-Host ""

try {
    Connect-MgGraph -Scopes "User.Read.All" -UseDeviceAuthentication -ErrorAction Stop
    Write-Host ""
    Write-Host "Connected successfully!" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to connect" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Getting all users from Azure AD..." -ForegroundColor Yellow
Write-Host "Please wait..." -ForegroundColor Gray
Write-Host ""

try {
    $allUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,AccountEnabled,PasswordPolicies,Department,JobTitle,CreatedDateTime,Id
    Write-Host "Found $($allUsers.Count) total users" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Failed to get users" -ForegroundColor Red
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph
    exit 1
}

Write-Host "Filtering for DisablePasswordExpiration..." -ForegroundColor Yellow

$filtered = $allUsers | Where-Object {$_.PasswordPolicies -like "*DisablePasswordExpiration*"}

Write-Host "Found $($filtered.Count) users with password expiration disabled" -ForegroundColor Green
Write-Host ""

if ($filtered.Count -eq 0) {
    Write-Host "No users found with DisablePasswordExpiration" -ForegroundColor Yellow
    Disconnect-MgGraph
    exit 0
}

Write-Host "Creating CSV file..." -ForegroundColor Yellow

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

Write-Host "CSV created!" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph | Out-Null

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SUCCESS" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total users: $($filtered.Count)" -ForegroundColor White
Write-Host ""
Write-Host "CSV file: $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "Opening CSV..." -ForegroundColor Green
Write-Host ""
Write-Host "SEND THIS TO TONY" -ForegroundColor Cyan
Write-Host ""
