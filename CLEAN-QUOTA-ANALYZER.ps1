# Databricks Quota Analyzer - NO ERRORS VERSION
# Just run it - no parameters needed

$workspace = "https://adb-324884819348686.6.azuredatabricks.net"
$token = "dapi9abaad71d0865d1a32a08cba05a318b7"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$rootCauses = @()

Write-Host ""
Write-Host "DATABRICKS QUOTA ANALYZER" -ForegroundColor Cyan
Write-Host ""

# Get Clusters
Write-Host "[1/3] Checking Clusters..." -ForegroundColor Yellow

$clusterData = @()
try {
    $response = Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/list" -Headers $headers -Method Get
    
    if ($response.clusters) {
        foreach ($c in $response.clusters) {
            $name = $c.cluster_name
            $state = $c.state
            $hasAutoscale = $false
            $hasAutoTerm = $false
            $maxWorkers = 0
            
            if ($c.autoscale) {
                $hasAutoscale = $true
                $maxWorkers = $c.autoscale.max_workers
                if ($maxWorkers -gt 20) {
                    $rootCauses += "Cluster '$name' max workers = $maxWorkers (QUOTA RISK)"
                }
            } else {
                $rootCauses += "Cluster '$name' has NO AUTOSCALING"
            }
            
            if ($c.autotermination_minutes) {
                $hasAutoTerm = $true
            } else {
                $rootCauses += "Cluster '$name' has NO AUTO-TERMINATION"
            }
            
            $clusterData += [PSCustomObject]@{
                Name = $name
                State = $state
                Autoscale = $hasAutoscale
                MaxWorkers = $maxWorkers
                AutoTerminate = $hasAutoTerm
            }
        }
        Write-Host "  Found $($response.clusters.Count) clusters" -ForegroundColor Green
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Get Warehouses
Write-Host "[2/3] Checking SQL Warehouses..." -ForegroundColor Yellow

$warehouseData = @()
try {
    $response = Invoke-RestMethod -Uri "$workspace/api/2.0/sql/warehouses" -Headers $headers -Method Get
    
    if ($response.warehouses) {
        foreach ($w in $response.warehouses) {
            $warehouseData += [PSCustomObject]@{
                Name = $w.name
                State = $w.state
                Size = $w.cluster_size
            }
        }
        Write-Host "  Found $($response.warehouses.Count) warehouses" -ForegroundColor Green
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Generate Report
Write-Host "[3/3] Generating Report..." -ForegroundColor Yellow

$reportFile = "DatabricksReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

$clusterRows = ""
foreach ($c in $clusterData) {
    $autoscaleText = if ($c.Autoscale) { "YES - $($c.MaxWorkers) max" } else { "NO" }
    $autoTermText = if ($c.AutoTerminate) { "YES" } else { "NO" }
    $clusterRows += "<tr><td>$($c.Name)</td><td>$($c.State)</td><td>$autoscaleText</td><td>$autoTermText</td></tr>"
}

$warehouseRows = ""
foreach ($w in $warehouseData) {
    $warehouseRows += "<tr><td>$($w.Name)</td><td>$($w.State)</td><td>$($w.Size)</td></tr>"
}

$rootCauseList = ""
if ($rootCauses.Count -eq 0) {
    $rootCauseList = "<p style='color:green;'>No critical issues found</p>"
} else {
    $rootCauseList = "<ul>"
    foreach ($rc in $rootCauses) {
        $rootCauseList += "<li>$rc</li>"
    }
    $rootCauseList += "</ul>"
}

$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
<title>Databricks Quota Report</title>
<style>
body { font-family: Arial; margin: 20px; background: #f5f5f5; }
h1 { color: #FF3621; }
h2 { color: #1B3139; border-bottom: 2px solid #FF3621; }
table { width: 100%; border-collapse: collapse; background: white; margin: 20px 0; }
th { background: #1B3139; color: white; padding: 10px; text-align: left; }
td { padding: 10px; border-bottom: 1px solid #ddd; }
.summary { background: white; padding: 20px; margin: 20px 0; }
</style>
</head>
<body>
<h1>Databricks Quota Analysis Report</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p>Workspace: $workspace</p>

<div class='summary'>
<h2>Summary</h2>
<p><strong>Total Clusters:</strong> $($clusterData.Count)</p>
<p><strong>Total SQL Warehouses:</strong> $($warehouseData.Count)</p>
<p><strong>Root Causes:</strong> $($rootCauses.Count)</p>
</div>

<h2>Root Causes Identified</h2>
$rootCauseList

<h2>Cluster Details</h2>
<table>
<tr><th>Name</th><th>State</th><th>Autoscaling</th><th>Auto-Terminate</th></tr>
$clusterRows
</table>

<h2>SQL Warehouses</h2>
<table>
<tr><th>Name</th><th>State</th><th>Size</th></tr>
$warehouseRows
</table>

<h2>Recommendations</h2>
<ul>
<li>Enable autoscaling on all clusters</li>
<li>Enable auto-termination (30-60 min)</li>
<li>Cap max workers at 12 per cluster</li>
<li>Monitor SQL warehouse usage</li>
</ul>

</body>
</html>
"@

Set-Content -Path $reportFile -Value $htmlContent
Write-Host "  Report saved: $reportFile" -ForegroundColor Green

Start-Process $reportFile

Write-Host ""
Write-Host "ROOT CAUSES FOUND: $($rootCauses.Count)" -ForegroundColor $(if ($rootCauses.Count -eq 0) { "Green" } else { "Red" })
if ($rootCauses.Count -gt 0) {
    Write-Host ""
    foreach ($rc in $rootCauses) {
        Write-Host "  - $rc" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "DONE - Report opened in browser" -ForegroundColor Green
Write-Host ""
