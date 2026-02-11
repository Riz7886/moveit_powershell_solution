# Azure Resource Group Environment Audit
# Identifies mislabeled resource groups and provides renaming recommendations

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE RESOURCE GROUP ENVIRONMENT AUDIT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure module
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "ERROR: Azure PowerShell module not installed!" -ForegroundColor Red
    Write-Host "Run: Install-Module -Name Az -AllowClobber -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Host "  Connected: $($context.Subscription.Name)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect" -ForegroundColor Red
    exit
}

Write-Host ""

# Get all resource groups
Write-Host "Scanning all resource groups..." -ForegroundColor Yellow
$allRGs = Get-AzResourceGroup
Write-Host "  Found: $($allRGs.Count) resource groups" -ForegroundColor Green
Write-Host ""

# Analyze each resource group
$analysis = @()

foreach ($rg in $allRGs) {
    Write-Host "Analyzing: $($rg.ResourceGroupName)" -ForegroundColor Gray
    
    $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
    $databricksWS = $resources | Where-Object {$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    
    $hasDatabricks = $databricksWS.Count -gt 0
    $isDatabricksManaged = $rg.ResourceGroupName -like "*databricks-rg-*"
    
    # Detect environment from name
    $detectedEnv = "Unknown"
    if ($rg.ResourceGroupName -like "*prod*" -and $rg.ResourceGroupName -notlike "*preprod*") {
        $detectedEnv = "Production"
    } elseif ($rg.ResourceGroupName -like "*preprod*" -or $rg.ResourceGroupName -like "*pre-prod*") {
        $detectedEnv = "PreProd"
    } elseif ($rg.ResourceGroupName -like "*poc*") {
        $detectedEnv = "POC"
    } elseif ($rg.ResourceGroupName -like "*dev*") {
        $detectedEnv = "Development"
    } elseif ($rg.ResourceGroupName -like "*test*" -or $rg.ResourceGroupName -like "*qa*") {
        $detectedEnv = "Test"
    }
    
    # Check for naming issues
    $namingIssues = @()
    
    # Check if POC contains production resources
    if ($rg.ResourceGroupName -like "*poc*") {
        foreach ($res in $resources) {
            if ($res.Name -like "*prod*" -and $res.Name -notlike "*preprod*") {
                $namingIssues += "POC resource group contains production-named resource: $($res.Name)"
            }
        }
    }
    
    # Check if preprod contains prod resources
    if ($rg.ResourceGroupName -like "*preprod*") {
        foreach ($res in $resources) {
            if ($res.Name -like "*-prod" -or $res.Name -like "*-prod-*") {
                $namingIssues += "PreProd resource group contains production-named resource: $($res.Name)"
            }
        }
    }
    
    $analysis += [PSCustomObject]@{
        ResourceGroup = $rg.ResourceGroupName
        Location = $rg.Location
        ResourceCount = $resources.Count
        HasDatabricks = $hasDatabricks
        DatabricksWorkspaces = ($databricksWS | Select-Object -ExpandProperty Name) -join ", "
        IsManagedRG = $isDatabricksManaged
        DetectedEnvironment = $detectedEnv
        NamingIssues = $namingIssues -join " | "
        Tags = ($rg.Tags.Keys | ForEach-Object {"$_=$($rg.Tags[$_])"}) -join ", "
    }
}

# Generate HTML Report
Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$reportFile = "Azure-Environment-Naming-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

# Build table rows
$allRGRows = ""
foreach ($item in $analysis | Sort-Object DetectedEnvironment, ResourceGroup) {
    $envColor = "gray"
    if ($item.DetectedEnvironment -eq "Production") { $envColor = "red" }
    elseif ($item.DetectedEnvironment -eq "PreProd") { $envColor = "orange" }
    elseif ($item.DetectedEnvironment -eq "POC") { $envColor = "purple" }
    
    $issueColor = if ($item.NamingIssues) { "red" } else { "green" }
    $issueText = if ($item.NamingIssues) { $item.NamingIssues } else { "None" }
    
    $allRGRows += "<tr>"
    $allRGRows += "<td><strong>$($item.ResourceGroup)</strong></td>"
    $allRGRows += "<td>$($item.Location)</td>"
    $allRGRows += "<td>$($item.ResourceCount)</td>"
    $allRGRows += "<td style='color:$envColor;font-weight:bold;'>$($item.DetectedEnvironment)</td>"
    $allRGRows += "<td>$($item.DatabricksWorkspaces)</td>"
    $allRGRows += "<td style='color:$issueColor;'>$issueText</td>"
    $allRGRows += "</tr>"
}

# Count issues
$issuesFound = ($analysis | Where-Object {$_.NamingIssues}).Count
$databricksRGs = ($analysis | Where-Object {$_.HasDatabricks}).Count

$currentDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$subName = $context.Subscription.Name

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Azure Environment Naming Audit</title>
<style>
body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}
.container{max-width:1800px;margin:0 auto;background:white;padding:40px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}
h1{color:#FF3621;font-size:36px;margin-bottom:10px;}
h2{color:#1B3139;border-bottom:3px solid #FF3621;padding-bottom:10px;margin-top:35px;font-size:24px;}
.summary{background:#f8f9fa;padding:25px;border-left:4px solid #FF3621;margin:25px 0;}
.warning{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:20px 0;}
table{width:100%;border-collapse:collapse;margin:25px 0;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
th{background:#1B3139;color:white;padding:15px;text-align:left;font-weight:600;}
td{padding:12px 15px;border-bottom:1px solid #ddd;font-size:14px;}
tr:hover{background:#f5f5f5;}
.metric{display:inline-block;background:#e3f2fd;padding:20px 30px;margin:10px;border-radius:5px;min-width:180px;text-align:center;}
.metric strong{display:block;font-size:32px;color:#1976d2;margin-bottom:5px;}
.rec{background:#e8f5e9;border-left:4px solid #28a745;padding:15px;margin:10px 0;}
</style>
</head>
<body>
<div class="container">

<h1>Azure Environment Naming Audit</h1>
<p><strong>Date:</strong> $currentDate</p>
<p><strong>Subscription:</strong> $subName</p>
<p><strong>Purpose:</strong> Identify mislabeled resource groups and provide renaming recommendations</p>

<div class="summary">
<h2 style="margin-top:0;border:none;">Summary</h2>
<div style="text-align:center;">
<div class="metric"><strong>$($allRGs.Count)</strong><span>Total Resource Groups</span></div>
<div class="metric"><strong>$databricksRGs</strong><span>Databricks Workspaces</span></div>
<div class="metric"><strong style="color:#dc3545;">$issuesFound</strong><span>Naming Issues Found</span></div>
</div>
</div>

<div class="warning">
<h2 style="margin-top:0;border:none;">Key Issues Identified</h2>
<ul>
<li><strong>POC resource groups may contain production resources</strong> - Need verification</li>
<li><strong>PreProd resource groups contain production-named resources</strong> - Creates confusion</li>
<li><strong>Inconsistent naming standards</strong> - Need standardization</li>
</ul>
</div>

<h2>All Resource Groups - Environment Analysis</h2>
<table>
<tr>
<th>Resource Group Name</th>
<th>Location</th>
<th>Resources</th>
<th>Detected Environment</th>
<th>Databricks Workspaces</th>
<th>Naming Issues</th>
</tr>
$allRGRows
</table>

<h2>Renaming Recommendations</h2>

<div class="rec">
<h3 style="margin-top:0;">Step 1: Identify True Environments</h3>
<p>Work with Brian and team to verify which resource groups are actually:</p>
<ul>
<li><strong>Production</strong> - Live, customer-facing environments</li>
<li><strong>PreProd</strong> - Pre-production staging environments</li>
<li><strong>Development</strong> - Developer testing environments</li>
<li><strong>POC</strong> - Proof of concept / temporary testing</li>
</ul>
</div>

<div class="rec">
<h3 style="margin-top:0;">Step 2: Establish Naming Convention</h3>
<p>Recommended format: <code>[Company]-[Project]-[Environment]-[Region]</code></p>
<p>Examples:</p>
<ul>
<li>Pyx-Warehouse-Prod-EastUS</li>
<li>Pyx-Warehouse-PreProd-EastUS</li>
<li>Pyx-Analytics-Prod-EastUS</li>
<li>Pyx-Analytics-Dev-EastUS</li>
</ul>
</div>

<div class="rec">
<h3 style="margin-top:0;">Step 3: Rename Resource Groups</h3>
<p><strong>Note:</strong> Azure does NOT support direct resource group renaming. You must:</p>
<ol>
<li>Create new resource group with correct name</li>
<li>Move resources to new resource group</li>
<li>Delete old resource group</li>
</ol>
<p><strong>PowerShell Example:</strong></p>
<pre style="background:#f0f0f0;padding:10px;border-radius:5px;overflow-x:auto;">
# Create new resource group
New-AzResourceGroup -Name "Pyx-Warehouse-Prod-EastUS" -Location "EastUS"

# Move resources (one at a time or in batch)
Move-AzResource -ResourceId "/subscriptions/.../resourceGroups/OLD-NAME/providers/..." `
                -DestinationResourceGroupName "Pyx-Warehouse-Prod-EastUS"

# After all resources moved, delete old RG
Remove-AzResourceGroup -Name "OLD-NAME" -Force
</pre>
</div>

<div class="warning">
<h3 style="margin-top:0;">Important Notes</h3>
<ul>
<li><strong>Databricks Managed RGs:</strong> Do NOT rename managed resource groups (databricks-rg-*)</li>
<li><strong>Plan Downtime:</strong> Some resources may require downtime during move</li>
<li><strong>Update References:</strong> Update any scripts, configs, or documentation with new names</li>
<li><strong>Test First:</strong> Test move process in dev/test before production</li>
</ul>
</div>

<h2>Next Steps</h2>
<ol>
<li>Share this report with Brian and team</li>
<li>Schedule meeting to confirm true environment designations</li>
<li>Document agreed-upon naming convention</li>
<li>Create resource group renaming plan with timeline</li>
<li>Execute renames during maintenance windows</li>
<li>Update all documentation and scripts</li>
</ol>

<p style="margin-top:60px;border-top:2px solid #ddd;padding-top:20px;">
<strong>Report Generated:</strong> $currentDate<br>
<strong>Subscription:</strong> $subName<br>
<strong>Action Required:</strong> Review with Brian and team to identify correct environment labels
</p>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host "Resource Groups: $($allRGs.Count)" -ForegroundColor White
Write-Host "Databricks Workspaces: $databricksRGs" -ForegroundColor White
Write-Host "Naming Issues Found: $issuesFound" -ForegroundColor $(if ($issuesFound -gt 0) {"Red"} else {"Green"})
Write-Host ""
Write-Host "Opening report..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
