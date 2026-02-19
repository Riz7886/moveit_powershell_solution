param(
    [string]$OutputFolder = "Reports"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AZURE ENTRA ID - PASSWORD EXPIRY DETECTION" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

function Install-RequiredModules {
    Write-Host "[1/4] Checking required modules..." -ForegroundColor Cyan
    
    $modules = @("Microsoft.Graph.Users", "Microsoft.Graph.Authentication")
    
    foreach ($module in $modules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "  Installing $module..." -ForegroundColor Yellow
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
        } else {
            Write-Host "  $module - OK" -ForegroundColor Green
        }
    }
    Write-Host ""
}

function Connect-ToEntraID {
    Write-Host "[2/4] Connecting to Azure Entra ID..." -ForegroundColor Cyan
    
    try {
        Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -NoWelcome -ErrorAction Stop
        
        $context = Get-MgContext
        Write-Host "  Connected to tenant: $($context.TenantId)" -ForegroundColor Green
        Write-Host ""
        return $true
    } catch {
        Write-Host "  ERROR: Failed to connect" -ForegroundColor Red
        return $false
    }
}

function Get-UsersWithPasswordExpiry {
    Write-Host "[3/4] Scanning all users..." -ForegroundColor Cyan
    Write-Host ""
    
    $allUsers = @()
    
    try {
        Write-Host "  Fetching users from Entra ID..." -ForegroundColor White
        $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,PasswordPolicies,Department,JobTitle,CompanyName,City,State,Country,EmployeeId,OnPremisesSyncEnabled,LastPasswordChangeDateTime,AssignedLicenses,UserType" -ErrorAction Stop
        
        $totalUsers = $users.Count
        Write-Host "  Total users in tenant: $totalUsers" -ForegroundColor Cyan
        
        $counter = 0
        $usersWithExpiry = 0
        
        foreach ($user in $users) {
            $counter++
            
            if ($counter % 50 -eq 0) {
                Write-Host "  Processing: $counter / $totalUsers" -ForegroundColor Gray
            }
            
            $passwordNeverExpires = $false
            if ($user.PasswordPolicies) {
                $passwordNeverExpires = $user.PasswordPolicies -like "*DisablePasswordExpiration*"
            }
            
            if (-not $passwordNeverExpires) {
                $usersWithExpiry++
                
                $lastPasswordChange = $user.LastPasswordChangeDateTime
                if ($lastPasswordChange) {
                    $passwordAge = (Get-Date) - $lastPasswordChange
                    $passwordAgeDays = [math]::Round($passwordAge.TotalDays, 0)
                } else {
                    $passwordAgeDays = "N/A"
                }
                
                $licenseCount = if ($user.AssignedLicenses) { $user.AssignedLicenses.Count } else { 0 }
                $licenseStatus = if ($licenseCount -gt 0) { "Licensed" } else { "Unlicensed" }
                
                $syncStatus = if ($user.OnPremisesSyncEnabled -eq $true) { "Synced" } else { "Cloud" }
                
                $userObject = [PSCustomObject]@{
                    DisplayName = if ($user.DisplayName) { $user.DisplayName } else { "N/A" }
                    UserPrincipalName = $user.UserPrincipalName
                    Email = if ($user.Mail) { $user.Mail } else { $user.UserPrincipalName }
                    UserType = if ($user.UserType) { $user.UserType } else { "Member" }
                    AccountEnabled = $user.AccountEnabled
                    PasswordNeverExpires = "NO"
                    LastPasswordChange = if ($lastPasswordChange) { $lastPasswordChange.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
                    PasswordAgeDays = $passwordAgeDays
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
                
                $allUsers += $userObject
            }
        }
        
        Write-Host ""
        Write-Host "  Found $usersWithExpiry users with password expiry enabled" -ForegroundColor Green
        Write-Host ""
        
        return $allUsers
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Export-ToCSV {
    param($Data, $FilePath)
    
    try {
        $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
        Write-Host "  CSV: $FilePath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR: CSV export failed" -ForegroundColor Red
        return $false
    }
}

function Export-ToHTML {
    param($Data, $FilePath)
    
    try {
        $totalUsers = $Data.Count
        $enabledUsers = ($Data | Where-Object { $_.AccountEnabled -eq $true }).Count
        $disabledUsers = ($Data | Where-Object { $_.AccountEnabled -eq $false }).Count
        $licensedUsers = ($Data | Where-Object { $_.LicenseStatus -eq "Licensed" }).Count
        $cloudUsers = ($Data | Where-Object { $_.SyncStatus -eq "Cloud" }).Count
        $syncedUsers = ($Data | Where-Object { $_.SyncStatus -eq "Synced" }).Count
        
        $usersOver90Days = ($Data | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 90 }).Count
        $usersOver180Days = ($Data | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 180 }).Count
        
        $context = Get-MgContext
        $tenantId = $context.TenantId
        $reportDate = Get-Date -Format "MMMM dd, yyyy HH:mm:ss"
        
$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <title>Password Expiry Report</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; margin: 0; }
        .container { max-width: 1600px; margin: 0 auto; background: white; border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; text-align: center; }
        .header h1 { font-size: 36px; margin: 0 0 10px 0; }
        .header p { font-size: 16px; margin: 5px 0; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 20px; padding: 40px; background: #f8f9fa; }
        .stat-card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); text-align: center; }
        .stat-number { font-size: 42px; font-weight: bold; color: #667eea; margin-bottom: 10px; }
        .stat-number.warning { color: #ffc107; }
        .stat-number.danger { color: #dc3545; }
        .stat-label { font-size: 13px; color: #666; text-transform: uppercase; }
        .alert { background: #fff3cd; border-left: 4px solid #ffc107; padding: 20px; margin: 20px 40px; border-radius: 4px; }
        .search-box { padding: 20px 40px; background: #f8f9fa; }
        .search-box input { width: 100%; padding: 12px 20px; border: 2px solid #ddd; border-radius: 6px; font-size: 14px; }
        .table-container { padding: 40px; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        thead { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        th { padding: 15px 10px; text-align: left; font-weight: 600; text-transform: uppercase; font-size: 11px; }
        td { padding: 12px 10px; border-bottom: 1px solid #e0e0e0; font-size: 13px; }
        tbody tr:hover { background: #f8f9fa; }
        .status-enabled { color: #28a745; font-weight: bold; }
        .status-disabled { color: #dc3545; font-weight: bold; }
        .status-warning { background: #fff3cd; color: #856404; font-weight: bold; padding: 4px 8px; }
        .status-danger { background: #f8d7da; color: #721c24; font-weight: bold; padding: 4px 8px; }
        .footer { background: #2c3e50; color: white; padding: 20px; text-align: center; }
    </style>
    <script>
        function searchTable() {
            var input = document.getElementById("searchInput");
            var filter = input.value.toUpperCase();
            var table = document.getElementById("userTable");
            var tr = table.getElementsByTagName("tr");
            for (var i = 1; i < tr.length; i++) {
                var tdArray = tr[i].getElementsByTagName("td");
                var found = false;
                for (var j = 0; j < tdArray.length; j++) {
                    var td = tdArray[j];
                    if (td) {
                        var txtValue = td.textContent || td.innerText;
                        if (txtValue.toUpperCase().indexOf(filter) > -1) {
                            found = true;
                            break;
                        }
                    }
                }
                tr[i].style.display = found ? "" : "none";
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AZURE ENTRA ID PASSWORD EXPIRY REPORT</h1>
            <p>Users with Password Never Expires = DISABLED</p>
            <p>Tenant: $tenantId</p>
            <p>Generated: $reportDate</p>
        </div>
        <div class="stats">
            <div class="stat-card"><div class="stat-number">$totalUsers</div><div class="stat-label">Total Users</div></div>
            <div class="stat-card"><div class="stat-number">$enabledUsers</div><div class="stat-label">Enabled</div></div>
            <div class="stat-card"><div class="stat-number">$disabledUsers</div><div class="stat-label">Disabled</div></div>
            <div class="stat-card"><div class="stat-number">$licensedUsers</div><div class="stat-label">Licensed</div></div>
            <div class="stat-card"><div class="stat-number">$cloudUsers</div><div class="stat-label">Cloud Only</div></div>
            <div class="stat-card"><div class="stat-number">$syncedUsers</div><div class="stat-label">Synced</div></div>
            <div class="stat-card"><div class="stat-number warning">$usersOver90Days</div><div class="stat-label">Over 90 Days</div></div>
            <div class="stat-card"><div class="stat-number danger">$usersOver180Days</div><div class="stat-label">Over 180 Days</div></div>
        </div>
        <div class="alert">
            <h3>ACTION REQUIRED</h3>
            <p><strong>$totalUsers users</strong> have password expiry enabled. <strong>$usersOver90Days users</strong> have passwords over 90 days old.</p>
        </div>
        <div class="search-box">
            <input type="text" id="searchInput" onkeyup="searchTable()" placeholder="Search by name, email, department...">
        </div>
        <div class="table-container">
            <table id="userTable">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Email</th>
                        <th>Status</th>
                        <th>Type</th>
                        <th>Last Changed</th>
                        <th>Age (Days)</th>
                        <th>Department</th>
                        <th>Job Title</th>
                        <th>License</th>
                        <th>Sync</th>
                        <th>City</th>
                        <th>Created</th>
                    </tr>
                </thead>
                <tbody>
"@

        $htmlBody = ""
        foreach ($user in $Data) {
            $statusClass = if ($user.AccountEnabled) { "status-enabled" } else { "status-disabled" }
            $accountStatus = if ($user.AccountEnabled) { "Enabled" } else { "Disabled" }
            
            $passwordAgeClass = ""
            $passwordAgeValue = $user.PasswordAgeDays
            if ($passwordAgeValue -ne "N/A") {
                $days = [int]$passwordAgeValue
                if ($days -gt 180) {
                    $passwordAgeClass = ' class="status-danger"'
                } elseif ($days -gt 90) {
                    $passwordAgeClass = ' class="status-warning"'
                }
            }
            
            $htmlBody += "<tr>"
            $htmlBody += "<td><strong>" + $user.DisplayName + "</strong></td>"
            $htmlBody += "<td>" + $user.Email + "</td>"
            $htmlBody += "<td class=`"$statusClass`">" + $accountStatus + "</td>"
            $htmlBody += "<td>" + $user.UserType + "</td>"
            $htmlBody += "<td>" + $user.LastPasswordChange + "</td>"
            $htmlBody += "<td$passwordAgeClass>" + $passwordAgeValue + "</td>"
            $htmlBody += "<td>" + $user.Department + "</td>"
            $htmlBody += "<td>" + $user.JobTitle + "</td>"
            $htmlBody += "<td>" + $user.LicenseStatus + "</td>"
            $htmlBody += "<td>" + $user.SyncStatus + "</td>"
            $htmlBody += "<td>" + $user.City + "</td>"
            $htmlBody += "<td>" + $user.CreatedDate + "</td>"
            $htmlBody += "</tr>`n"
        }

$htmlFooter = @"
                </tbody>
            </table>
        </div>
        <div class="footer">
            <p>Azure Entra ID Password Expiry Report</p>
        </div>
    </div>
</body>
</html>
"@

        $fullHtml = $htmlHeader + $htmlBody + $htmlFooter
        $fullHtml | Out-File -FilePath $FilePath -Encoding UTF8
        
        Write-Host "  HTML: $FilePath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR: HTML export failed - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Install-RequiredModules

if (-not (Connect-ToEntraID)) {
    Write-Host "Failed to connect. Exiting..." -ForegroundColor Red
    exit
}

$userData = Get-UsersWithPasswordExpiry

if ($userData.Count -eq 0) {
    Write-Host "No users found!" -ForegroundColor Yellow
    exit
}

Write-Host "[4/4] Exporting reports..." -ForegroundColor Cyan

$csvPath = Join-Path $OutputFolder "PasswordExpiry_$timestamp.csv"
$htmlPath = Join-Path $OutputFolder "PasswordExpiry_$timestamp.html"

Export-ToCSV -Data $userData -FilePath $csvPath
Export-ToHTML -Data $userData -FilePath $htmlPath

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Total Users: $($userData.Count)" -ForegroundColor White
Write-Host ""
Write-Host "  CSV:  $csvPath" -ForegroundColor Cyan
Write-Host "  HTML: $htmlPath" -ForegroundColor Cyan
Write-Host ""

Disconnect-MgGraph | Out-Null
