# AZURE MULTI-SUB AUDIT - DEVICE CODE AUTH
# This version uses device code - MOST RELIABLE!

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AZURE MULTI-SUBSCRIPTION AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Clear old sessions
Write-Host "Clearing old sessions..." -ForegroundColor Yellow
Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
Clear-AzContext -Force -ErrorAction SilentlyContinue

# Connect with DEVICE CODE (most reliable)
Write-Host ""
Write-Host "LOGGING IN WITH DEVICE CODE..." -ForegroundColor Cyan
Write-Host "A browser window will open for you to login" -ForegroundColor Yellow
Write-Host ""

try {
    Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
} catch {
    Write-Host "ERROR: Login failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

Write-Host ""
Write-Host "Login successful!" -ForegroundColor Green
Write-Host ""

# Get ALL subscriptions
Write-Host "Loading subscriptions..." -ForegroundColor Yellow
$allSubs = Get-AzSubscription

if ($allSubs.Count -eq 0) {
    Write-Host ""
    Write-Host "ERROR: No subscriptions found!" -ForegroundColor Red
    Write-Host "Your account may not have access to any subscriptions." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "Found: $($allSubs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

# Show subscription menu
Write-Host "SELECT SUBSCRIPTION:" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $allSubs.Count; $i++) {
    $sub = $allSubs[$i]
    $num = $i + 1
    Write-Host "  [$num] $($sub.Name)" -ForegroundColor White
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

# Select subscriptions to audit
$subsToAudit = @()

if ($choice -eq "A" -or $choice -eq "a") {
    Write-Host ""
    Write-Host "Will audit ALL $($allSubs.Count) subscriptions" -ForegroundColor Yellow
    $subsToAudit = $allSubs
} else {
    try {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $allSubs.Count) {
            $subsToAudit = @($allSubs[$index])
            Write-Host ""
            Write-Host "Will audit: $($subsToAudit[0].Name)" -ForegroundColor Yellow
        } else {
            Write-Host "Invalid choice" -ForegroundColor Red
            exit
        }
    } catch {
        Write-Host "Invalid input" -ForegroundColor Red
        exit
    }
}

Write-Host ""
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Cancelled" -ForegroundColor Yellow
    exit
}

# Run audit
Write-Host ""
Write-Host "Starting audit..." -ForegroundColor Cyan
Write-Host ""

$allIssues = @()
$totalRGs = 0

foreach ($sub in $subsToAudit) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $($sub.Name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    try {
        Set-AzContext -Subscription $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "ERROR: Cannot access subscription" -ForegroundColor Red
        continue
    }
    
    $rgs = Get-AzResourceGroup
    $totalRGs += $rgs.Count
    Write-Host "Resource Groups: $($rgs.Count)" -ForegroundColor Green
    Write-Host ""
    
    foreach ($rg in $rgs) {
        Write-Host "  Checking: $($rg.ResourceGroupName)" -ForegroundColor Gray
        
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
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
        } elseif ($rg.ResourceGroupName -match "test|qa") {
            $env = "Test"
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
            foreach ($p in $problems) {
                $allIssues += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rg.ResourceGroupName
                    Environment = $env
                    Location = $rg.Location
                    ResourceCount = $resources.Count
                    Databricks = if ($databricks) {($databricks.Name -join ", ")} else {"None"}
                    Issue = $p
                }
            }
        }
    }
    
    Write-Host ""
}

# Show results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Subscriptions Scanned: $($subsToAudit.Count)" -ForegroundColor White
Write-Host "Resource Groups Scanned: $totalRGs" -ForegroundColor White
Write-Host "Naming Issues Found: $($allIssues.Count)" -ForegroundColor $(if ($allIssues.Count -gt 0) {"Red"} else {"Green"})
Write-Host ""

if ($allIssues.Count -eq 0) {
    Write-Host "No naming issues found!" -ForegroundColor Green
} else {
    Write-Host "ISSUES FOUND:" -ForegroundColor Yellow
    Write-Host ""
    $allIssues | Format-Table Subscription, ResourceGroup, Environment, Issue -AutoSize -Wrap
}

# Generate HTML report
$reportFile = "Azure-Naming-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$rows = ""
foreach ($issue in $allIssues) {
    $rows += "<tr><td>$($issue.Subscription)</td><td><strong>$($issue.ResourceGroup)</strong></td><td>$($issue.Environment)</td><td>$($issue.Location)</td><td>$($issue.ResourceCount)</td><td>$($issue.Databricks)</td><td style='color:red;font-size:12px'>$($issue.Issue)</td></tr>"
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
<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<div class="summary">
<h3>Summary</h3>
<p><strong>Subscriptions Scanned:</strong> $($subsToAudit.Count)</p>
<p><strong>Resource Groups Scanned:</strong> $totalRGs</p>
<p><strong>Issues Found:</strong> $($allIssues.Count)</p>
</div>
<h2>Issues Detected</h2>
<table>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Environment</th>
<th>Location</th>
<th>Resources</th>
<th>Databricks</th>
<th>Issue</th>
</tr>
$rows
</table>
</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "Report saved: $reportFile" -ForegroundColor Green
Write-Host "Opening report..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"
