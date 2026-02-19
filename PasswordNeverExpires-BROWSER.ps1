param(
    [string]$OutputFolder = "Reports"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  PASSWORD NEVER EXPIRES REPORT - ENTRA ID" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking modules..." -ForegroundColor Cyan
$modules = @("Microsoft.Graph.Users", "Microsoft.Graph.Authentication")
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
}
Write-Host "Modules ready" -ForegroundColor Green
Write-Host ""

Write-Host "Connecting to Entra ID (browser will open)..." -ForegroundColor Cyan
try {
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -ErrorAction Stop
    Write-Host "Connected successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

$context = Get-MgContext
Write-Host "Tenant: $($context.TenantId)" -ForegroundColor White
Write-Host ""

Write-Host "Fetching all users from Entra ID..." -ForegroundColor Cyan
Write-Host ""

$allUsersData = @()

try {
    $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,PasswordPolicies,Department,JobTitle,CompanyName,City,State,Country,EmployeeId,OnPremisesSyncEnabled,LastPasswordChangeDateTime,AssignedLicenses,UserType" -ErrorAction Stop
    
    $total = $users.Count
    Write-Host "Total users in tenant: $total" -ForegroundColor Cyan
    Write-Host ""
    
    $counter = 0
    $foundCount = 0
    
    foreach ($user in $users) {
        $counter++
        
        if ($counter % 100 -eq 0) {
            Write-Host "Processing: $counter / $total" -ForegroundColor Gray
        }
        
        $hasPasswordNeverExpires = $false
        if ($user.PasswordPolicies) {
            $hasPasswordNeverExpires = $user.PasswordPolicies -like "*DisablePasswordExpiration*"
        }
        
        if ($hasPasswordNeverExpires) {
            $foundCount++
            
            $lastChange = $user.LastPasswordChangeDateTime
            $passwordAge = "N/A"
            
            if ($lastChange) {
                $age = (Get-Date) - $lastChange
                $passwordAge = [math]::Round($age.TotalDays, 0)
            }
            
            $licenses = if ($user.AssignedLicenses) { $user.AssignedLicenses.Count } else { 0 }
            $licenseStatus = if ($licenses -gt 0) { "Licensed" } else { "Unlicensed" }
            $syncStatus = if ($user.OnPremisesSyncEnabled -eq $true) { "Synced from On-Prem" } else { "Cloud Only" }
            
            $userData = [PSCustomObject]@{
                DisplayName = if ($user.DisplayName) { $user.DisplayName } else { "N/A" }
                UserPrincipalName = $user.UserPrincipalName
                Email = if ($user.Mail) { $user.Mail } else { $user.UserPrincipalName }
                UserType = if ($user.UserType) { $user.UserType } else { "Member" }
                AccountEnabled = if ($user.AccountEnabled) { "Enabled" } else { "Disabled" }
                PasswordNeverExpires = "YES"
                PasswordPolicies = $user.PasswordPolicies
                LastPasswordChange = if ($lastChange) { $lastChange.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never Changed" }
                PasswordAgeDays = $passwordAge
                Department = if ($user.Department) { $user.Department } else { "N/A" }
                JobTitle = if ($user.JobTitle) { $user.JobTitle } else { "N/A" }
                Company = if ($user.CompanyName) { $user.CompanyName } else { "N/A" }
                City = if ($user.City) { $user.City } else { "N/A" }
                State = if ($user.State) { $user.State } else { "N/A" }
                Country = if ($user.Country) { $user.Country } else { "N/A" }
                EmployeeId = if ($user.EmployeeId) { $user.EmployeeId } else { "N/A" }
                LicenseStatus = $licenseStatus
                SyncStatus = $syncStatus
                CreatedDate = if ($user.CreatedDateTime) { $user.CreatedDateTime.ToString("yyyy-MM-dd") } else { "N/A" }
                UserId = $user.Id
            }
            
            $allUsersData += $userData
        }
    }
    
    Write-Host ""
    Write-Host "Found $foundCount users with Password Never Expires policy" -ForegroundColor Green
    Write-Host ""
    
    if ($foundCount -eq 0) {
        Write-Host "No users found with Password Never Expires policy!" -ForegroundColor Yellow
        Disconnect-MgGraph | Out-Null
        exit
    }
    
    Write-Host "Exporting reports..." -ForegroundColor Cyan
    
    $csvPath = Join-Path $OutputFolder "PasswordNeverExpires_Users_$timestamp.csv"
    $allUsersData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV exported: $csvPath" -ForegroundColor Green
    
    $htmlPath = Join-Path $OutputFolder "PasswordNeverExpires_Dashboard_$timestamp.html"
    
    $enabledCount = ($allUsersData | Where-Object { $_.AccountEnabled -eq "Enabled" }).Count
    $disabledCount = ($allUsersData | Where-Object { $_.AccountEnabled -eq "Disabled" }).Count
    $licensedCount = ($allUsersData | Where-Object { $_.LicenseStatus -eq "Licensed" }).Count
    $cloudCount = ($allUsersData | Where-Object { $_.SyncStatus -eq "Cloud Only" }).Count
    $syncedCount = ($allUsersData | Where-Object { $_.SyncStatus -eq "Synced from On-Prem" }).Count
    
    $over90 = ($allUsersData | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 90 }).Count
    $over180 = ($allUsersData | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 180 }).Count
    $over365 = ($allUsersData | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 365 }).Count
    $neverChanged = ($allUsersData | Where-Object { $_.LastPasswordChange -eq "Never Changed" }).Count
    
    $reportDate = Get-Date -Format "MMMM dd, yyyy HH:mm:ss"
    
$html = @"
<!DOCTYPE html>
<html>
<head>
<title>Password Never Expires Report</title>
<meta charset="UTF-8">
<style>
body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:white;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:40px;text-align:center}
.header h1{font-size:36px;margin:0 0 10px 0}
.header p{font-size:16px;margin:5px 0}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:20px;padding:40px;background:#f8f9fa}
.stat-card{background:white;padding:25px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1);text-align:center}
.stat-number{font-size:42px;font-weight:bold;color:#667eea;margin-bottom:10px}
.stat-number.warning{color:#ffc107}
.stat-number.danger{color:#dc3545}
.stat-label{font-size:13px;color:#666;text-transform:uppercase}
.alert{background:#d1ecf1;border-left:4px solid #0c5460;padding:20px;margin:20px 40px;border-radius:4px;color:#0c5460}
.search-box{padding:20px 40px;background:#f8f9fa}
.search-box input{width:100%;padding:12px 20px;border:2px solid #ddd;border-radius:6px;font-size:14px}
.table-container{padding:40px;overflow-x:auto}
table{width:100%;border-collapse:collapse;background:white;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
thead{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white}
th{padding:15px 10px;text-align:left;font-weight:600;text-transform:uppercase;font-size:11px}
td{padding:12px 10px;border-bottom:1px solid #e0e0e0;font-size:13px}
tbody tr:hover{background:#f8f9fa}
.status-enabled{color:#28a745;font-weight:bold}
.status-disabled{color:#dc3545;font-weight:bold}
.status-warning{background:#fff3cd;color:#856404;font-weight:bold;padding:4px 8px}
.status-danger{background:#f8d7da;color:#721c24;font-weight:bold;padding:4px 8px}
.footer{background:#2c3e50;color:white;padding:20px;text-align:center}
</style>
<script>
function searchTable(){var input=document.getElementById("searchInput");var filter=input.value.toUpperCase();var table=document.getElementById("userTable");var tr=table.getElementsByTagName("tr");for(var i=1;i<tr.length;i++){var tdArray=tr[i].getElementsByTagName("td");var found=false;for(var j=0;j<tdArray.length;j++){var td=tdArray[j];if(td){var txtValue=td.textContent||td.innerText;if(txtValue.toUpperCase().indexOf(filter)>-1){found=true;break}}}tr[i].style.display=found?"":"none"}}
</script>
</head>
<body>
<div class="container">
<div class="header">
<h1>PASSWORD NEVER EXPIRES REPORT</h1>
<p>Users with Password Never Expires Policy Applied</p>
<p>Tenant: $($context.TenantId)</p>
<p>Generated: $reportDate</p>
</div>
<div class="stats">
<div class="stat-card"><div class="stat-number">$foundCount</div><div class="stat-label">Total Users</div></div>
<div class="stat-card"><div class="stat-number">$enabledCount</div><div class="stat-label">Enabled</div></div>
<div class="stat-card"><div class="stat-number">$disabledCount</div><div class="stat-label">Disabled</div></div>
<div class="stat-card"><div class="stat-number">$licensedCount</div><div class="stat-label">Licensed</div></div>
<div class="stat-card"><div class="stat-number">$cloudCount</div><div class="stat-label">Cloud Only</div></div>
<div class="stat-card"><div class="stat-number">$syncedCount</div><div class="stat-label">Synced On-Prem</div></div>
<div class="stat-card"><div class="stat-number warning">$over90</div><div class="stat-label">Over 90 Days</div></div>
<div class="stat-card"><div class="stat-number warning">$over180</div><div class="stat-label">Over 180 Days</div></div>
<div class="stat-card"><div class="stat-number danger">$over365</div><div class="stat-label">Over 1 Year</div></div>
<div class="stat-card"><div class="stat-number danger">$neverChanged</div><div class="stat-label">Never Changed</div></div>
</div>
<div class="alert">
<h3>PASSWORD NEVER EXPIRES POLICY APPLIED</h3>
<p><strong>$foundCount users</strong> have the Password Never Expires policy applied. Their passwords will NOT expire automatically.</p>
<p>These are typically service accounts, admin accounts, or special purpose accounts that should not have password expiration.</p>
</div>
<div class="search-box">
<input type="text" id="searchInput" onkeyup="searchTable()" placeholder="Search by name, email, department, job title, or any field...">
</div>
<div class="table-container">
<table id="userTable">
<thead>
<tr>
<th>Display Name</th>
<th>Email</th>
<th>Account Status</th>
<th>User Type</th>
<th>Password Never Expires</th>
<th>Last Password Change</th>
<th>Password Age (Days)</th>
<th>Department</th>
<th>Job Title</th>
<th>License Status</th>
<th>Sync Status</th>
<th>City</th>
<th>State</th>
<th>Created Date</th>
</tr>
</thead>
<tbody>
"@

    foreach ($user in $allUsersData) {
        $statusClass = if ($user.AccountEnabled -eq "Enabled") { "status-enabled" } else { "status-disabled" }
        
        $ageClass = ""
        if ($user.PasswordAgeDays -ne "N/A") {
            $days = [int]$user.PasswordAgeDays
            if ($days -gt 365) {
                $ageClass = ' class="status-danger"'
            } elseif ($days -gt 180) {
                $ageClass = ' class="status-warning"'
            }
        }
        
        $html += "<tr>"
        $html += "<td><strong>$($user.DisplayName)</strong></td>"
        $html += "<td>$($user.Email)</td>"
        $html += "<td class=`"$statusClass`">$($user.AccountEnabled)</td>"
        $html += "<td>$($user.UserType)</td>"
        $html += "<td><strong style='color:#0c5460'>YES</strong></td>"
        $html += "<td>$($user.LastPasswordChange)</td>"
        $html += "<td$ageClass>$($user.PasswordAgeDays)</td>"
        $html += "<td>$($user.Department)</td>"
        $html += "<td>$($user.JobTitle)</td>"
        $html += "<td>$($user.LicenseStatus)</td>"
        $html += "<td>$($user.SyncStatus)</td>"
        $html += "<td>$($user.City)</td>"
        $html += "<td>$($user.State)</td>"
        $html += "<td>$($user.CreatedDate)</td>"
        $html += "</tr>"
    }

    $html += @"
</tbody>
</table>
</div>
<div class="footer">
<p>Azure Entra ID - Password Never Expires Report</p>
<p>These users have the policy applied and their passwords will NOT expire</p>
</div>
</div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML exported: $htmlPath" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  REPORT COMPLETE!" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Total Users with Policy: $foundCount" -ForegroundColor White
    Write-Host ""
    Write-Host "Reports saved:" -ForegroundColor White
    Write-Host "  CSV:  $csvPath" -ForegroundColor Cyan
    Write-Host "  HTML: $htmlPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Open the HTML file in your browser for interactive dashboard!" -ForegroundColor Yellow
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

Disconnect-MgGraph | Out-Null
Write-Host "Disconnected from Entra ID" -ForegroundColor Gray
