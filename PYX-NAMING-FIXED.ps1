# ====================================================================
# PYX HEALTH - AZURE NAMING AUDIT AND FIX
# ====================================================================
# FIXED VERSION - Processes ALL resource groups even if environment
# cannot be auto-detected
# ====================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("REPORT","FIX")]
    [string]$Mode = "REPORT"
)

Clear-Host

if ($Mode -eq "FIX") {
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host "  PYX HEALTH - FIX MODE" -ForegroundColor Red  
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: This will tag resources!" -ForegroundColor Yellow
    $confirm = Read-Host "Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit
    }
} else {
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  PYX HEALTH - REPORT MODE" -ForegroundColor Cyan  
    Write-Host "=====================================" -ForegroundColor Cyan
}

Write-Host ""

# Login
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot connect" -ForegroundColor Red
    exit
}

Write-Host ""

# Get subscriptions
Write-Host "Getting subscriptions..." -ForegroundColor Yellow
$subs = Get-AzSubscription
Write-Host "Found: $($subs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

# Data
$allIssues = @()
$allDatabricks = @()
$changeLog = @()
$allResourceGroups = @()
$totalRGs = 0

# Process
foreach ($sub in $subs) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $($sub.Name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "ERROR: Cannot access" -ForegroundColor Red
        continue
    }
    
    $rgs = Get-AzResourceGroup
    $totalRGs += $rgs.Count
    Write-Host "Resource Groups: $($rgs.Count)" -ForegroundColor White
    Write-Host ""
    
    foreach ($rg in $rgs) {
        $rgName = $rg.ResourceGroupName
        Write-Host "  Checking: $rgName" -ForegroundColor Gray
        
        # Auto-detect environment (but don't skip if unknown)
        $rgEnv = "Unknown"
        $rgEnvTag = "unknown"
        
        if ($rgName -match "preprod") {
            $rgEnv = "PreProd"
            $rgEnvTag = "preprod"
        }
        elseif ($rgName -match "prod") {
            $rgEnv = "Production"
            $rgEnvTag = "prod"
        }
        elseif ($rgName -match "poc") {
            $rgEnv = "POC"
            $rgEnvTag = "poc"
        }
        elseif ($rgName -match "dev") {
            $rgEnv = "Development"
            $rgEnvTag = "dev"
        }
        elseif ($rgName -match "test") {
            $rgEnv = "Test"
            $rgEnvTag = "test"
        }
        elseif ($rgName -match "qa") {
            $rgEnv = "QA"
            $rgEnvTag = "qa"
        }
        elseif ($rgName -match "uat") {
            $rgEnv = "UAT"
            $rgEnvTag = "uat"
        }
        
        Write-Host "    Environment: $rgEnv" -ForegroundColor Cyan
        
        # Get resources
        $res = Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue
        
        if (-not $res) {
            Write-Host "    No resources" -ForegroundColor DarkGray
            continue
        }
        
        Write-Host "    Resources: $($res.Count)" -ForegroundColor White
        
        # Track this RG
        $allResourceGroups += [PSCustomObject]@{
            Subscription = $sub.Name
            ResourceGroup = $rgName
            Environment = $rgEnv
            Location = $rg.Location
            ResourceCount = $res.Count
        }
        
        # Find Databricks
        $dbWS = $res | Where-Object {$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
        
        if ($dbWS) {
            foreach ($db in $dbWS) {
                $allDatabricks += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rgName
                    Workspace = $db.Name
                    Location = $db.Location
                    ResourceCount = $res.Count
                }
                Write-Host "    DATABRICKS: $($db.Name)" -ForegroundColor Green
            }
        }
        
        # Check naming issues (ONLY if we know the environment)
        if ($rgEnv -ne "Unknown") {
            foreach ($r in $res) {
                $hasIssue = $false
                $oldName = $r.Name
                $newName = $r.Name
                $issueDesc = ""
                $changeReason = ""
                
                # POC
                if ($rgEnv -eq "POC") {
                    if ($r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                        $hasIssue = $true
                        $issueDesc = "POC RG has prod-named resource"
                        $newName = $r.Name -replace "prod", "poc"
                        $changeReason = "Resource in POC should contain 'poc' not 'prod'"
                    }
                }
                
                # Production
                elseif ($rgEnv -eq "Production") {
                    if ($r.Name -match "dev") {
                        $hasIssue = $true
                        $issueDesc = "Prod RG has dev-named resource"
                        $newName = $r.Name -replace "dev", "prod"
                        $changeReason = "Resource in Production should contain 'prod' not 'dev'"
                    }
                    elseif ($r.Name -match "test" -and $r.Name -notmatch "latest") {
                        $hasIssue = $true
                        $issueDesc = "Prod RG has test-named resource"
                        $newName = $r.Name -replace "test", "prod"
                        $changeReason = "Resource in Production should contain 'prod' not 'test'"
                    }
                    elseif ($r.Name -match "preprod") {
                        $hasIssue = $true
                        $issueDesc = "Prod RG has preprod-named resource"
                        $newName = $r.Name -replace "preprod", "prod"
                        $changeReason = "Resource in Production should contain 'prod' not 'preprod'"
                    }
                }
                
                # PreProd
                elseif ($rgEnv -eq "PreProd") {
                    if ($r.Name -match "\\-prod" -and $r.Name -notmatch "preprod") {
                        $hasIssue = $true
                        $issueDesc = "PreProd RG has prod-named resource"
                        $newName = $r.Name -replace "\\-prod", "-preprod"
                        $changeReason = "Resource in PreProd should contain 'preprod' not 'prod'"
                    }
                }
                
                if ($hasIssue) {
                    Write-Host "      ISSUE: $oldName → $newName" -ForegroundColor Yellow
                    
                    # Log the issue
                    $changeLog += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rgName
                        ResourceType = $r.ResourceType
                        OldName = $oldName
                        SuggestedName = $newName
                        Environment = $rgEnvTag.ToUpper()
                        Reason = $changeReason
                        Status = if ($Mode -eq "FIX") {"Will be tagged"} else {"Detected in report"}
                    }
                    
                    # FIX mode - tag the resource
                    if ($Mode -eq "FIX") {
                        try {
                            $tags = $r.Tags
                            if (-not $tags) { $tags = @{} }
                            
                            $tags["PYX-Environment"] = $rgEnvTag.ToUpper()
                            $tags["PYX-NamingIssue"] = "TRUE"
                            $tags["PYX-SuggestedName"] = $newName
                            $tags["PYX-Reason"] = $changeReason
                            $tags["PYX-FixedDate"] = (Get-Date -Format "yyyy-MM-dd")
                            
                            Set-AzResource -ResourceId $r.ResourceId -Tag $tags -Force | Out-Null
                            Write-Host "        TAGGED!" -ForegroundColor Green
                            
                        } catch {
                            Write-Host "        ERROR: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
            }
        }
    }
    
    Write-Host ""
}

# Generate Report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = "PYX-Report-$timestamp.html"

# RG table
$rgRows = ""
if ($allResourceGroups.Count -gt 0) {
    foreach ($rg in $allResourceGroups) {
        $envColor = if ($rg.Environment -eq "Unknown") {"#ffc107"} else {"#28a745"}
        $rgRows += "<tr><td>$($rg.Subscription)</td><td><strong>$($rg.ResourceGroup)</strong></td><td style='color:$envColor'>$($rg.Environment)</td><td>$($rg.Location)</td><td>$($rg.ResourceCount)</td></tr>"
    }
} else {
    $rgRows = "<tr><td colspan='5' style='text-align:center'>No resource groups found</td></tr>"
}

# Databricks table
$dbRows = ""
if ($allDatabricks.Count -gt 0) {
    foreach ($db in $allDatabricks) {
        $dbRows += "<tr><td>$($db.Subscription)</td><td>$($db.ResourceGroup)</td><td><strong>$($db.Workspace)</strong></td><td>$($db.Location)</td></tr>"
    }
} else {
    $dbRows = "<tr><td colspan='4' style='text-align:center'>No Databricks found</td></tr>"
}

# Change log table
$changeRows = ""
if ($changeLog.Count -gt 0) {
    foreach ($c in $changeLog) {
        $changeRows += @"
<tr>
<td>$($c.Subscription)</td>
<td>$($c.ResourceGroup)</td>
<td style='font-size:12px'>$($c.ResourceType)</td>
<td><span style='background:#ffe6e6;padding:5px 10px;border-radius:4px;color:#c00'>$($c.OldName)</span></td>
<td><span style='background:#e6ffe6;padding:5px 10px;border-radius:4px;color:#060'>$($c.SuggestedName)</span></td>
<td>$($c.Environment)</td>
<td style='font-size:12px'>$($c.Reason)</td>
<td>$($c.Status)</td>
</tr>
"@
    }
} else {
    $changeRows = "<tr><td colspan='8' style='text-align:center;color:#28a745;font-weight:bold'>No naming issues found!</td></tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Pyx Health - Azure Naming Report</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f7fa;padding:20px}
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:40px;border-radius:12px;margin-bottom:30px}
.header h1{font-size:36px;margin-bottom:10px}
.header .sub{font-size:16px;opacity:0.9}
.mode{display:inline-block;padding:8px 20px;border-radius:20px;font-weight:bold;margin-left:15px;background:rgba(255,255,255,0.2);border:2px solid rgba(255,255,255,0.5)}
.container{max-width:1800px;margin:0 auto}
.card{background:white;padding:30px;border-radius:12px;margin-bottom:25px;box-shadow:0 2px 10px rgba(0,0,0,0.08)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:25px 0}
.box{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:25px;border-radius:10px;text-align:center}
.box .val{font-size:42px;font-weight:bold;margin-bottom:8px}
.box .label{font-size:14px;opacity:0.9}
h2{color:#2c3e50;font-size:26px;margin:30px 0 20px 0;padding-bottom:12px;border-bottom:3px solid #667eea}
table{width:100%;border-collapse:collapse;margin:20px 0}
thead{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
th{color:white;padding:15px;text-align:left;font-weight:600;font-size:13px}
td{padding:12px 15px;border-bottom:1px solid #ecf0f1;font-size:14px}
tbody tr:hover{background:#f8f9fa}
tbody tr:nth-child(even){background:#fafbfc}
.footer{margin-top:40px;padding:25px;background:#2c3e50;color:white;border-radius:12px;text-align:center}
</style>
</head>
<body>
<div class="container">

<div class="header">
<h1>PYX HEALTH - Azure Naming Report <span class="mode">$Mode</span></h1>
<div class="sub">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Account: $($context.Account.Id)</div>
</div>

<div class="card">
<h2>Summary</h2>
<div class="grid">
<div class="box"><div class="val">$($subs.Count)</div><div class="label">Subscriptions</div></div>
<div class="box"><div class="val">$totalRGs</div><div class="label">Resource Groups</div></div>
<div class="box"><div class="val">$($allDatabricks.Count)</div><div class="label">Databricks</div></div>
<div class="box"><div class="val">$($changeLog.Count)</div><div class="label">Issues Found</div></div>
</div>
</div>

<div class="card">
<h2>ALL RESOURCE GROUPS SCANNED</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Environment</th><th>Location</th><th>Resources</th></tr></thead>
<tbody>$rgRows</tbody>
</table>
</div>

<div class="card">
<h2>DATABRICKS WORKSPACES</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Workspace</th><th>Location</th></tr></thead>
<tbody>$dbRows</tbody>
</table>
</div>

<div class="card">
<h2>NAMING ISSUES - OLD vs NEW</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Type</th><th>OLD NAME</th><th>SUGGESTED NEW</th><th>Env</th><th>Reason</th><th>Status</th></tr></thead>
<tbody>$changeRows</tbody>
</table>
</div>

<div class="footer">
<strong>Pyx Health - Azure Naming Report</strong><br>
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Mode: $Mode<br>
Subscriptions: $($subs.Count) | Resource Groups: $totalRGs | Databricks: $($allDatabricks.Count) | Issues: $($changeLog.Count)
</div>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Mode: $Mode" -ForegroundColor White
Write-Host "Subscriptions: $($subs.Count)" -ForegroundColor White
Write-Host "Resource Groups: $totalRGs" -ForegroundColor White
Write-Host "Databricks: $($allDatabricks.Count)" -ForegroundColor White
Write-Host "Issues: $($changeLog.Count)" -ForegroundColor $(if ($changeLog.Count -gt 0) {"Yellow"} else {"Green"})
Write-Host ""
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host ""

Start-Process $reportFile

Write-Host "Done!" -ForegroundColor Green
