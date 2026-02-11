# AZURE DATABRICKS RESOURCE AUDIT
# Identifies what Databricks resources exist and what can be cleaned up

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE DATABRICKS RESOURCE AUDIT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if Az module is installed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "ERROR: Azure PowerShell module not installed!" -ForegroundColor Red
    Write-Host "Run: Install-Module -Name Az -AllowClobber -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    Connect-AzAccount -ErrorAction Stop | Out-Null
    Write-Host "  Connected successfully!" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect to Azure" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Get current subscription
$subscription = Get-AzContext
Write-Host "Subscription: $($subscription.Subscription.Name)" -ForegroundColor White
Write-Host ""

# Storage for audit data
$auditData = @{
    workspaces = @()
    managedRGs = @()
    orphanedRGs = @()
    otherResources = @()
    totalCost = 0
}

# Get all resource groups
Write-Host "[1/4] Getting all resource groups..." -ForegroundColor Yellow
$allResourceGroups = Get-AzResourceGroup
Write-Host "  Found: $($allResourceGroups.Count) resource groups" -ForegroundColor Green

# Get Databricks workspaces
Write-Host "[2/4] Finding Databricks workspaces..." -ForegroundColor Yellow
$workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces"
Write-Host "  Found: $($workspaces.Count) Databricks workspaces" -ForegroundColor Green

foreach ($ws in $workspaces) {
    $wsDetails = Get-AzResource -ResourceId $ws.ResourceId
    
    Write-Host "    - $($ws.Name) [$($ws.Location)]" -ForegroundColor White
    
    $auditData.workspaces += [PSCustomObject]@{
        Name = $ws.Name
        ResourceGroup = $ws.ResourceGroupName
        Location = $ws.Location
        State = $wsDetails.Properties.provisioningState
        ManagedResourceGroup = $wsDetails.Properties.managedResourceGroupId
        WorkspaceId = $wsDetails.Properties.workspaceId
        WorkspaceUrl = $wsDetails.Properties.workspaceUrl
        Created = $ws.Tags.CreatedDate
    }
}

# Find managed resource groups
Write-Host "[3/4] Finding managed resource groups..." -ForegroundColor Yellow
$managedRGNames = $workspaces | ForEach-Object {
    $wsDetails = Get-AzResource -ResourceId $_.ResourceId
    $wsDetails.Properties.managedResourceGroupId -split '/' | Select-Object -Last 1
}

foreach ($rg in $allResourceGroups) {
    if ($rg.ResourceGroupName -like "*databricks-rg-*" -or $rg.ResourceGroupName -like "*databricks*managed*") {
        $isActive = $managedRGNames -contains $rg.ResourceGroupName
        
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
        
        if ($isActive) {
            Write-Host "    - $($rg.ResourceGroupName) [ACTIVE - $($resources.Count) resources]" -ForegroundColor Green
            $auditData.managedRGs += [PSCustomObject]@{
                Name = $rg.ResourceGroupName
                Location = $rg.Location
                Status = "Active"
                ResourceCount = $resources.Count
                LinkedWorkspace = ($workspaces | Where-Object { 
                    $wsDetails = Get-AzResource -ResourceId $_.ResourceId
                    ($wsDetails.Properties.managedResourceGroupId -split '/' | Select-Object -Last 1) -eq $rg.ResourceGroupName
                } | Select-Object -First 1).Name
            }
        } else {
            Write-Host "    - $($rg.ResourceGroupName) [ORPHANED - $($resources.Count) resources]" -ForegroundColor Red
            $auditData.orphanedRGs += [PSCustomObject]@{
                Name = $rg.ResourceGroupName
                Location = $rg.Location
                Status = "Orphaned"
                ResourceCount = $resources.Count
                CanDelete = $true
                Reason = "No active workspace linked"
            }
        }
    }
}

# Find other Databricks-related resources
Write-Host "[4/4] Finding other Databricks resources..." -ForegroundColor Yellow
$otherResources = Get-AzResource | Where-Object { 
    $_.Name -like "*databricks*" -and 
    $_.ResourceType -ne "Microsoft.Databricks/workspaces"
}

foreach ($res in $otherResources) {
    Write-Host "    - $($res.Name) [$($res.ResourceType)]" -ForegroundColor White
    $auditData.otherResources += [PSCustomObject]@{
        Name = $res.Name
        Type = $res.ResourceType
        ResourceGroup = $res.ResourceGroupName
        Location = $res.Location
    }
}

# Generate HTML Report
Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Yellow

$reportFile = "Azure-Databricks-Cleanup-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$workspaceRows = ""
foreach ($ws in $auditData.workspaces) {
    $stateColor = if ($ws.State -eq "Succeeded") { "green" } else { "orange" }
    $workspaceRows += "<tr>"
    $workspaceRows += "<td><strong>$($ws.Name)</strong></td>"
    $workspaceRows += "<td>$($ws.ResourceGroup)</td>"
    $workspaceRows += "<td>$($ws.Location)</td>"
    $workspaceRows += "<td style='color:$stateColor;font-weight:bold;'>$($ws.State)</td>"
    $workspaceRows += "<td><a href='https://$($ws.WorkspaceUrl)'>$($ws.WorkspaceUrl)</a></td>"
    $workspaceRows += "<td style='color:green;font-weight:bold;'>KEEP</td>"
    $workspaceRows += "</tr>"
}

$managedRGRows = ""
foreach ($rg in $auditData.managedRGs) {
    $managedRGRows += "<tr>"
    $managedRGRows += "<td><strong>$($rg.Name)</strong></td>"
    $managedRGRows += "<td>$($rg.Location)</td>"
    $managedRGRows += "<td>$($rg.ResourceCount)</td>"
    $managedRGRows += "<td>$($rg.LinkedWorkspace)</td>"
    $managedRGRows += "<td style='color:green;font-weight:bold;'>Active</td>"
    $managedRGRows += "<td style='color:green;font-weight:bold;'>KEEP</td>"
    $managedRGRows += "</tr>"
}

$orphanedRGRows = ""
$totalOrphaned = 0
foreach ($rg in $auditData.orphanedRGs) {
    $totalOrphaned++
    $orphanedRGRows += "<tr>"
    $orphanedRGRows += "<td><strong>$($rg.Name)</strong></td>"
    $orphanedRGRows += "<td>$($rg.Location)</td>"
    $orphanedRGRows += "<td>$($rg.ResourceCount)</td>"
    $orphanedRGRows += "<td style='color:red;font-weight:bold;'>Orphaned</td>"
    $orphanedRGRows += "<td>$($rg.Reason)</td>"
    $orphanedRGRows += "<td style='color:red;font-weight:bold;'>CAN DELETE</td>"
    $orphanedRGRows += "</tr>"
}

$otherResourceRows = ""
foreach ($res in $auditData.otherResources) {
    $otherResourceRows += "<tr>"
    $otherResourceRows += "<td><strong>$($res.Name)</strong></td>"
    $otherResourceRows += "<td>$($res.Type)</td>"
    $otherResourceRows += "<td>$($res.ResourceGroup)</td>"
    $otherResourceRows += "<td>$($res.Location)</td>"
    $otherResourceRows += "<td>Review manually</td>"
    $otherResourceRows += "</tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Azure Databricks Resource Audit</title>
<style>
body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}
.container{max-width:1800px;margin:0 auto;background:white;padding:40px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}
h1{color:#FF3621;font-size:36px;margin-bottom:10px;}
h2{color:#1B3139;border-bottom:3px solid #FF3621;padding-bottom:10px;margin-top:35px;font-size:24px;}
.summary{background:#f8f9fa;padding:25px;border-left:4px solid #FF3621;margin:25px 0;}
.warning{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:20px 0;}
.danger{background:#f8d7da;border-left:5px solid #dc3545;padding:20px;margin:20px 0;}
table{width:100%;border-collapse:collapse;margin:25px 0;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
th{background:#1B3139;color:white;padding:15px;text-align:left;font-weight:600;}
td{padding:12px 15px;border-bottom:1px solid #ddd;}
tr:hover{background:#f5f5f5;}
.metric{display:inline-block;background:#e3f2fd;padding:20px 30px;margin:10px;border-radius:5px;min-width:200px;text-align:center;}
.metric strong{display:block;font-size:32px;color:#1976d2;margin-bottom:5px;}
</style>
</head>
<body>
<div class="container">

<h1>Azure Databricks Resource Audit</h1>
<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Subscription:</strong> $($subscription.Subscription.Name)</p>
<p><strong>Subscription ID:</strong> $($subscription.Subscription.Id)</p>

<div class="summary">
<h2 style="margin-top:0;border:none;">Summary</h2>
<div style="text-align:center;">
<div class="metric"><strong>$($auditData.workspaces.Count)</strong><span>Active Workspaces</span></div>
<div class="metric"><strong>$($auditData.managedRGs.Count)</strong><span>Managed Resource Groups</span></div>
<div class="metric"><strong style="color:#dc3545;">$totalOrphaned</strong><span>Orphaned Resources</span></div>
<div class="metric"><strong>$($auditData.otherResources.Count)</strong><span>Other Resources</span></div>
</div>
</div>

$(if ($totalOrphaned -gt 0) {
"<div class='danger'>
<h2 style='margin-top:0;border:none;'>⚠️ Cleanup Opportunities Found</h2>
<p><strong>$totalOrphaned orphaned resource groups can be deleted to reduce clutter and potentially save costs.</strong></p>
<p>These are managed resource groups from deleted or failed Databricks workspaces that are no longer needed.</p>
</div>"
} else {
"<div class='summary' style='background:#d4edda;border-left:4px solid #28a745;'>
<h2 style='margin-top:0;border:none;'>✓ No Cleanup Needed</h2>
<p>All Databricks resources are active and properly configured. No orphaned resources found.</p>
</div>"
})

<h2>Active Databricks Workspaces</h2>
<p>These are your active Databricks workspaces - <strong>DO NOT DELETE</strong></p>
<table>
<tr>
<th>Workspace Name</th>
<th>Resource Group</th>
<th>Location</th>
<th>State</th>
<th>Workspace URL</th>
<th>Action</th>
</tr>
$workspaceRows
</table>

<h2>Managed Resource Groups (Active)</h2>
<p>These are managed by Databricks for active workspaces - <strong>DO NOT DELETE</strong></p>
<table>
<tr>
<th>Resource Group Name</th>
<th>Location</th>
<th>Resource Count</th>
<th>Linked Workspace</th>
<th>Status</th>
<th>Action</th>
</tr>
$managedRGRows
</table>

$(if ($totalOrphaned -gt 0) {
"<h2 style='color:#dc3545;'>Orphaned Resource Groups (Can Delete)</h2>
<p style='color:#dc3545;font-weight:bold;'>These resource groups are NOT linked to any active workspace and can be safely deleted.</p>
<table>
<tr>
<th>Resource Group Name</th>
<th>Location</th>
<th>Resource Count</th>
<th>Status</th>
<th>Reason</th>
<th>Recommendation</th>
</tr>
$orphanedRGRows
</table>

<h2>How to Clean Up Orphaned Resources</h2>
<div class='warning'>
<h3 style='margin-top:0;'>PowerShell Command to Delete Orphaned Resource Groups:</h3>
<pre style='background:#f0f0f0;padding:15px;border-radius:5px;overflow-x:auto;'>
# Review the resource group first
Get-AzResourceGroup -Name 'RESOURCE_GROUP_NAME' | Get-AzResource

# If confirmed safe to delete:
Remove-AzResourceGroup -Name 'RESOURCE_GROUP_NAME' -Force
</pre>
<p><strong>⚠️ WARNING:</strong> Always verify the resource group contents before deletion!</p>
</div>
"
})

$(if ($auditData.otherResources.Count -gt 0) {
"<h2>Other Databricks-Related Resources</h2>
<p>Review these resources manually to determine if they're still needed.</p>
<table>
<tr>
<th>Resource Name</th>
<th>Type</th>
<th>Resource Group</th>
<th>Location</th>
<th>Action</th>
</tr>
$otherResourceRows
</table>"
})

<h2>Cleanup Recommendations</h2>

<h3>Safe to Delete:</h3>
<ul>
$(if ($totalOrphaned -gt 0) {
    "<li><strong style='color:#dc3545;'>$totalOrphaned orphaned managed resource groups</strong> - These are from deleted/failed workspaces</li>"
} else {
    "<li>None - All resources are active</li>"
})
</ul>

<h3>Keep (DO NOT DELETE):</h3>
<ul>
<li><strong>All $($auditData.workspaces.Count) active Databricks workspaces</strong></li>
<li><strong>All $($auditData.managedRGs.Count) managed resource groups</strong> linked to active workspaces</li>
<li>Any storage accounts currently in use</li>
<li>Network resources (VNets, NSGs) if configured</li>
</ul>

<h2>Next Steps</h2>
<ol>
<li>Review this report with the team</li>
<li>Verify orphaned resources are truly unused</li>
<li>Delete orphaned resource groups during maintenance window</li>
<li>Monitor for any issues after cleanup</li>
<li>Document cleanup actions taken</li>
</ol>

<p style="margin-top:60px;border-top:2px solid #ddd;padding-top:20px;">
<strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Generated By:</strong> $($env:USERNAME)<br>
<strong>Subscription:</strong> $($subscription.Subscription.Name)
</p>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host "Active Workspaces: $($auditData.workspaces.Count)" -ForegroundColor White
Write-Host "Managed RGs: $($auditData.managedRGs.Count)" -ForegroundColor White
Write-Host "Orphaned RGs: $totalOrphaned" -ForegroundColor $(if ($totalOrphaned -gt 0) {"Red"} else {"Green"})
Write-Host ""

if ($totalOrphaned -gt 0) {
    Write-Host "⚠️  CLEANUP OPPORTUNITY: $totalOrphaned orphaned resource groups found!" -ForegroundColor Yellow
} else {
    Write-Host "✓  No cleanup needed - all resources are active!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Opening report..." -ForegroundColor Yellow
Start-Process $reportFile
