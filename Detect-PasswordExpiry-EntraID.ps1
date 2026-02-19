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
Write-Host "  Finds users with 'Password Never Expires' = DISABLED" -ForegroundColor Yellow
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
        Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "AuditLog.Read.All" -NoWelcome -ErrorAction Stop
        
        $context = Get-MgContext
        Write-Host "  Connected to tenant: $($context.TenantId)" -ForegroundColor Green
        Write-Host "  Account: $($context.Account)" -ForegroundColor Green
        Write-Host ""
        return $true
    } catch {
        Write-Host "  ERROR: Failed to connect to Entra ID" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-UsersWithPasswordExpiry {
    Write-Host "[3/4] Scanning all users in Entra ID..." -ForegroundColor Cyan
    Write-Host "  Looking for users where Password Never Expires = DISABLED" -ForegroundColor Yellow
    Write-Host ""
    
    $allUsers = @()
    
    try {
        Write-Host "  Fetching all users..." -ForegroundColor White
        $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,PasswordPolicies,Department,JobTitle,CompanyName,City,State,Country,EmployeeId,OnPremisesSyncEnabled,LastPasswordChangeDateTime,AssignedLicenses,UserType,OfficeLocation,MobilePhone,BusinessPhones" -ErrorAction Stop
        
        $totalUsers = $users.Count
        Write-Host "  Total users in tenant: $totalUsers" -ForegroundColor Cyan
        
        $counter = 0
        $usersWithExpiry = 0
        
        foreach ($user in $users) {
            $counter++
            
            if ($counter % 50 -eq 0) {
                Write-Host "  Processing: $counter / $totalUsers users..." -ForegroundColor Gray
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
                $licenseStatus = if ($licenseCount -gt 0) { "Licensed ($licenseCount)" } else { "Unlicensed" }
                
                $syncStatus = if ($user.OnPremisesSyncEnabled -eq $true) { "Synced from On-Prem" } else { "Cloud Only" }
                
                $phone = if ($user.MobilePhone) { 
                    $user.MobilePhone 
                } elseif ($user.BusinessPhones -and $user.BusinessPhones.Count -gt 0) { 
                    $user.BusinessPhones[0] 
                } else { 
                    "N/A" 
                }
                
                $userObject = [PSCustomObject]@{
                    DisplayName = if ($user.DisplayName) { $user.DisplayName } else { "N/A" }
                    UserPrincipalName = $user.UserPrincipalName
                    Email = if ($user.Mail) { $user.Mail } else { $user.UserPrincipalName }
                    UserType = if ($user.UserType) { $user.UserType } else { "Member" }
                    AccountEnabled = $user.AccountEnabled
                    PasswordNeverExpires = "NO (Password WILL Expire)"
                    LastPasswordChange = if ($lastPasswordChange) { $lastPasswordChange.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never Changed" }
                    PasswordAgeDays = $passwordAgeDays
                    Department = if ($user.Department) { $user.Department } else { "N/A" }
                    JobTitle = if ($user.JobTitle) { $user.JobTitle } else { "N/A" }
                    Company = if ($user.CompanyName) { $user.CompanyName } else { "N/A" }
                    OfficeLocation = if ($user.OfficeLocation) { $user.OfficeLocation } else { "N/A" }
                    City = if ($user.City) { $user.City } else { "N/A" }
                    State = if ($user.State) { $user.State } else { "N/A" }
                    Country = if ($user.Country) { $user.Country } else { "N/A" }
                    Phone = $phone
                    EmployeeId = if ($user.EmployeeId) { $user.EmployeeId } else { "N/A" }
                    LicenseStatus = $licenseStatus
                    SyncStatus = $syncStatus
                    CreatedDate = if ($user.CreatedDateTime) { $user.CreatedDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
                    UserId = $user.Id
                }
                
                $allUsers += $userObject
            }
        }
        
        Write-Host ""
        Write-Host "  ✓ Found $usersWithExpiry users with password expiry ENABLED" -ForegroundColor Green
        Write-Host "  ✓ These users' passwords WILL expire per policy" -ForegroundColor Green
        Write-Host ""
        
        return $allUsers
    } catch {
        Write-Host "  ERROR: Failed to get users" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Export-ToCSV {
    param($Data, $FilePath)
    
    try {
        $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
        Write-Host "  ✓ CSV exported: $FilePath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR: Failed to export CSV" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Export-ToHTML {
    param($Data, $FilePath)
    
    try {
        $totalUsers = $Data.Count
        $enabledUsers = ($Data | Where-Object { $_.AccountEnabled -eq $true }).Count
        $disabledUsers = ($Data | Where-Object { $_.AccountEnabled -eq $false }).Count
        $licensedUsers = ($Data | Where-Object { $_.LicenseStatus -like "Licensed*" }).Count
        $unlicensedUsers = ($Data | Where-Object { $_.LicenseStatus -eq "Unlicensed" }).Count
        $cloudUsers = ($Data | Where-Object { $_.SyncStatus -eq "Cloud Only" }).Count
        $syncedUsers = ($Data | Where-Object { $_.SyncStatus -eq "Synced from On-Prem" }).Count
        $guestUsers = ($Data | Where-Object { $_.UserType -eq "Guest" }).Count
        
        $usersOver90Days = ($Data | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 90 }).Count
        $usersOver180Days = ($Data | Where-Object { $_.PasswordAgeDays -ne "N/A" -and [int]$_.PasswordAgeDays -gt 180 }).Count
        $neverChanged = ($Data | Where-Object { $_.LastPasswordChange -eq "Never Changed" }).Count
        
        $context = Get-MgContext
        $tenantId = $context.TenantId
        
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Entra ID Password Expiry Report</title>
    <meta charset="UTF-8">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header h1 {
            font-size: 36px;
            margin-bottom: 10px;
        }
        .header p {
            font-size: 16px;
            opacity: 0.9;
            margin-top: 5px;
        }
        .tenant-info {
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 5px;
            margin-top: 20px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 20px;
            padding: 40px;
            background: #f8f9fa;
        }
        .stat-card {
            background: white;
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            text-align: center;
            transition: transform 0.3s;
        }
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 20px rgba(0,0,0,0.15);
        }
        .stat-number {
            font-size: 42px;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 10px;
        }
        .stat-number.warning {
            color: #ffc107;
        }
        .stat-number.danger {
            color: #dc3545;
        }
        .stat-label {
            font-size: 13px;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .alert {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 20px;
            margin: 20px 40px;
            border-radius: 4px;
        }
        .alert h3 {
            color: #856404;
            margin-bottom: 10px;
            font-size: 18px;
        }
        .alert ul {
            margin-left: 20px;
            color: #856404;
        }
        .alert li {
            margin: 5px 0;
        }
        .table-container {
            padding: 40px;
            overflow-x: auto;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        thead {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }
        th {
            padding: 15px 10px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 0.5px;
        }
        td {
            padding: 12px 10px;
            border-bottom: 1px solid #e0e0e0;
            font-size: 13px;
        }
        tbody tr:hover {
            background: #f8f9fa;
        }
        .status-enabled {
            color: #28a745;
            font-weight: bold;
        }
        .status-disabled {
            color: #dc3545;
            font-weight: bold;
        }
        .status-warning {
            background: #fff3cd;
            color: #856404;
            font-weight: bold;
        }
        .status-danger {
            background: #f8d7da;
            color: #721c24;
            font-weight: bold;
        }
        .footer {
            background: #2c3e50;
            color: white;
            padding: 20px;
            text-align: center;
            font-size: 14px;
        }
        .search-box {
            padding: 20px 40px;
            background: #f8f9fa;
            border-bottom: 2px solid #ddd;
        }
        .search-box input {
            width: 100%;
            padding: 12px 20px;
            border: 2px solid #ddd;
            border-radius: 6px;
            font-size: 14px;
        }
        .search-box input:focus {
            outline: none;
            border-color: #667eea;
        }
        .filters {
            padding: 20px 40px;
            background: white;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        .filter-btn {
            padding: 8px 16px;
            border: 2px solid #667eea;
            background: white;
            color: #667eea;
            border-radius: 20px;
            cursor: pointer;
            font-size: 13px;
            transition: all 0.3s;
        }
        .filter-btn:hover {
            background: #667eea;
            color: white;
        }
        .filter-btn.active {
            background: #667eea;
            color: white;
        }
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
                
                if (found) {
                    tr[i].style.display = "";
                } else {
                    tr[i].style.display = "none";
                }
            }
        }
        
        function filterTable(criteria) {
            var table = document.getElementById("userTable");
            var tr = table.getElementsByTagName("tr");
            
            for (var i = 1; i < tr.length; i++) {
                var show = false;
                
                if (criteria === 'all') {
                    show = true;
                } else if (criteria === 'over90') {
                    var ageCell = tr[i].getElementsByTagName("td")[5];
                    if (ageCell) {
                        var age = ageCell.textContent;
                        if (age !== 'N/A' && parseInt(age) > 90) {
                            show = true;
                        }
                    }
                } else if (criteria === 'over180') {
                    var ageCell = tr[i].getElementsByTagName("td")[5];
                    if (ageCell) {
                        var age = ageCell.textContent;
                        if (age !== 'N/A' && parseInt(age) > 180) {
                            show = true;
                        }
                    }
                } else if (criteria === 'enabled') {
                    var statusCell = tr[i].getElementsByTagName("td")[2];
                    if (statusCell && statusCell.textContent === 'Enabled') {
                        show = true;
                    }
                } else if (criteria === 'disabled') {
                    var statusCell = tr[i].getElementsByTagName("td")[2];
                    if (statusCell && statusCell.textContent === 'Disabled') {
                        show = true;
                    }
                } else if (criteria === 'licensed') {
                    var licenseCell = tr[i].getElementsByTagName("td")[8];
                    if (licenseCell && licenseCell.textContent.indexOf('Licensed') !== -1) {
                        show = true;
                    }
                }
                
                tr[i].style.display = show ? "" : "none";
            }
            
            var buttons = document.getElementsByClassName('filter-btn');
            for (var i = 0; i < buttons.length; i++) {
                buttons[i].classList.remove('active');
            }
            event.target.classList.add('active');
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔐 AZURE ENTRA ID PASSWORD EXPIRY REPORT</h1>
            <p>Users with "Password Never Expires" = DISABLED</p>
            <p>(These passwords WILL expire per policy)</p>
            <div class="tenant-info">
                <p><strong>Tenant ID:</strong> $tenantId</p>
                <p><strong>Report Generated:</strong> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
            </div>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number">$totalUsers</div>
                <div class="stat-label">Total Users</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$enabledUsers</div>
                <div class="stat-label">Enabled Accounts</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$disabledUsers</div>
                <div class="stat-label">Disabled Accounts</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$licensedUsers</div>
                <div class="stat-label">Licensed Users</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$cloudUsers</div>
                <div class="stat-label">Cloud Only</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$syncedUsers</div>
                <div class="stat-label">Synced On-Prem</div>
            </div>
            <div class="stat-card">
                <div class="stat-number">$guestUsers</div>
                <div class="stat-label">Guest Users</div>
            </div>
            <div class="stat-card">
                <div class="stat-number warning">$usersOver90Days</div>
                <div class="stat-label">Password &gt; 90 Days</div>
            </div>
            <div class="stat-card">
                <div class="stat-number danger">$usersOver180Days</div>
                <div class="stat-label">Password &gt; 180 Days</div>
            </div>
            <div class="stat-card">
                <div class="stat-number danger">$neverChanged</div>
                <div class="stat-label">Never Changed</div>
            </div>
        </div>
        
        <div class="alert">
            <h3>⚠️ IMPORTANT - ACTION REQUIRED</h3>
            <ul>
                <li><strong>$totalUsers users</strong> have password expiry ENABLED (not set to "Never Expires")</li>
                <li><strong>$usersOver90Days users</strong> have passwords older than 90 days - should change soon</li>
                <li><strong>$usersOver180Days users</strong> have passwords older than 180 days - CRITICAL</li>
                <li><strong>$neverChanged users</strong> have NEVER changed their password</li>
                <li>Review your organization's password policy in Entra ID settings</li>
            </ul>
        </div>
        
        <div class="filters">
            <button class="filter-btn active" onclick="filterTable('all')">Show All</button>
            <button class="filter-btn" onclick="filterTable('over90')">Password &gt; 90 Days</button>
            <button class="filter-btn" onclick="filterTable('over180')">Password &gt; 180 Days</button>
            <button class="filter-btn" onclick="filterTable('enabled')">Enabled Only</button>
            <button class="filter-btn" onclick="filterTable('disabled')">Disabled Only</button>
            <button class="filter-btn" onclick="filterTable('licensed')">Licensed Only</button>
        </div>
        
        <div class="search-box">
            <input type="text" id="searchInput" onkeyup="searchTable()" placeholder="🔍 Search by name, email, department, job title, or any field...">
        </div>
        
        <div class="table-container">
            <table id="userTable">
                <thead>
                    <tr>
                        <th>Display Name</th>
                        <th>Email</th>
                        <th>Account Status</th>
                        <th>User Type</th>
                        <th>Last Password Change</th>
                        <th>Age (Days)</th>
                        <th>Department</th>
                        <th>Job Title</th>
                        <th>License Status</th>
                        <th>Sync Status</th>
                        <th>Office</th>
                        <th>City</th>
                        <th>Phone</th>
                        <th>Created Date</th>
                    </tr>
                </thead>
                <tbody>
"@

        foreach ($user in $Data) {
            $statusClass = if ($user.AccountEnabled) { "status-enabled" } else { "status-disabled" }
            $accountStatus = if ($user.AccountEnabled) { "Enabled" } else { "Disabled" }
            
            $passwordAgeClass = ""
            $passwordAgeValue = $user.PasswordAgeDays
            if ($passwordAgeValue -ne "N/A") {
                $days = [int]$passwordAgeValue
                if ($days -gt 180) {
                    $passwordAgeClass = "status-danger"
                } elseif ($days -gt 90) {
                    $passwordAgeClass = "status-warning"
                }
            }
            
            $html += @"
                    <tr>
                        <td><strong>$($user.DisplayName)</strong></td>
                        <td>$($user.Email)</td>
                        <td class="$statusClass">$accountStatus</td>
                        <td>$($user.UserType)</td>
                        <td>$($user.LastPasswordChange)</td>
                        <td class="$passwordAgeClass">$passwordAgeValue</td>
                        <td>$($user.Department)</td>
                        <td>$($user.JobTitle)</td>
                        <td>$($user.LicenseStatus)</td>
                        <td>$($user.SyncStatus)</td>
                        <td>$($user.OfficeLocation)</td>
                        <td>$($user.City), $($user.State)</td>
                        <td>$($user.Phone)</td>
                        <td>$($user.CreatedDate)</td>
                    </tr>
"@
        }

        $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Azure Entra ID Password Expiry Report | Generated by PowerShell Script</p>
            <p>These users have password expiry enabled and will need to change passwords per policy</p>
        </div>
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $FilePath -Encoding UTF8
        Write-Host "  ✓ HTML dashboard exported: $FilePath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR: Failed to export HTML" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Install-RequiredModules

if (-not (Connect-ToEntraID)) {
    Write-Host ""
    Write-Host "Failed to connect. Exiting..." -ForegroundColor Red
    exit
}

$userData = Get-UsersWithPasswordExpiry

if ($userData.Count -eq 0) {
    Write-Host ""
    Write-Host "No users found with password expiry enabled!" -ForegroundColor Yellow
    Write-Host "This means ALL users have 'Password Never Expires' set." -ForegroundColor Yellow
    Write-Host ""
    exit
}

Write-Host "[4/4] Exporting reports..." -ForegroundColor Cyan

$csvPath = Join-Path $OutputFolder "PasswordExpiry_Users_$timestamp.csv"
$htmlPath = Join-Path $OutputFolder "PasswordExpiry_Dashboard_$timestamp.html"

Export-ToCSV -Data $userData -FilePath $csvPath
Export-ToHTML -Data $userData -FilePath $htmlPath

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SCAN COMPLETE!" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Total Users Found: $($userData.Count)" -ForegroundColor White
Write-Host ""
Write-Host "  Reports saved to:" -ForegroundColor White
Write-Host "    CSV:  $csvPath" -ForegroundColor Cyan
Write-Host "    HTML: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Open the HTML file in your browser for interactive dashboard!" -ForegroundColor Yellow
Write-Host ""

Disconnect-MgGraph | Out-Null
