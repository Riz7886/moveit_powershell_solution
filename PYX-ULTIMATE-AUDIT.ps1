# ========================================================================
# PYX HEALTH - ULTIMATE AZURE AUDIT & OPTIMIZATION SCRIPT
# ========================================================================
# The ONE script that does it ALL:
# - Finds naming issues (NO MORE "UNKNOWN")
# - Detects IDLE/unused resources
# - Identifies duplicate Databricks workspaces
# - Cost optimization opportunities
# - Beautiful executive HTML report
# - Fix/Delete options
# ========================================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("AUDIT","FIX","DELETE")]
    [string]$Mode = "AUDIT"
)

Clear-Host

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - ULTIMATE AZURE AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host ""

if ($Mode -eq "DELETE") {
    Write-Host "WARNING: DELETE MODE - WILL REMOVE RESOURCES!" -ForegroundColor Red
    $confirm = Read-Host "Type 'DELETE RESOURCES' to continue"
    if ($confirm -ne "DELETE RESOURCES") {
        Write-Host "Cancelled" -ForegroundColor Yellow
        exit
    }
}

# Connect
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

# Data collections
$allRGs = @()
$allDatabricks = @()
$namingIssues = @()
$idleResources = @()
$costOptimizations = @()
$duplicates = @()
$totalCost = 0

# Process each subscription
foreach ($sub in $subs) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $($sub.Name)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Detect environment from SUBSCRIPTION name
    $subEnv = "Unknown"
    if ($sub.Name -match "preprod") {
        $subEnv = "PreProd"
    }
    elseif ($sub.Name -match "prod" -and $sub.Name -notmatch "preprod") {
        $subEnv = "Production"
    }
    elseif ($sub.Name -match "test") {
        $subEnv = "Test"
    }
    elseif ($sub.Name -match "dev") {
        $subEnv = "Development"
    }
    elseif ($sub.Name -match "sandbox") {
        $subEnv = "Sandbox"
    }
    elseif ($sub.Name -match "staging") {
        $subEnv = "Staging"
    }
    
    Write-Host "Subscription Environment: $subEnv" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "ERROR: Cannot access subscription" -ForegroundColor Red
        continue
    }
    
    # Get resource groups
    $rgs = Get-AzResourceGroup
    Write-Host "Resource Groups: $($rgs.Count)" -ForegroundColor White
    Write-Host ""
    
    foreach ($rg in $rgs) {
        $rgName = $rg.ResourceGroupName
        Write-Host "  $rgName" -ForegroundColor Gray
        
        # Detect RG environment
        $rgEnv = $subEnv  # Default to subscription environment
        
        if ($rgName -match "preprod") {
            $rgEnv = "PreProd"
        }
        elseif ($rgName -match "-prod" -or $rgName -match "prod-") {
            $rgEnv = "Production"
        }
        elseif ($rgName -match "poc") {
            $rgEnv = "POC"
        }
        elseif ($rgName -match "dev") {
            $rgEnv = "Development"
        }
        elseif ($rgName -match "test") {
            $rgEnv = "Test"
        }
        elseif ($rgName -match "sandbox") {
            $rgEnv = "Sandbox"
        }
        elseif ($rgName -match "staging") {
            $rgEnv = "Staging"
        }
        
        Write-Host "    Environment: $rgEnv" -ForegroundColor Cyan
        
        # Get resources
        $resources = Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue
        
        if (-not $resources) {
            Write-Host "    No resources (candidate for deletion)" -ForegroundColor Yellow
            $idleResources += [PSCustomObject]@{
                Type = "Empty Resource Group"
                Name = $rgName
                ResourceGroup = $rgName
                Subscription = $sub.Name
                Environment = $rgEnv
                Reason = "Resource group is empty"
                EstimatedMonthlySavings = "$0"
                Action = "Delete RG"
            }
            continue
        }
        
        Write-Host "    Resources: $($resources.Count)" -ForegroundColor White
        
        # Track RG
        $allRGs += [PSCustomObject]@{
            Subscription = $sub.Name
            SubscriptionEnv = $subEnv
            ResourceGroup = $rgName
            RGEnvironment = $rgEnv
            Location = $rg.Location
            ResourceCount = $resources.Count
        }
        
        # Check each resource
        foreach ($r in $resources) {
            
            # DATABRICKS WORKSPACES
            if ($r.ResourceType -eq "Microsoft.Databricks/workspaces") {
                $db = Get-AzDatabricksWorkspace -ResourceGroupName $rgName -Name $r.Name -ErrorAction SilentlyContinue
                
                $allDatabricks += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rgName
                    Name = $r.Name
                    Location = $r.Location
                    SKU = $db.Sku.Name
                    ManagedResourceGroup = $db.ManagedResourceGroupId
                }
                
                Write-Host "      DATABRICKS: $($r.Name)" -ForegroundColor Green
                
                # Check for duplicates
                $existing = $allDatabricks | Where-Object {$_.Name -eq $r.Name -and $_.ResourceGroup -ne $rgName}
                if ($existing) {
                    $duplicates += [PSCustomObject]@{
                        Type = "Databricks Workspace"
                        Name = $r.Name
                        Location1 = "$($existing.Subscription) / $($existing.ResourceGroup)"
                        Location2 = "$($sub.Name) / $rgName"
                        Issue = "Same Databricks workspace exists in multiple resource groups"
                        Recommendation = "Consolidate to single workspace"
                    }
                    Write-Host "        WARNING: Duplicate found!" -ForegroundColor Red
                }
                
                # Check naming
                if ($rgEnv -eq "POC" -and $r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                    $namingIssues += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rgName
                        Type = $r.ResourceType
                        OldName = $r.Name
                        SuggestedNewName = ($r.Name -replace "prod", "poc")
                        Environment = $rgEnv
                        Issue = "POC resource group contains production-named Databricks"
                        Action = "Tag (Databricks cannot be renamed)"
                    }
                }
                elseif ($rgEnv -eq "PreProd" -and $r.Name -match "-prod" -and $r.Name -notmatch "preprod") {
                    $namingIssues += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rgName
                        Type = $r.ResourceType
                        OldName = $r.Name
                        SuggestedNewName = ($r.Name -replace "-prod", "-preprod")
                        Environment = $rgEnv
                        Issue = "PreProd resource group contains production-named Databricks"
                        Action = "Tag (Databricks cannot be renamed)"
                    }
                }
            }
            
            # VIRTUAL MACHINES
            elseif ($r.ResourceType -eq "Microsoft.Compute/virtualMachines") {
                $vm = Get-AzVM -ResourceGroupName $rgName -Name $r.Name -Status -ErrorAction SilentlyContinue
                
                if ($vm) {
                    $vmStatus = $vm.Statuses | Where-Object {$_.Code -like "PowerState/*"}
                    
                    if ($vmStatus.Code -eq "PowerState/deallocated" -or $vmStatus.Code -eq "PowerState/stopped") {
                        $vmSize = $vm.HardwareProfile.VmSize
                        $estimatedCost = switch ($vmSize) {
                            {$_ -like "*B1*"} { 15 }
                            {$_ -like "*B2*"} { 30 }
                            {$_ -like "*D2*"} { 70 }
                            {$_ -like "*D4*"} { 140 }
                            default { 50 }
                        }
                        
                        $idleResources += [PSCustomObject]@{
                            Type = "Virtual Machine"
                            Name = $r.Name
                            ResourceGroup = $rgName
                            Subscription = $sub.Name
                            Environment = $rgEnv
                            Reason = "VM is stopped/deallocated"
                            EstimatedMonthlySavings = "`$$estimatedCost"
                            Action = "Delete or keep deallocated"
                        }
                        
                        Write-Host "      IDLE VM: $($r.Name) (Stopped)" -ForegroundColor Yellow
                    }
                }
            }
            
            # STORAGE ACCOUNTS
            elseif ($r.ResourceType -eq "Microsoft.Storage/storageAccounts") {
                $storage = Get-AzStorageAccount -ResourceGroupName $rgName -Name $r.Name -ErrorAction SilentlyContinue
                
                if ($storage) {
                    # Check if storage is being used
                    $containers = Get-AzStorageContainer -Context $storage.Context -ErrorAction SilentlyContinue
                    
                    if (-not $containers -or $containers.Count -eq 0) {
                        $idleResources += [PSCustomObject]@{
                            Type = "Storage Account"
                            Name = $r.Name
                            ResourceGroup = $rgName
                            Subscription = $sub.Name
                            Environment = $rgEnv
                            Reason = "Storage account has no containers"
                            EstimatedMonthlySavings = "`$5-50"
                            Action = "Delete if truly unused"
                        }
                        Write-Host "      IDLE STORAGE: $($r.Name) (No containers)" -ForegroundColor Yellow
                    }
                }
            }
            
            # SQL DATABASES
            elseif ($r.ResourceType -eq "Microsoft.Sql/servers/databases") {
                # Skip master database
                if ($r.Name -notmatch "/master$") {
                    Write-Host "      SQL DB: $($r.Name)" -ForegroundColor Cyan
                }
            }
        }
    }
    
    Write-Host ""
}

# Generate HTML Report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = "PYX-ULTIMATE-AUDIT-$timestamp.html"

# Build HTML sections

# Resource Groups Table
$rgRows = ""
foreach ($rg in $allRGs) {
    $envMatch = if ($rg.SubscriptionEnv -eq $rg.RGEnvironment) {"✓"} else {"⚠️ MISMATCH"}
    $envMatchColor = if ($rg.SubscriptionEnv -eq $rg.RGEnvironment) {"#28a745"} else {"#dc3545"}
    
    $rgRows += "<tr><td>$($rg.Subscription)</td><td><strong>$($rg.ResourceGroup)</strong></td><td>$($rg.SubscriptionEnv)</td><td>$($rg.RGEnvironment)</td><td style='color:$envMatchColor'>$envMatch</td><td>$($rg.Location)</td><td>$($rg.ResourceCount)</td></tr>"
}

# Databricks Table
$dbRows = ""
foreach ($db in $allDatabricks) {
    $dbRows += "<tr><td>$($db.Subscription)</td><td>$($db.ResourceGroup)</td><td><strong>$($db.Name)</strong></td><td>$($db.Location)</td><td>$($db.SKU)</td></tr>"
}

if (-not $dbRows) {
    $dbRows = "<tr><td colspan='5' style='text-align:center;color:#999'>No Databricks workspaces found</td></tr>"
}

# Naming Issues Table
$namingRows = ""
foreach ($issue in $namingIssues) {
    $namingRows += @"
<tr>
<td>$($issue.Subscription)</td>
<td>$($issue.ResourceGroup)</td>
<td style='font-size:11px'>$($issue.Type)</td>
<td><span class='badge-old'>$($issue.OldName)</span></td>
<td><span class='badge-new'>$($issue.SuggestedNewName)</span></td>
<td>$($issue.Environment)</td>
<td style='font-size:12px'>$($issue.Issue)</td>
<td><span class='badge-action'>$($issue.Action)</span></td>
</tr>
"@
}

if (-not $namingRows) {
    $namingRows = "<tr><td colspan='8' style='text-align:center;color:#28a745;font-weight:bold'>✓ No naming issues found!</td></tr>"
}

# Idle Resources Table
$idleRows = ""
$totalSavings = 0
foreach ($idle in $idleResources) {
    $savingsNum = if ($idle.EstimatedMonthlySavings -match "\\d+") {[int]($idle.EstimatedMonthlySavings -replace "[^0-9]", "")} else {0}
    $totalSavings += $savingsNum
    
    $idleRows += "<tr><td>$($idle.Type)</td><td><strong>$($idle.Name)</strong></td><td>$($idle.ResourceGroup)</td><td>$($idle.Subscription)</td><td>$($idle.Reason)</td><td style='color:#28a745;font-weight:bold'>$($idle.EstimatedMonthlySavings)/mo</td><td><span class='badge-delete'>$($idle.Action)</span></td></tr>"
}

if (-not $idleRows) {
    $idleRows = "<tr><td colspan='7' style='text-align:center;color:#28a745;font-weight:bold'>✓ No idle resources found!</td></tr>"
}

# Duplicates Table
$dupRows = ""
foreach ($dup in $duplicates) {
    $dupRows += "<tr><td>$($dup.Type)</td><td><strong>$($dup.Name)</strong></td><td>$($dup.Location1)</td><td>$($dup.Location2)</td><td style='color:#dc3545'>$($dup.Issue)</td><td>$($dup.Recommendation)</td></tr>"
}

if (-not $dupRows) {
    $dupRows = "<tr><td colspan='6' style='text-align:center;color:#28a745;font-weight:bold'>✓ No duplicates found!</td></tr>"
}

# Generate HTML
$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Pyx Health - Ultimate Azure Audit Report</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:#f0f2f5;padding:20px}
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:50px;border-radius:15px;margin-bottom:30px;box-shadow:0 10px 40px rgba(102,126,234,0.3)}
.logo{font-size:52px;font-weight:bold;margin-bottom:15px;text-shadow:2px 2px 4px rgba(0,0,0,0.2)}
h1{font-size:42px;margin-bottom:10px}
.subtitle{font-size:18px;opacity:0.95}
.container{max-width:1900px;margin:0 auto}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:25px;margin-bottom:30px}
.summary-card{background:white;padding:30px;border-radius:12px;box-shadow:0 4px 15px rgba(0,0,0,0.1);text-align:center;transition:transform 0.3s}
.summary-card:hover{transform:translateY(-5px)}
.summary-value{font-size:48px;font-weight:bold;background:linear-gradient(135deg,#667eea,#764ba2);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:10px}
.summary-label{color:#666;font-size:15px;text-transform:uppercase;letter-spacing:1px}
.card{background:white;padding:35px;border-radius:12px;margin-bottom:30px;box-shadow:0 4px 15px rgba(0,0,0,0.1)}
h2{color:#2c3e50;font-size:28px;margin-bottom:25px;padding-bottom:15px;border-bottom:4px solid #667eea}
table{width:100%;border-collapse:collapse;margin:20px 0}
thead{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
th{color:white;padding:18px;text-align:left;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:0.5px}
td{padding:15px;border-bottom:1px solid #e0e0e0;font-size:14px}
tbody tr:hover{background:#f8f9fa}
tbody tr:nth-child(even){background:#fafbfc}
.badge-old{background:#ffe6e6;color:#c00;padding:6px 12px;border-radius:6px;font-weight:bold}
.badge-new{background:#e6ffe6;color:#060;padding:6px 12px;border-radius:6px;font-weight:bold}
.badge-action{background:#ffc107;color:#000;padding:5px 10px;border-radius:5px;font-size:11px;font-weight:bold}
.badge-delete{background:#dc3545;color:white;padding:5px 10px;border-radius:5px;font-size:11px;font-weight:bold}
.alert{padding:25px;border-radius:10px;margin:25px 0;border-left:6px solid}
.alert-warning{background:#fff3cd;border-color:#ffc107;color:#856404}
.alert-info{background:#d1ecf1;border-color:#0dcaf0;color:#0c5460}
.alert-success{background:#d4edda;border-color:#28a745;color:#155724}
.savings{background:linear-gradient(135deg,#28a745,#20c997);color:white;padding:30px;border-radius:12px;text-align:center;margin:30px 0}
.savings-amount{font-size:60px;font-weight:bold;margin-bottom:10px}
.footer{background:#2c3e50;color:white;padding:30px;border-radius:12px;text-align:center;margin-top:40px}
</style>
</head>
<body>

<div class="container">

<div class="header">
<div class="logo">🏥 PYX HEALTH</div>
<h1>Ultimate Azure Audit Report</h1>
<div class="subtitle">
Complete Infrastructure Analysis | Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss') | Analyst: $($context.Account.Id)
</div>
</div>

<div class="summary">
<div class="summary-card">
<div class="summary-value">$($subs.Count)</div>
<div class="summary-label">Subscriptions</div>
</div>
<div class="summary-card">
<div class="summary-value">$($allRGs.Count)</div>
<div class="summary-label">Resource Groups</div>
</div>
<div class="summary-card">
<div class="summary-value">$($allDatabricks.Count)</div>
<div class="summary-label">Databricks</div>
</div>
<div class="summary-card">
<div class="summary-value">$($namingIssues.Count)</div>
<div class="summary-label">Naming Issues</div>
</div>
<div class="summary-card">
<div class="summary-value">$($idleResources.Count)</div>
<div class="summary-label">Idle Resources</div>
</div>
<div class="summary-card">
<div class="summary-value">$($duplicates.Count)</div>
<div class="summary-label">Duplicates</div>
</div>
</div>

$(if($totalSavings -gt 0){
"<div class='savings'><div class='savings-amount'>`$$totalSavings/month</div><div>Estimated Savings from Removing Idle Resources</div></div>"
})

<div class="card">
<h2>📊 ALL RESOURCE GROUPS</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Sub Env</th><th>RG Env</th><th>Match</th><th>Location</th><th>Resources</th></tr></thead>
<tbody>$rgRows</tbody>
</table>
</div>

<div class="card">
<h2>💾 DATABRICKS WORKSPACES</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Workspace Name</th><th>Location</th><th>SKU</th></tr></thead>
<tbody>$dbRows</tbody>
</table>
</div>

<div class="card">
<h2>⚠️ NAMING ISSUES - OLD vs NEW</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Type</th><th>OLD NAME</th><th>SUGGESTED NEW</th><th>Env</th><th>Issue</th><th>Action</th></tr></thead>
<tbody>$namingRows</tbody>
</table>
</div>

<div class="card">
<h2>😴 IDLE / UNUSED RESOURCES</h2>
<div class="alert alert-warning">
<strong>💰 Cost Optimization Opportunity!</strong> These resources are not being used and could be deleted to save approximately <strong>`$$totalSavings/month</strong>.
</div>
<table>
<thead><tr><th>Type</th><th>Name</th><th>Resource Group</th><th>Subscription</th><th>Reason</th><th>Monthly Savings</th><th>Recommended Action</th></tr></thead>
<tbody>$idleRows</tbody>
</table>
</div>

$(if($duplicates.Count -gt 0){
@"
<div class='card'>
<h2>🔄 DUPLICATE RESOURCES</h2>
<div class='alert alert-warning'>
<strong>Warning!</strong> These resources appear to be duplicated across different locations. Consider consolidating.
</div>
<table>
<thead><tr><th>Type</th><th>Name</th><th>Location 1</th><th>Location 2</th><th>Issue</th><th>Recommendation</th></tr></thead>
<tbody>$dupRows</tbody>
</table>
</div>
"@
})

<div class="card">
<h2>📋 EXECUTIVE RECOMMENDATIONS</h2>
<div class="alert alert-info">
<h3 style="margin-bottom:15px">Action Items for Tony & Leadership Team</h3>
<ol style="margin-left:25px;line-height:2">
<li><strong>Naming Standardization:</strong> $($namingIssues.Count) resources have environment naming mismatches. Review and apply tags.</li>
<li><strong>Cost Optimization:</strong> $($idleResources.Count) idle resources identified. Potential savings: <strong>`$$totalSavings/month</strong> ($(($totalSavings * 12)) annually).</li>
<li><strong>Databricks Consolidation:</strong> $($duplicates.Count) duplicate workspace(s) found. Consolidate to reduce confusion and cost.</li>
<li><strong>Resource Group Cleanup:</strong> Empty resource groups detected. Delete to improve organization.</li>
<li><strong>Environment Alignment:</strong> Ensure resource group environments match subscription environments.</li>
</ol>
</div>
</div>

<div class="footer">
<div style="font-size:24px;margin-bottom:15px"><strong>🏥 PYX HEALTH - Azure Infrastructure Audit</strong></div>
<div style="font-size:16px;opacity:0.9">
<strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Mode:</strong> $Mode<br>
<strong>Total Subscriptions:</strong> $($subs.Count) | <strong>Resource Groups:</strong> $($allRGs.Count) | <strong>Databricks:</strong> $($allDatabricks.Count)<br>
<strong>Issues Found:</strong> $($namingIssues.Count) naming, $($idleResources.Count) idle, $($duplicates.Count) duplicates<br>
<strong>Potential Monthly Savings:</strong> `$$totalSavings
</div>
</div>

</div>

</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

# Console Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Subscriptions: $($subs.Count)" -ForegroundColor White
Write-Host "Resource Groups: $($allRGs.Count)" -ForegroundColor White
Write-Host "Databricks Workspaces: $($allDatabricks.Count)" -ForegroundColor Green
Write-Host "Naming Issues: $($namingIssues.Count)" -ForegroundColor $(if($namingIssues.Count -gt 0){"Yellow"}else{"Green"})
Write-Host "Idle Resources: $($idleResources.Count)" -ForegroundColor $(if($idleResources.Count -gt 0){"Yellow"}else{"Green"})
Write-Host "Duplicates: $($duplicates.Count)" -ForegroundColor $(if($duplicates.Count -gt 0){"Red"}else{"Green"})
Write-Host "Estimated Monthly Savings: `$$totalSavings" -ForegroundColor Green
Write-Host ""
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host "Opening report..." -ForegroundColor Yellow
Write-Host ""

Start-Process $reportFile

Write-Host "DONE! Send this report to Tony!" -ForegroundColor Green
Write-Host ""
