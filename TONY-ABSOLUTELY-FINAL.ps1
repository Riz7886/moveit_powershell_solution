$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " PASSWORD NEVER EXPIRES - EXPORT" -ForegroundColor Cyan
Write-Host " For: Tony Schlak" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$env:USERPROFILE\Desktop\PasswordNeverExpires_$timestamp.csv"

Write-Host "Step 1: Connecting to Azure AD..." -ForegroundColor Yellow
Write-Host ""
Write-Host "A CODE will appear below." -ForegroundColor White
Write-Host "Go to: https://microsoft.com/devicelogin" -ForegroundColor Cyan
Write-Host "Enter the code and sign in" -ForegroundColor White
Write-Host ""

try {
    $null = Connect-MgGraph -Scopes "User.Read.All" -UseDeviceCode -ErrorAction Stop
    Write-Host ""
    Write-Host "Connected!" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "CONNECTION FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Copy/paste these 3 commands instead:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Connect-MgGraph -Scopes User.Read.All -UseDeviceCode" -ForegroundColor White
    Write-Host ""
    Write-Host "Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,AccountEnabled,PasswordPolicies,Department,JobTitle,CreatedDateTime,Id | Where-Object {`$_.PasswordPolicies -like '*DisablePasswordExpiration*'} | Export-Csv -Path `"$env:USERPROFILE\Desktop\PasswordNeverExpires.csv`" -NoTypeInformation" -ForegroundColor White
    Write-Host ""
    Write-Host "Start-Process `"$env:USERPROFILE\Desktop\PasswordNeverExpires.csv`"" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Step 2: Getting all users..." -ForegroundColor Yellow

try {
    $allUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,Mail,AccountEnabled,PasswordPolicies,Department,JobTitle,CreatedDateTime,Id
    Write-Host "Total users: $($allUsers.Count)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "FAILED to get users" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Step 3: Filtering..." -ForegroundColor Yellow

$filtered = $allUsers | Where-Object {$_.PasswordPolicies -like "*DisablePasswordExpiration*"}

Write-Host "Users with DisablePasswordExpiration: $($filtered.Count)" -ForegroundColor Green
Write-Host ""

if ($filtered.Count -eq 0) {
    Write-Host "No users found!" -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit 0
}

Write-Host "Step 4: Creating CSV..." -ForegroundColor Yellow

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

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " SUCCESS!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Total: $($filtered.Count) users" -ForegroundColor White
Write-Host "File: $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "CSV opened - Send to Tony!" -ForegroundColor Cyan
Write-Host ""
