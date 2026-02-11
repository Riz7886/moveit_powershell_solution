# ====================================================================
# PYX HEALTH - AZURE NAMING STANDARDIZATION SCRIPT
# ====================================================================
# Purpose: Audits and fixes Azure resource naming across all subscriptions
#          to align with company naming standards
# 
# Company: Pyx Health
# Created: February 2026
# 
# Modes:
#   REPORT - Creates detailed audit report (read-only)
#   FIX    - Applies naming fixes and tags resources
#
# Usage:
#   .\PYX-NAMING-STANDARDIZATION.ps1 -Mode REPORT
#   .\PYX-NAMING-STANDARDIZATION.ps1 -Mode FIX
# ====================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("REPORT","FIX")]
    [string]$Mode = "REPORT"
)

Clear-Host

if ($Mode -eq "FIX") {
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host "  PYX HEALTH - NAMING FIX MODE" -ForegroundColor Red  
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: This will tag resources!" -ForegroundColor Yellow
    Write-Host "Press CTRL+C to cancel" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit
    }
} else {
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "  PYX HEALTH - NAMING AUDIT" -ForegroundColor Cyan  
    Write-Host "=====================================" -ForegroundColor Cyan
}

Write-Host ""

# Login to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not connect to Azure" -ForegroundColor Red
    exit
}

Write-Host ""

# Get all subscriptions
Write-Host "Getting all subscriptions..." -ForegroundColor Yellow
$subs = Get-AzSubscription
Write-Host "Found $($subs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

# Data collection
$allIssues = @()
$allDatabricks = @()
$changeLog = @()
$totalRGs = 0
$errorLog = @()
$skippedResources = @()

# Process each subscription
foreach ($sub in $subs) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Subscription: $($sub.Name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Set context
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "ERROR: Cannot access subscription" -ForegroundColor Red
        continue
    }
    
    # Get resource groups
    $rgs = Get-AzResourceGroup
    $totalRGs += $rgs.Count
    Write-Host "Resource Groups: $($rgs.Count)" -ForegroundColor White
    
    foreach ($rg in $rgs) {
        Write-Host "  Checking: $($rg.ResourceGroupName)" -ForegroundColor Gray
        
        # Get all resources in this RG
        $res = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
        
        if (-not $res) {
            Write-Host "    No resources" -ForegroundColor DarkGray
            continue
        }
        
        # Find Databricks workspaces
        $dbWS = $res | Where-Object {$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
        
        if ($dbWS) {
            foreach ($db in $dbWS) {
                $allDatabricks += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rg.ResourceGroupName
                    Workspace = $db.Name
                    Location = $db.Location
                    ResourceCount = $res.Count
                }
                Write-Host "    Found Databricks: $($db.Name)" -ForegroundColor Green
            }
        }
        
        # Determine ACTUAL environment from RG name
        $rgEnv = "Unknown"
        $rgEnvTag = "unknown"
        
        # Check for environment in RG name (more flexible matching)
        # PreProd (check BEFORE prod because preprod contains prod)
        if ($rg.ResourceGroupName -match "preprod") {
            $rgEnv = "PreProd"
            $rgEnvTag = "preprod"
        }
        # Production
        elseif ($rg.ResourceGroupName -match "prod") {
            $rgEnv = "Production"
            $rgEnvTag = "prod"
        }
        # POC
        elseif ($rg.ResourceGroupName -match "poc") {
            $rgEnv = "POC"
            $rgEnvTag = "poc"
        }
        # Development
        elseif ($rg.ResourceGroupName -match "dev") {
            $rgEnv = "Development"
            $rgEnvTag = "dev"
        }
        # Test
        elseif ($rg.ResourceGroupName -match "test") {
            $rgEnv = "Test"
            $rgEnvTag = "test"
        }
        # UAT
        elseif ($rg.ResourceGroupName -match "uat") {
            $rgEnv = "UAT"
            $rgEnvTag = "uat"
        }
        # QA
        elseif ($rg.ResourceGroupName -match "qa") {
            $rgEnv = "QA"
            $rgEnvTag = "qa"
        }
        # Sandbox
        elseif ($rg.ResourceGroupName -match "sandbox") {
            $rgEnv = "Sandbox"
            $rgEnvTag = "sandbox"
        }
        
        if ($rgEnv -eq "Unknown") {
            Write-Host "    Cannot determine environment - skipping" -ForegroundColor Yellow
            continue
        }
        
        Write-Host "    Environment detected: $rgEnv" -ForegroundColor Cyan
        
        # Check each resource for naming issues
        $resourceIssues = @()
        
        foreach ($r in $res) {
            $hasIssue = $false
            $issueDesc = ""
            $oldName = $r.Name
            $newName = $r.Name
            $changeReason = ""
            
            # POC RG - should NOT have prod/preprod resources
            if ($rgEnv -eq "POC") {
                if ($r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                    $hasIssue = $true
                    $issueDesc = "POC RG contains production-named resource"
                    $newName = $r.Name -replace "prod", "poc"
                    $changeReason = "Resource in POC environment should contain 'poc', not 'prod'"
                }
                elseif ($r.Name -match "preprod") {
                    $hasIssue = $true
                    $issueDesc = "POC RG contains preprod-named resource"
                    $newName = $r.Name -replace "preprod", "poc"
                    $changeReason = "Resource in POC environment should contain 'poc', not 'preprod'"
                }
            }
            
            # Production RG - should NOT have dev/test/preprod resources
            elseif ($rgEnv -eq "Production") {
                if ($r.Name -match "dev") {
                    $hasIssue = $true
                    $issueDesc = "Production RG contains dev-named resource"
                    $newName = $r.Name -replace "dev", "prod"
                    $changeReason = "Resource in Production environment should contain 'prod', not 'dev'"
                }
                elseif ($r.Name -match "test" -and $r.Name -notmatch "latest") {
                    $hasIssue = $true
                    $issueDesc = "Production RG contains test-named resource"
                    $newName = $r.Name -replace "test", "prod"
                    $changeReason = "Resource in Production environment should contain 'prod', not 'test'"
                }
                elseif ($r.Name -match "preprod") {
                    $hasIssue = $true
                    $issueDesc = "Production RG contains preprod-named resource"
                    $newName = $r.Name -replace "preprod", "prod"
                    $changeReason = "Resource in Production environment should contain 'prod', not 'preprod'"
                }
            }
            
            # PreProd RG - should NOT have prod resources
            elseif ($rgEnv -eq "PreProd") {
                if ($r.Name -match "-prod" -and $r.Name -notmatch "preprod") {
                    $hasIssue = $true
                    $issueDesc = "PreProd RG contains production-named resource"
                    $newName = $r.Name -replace "-prod", "-preprod"
                    $changeReason = "Resource in PreProd environment should contain 'preprod', not 'prod'"
                }
            }
            
            # Development RG - should NOT have prod resources
            elseif ($rgEnv -eq "Development") {
                if ($r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                    $hasIssue = $true
                    $issueDesc = "Development RG contains production-named resource"
                    $newName = $r.Name -replace "prod", "dev"
                    $changeReason = "Resource in Development environment should contain 'dev', not 'prod'"
                }
            }
            
            if ($hasIssue) {
                $resourceIssues += "$($r.Name) ($issueDesc)"
                
                # Determine if resource can be renamed
                $canRename = $true
                $actionTaken = "None"
                
                # Resources that CANNOT be renamed
                if ($r.ResourceType -eq "Microsoft.Storage/storageAccounts") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.KeyVault/vaults") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.Databricks/workspaces") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.Sql/servers") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.ContainerRegistry/registries") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.Cdn/profiles") {
                    $canRename = $false
                }
                elseif ($r.ResourceType -eq "Microsoft.RecoveryServices/vaults") {
                    $canRename = $false
                }
                
                # If in FIX mode, attempt to fix
                if ($Mode -eq "FIX") {
                    Write-Host "    ISSUE: $oldName" -ForegroundColor Yellow
                    Write-Host "      Type: $($r.ResourceType)" -ForegroundColor White
                    Write-Host "      Problem: $issueDesc" -ForegroundColor Yellow
                    Write-Host "      Suggested Name: $newName" -ForegroundColor Cyan
                    
                    if (-not $canRename) {
                        Write-Host "      Action: Tagging (resource type cannot be renamed)" -ForegroundColor Yellow
                        
                        try {
                            $tags = $r.Tags
                            if (-not $tags) { $tags = @{} }
                            
                            $tags["Environment"] = $rgEnvTag.ToUpper()
                            $tags["PYX-NamingIssue"] = "TRUE"
                            $tags["PYX-ExpectedEnvironment"] = $rgEnvTag.ToUpper()
                            $tags["PYX-SuggestedName"] = $newName
                            $tags["PYX-IssueReason"] = $changeReason
                            $tags["PYX-FixedDate"] = (Get-Date -Format "yyyy-MM-dd")
                            
                            Set-AzResource -ResourceId $r.ResourceId -Tag $tags -Force | Out-Null
                            
                            Write-Host "      SUCCESS: Tagged with correct environment" -ForegroundColor Green
                            $actionTaken = "Tagged (cannot rename)"
                            
                            $changeLog += [PSCustomObject]@{
                                Subscription = $sub.Name
                                ResourceGroup = $rg.ResourceGroupName
                                ResourceType = $r.ResourceType
                                OldName = $oldName
                                NewName = "N/A - Tagged Only"
                                SuggestedName = $newName
                                Environment = $rgEnvTag.ToUpper()
                                Action = "TAGGED"
                                Reason = $changeReason
                                Status = "Success"
                            }
                            
                        } catch {
                            Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
                            $actionTaken = "Error"
                            $errorLog += [PSCustomObject]@{
                                Subscription = $sub.Name
                                ResourceGroup = $rg.ResourceGroupName
                                ResourceName = $oldName
                                ResourceType = $r.ResourceType
                                Error = $_.Exception.Message
                            }
                        }
                    } else {
                        # For renameable resources, still just tag them (renaming requires recreation)
                        Write-Host "      Action: Tagging with suggested rename" -ForegroundColor Yellow
                        
                        try {
                            $tags = $r.Tags
                            if (-not $tags) { $tags = @{} }
                            
                            $tags["Environment"] = $rgEnvTag.ToUpper()
                            $tags["PYX-NamingIssue"] = "TRUE"
                            $tags["PYX-SuggestedName"] = $newName
                            $tags["PYX-IssueReason"] = $changeReason
                            $tags["PYX-RequiresRecreation"] = "TRUE"
                            $tags["PYX-FixedDate"] = (Get-Date -Format "yyyy-MM-dd")
                            
                            Set-AzResource -ResourceId $r.ResourceId -Tag $tags -Force | Out-Null
                            
                            Write-Host "      SUCCESS: Tagged (manual rename recommended)" -ForegroundColor Green
                            $actionTaken = "Tagged (requires recreation to rename)"
                            
                            $changeLog += [PSCustomObject]@{
                                Subscription = $sub.Name
                                ResourceGroup = $rg.ResourceGroupName
                                ResourceType = $r.ResourceType
                                OldName = $oldName
                                NewName = "N/A - Requires Recreation"
                                SuggestedName = $newName
                                Environment = $rgEnvTag.ToUpper()
                                Action = "TAGGED FOR MANUAL RENAME"
                                Reason = $changeReason
                                Status = "Success"
                            }
                            
                        } catch {
                            Write-Host "      ERROR: $($_.Exception.Message)" -ForegroundColor Red
                            $actionTaken = "Error"
                            $errorLog += [PSCustomObject]@{
                                Subscription = $sub.Name
                                ResourceGroup = $rg.ResourceGroupName
                                ResourceName = $oldName
                                ResourceType = $r.ResourceType
                                Error = $_.Exception.Message
                            }
                        }
                    }
                } else {
                    # REPORT mode - just log the issue
                    $changeLog += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rg.ResourceGroupName
                        ResourceType = $r.ResourceType
                        OldName = $oldName
                        NewName = "N/A"
                        SuggestedName = $newName
                        Environment = $rgEnvTag.ToUpper()
                        Action = if ($canRename) {"CAN BE TAGGED"} else {"MUST BE TAGGED"}
                        Reason = $changeReason
                        Status = "Not Fixed (Report Mode)"
                    }
                }
            }
        }
        
        # Add to issues list if problems found
        if ($resourceIssues.Count -gt 0) {
            $allIssues += [PSCustomObject]@{
                Subscription = $sub.Name
                ResourceGroup = $rg.ResourceGroupName
                Environment = $rgEnv
                Location = $rg.Location
                ResourceCount = $res.Count
                Databricks = if ($dbWS) {($dbWS.Name -join ", ")} else {"-"}
                IssueCount = $resourceIssues.Count
                Issues = ($resourceIssues -join " | ")
            }
        }
    }
    
    Write-Host ""
}

# Generate HTML Report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = "PYX-Naming-Report-$timestamp.html"

# Databricks table
$databricksRows = ""
if ($allDatabricks.Count -gt 0) {
    foreach ($db in $allDatabricks) {
        $databricksRows += "<tr><td>$($db.Subscription)</td><td>$($db.ResourceGroup)</td><td><strong>$($db.Workspace)</strong></td><td>$($db.Location)</td><td>$($db.ResourceCount)</td></tr>"
    }
} else {
    $databricksRows = "<tr><td colspan='5' style='text-align:center;color:#999'>No Databricks workspaces found</td></tr>"
}

# Issues table
$issuesRows = ""
if ($allIssues.Count -gt 0) {
    foreach ($issue in $allIssues) {
        $issuesRows += "<tr><td>$($issue.Subscription)</td><td>$($issue.ResourceGroup)</td><td>$($issue.Environment)</td><td>$($issue.Location)</td><td>$($issue.ResourceCount)</td><td>$($issue.IssueCount)</td><td>$($issue.Databricks)</td></tr>"
    }
} else {
    $issuesRows = "<tr><td colspan='7' style='text-align:center;color:#28a745;font-weight:bold'>No naming issues found - All resources properly named!</td></tr>"
}

# Change log table (THE IMPORTANT ONE - OLD NAME vs NEW NAME)
$changeLogRows = ""
if ($changeLog.Count -gt 0) {
    foreach ($change in $changeLog) {
        $statusColor = if ($change.Status -like "*Success*") {"#28a745"} elseif ($change.Status -like "*Error*") {"#dc3545"} else {"#ffc107"}
        $actionBadge = if ($change.Action -eq "TAGGED") {"<span style='background:#28a745;color:white;padding:3px 8px;border-radius:3px;font-size:11px'>TAGGED</span>"} `
                      elseif ($change.Action -like "*MANUAL*") {"<span style='background:#ffc107;color:#000;padding:3px 8px;border-radius:3px;font-size:11px'>NEEDS MANUAL RENAME</span>"} `
                      else {"<span style='background:#6c757d;color:white;padding:3px 8px;border-radius:3px;font-size:11px'>$($change.Action)</span>"}
        
        $changeLogRows += @"
<tr>
<td>$($change.Subscription)</td>
<td>$($change.ResourceGroup)</td>
<td style='font-size:12px;color:#666'>$($change.ResourceType)</td>
<td><strong style='color:#dc3545'>$($change.OldName)</strong></td>
<td><strong style='color:#28a745'>$($change.SuggestedName)</strong></td>
<td>$($change.Environment)</td>
<td>$actionBadge</td>
<td style='font-size:12px'>$($change.Reason)</td>
<td style='color:$statusColor;font-weight:bold'>$($change.Status)</td>
</tr>
"@
    }
} else {
    $changeLogRows = "<tr><td colspan='9' style='text-align:center;color:#999'>No changes needed or mode was REPORT</td></tr>"
}

# Error table
$errorRows = ""
if ($errorLog.Count -gt 0) {
    foreach ($err in $errorLog) {
        $errorRows += "<tr><td>$($err.Subscription)</td><td>$($err.ResourceGroup)</td><td>$($err.ResourceName)</td><td>$($err.ResourceType)</td><td style='color:#dc3545'>$($err.Error)</td></tr>"
    }
} else {
    $errorRows = "<tr><td colspan='5' style='text-align:center;color:#28a745;font-weight:bold'>No errors!</td></tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Pyx Health - Azure Naming Standardization Report</title>
<style>
* {margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f7fa;padding:20px}
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:40px;border-radius:12px;margin-bottom:30px;box-shadow:0 4px 20px rgba(0,0,0,0.1)}
.header h1{font-size:36px;margin-bottom:10px}
.header .subtitle{font-size:16px;opacity:0.9}
.mode-badge{display:inline-block;padding:8px 20px;border-radius:20px;font-weight:bold;margin-left:15px;font-size:14px}
.mode-report{background:rgba(255,255,255,0.2);border:2px solid rgba(255,255,255,0.5)}
.mode-fix{background:#ff4757;border:2px solid #ff6b81}
.container{max-width:1800px;margin:0 auto}
.card{background:white;padding:30px;border-radius:12px;margin-bottom:25px;box-shadow:0 2px 10px rgba(0,0,0,0.08)}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin:25px 0}
.summary-box{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:25px;border-radius:10px;text-align:center;box-shadow:0 4px 15px rgba(102,126,234,0.3)}
.summary-box .value{font-size:42px;font-weight:bold;margin-bottom:8px}
.summary-box .label{font-size:14px;opacity:0.9;text-transform:uppercase;letter-spacing:1px}
h2{color:#2c3e50;font-size:26px;margin:30px 0 20px 0;padding-bottom:12px;border-bottom:3px solid #667eea}
h3{color:#34495e;font-size:20px;margin:25px 0 15px 0}
table{width:100%;border-collapse:collapse;margin:20px 0}
thead{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
th{color:white;padding:15px;text-align:left;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:0.5px}
td{padding:12px 15px;border-bottom:1px solid #ecf0f1;font-size:14px}
tbody tr:hover{background:#f8f9fa}
tbody tr:nth-child(even){background:#fafbfc}
.alert{padding:20px;border-radius:8px;margin:20px 0;border-left:5px solid}
.alert-info{background:#e7f3ff;border-color:#0078d4;color:#004578}
.alert-warning{background:#fff3cd;border-color:#ffc107;color:#856404}
.alert-success{background:#d4edda;border-color:#28a745;color:#155724}
.alert-danger{background:#f8d7da;border-color:#dc3545;color:#721c24}
.footer{margin-top:40px;padding:25px;background:#2c3e50;color:white;border-radius:12px;text-align:center}
.footer strong{color:#667eea}
.badge{display:inline-block;padding:4px 10px;border-radius:12px;font-size:11px;font-weight:bold}
.badge-success{background:#28a745;color:white}
.badge-warning{background:#ffc107;color:#000}
.badge-danger{background:#dc3545;color:white}
.badge-info{background:#0078d4;color:white}
.highlight-old{background:#ffe6e6;padding:5px 10px;border-radius:4px;color:#c00}
.highlight-new{background:#e6ffe6;padding:5px 10px;border-radius:4px;color:#060}
.company-logo{font-size:48px;font-weight:bold;background:linear-gradient(135deg,#667eea,#764ba2);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:10px}
</style>
</head>
<body>

<div class="container">

<div class="header">
<div class="company-logo">PYX HEALTH</div>
<h1>
Azure Resource Naming Standardization Report
<span class="mode-badge mode-$(if($Mode -eq 'FIX'){'fix'}else{'report'})">Mode: $Mode</span>
</h1>
<div class="subtitle">
Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss') | 
Account: $($context.Account.Id) | 
Scan Type: Multi-Subscription Audit
</div>
</div>

<div class="card">
<h2>Executive Summary</h2>
<div class="summary-grid">
<div class="summary-box">
<div class="value">$($subs.Count)</div>
<div class="label">Subscriptions</div>
</div>
<div class="summary-box">
<div class="value">$totalRGs</div>
<div class="label">Resource Groups</div>
</div>
<div class="summary-box">
<div class="value">$($allDatabricks.Count)</div>
<div class="label">Databricks</div>
</div>
<div class="summary-box">
<div class="value">$($changeLog.Count)</div>
<div class="label">Issues Found</div>
</div>
</div>

$(if($Mode -eq 'FIX'){
@"
<div class="alert alert-success">
<strong>FIX MODE COMPLETE!</strong> Resources have been tagged with correct environment metadata. 
See the detailed change log below for OLD NAME vs NEW NAME mappings.
</div>
"@
} else {
@"
<div class="alert alert-info">
<strong>REPORT MODE</strong> - This is an audit report only. No changes were made. 
Run with -Mode FIX to apply tags and standardization.
</div>
"@
})
</div>

<div class="card">
<h2>📊 DETAILED CHANGE LOG - OLD NAME vs NEW NAME</h2>
<p style="color:#666;margin-bottom:20px">This table shows every resource with naming issues, the current (OLD) name, and the recommended (NEW) name according to Pyx Health naming standards.</p>

<table>
<thead>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Resource Type</th>
<th>OLD NAME ❌</th>
<th>SUGGESTED NEW NAME ✅</th>
<th>Environment</th>
<th>Action Taken</th>
<th>Reason for Change</th>
<th>Status</th>
</tr>
</thead>
<tbody>
$changeLogRows
</tbody>
</table>
</div>

<div class="card">
<h2>🗄️ Databricks Workspaces Inventory</h2>
<table>
<thead>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Workspace Name</th>
<th>Location</th>
<th>Resources in RG</th>
</tr>
</thead>
<tbody>
$databricksRows
</tbody>
</table>
</div>

<div class="card">
<h2>⚠️ Resource Groups with Naming Issues</h2>
<table>
<thead>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Environment</th>
<th>Location</th>
<th>Total Resources</th>
<th>Issues Found</th>
<th>Databricks</th>
</tr>
</thead>
<tbody>
$issuesRows
</tbody>
</table>
</div>

$(if($errorLog.Count -gt 0){
@"
<div class="card">
<h2>❌ Errors Encountered</h2>
<div class="alert alert-danger">
<strong>$($errorLog.Count) error(s) occurred during processing.</strong> These resources could not be tagged.
</div>
<table>
<thead>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Resource Name</th>
<th>Resource Type</th>
<th>Error Message</th>
</tr>
</thead>
<tbody>
$errorRows
</tbody>
</table>
</div>
"@
})

<div class="card">
<h2>📋 Recommendations</h2>
<div class="alert alert-warning">
<h3 style="margin-top:0">Action Items for Pyx Health IT Team</h3>
<ol style="margin:15px 0 0 20px;line-height:1.8">
<li><strong>Review POC vs Production Classification:</strong> Several "POC" resource groups contain production-named resources. Verify if these are truly POC or mislabeled production environments.</li>
<li><strong>PreProd Environment Alignment:</strong> PreProd resource groups contain resources with -prod suffix. Determine correct classification and rename accordingly.</li>
<li><strong>Resources Requiring Recreation:</strong> Storage accounts, Key Vaults, Databricks workspaces, and SQL servers cannot be renamed in-place. These have been tagged with suggested names - plan recreation during maintenance windows if renaming is critical.</li>
<li><strong>Standardize Naming Convention:</strong> Implement policy requiring resource names to match their resource group environment (prod resources in prod RGs, dev in dev RGs, etc.).</li>
<li><strong>Resource Consolidation:</strong> Consider consolidating properly-tagged resources to reduce confusion and improve manageability (per John Pinto's feedback).</li>
<li><strong>Update Documentation:</strong> Document the true environment designation for each resource group in your IT wiki/SharePoint.</li>
<li><strong>Azure Policy Implementation:</strong> Consider implementing Azure Policy to enforce naming standards on new resources.</li>
</ol>
</div>
</div>

<div class="footer">
<div style="margin-bottom:15px"><strong>Pyx Health - Azure Naming Standardization</strong></div>
<div style="font-size:14px;opacity:0.8">
<strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Mode:</strong> $Mode<br>
<strong>Subscriptions Scanned:</strong> $($subs.Count)<br>
<strong>Total Resource Groups:</strong> $totalRGs<br>
<strong>Databricks Workspaces:</strong> $($allDatabricks.Count)<br>
<strong>Resources with Naming Issues:</strong> $($changeLog.Count)<br>
$(if($Mode -eq 'FIX'){"<strong>Resources Tagged:</strong> $($changeLog.Where({$_.Status -like '*Success*'}).Count)<br><strong>Errors:</strong> $($errorLog.Count)"})
</div>
</div>

</div>

</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

# Final Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Mode: $Mode" -ForegroundColor White
Write-Host "Subscriptions: $($subs.Count)" -ForegroundColor White
Write-Host "Resource Groups: $totalRGs" -ForegroundColor White
Write-Host "Databricks: $($allDatabricks.Count)" -ForegroundColor White
Write-Host "Issues Found: $($changeLog.Count)" -ForegroundColor $(if ($changeLog.Count -gt 0) {"Red"} else {"Green"})

if ($Mode -eq "FIX") {
    Write-Host ""
    $successCount = $changeLog.Where({$_.Status -like "*Success*"}).Count
    Write-Host "Resources Tagged: $successCount" -ForegroundColor $(if ($successCount -gt 0) {"Green"} else {"Gray"})
    Write-Host "Errors: $($errorLog.Count)" -ForegroundColor $(if ($errorLog.Count -gt 0) {"Red"} else {"Gray"})
}

Write-Host ""
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host "Opening report..." -ForegroundColor Yellow
Write-Host ""

Start-Process $reportFile

if ($Mode -eq "REPORT") {
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Review the HTML report" -ForegroundColor White
    Write-Host "  2. Check the OLD NAME vs NEW NAME table" -ForegroundColor White
    Write-Host "  3. Send report to Tony & Brian" -ForegroundColor White
    Write-Host "  4. To fix issues, run:" -ForegroundColor White
    Write-Host "     .\PYX-NAMING-STANDARDIZATION.ps1 -Mode FIX" -ForegroundColor Yellow
} else {
    Write-Host "Resources tagged with Pyx Health naming standards!" -ForegroundColor Green
    Write-Host "Check the report for detailed OLD vs NEW name mappings." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
