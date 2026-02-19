Import-Module AzureAD

Connect-AzureAD

$allUsers = Get-AzureADUser -All $true

$results = @()

foreach ($user in $allUsers) {
    if ($user.PasswordPolicies -like "*DisablePasswordExpiration*") {
        $results += [PSCustomObject]@{
            'Display Name' = $user.DisplayName
            'User Principal Name' = $user.UserPrincipalName
            'Email' = $user.Mail
            'Account Enabled' = $user.AccountEnabled
            'Password Policy' = $user.PasswordPolicies
            'Department' = $user.Department
            'Job Title' = $user.JobTitle
        }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "C:\Users\SyedRizvi\Desktop\PasswordNeverExpires_$timestamp.csv"

$results | Export-Csv -Path $csvFile -NoTypeInformation

Write-Host "DONE! Found $($results.Count) users" -ForegroundColor Green
Write-Host "CSV: $csvFile" -ForegroundColor Green

Start-Process $csvFile
