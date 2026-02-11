# AZURE ENVIRONMENT NAMING AUDIT - AUTO CONNECT
# Identifies mislabeled resource groups for John's request

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AZURE ENVIRONMENT NAMING AUDIT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Auto-connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount -ErrorAction Stop | Out-Null
        $context = Get-AzContext
    }
    Write-Host "  Connected: $($context.Subscription.Name)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect" -ForegroundColor Red
    exit
}

Write-Host ""

# Get all resource groups
Write-Host "Scanning resource groups..." -ForegroundColor Yellow
$allRGs = Get-AzResourceGroup
Write-Host "  Found: $($allRGs.Count) resource groups" -ForegroundColor Green
Write-Host ""

# Analyze each resource group
$analysis = @()

foreach ($rg in $allRGs) {
    Write-Host "  Checking: $($rg.ResourceGroupName)" -ForegroundColor Gray
    
    $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
    $databricksWS = $resources | Where-Object {$_.ResourceType -eq "Microsoft.Databricks/workspaces"}
    
    # Detect environment
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
    $issues = @()
    
    if ($rg.ResourceGroupName -like "*poc*") {
        foreach ($res in $resources) {
            if ($res.Name -like "*prod*" -and $res.Name -notlike "*preprod*") {
                $issues += "Contains production resource: $($res.Name)"
            }
        }
    }
    
    if ($rg.ResourceGroupName -like "*preprod*") {
        foreach ($res in $resources) {
            if ($res.Name -like "*-prod" -or $res.Name -like "*-prod-*") {
                $issues += "Contains prod-named resource: $($res.Name)"
            }
        }
    }
    
    $analysis += [PSCustomObject]@{
        ResourceGroup = $rg.ResourceGroupName
        Location = $rg.Location
        ResourceCount = $resources.Count
        HasDatabricks = ($databricksWS.Count -gt 0)
        DatabricksWorkspaces = ($databricksWS | Select-Object -ExpandProperty Name) -join ", "
        DetectedEnvironment = $detectedEnv
        Issues = ($issues -join " | ")
    }
}

# Generate report
Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$reportFile = "Azure-Environment-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$tableRows = ""
foreach ($item in $analysis | Sort-Object DetectedEnvironment, ResourceGroup) {
    $envColor = "gray"
    if ($item.DetectedEnvironment -eq "Production") { $envColor = "red" }
    elseif ($item.DetectedEnvironment -eq "PreProd") { $envColor = "orange" }
    elseif ($item.DetectedEnvironment -eq "POC") { $envColor = "purple" }
    
    $issueColor = if ($item.Issues) { "red" } else { "green" }
    $issueText = if ($item.Issues) { $item.Issues } else { "None" }
    
    $tableRows += "<tr><td><strong>$($item.ResourceGroup)</strong></td><td>$($item.Location)</td><td>$($item.ResourceCount)</td><td style='color:$envColor;font-weight:bold;'>$($item.DetectedEnvironment)</td><td>$($item.DatabricksWorkspaces)</td><td style='color:$issueColor;'>$issueText</td></tr>"
}

$issuesCount = ($analysis | Where-Object {$_.Issues}).Count
$databricksCount = ($analysis | Where-Object {$_.HasDatabricks}).Count
$currentDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$subName = $context.Subscription.Name

$html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>Azure Environment Naming Audit</title><style>body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}.container{max-width:1800px;margin:0 auto;background:white;padding:40px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}h1{color:#FF3621;font-size:36px;margin-bottom:10px;}h2{color:#1B3139;border-bottom:3px solid #FF3621;padding-bottom:10px;margin-top:35px;font-size:24px;}.summary{background:#f8f9fa;padding:25px;border-left:4px solid #FF3621;margin:25px 0;}.warning{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:20px 0;}table{width:100%;border-collapse:collapse;margin:25px 0;box-shadow:0 1px 3px rgba(0,0,0,0.1);}th{background:#1B3139;color:white;padding:15px;text-align:left;font-weight:600;}td{padding:12px 15px;border-bottom:1px solid #ddd;font-size:14px;}tr:hover{background:#f5f5f5;}.metric{display:inline-block;background:#e3f2fd;padding:20px 30px;margin:10px;border-radius:5px;min-width:180px;text-align:center;}.metric strong{display:block;font-size:32px;color:#1976d2;margin-bottom:5px;}</style></head><body><div class='container'><h1>Azure Environment Naming Audit</h1><p><strong>Date:</strong> $currentDate</p><p><strong>Subscription:</strong> $subName</p><p><strong>Purpose:</strong> Identify mislabeled resource groups per John's request</p><div class='summary'><h2 style='margin-top:0;border:none;'>Summary</h2><div style='text-align:center;'><div class='metric'><strong>$($allRGs.Count)</strong><span>Total Resource Groups</span></div><div class='metric'><strong>$databricksCount</strong><span>Databricks Workspaces</span></div><div class='metric'><strong style='color:#dc3545;'>$issuesCount</strong><span>Naming Issues</span></div></div></div><div class='warning'><h2 style='margin-top:0;border:none;'>Key Findings</h2><ul><li><strong>POC resource groups contain production-named resources</strong></li><li><strong>PreProd resource groups contain prod-named resources</strong></li><li><strong>Need to verify true environment designations with Brian</strong></li></ul></div><h2>All Resource Groups - Environment Analysis</h2><table><tr><th>Resource Group Name</th><th>Location</th><th>Resources</th><th>Detected Environment</th><th>Databricks Workspaces</th><th>Naming Issues</th></tr>$tableRows</table><h2>Recommendations</h2><ol><li>Share this report with Brian and team</li><li>Identify which resource groups are truly Production vs PreProd vs POC</li><li>Establish naming convention: Company-Project-Environment-Region</li><li>Create resource group renaming plan</li><li>Execute renames during maintenance window</li></ol><p style='margin-top:60px;border-top:2px solid #ddd;padding-top:20px;'><strong>Generated:</strong> $currentDate<br><strong>Subscription:</strong> $subName<br><strong>For:</strong> John Pinto - Environment naming cleanup</p></div></body></html>"

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  AUDIT COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host "Resource Groups: $($allRGs.Count)" -ForegroundColor White
Write-Host "Databricks Workspaces: $databricksCount" -ForegroundColor White
Write-Host "Naming Issues: $issuesCount" -ForegroundColor $(if ($issuesCount -gt 0) {"Red"} else {"Green"})
Write-Host ""
Write-Host "Opening report..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
