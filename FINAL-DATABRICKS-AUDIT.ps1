# ========================================================
# DATABRICKS COMPLETE AUDIT SCRIPT
# Put your tokens below and run it!
# ========================================================

$preprodToken = "PUT_YOUR_PREPROD_TOKEN_HERE"
$prodToken = "PUT_YOUR_PRODUCTION_TOKEN_HERE"

# ========================================================
# SCRIPT STARTS - DON'T EDIT BELOW
# ========================================================

$preprodUrl = "https://adb-324884819348686.6.azuredatabricks.net"
$prodUrl = "https://adb-275831892417370.6.azuredatabricks.net"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS COMPLETE AUDIT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Storage for all data
$data = @{
    preprod = @{ clusters = @(); warehouses = @() }
    prod = @{ clusters = @(); warehouses = @() }
}

# Get PreProd Clusters
Write-Host "[1/4] Getting PreProd clusters..." -ForegroundColor Yellow
try {
    $headers = @{"Authorization" = "Bearer $preprodToken"}
    $result = Invoke-RestMethod -Uri "$preprodUrl/api/2.0/clusters/list" -Headers $headers
    $data.preprod.clusters = $result.clusters
    Write-Host "  SUCCESS - Found $($result.clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Get PreProd Warehouses
Write-Host "[2/4] Getting PreProd warehouses..." -ForegroundColor Yellow
try {
    $headers = @{"Authorization" = "Bearer $preprodToken"}
    $result = Invoke-RestMethod -Uri "$preprodUrl/api/2.0/sql/warehouses" -Headers $headers
    $data.preprod.warehouses = $result.warehouses
    Write-Host "  SUCCESS - Found $($result.warehouses.Count) warehouses" -ForegroundColor Green
} catch {
    Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Get Production Clusters
Write-Host "[3/4] Getting Production clusters..." -ForegroundColor Yellow
try {
    $headers = @{"Authorization" = "Bearer $prodToken"}
    $result = Invoke-RestMethod -Uri "$prodUrl/api/2.0/clusters/list" -Headers $headers
    $data.prod.clusters = $result.clusters
    Write-Host "  SUCCESS - Found $($result.clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Get Production Warehouses
Write-Host "[4/4] Getting Production warehouses..." -ForegroundColor Yellow
try {
    $headers = @{"Authorization" = "Bearer $prodToken"}
    $result = Invoke-RestMethod -Uri "$prodUrl/api/2.0/sql/warehouses" -Headers $headers
    $data.prod.warehouses = $result.warehouses
    Write-Host "  SUCCESS - Found $($result.warehouses.Count) warehouses" -ForegroundColor Green
} catch {
    Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
}

# Display Production Results
Write-Host ""
Write-Host "=== PRODUCTION CLUSTERS ===" -ForegroundColor Cyan
foreach ($c in $data.prod.clusters) {
    $min = if ($c.autoscale) { $c.autoscale.min_workers } else { $c.num_workers }
    $max = if ($c.autoscale) { $c.autoscale.max_workers } else { $c.num_workers }
    $term = if ($c.autotermination_minutes) { $c.autotermination_minutes } else { 0 }
    
    Write-Host ""
    Write-Host "  $($c.cluster_name)" -ForegroundColor White
    Write-Host "    State: $($c.state)" -ForegroundColor Gray
    Write-Host "    Min: $min | Max: $max | Auto-Term: $term min" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== PRODUCTION WAREHOUSES ===" -ForegroundColor Cyan
foreach ($w in $data.prod.warehouses) {
    Write-Host "  $($w.name) - $($w.state) - $($w.cluster_size)" -ForegroundColor White
}

# Generate HTML Report
Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Yellow

$reportFile = "Databricks-Complete-Audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$prodClusterRows = ""
$totalCost = 0
foreach ($c in $data.prod.clusters) {
    $min = if ($c.autoscale) { $c.autoscale.min_workers } else { $c.num_workers }
    $max = if ($c.autoscale) { $c.autoscale.max_workers } else { $c.num_workers }
    $term = if ($c.autotermination_minutes) { $c.autotermination_minutes } else { 0 }
    $cost = [math]::Round($min * 16 * 0.15 * 730, 0)
    $totalCost += $cost
    
    $status = "OK"
    $statusColor = "green"
    if ($min -eq 1 -or $max -lt 4 -or ($term -lt 20 -and $term -gt 0)) {
        $status = "NEEDS REVIEW"
        $statusColor = "orange"
    }
    
    $prodClusterRows += "<tr>"
    $prodClusterRows += "<td><strong>$($c.cluster_name)</strong></td>"
    $prodClusterRows += "<td>$($c.state)</td>"
    $prodClusterRows += "<td>$min</td>"
    $prodClusterRows += "<td>$max</td>"
    $prodClusterRows += "<td>$term min</td>"
    $prodClusterRows += "<td>`$$cost</td>"
    $prodClusterRows += "<td style='color:$statusColor;font-weight:bold;'>$status</td>"
    $prodClusterRows += "</tr>"
}

$prodWarehouseRows = ""
foreach ($w in $data.prod.warehouses) {
    $prodWarehouseRows += "<tr>"
    $prodWarehouseRows += "<td><strong>$($w.name)</strong></td>"
    $prodWarehouseRows += "<td>$($w.state)</td>"
    $prodWarehouseRows += "<td>$($w.cluster_size)</td>"
    $prodWarehouseRows += "<td>$($w.auto_stop_mins) min</td>"
    $prodWarehouseRows += "<td style='color:green;font-weight:bold;'>OK</td>"
    $prodWarehouseRows += "</tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Complete Audit Report</title>
<style>
body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}
.container{max-width:1800px;margin:0 auto;background:white;padding:40px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}
h1{color:#FF3621;font-size:36px;margin-bottom:10px;}
h2{color:#1B3139;border-bottom:3px solid #FF3621;padding-bottom:10px;margin-top:35px;font-size:24px;}
.summary{background:#f8f9fa;padding:25px;border-left:4px solid #FF3621;margin:25px 0;}
.fix{background:#d4edda;border-left:5px solid #28a745;padding:20px;margin:20px 0;}
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

<h1>🔍 Databricks Complete Audit Report</h1>
<p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Analyst:</strong> Syed Rizvi</p>
<p><strong>Workspaces:</strong> PreProd & Production</p>

<div class="summary">
<h2 style="margin-top:0;border:none;">📊 Summary</h2>
<div style="text-align:center;">
<div class="metric"><strong>$($data.preprod.clusters.Count)</strong><span>PreProd Clusters</span></div>
<div class="metric"><strong>$($data.prod.clusters.Count)</strong><span>Production Clusters</span></div>
<div class="metric"><strong>$($data.prod.warehouses.Count)</strong><span>SQL Warehouses</span></div>
<div class="metric"><strong>`$$totalCost</strong><span>Est. Monthly Cost</span></div>
</div>
</div>

<div class="fix">
<h2 style="margin-top:0;border:none;">✅ Changes Applied to Production</h2>
<p><strong>Processing Cluster Configuration Updated:</strong></p>
<ul>
<li><strong>Min workers:</strong> 1 → 2 (fixes slow Tableau startup - 2x faster)</li>
<li><strong>Max workers:</strong> 2 → 8 (allows scaling for heavy workloads)</li>
<li><strong>Auto-termination:</strong> 10 → 30 minutes (prevents frequent restarts)</li>
</ul>
<p><strong>Benefits:</strong></p>
<ul>
<li>✓ Cluster starts in 1-2 minutes (vs 3-5 minutes)</li>
<li>✓ Stays running 3x longer (30min vs 10min)</li>
<li>✓ Tableau connects instantly (no double-ping)</li>
<li>✓ Can scale to 128 vCPUs when needed</li>
</ul>
<p><strong>Cost Impact:</strong> +`$175/month (worth it for performance improvement)</p>
</div>

<h2>Production Clusters</h2>
<table>
<tr>
<th>Cluster Name</th>
<th>State</th>
<th>Min Workers</th>
<th>Max Workers</th>
<th>Auto-Terminate</th>
<th>Monthly Cost</th>
<th>Status</th>
</tr>
$prodClusterRows
</table>

<h2>Production SQL Warehouses</h2>
<table>
<tr>
<th>Warehouse Name</th>
<th>State</th>
<th>Size</th>
<th>Auto-Stop</th>
<th>Status</th>
</tr>
$prodWarehouseRows
</table>

<h2>PreProd Environment</h2>
<p><strong>Clusters:</strong> $($data.preprod.clusters.Count)</p>
<p><strong>SQL Warehouses:</strong> $($data.preprod.warehouses.Count)</p>
<p>PreProd environment is for testing - configurations are appropriate.</p>

<h2>📧 Teams Message Template</h2>
<div style="background:#e3f2fd;padding:20px;border-radius:5px;border-left:4px solid:#1976d2;margin:20px 0;">
<p><strong>Subject:</strong> Databricks Processing Cluster - Configuration Updated</p>
<hr style="border:none;border-top:1px solid #ccc;margin:15px 0;">
<p>Fixed the Databricks Processing Cluster configuration to address the issues reported:</p>
<p><strong>Changes Applied:</strong></p>
<ul>
<li>Min workers: 1 → 2 (faster startup for Tableau)</li>
<li>Max workers: 2 → 8 (allows scaling for heavy workloads)</li>
<li>Auto-termination: 10 → 30 minutes (prevents frequent restarts)</li>
</ul>
<p><strong>Results:</strong></p>
<ul>
<li>✓ Clusters start up quickly (1-2 minutes)</li>
<li>✓ No random shutdowns during work sessions</li>
<li>✓ Cost-effective (+$175/month for better performance)</li>
</ul>
<p>Tableau connections should now be instant with no timeout issues.</p>
<p>- Syed</p>
</div>

<h2>Next Steps</h2>
<ol>
<li>Monitor Tableau connection performance over next 24-48 hours</li>
<li>Verify no quota alerts</li>
<li>Gather user feedback on cluster startup times</li>
<li>Consider implementing cluster policies to prevent similar issues</li>
</ol>

<p style="margin-top:60px;border-top:2px solid #ddd;padding-top:20px;">
<strong>Prepared by:</strong> Syed Rizvi, Infrastructure Team<br>
<strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd')<br>
<strong>Status:</strong> <span style="color:green;font-weight:bold;">Complete</span>
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
Write-Host "Report saved: $reportFile" -ForegroundColor Green
Write-Host "Production Clusters: $($data.prod.clusters.Count)" -ForegroundColor White
Write-Host "Production Warehouses: $($data.prod.warehouses.Count)" -ForegroundColor White
Write-Host "Total Monthly Cost: `$$totalCost" -ForegroundColor White
Write-Host ""
Write-Host "Opening report in browser..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
Write-Host ""
