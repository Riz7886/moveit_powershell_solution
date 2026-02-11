# AZURE NAMING AUDIT - COMPLETE WITH ALL PREREQ CHECKS
# Checks EVERYTHING before running!

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AZURE NAMING AUDIT - FULL CHECKS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Check PowerShell version
Write-Host "[1/6] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "  PowerShell: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor White

if ($psVersion.Major -lt 5) {
    Write-Host "  ERROR: Need PowerShell 5.1 or higher!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}
Write-Host "  OK - PowerShell version is good" -ForegroundColor Green
Write-Host ""

# STEP 2: Check if Az module is installed
Write-Host "[2/6] Checking Az module..." -ForegroundColor Yellow
$azModule = Get-Module -ListAvailable -Name Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1

if (-not $azModule) {
    Write-Host "  ERROR: Az module not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  FIX: Run PowerShell as Administrator and execute:" -ForegroundColor Yellow
    Write-Host "  Install-Module -Name Az -Repository PSGallery -Force" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "  Installed: Az.Accounts version $($azModule.Version)" -ForegroundColor White

# Check if version is too old
$minVersion = [System.Version]"2.10.0"
if ($azModule.Version -lt $minVersion) {
    Write-Host "  WARNING: Az module is outdated (need 2.10.0+)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Your version: $($azModule.Version)" -ForegroundColor Yellow
    Write-Host "  Required: 2.10.0 or higher" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  FIX: Run PowerShell as Administrator and execute:" -ForegroundColor Yellow
    Write-Host "  Update-Module -Name Az -Force" -ForegroundColor White
    Write-Host ""
    $continue = Read-Host "Continue anyway? (NOT RECOMMENDED) Y/N"
    if ($continue -ne "Y" -and $continue -ne "y") {
        exit
    }
} else {
    Write-Host "  OK - Module version is good" -ForegroundColor Green
}
Write-Host ""

# STEP 3: Import Az module
Write-Host "[3/6] Loading Az module..." -ForegroundColor Yellow
try {
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Resources -ErrorAction Stop
    Write-Host "  OK - Module loaded" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Cannot load Az module" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}
Write-Host ""

# STEP 4: Clear old sessions
Write-Host "[4/6] Clearing old Azure sessions..." -ForegroundColor Yellow
try {
    Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  OK - Old sessions cleared" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not clear old sessions (might be OK)" -ForegroundColor Yellow
}
Write-Host ""

# STEP 5: Connect to Azure with fallback methods
Write-Host "[5/6] Connecting to Azure..." -ForegroundColor Yellow
Write-Host ""

$connected = $false
$context = $null

# Try Method 1: Device Code (most reliable)
Write-Host "  Trying: Device Code Authentication" -ForegroundColor Cyan
Write-Host "  (Opens browser - most reliable method)" -ForegroundColor Gray
Write-Host ""

try {
    Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
    $context = Get-AzContext -ErrorAction Stop
    if ($context) {
        $connected = $true
        Write-Host "  SUCCESS: Connected via Device Code" -ForegroundColor Green
    }
} catch {
    Write-Host "  FAILED: Device Code auth failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
}

# Try Method 2: Normal interactive login
if (-not $connected) {
    Write-Host ""
    Write-Host "  Trying: Interactive Login" -ForegroundColor Cyan
    Write-Host "  (Browser popup)" -ForegroundColor Gray
    Write-Host ""
    
    try {
        Connect-AzAccount -ErrorAction Stop | Out-Null
        $context = Get-AzContext -ErrorAction Stop
        if ($context) {
            $connected = $true
            Write-Host "  SUCCESS: Connected via Interactive Login" -ForegroundColor Green
        }
    } catch {
        Write-Host "  FAILED: Interactive login failed" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# Check if we connected
if (-not $connected) {
    Write-Host ""
    Write-Host "  ERROR: All authentication methods failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Possible issues:" -ForegroundColor Yellow
    Write-Host "  - Azure is having outages (check status.azure.com)" -ForegroundColor White
    Write-Host "  - Corporate security blocking authentication" -ForegroundColor White
    Write-Host "  - Az module version too old" -ForegroundColor White
    Write-Host "  - Account permissions issue" -ForegroundColor White
    Write-Host ""
    Write-Host "  Contact your IT support for help" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host ""
Write-Host "  Connected Account: $($context.Account.Id)" -ForegroundColor White
Write-Host "  Tenant: $($context.Tenant.Id)" -ForegroundColor White
Write-Host ""

# STEP 6: Get subscriptions
Write-Host "[6/6] Loading subscriptions..." -ForegroundColor Yellow

try {
    $allSubs = Get-AzSubscription -ErrorAction Stop
} catch {
    Write-Host "  ERROR: Cannot get subscriptions" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

if ($allSubs.Count -eq 0) {
    Write-Host "  ERROR: No subscriptions found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Your account ($($context.Account.Id)) has access to 0 subscriptions." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This means:" -ForegroundColor Yellow
    Write-Host "  - Your permissions were removed" -ForegroundColor White
    Write-Host "  - Or you need to be added to subscription access" -ForegroundColor White
    Write-Host ""
    Write-Host "  Contact your Azure administrator to restore access" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "  OK - Found $($allSubs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

# All checks passed!
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALL PREREQ CHECKS PASSED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 2

# NOW RUN THE ACTUAL AUDIT
Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SUBSCRIPTION SELECTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "SELECT SUBSCRIPTION TO AUDIT:" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $allSubs.Count; $i++) {
    $sub = $allSubs[$i]
    $num = $i + 1
    $stateColor = if ($sub.State -eq "Enabled") {"Green"} else {"Yellow"}
    Write-Host "  [$num] $($sub.Name) " -NoNewline -ForegroundColor White
    Write-Host "($($sub.State))" -ForegroundColor $stateColor
}

Write-Host ""
Write-Host "  [A] Audit ALL subscriptions" -ForegroundColor Yellow
Write-Host "  [X] Exit" -ForegroundColor Red
Write-Host ""

$choice = Read-Host "Enter your choice"

if ($choice -eq "X" -or $choice -eq "x") {
    Write-Host "Exiting..." -ForegroundColor Yellow
    exit
}

$subsToAudit = @()

if ($choice -eq "A" -or $choice -eq "a") {
    $subsToAudit = $allSubs
    Write-Host ""
    Write-Host "Will audit ALL $($allSubs.Count) subscriptions" -ForegroundColor Yellow
} else {
    try {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $allSubs.Count) {
            $subsToAudit = @($allSubs[$index])
            Write-Host ""
            Write-Host "Will audit: $($subsToAudit[0].Name)" -ForegroundColor Yellow
        } else {
            Write-Host "Invalid selection" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit
        }
    } catch {
        Write-Host "Invalid input" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit
    }
}

Write-Host ""
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit
}

# RUN AUDIT
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RUNNING AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allIssues = @()
$totalRGs = 0

foreach ($sub in $subsToAudit) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Cyan
    
    try {
        Set-AzContext -Subscription $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  ERROR: Cannot access subscription" -ForegroundColor Red
        continue
    }
    
    try {
        $rgs = Get-AzResourceGroup -ErrorAction Stop
    } catch {
        Write-Host "  ERROR: Cannot get resource groups" -ForegroundColor Red
        continue
    }
    
    $totalRGs += $rgs.Count
    Write-Host "  Resource Groups: $($rgs.Count)" -ForegroundColor Green
    
    foreach ($rg in $rgs) {
        Write-Host "    Checking: $($rg.ResourceGroupName)" -ForegroundColor Gray
        
        try {
            $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction Stop
        } catch {
            Write-Host "      ERROR: Cannot get resources" -ForegroundColor Red
            continue
        }
        
        if (-not $resources) { continue }
        
        $databricks = $resources | Where-Object {$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
        
        # Detect environment
        $env = "Unknown"
        if ($rg.ResourceGroupName -match "prod" -and $rg.ResourceGroupName -notmatch "preprod") {
            $env = "Production"
        } elseif ($rg.ResourceGroupName -match "preprod|pre-prod") {
            $env = "PreProd"
        } elseif ($rg.ResourceGroupName -match "poc") {
            $env = "POC"
        } elseif ($rg.ResourceGroupName -match "dev") {
            $env = "Development"
        }
        
        # Find issues
        $problems = @()
        
        if ($env -eq "POC") {
            foreach ($r in $resources) {
                if ($r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                    $problems += "POC RG contains production resource: $($r.Name)"
                }
            }
        }
        
        if ($env -eq "PreProd") {
            foreach ($r in $resources) {
                if ($r.Name -match "-prod$|^prod-") {
                    $problems += "PreProd RG contains prod-named resource: $($r.Name)"
                }
            }
        }
        
        if ($problems.Count -gt 0) {
            foreach ($prob in $problems) {
                $allIssues += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rg.ResourceGroupName
                    Environment = $env
                    Location = $rg.Location
                    ResourceCount = $resources.Count
                    Databricks = if ($databricks) {($databricks.Name -join ", ")} else {"None"}
                    Issue = $prob
                }
            }
        }
    }
    
    Write-Host ""
}

# SHOW RESULTS
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Subscriptions Scanned: $($subsToAudit.Count)" -ForegroundColor White
Write-Host "Resource Groups Scanned: $totalRGs" -ForegroundColor White
Write-Host "Naming Issues Found: $($allIssues.Count)" -ForegroundColor $(if ($allIssues.Count -gt 0) {"Red"} else {"Green"})
Write-Host ""

if ($allIssues.Count -eq 0) {
    Write-Host "No naming issues found!" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "ISSUES FOUND:" -ForegroundColor Yellow
Write-Host ""
$allIssues | Format-Table Subscription, ResourceGroup, Environment, Issue -AutoSize -Wrap

# GENERATE HTML REPORT
Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Yellow

$reportFile = "Azure-Naming-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$rows = ""
foreach ($issue in $allIssues) {
    $rows += "<tr><td>$($issue.Subscription)</td><td><b>$($issue.ResourceGroup)</b></td><td>$($issue.Environment)</td><td>$($issue.Location)</td><td>$($issue.ResourceCount)</td><td>$($issue.Databricks)</td><td style='color:red;font-size:12px'>$($issue.Issue)</td></tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Azure Naming Audit</title>
<style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1800px;margin:0 auto;background:white;padding:30px;border-radius:8px}
h1{color:#FF3621}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#1B3139;color:white;padding:10px;text-align:left;font-size:13px}
td{padding:8px;border-bottom:1px solid #ddd;font-size:12px}
tr:hover{background:#f5f5f5}
.summary{background:#f8f9fa;padding:20px;margin:20px 0;border-left:4px solid #FF3621}
</style>
</head>
<body>
<div class="container">
<h1>Azure Naming Audit Report</h1>
<p><b>Date:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><b>Account:</b> $($context.Account.Id)</p>
<div class="summary">
<h3>Summary</h3>
<p><b>Subscriptions Scanned:</b> $($subsToAudit.Count)</p>
<p><b>Resource Groups Scanned:</b> $totalRGs</p>
<p><b>Issues Found:</b> $($allIssues.Count)</p>
</div>
<h2>Naming Issues</h2>
<table>
<tr><th>Subscription</th><th>Resource Group</th><th>Environment</th><th>Location</th><th>Resources</th><th>Databricks</th><th>Issue</th></tr>
$rows
</table>
</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host "Report saved: $reportFile" -ForegroundColor Green
Write-Host "Opening report..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"
