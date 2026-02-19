Import-Module AzureAD

Write-Host "Connecting to Azure AD..." -ForegroundColor Cyan
Write-Host ""

Connect-AzureAD | Out-Null

Write-Host "Connected!" -ForegroundColor Green
Write-Host ""
Write-Host "Getting ALL users from Azure AD..." -ForegroundColor Cyan
Write-Host "Please wait..." -ForegroundColor Yellow
Write-Host ""

$allUsers = Get-AzureADUser -All $true

Write-Host "Total users retrieved: $($allUsers.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "Filtering for users with password expiration disabled..." -ForegroundColor Cyan
Write-Host ""

$results = @()

foreach ($user in $allUsers) {
    $hasNoExpiry = $false
    
    if ($user.PasswordPolicies -ne $null) {
        if ($user.PasswordPolicies -contains "DisablePasswordExpiration") {
            $hasNoExpiry = $true
        }
        if ($user.PasswordPolicies -like "*DisablePasswordExpiration*") {
            $hasNoExpiry = $true
        }
    }
    
    if ($hasNoExpiry) {
        $results += [PSCustomObject]@{
            'DisplayName' = $user.DisplayName
            'UserPrincipalName' = $user.UserPrincipalName
            'Email' = $user.Mail
            'AccountEnabled' = $user.AccountEnabled
            'PasswordPolicies' = $user.PasswordPolicies
            'Department' = $user.Department
            'JobTitle' = $user.JobTitle
            'ObjectId' = $user.ObjectId
        }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "C:\Users\SyedRizvi\Desktop\PasswordNeverExpires_$timestamp.csv"

if ($results.Count -eq 0) {
    Write-Host "WARNING: No users found with DisablePasswordExpiration!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Exporting ALL users instead so Tony can check..." -ForegroundColor Yellow
    Write-Host ""
    
    $allResults = @()
    foreach ($user in $allUsers) {
        $allResults += [PSCustomObject]@{
            'DisplayName' = $user.DisplayName
            'UserPrincipalName' = $user.UserPrincipalName
            'Email' = $user.Mail
            'AccountEnabled' = $user.AccountEnabled
            'PasswordPolicies' = $user.PasswordPolicies
            'Department' = $user.Department
            'JobTitle' = $user.JobTitle
            'ObjectId' = $user.ObjectId
        }
    }
    
    $allResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    
    Write-Host "Exported all $($allUsers.Count) users to CSV" -ForegroundColor Green
} else {
    $results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    
    Write-Host "Found $($results.Count) users with password expiration disabled!" -ForegroundColor Green
}

Write-Host ""
Write-Host "CSV saved to: $csvFile" -ForegroundColor White
Write-Host ""

Start-Process $csvFile

Write-Host "Opening CSV file..." -ForegroundColor Green
Write-Host ""
Write-Host "DONE - Send this to Tony!" -ForegroundColor Cyan
Write-Host ""
