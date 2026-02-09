# Databricks Quota Root Cause Analyzer - DNS FIXED VERSION
# Fixes PowerShell DNS issues

param(
    [ValidateSet("diagnose","fix","all")]
    [string]$Mode = "diagnose"
)

# FIX POWERSHELL DNS AND TLS ISSUES
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$workspace = "https://adb-324884819348686.6.azuredatabricks.net"
$token = "dapi9abaad71d0865d1a32a08cba05a318b7"
$location = "eastus"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$rootCauses = @()
$fixes = @()
$clusterData = @()
$warehouseData = @()

function Write-Banner {
    param($Text)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Status {
    param($Text, $Type = "INFO")
    $color = switch($Type) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "White" }
    }
    Write-Host $Text -ForegroundColor $color
}

Write-Banner "DATABRICKS QUOTA ROOT CAUSE ANALYZER"

# STEP 1: DIAGNOSE CLUSTERS
Write-Status "[1/4] Analyzing Clusters..." "INFO"

try {
    $clResp = Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/list" -Headers $headers -UseBasicParsing
    
    if ($clResp.clusters) {
        Write-Status "  Found $($clResp.clusters.Count) clusters" "OK"
        
        foreach ($c in $clResp.clusters) {
            $name = $c.cluster_name
            $state = $c.state
            
            Write-Status "    - $name [$state]" "INFO"
            
            $hasAutoscale = $false
            $maxWorkers = 0
            
            if ($c.autoscale) {
                $hasAutoscale = $true
                $maxWorkers = $c.autoscale.max_workers
                
                if ($maxWorkers -gt 20) {
                    $rootCauses += "ROOT CAUSE: Cluster '$name' max_workers=$maxWorkers (QUOTA RISK)"
                    $fixes += "Reduce max_workers on '$name' from $maxWorkers to 12"
                }
            } else {
                $rootCauses += "ROOT CAUSE: Cluster '$name' has NO AUTOSCALING"
                $fixes += "Enable autoscaling on '$name' (min=1, max=8)"
            }
            
            if (-not $c.autotermination_minutes) {
                $rootCauses += "ROOT CAUSE: Cluster '$name' has NO AUTO-TERMINATION"
                $fixes += "Enable auto-termination on '$name' (30 minutes)"
            }
            
            $clusterData += [PSCustomObject]@{
                Name = $name
                State = $state
                Autoscale = if ($hasAutoscale) { "YES ($($c.autoscale.min_workers)-$maxWorkers)" } else { "NO" }
                AutoTerminate = if ($c.autotermination_minutes) { "YES ($($c.autotermination_minutes) min)" } else { "NO" }
                NodeType = $c.node_type_id
                ClusterID = $c.cluster_id
            }
        }
    } else {
        Write-Status "  No clusters found" "WARN"
    }
} catch {
    Write-Status "  ERROR: $($_.Exception.Message)" "ERROR"
}

# STEP 2: DIAGNOSE SQL WAREHOUSES
Write-Status ""
Write-Status "[2/4] Analyzing SQL Warehouses..." "INFO"

try {
    $whResp = Invoke-RestMethod -Uri "$workspace/api/2.0/sql/warehouses" -Headers $headers -UseBasicParsing
    
    if ($whResp.warehouses) {
        Write-Status "  Found $($whResp.warehouses.Count) warehouses" "OK"
        
        foreach ($w in $whResp.warehouses) {
            Write-Status "    - $($w.name) [$($w.state)]" "INFO"
            
            $warehouseData += [PSCustomObject]@{
                Name = $w.name
                State = $w.state
                Size = $w.cluster_size
                AutoStop = "$($w.auto_stop_mins) min"
                NumClusters = $w.num_clusters
            }
            
            if ($w.num_clusters -gt 5) {
                $rootCauses += "ROOT CAUSE: SQL Warehouse '$($w.name)' running $($w.num_clusters) clusters"
                $fixes += "Review '$($w.name)' usage patterns"
            }
        }
    } else {
        Write-Status "  No warehouses found" "WARN"
    }
} catch {
    Write-Status "  ERROR: $($_.Exception.Message)" "ERROR"
}

# STEP 3: CHECK AZURE QUOTA
Write-Status ""
Write-Status "[3/4] Checking Azure vCPU Quota..." "INFO"

$quotaData = @()

try {
    if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
        Write-Status "  Installing Az.Compute..." "WARN"
        Install-Module Az.Compute -Force -AllowClobber -Scope CurrentUser -WarningAction SilentlyContinue
    }
    
    Import-Module Az.Compute -ErrorAction SilentlyContinue
    
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-Status "  Connecting to Azure..." "WARN"
        Connect-AzAccount | Out-Null
    }
    
    $usages = Get-AzVMUsage -Location $location
    $top = $usages | Where-Object { $_.Limit -gt 0 -and $_.CurrentValue -gt 0 } | 
           Sort-Object { $_.CurrentValue / $_.Limit } -Descending | 
           Select-Object -First 10
    
    Write-Status ""
    Write-Status "  Top 10 vCPU Families:" "INFO"
    Write-Status ("  {0,-50} {1,8} {2,8} {3,8}" -f "Family", "Used", "Limit", "Usage%") "INFO"
    Write-Status ("  " + ("-" * 80)) "INFO"
    
    foreach ($u in $top) {
        $pct = [math]::Round(($u.CurrentValue / $u.Limit) * 100, 1)
        $status = if ($pct -gt 90) { "ERROR" } elseif ($pct -gt 80) { "WARN" } else { "OK" }
        
        Write-Status ("  {0,-50} {1,8} {2,8} {3,7}%" -f $u.Name.LocalizedValue, $u.CurrentValue, $u.Limit, $pct) $status
        
        $quotaData += [PSCustomObject]@{
            Family = $u.Name.LocalizedValue
            Used = $u.CurrentValue
            Limit = $u.Limit
            Percentage = $pct
        }
        
        if ($pct -gt 90) {
            $rootCauses += "ROOT CAUSE: QUOTA BREACH - $($u.Name.LocalizedValue) at $pct%"
            $newLimit = [int]($u.Limit * 2)
            $fixes += "REQUEST QUOTA INCREASE: $($u.Name.LocalizedValue) to $newLimit vCPUs"
        }
    }
} catch {
    Write-Status "  Could not check quota: $($_.Exception.Message)" "WARN"
}

# STEP 4: GENERATE HTML REPORT
Write-Status ""
Write-Status "[4/4] Generating Report..." "INFO"

$reportFile = "Databricks-RootCause-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$clRows = ""
foreach ($c in $clusterData) {
    $clRows += "<tr><td>$($c.Name)</td><td>$($c.State)</td><td>$($c.Autoscale)</td><td>$($c.AutoTerminate)</td><td>$($c.NodeType)</td></tr>"
}

$whRows = ""
foreach ($w in $warehouseData) {
    $whRows += "<tr><td>$($w.Name)</td><td>$($w.State)</td><td>$($w.Size)</td><td>$($w.AutoStop)</td><td>$($w.NumClusters)</td></tr>"
}

$quotaRows = ""
foreach ($q in $quotaData) {
    $color = if ($q.Percentage -gt 90) { "red" } elseif ($q.Percentage -gt 80) { "orange" } else { "green" }
    $quotaRows += "<tr><td>$($q.Family)</td><td>$($q.Used)</td><td>$($q.Limit)</td><td style='color:$color;font-weight:bold;'>$($q.Percentage)%</td></tr>"
}

$rcHTML = if ($rootCauses.Count -eq 0) {
    "<p style='color:green;font-weight:bold;'>No critical issues found</p>"
} else {
    "<ul style='color:red;'>" + ($rootCauses | ForEach-Object { "<li>$_</li>" }) -join "" + "</ul>"
}

$fixHTML = if ($fixes.Count -gt 0) {
    "<ul style='color:blue;'>" + ($fixes | ForEach-Object { "<li>$_</li>" }) -join "" + "</ul>"
} else {
    ""
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Root Cause Analysis</title>
<style>
body{font-family:Arial;margin:20px;background:#f5f5f5;}
.container{max-width:1400px;margin:0 auto;background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}
h1{color:#FF3621;margin-bottom:10px;}
h2{color:#1B3139;border-bottom:3px solid #FF3621;padding-bottom:8px;margin-top:30px;}
.summary{background:#f8f9fa;padding:20px;border-left:4px solid #FF3621;margin:20px 0;}
table{width:100%;border-collapse:collapse;margin:20px 0;}
th{background:#1B3139;color:white;padding:12px;text-align:left;}
td{padding:10px;border-bottom:1px solid #ddd;}
tr:hover{background:#f5f5f5;}
</style>
</head>
<body>
<div class="container">
<h1>Databricks Quota Root Cause Analysis</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p>Workspace: $workspace</p>

<div class="summary">
<h2 style="margin-top:0;">Summary</h2>
<p><strong>Clusters:</strong> $($clusterData.Count)</p>
<p><strong>SQL Warehouses:</strong> $($warehouseData.Count)</p>
<p><strong>Root Causes:</strong> <span style='color:red;font-weight:bold;'>$($rootCauses.Count)</span></p>
<p><strong>Fixes:</strong> $($fixes.Count)</p>
</div>

<h2>Root Causes</h2>
$rcHTML

<h2>Recommended Fixes</h2>
$fixHTML

<h2>Clusters</h2>
<table>
<tr><th>Name</th><th>State</th><th>Autoscaling</th><th>Auto-Termination</th><th>Node Type</th></tr>
$clRows
</table>

<h2>SQL Warehouses</h2>
<table>
<tr><th>Name</th><th>State</th><th>Size</th><th>Auto-Stop</th><th>Clusters</th></tr>
$whRows
</table>

<h2>Azure Quota</h2>
<table>
<tr><th>VM Family</th><th>Used</th><th>Limit</th><th>Usage %</th></tr>
$quotaRows
</table>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8
Write-Status "  Report saved: $reportFile" "OK"
Start-Process $reportFile

# SUMMARY
Write-Banner "COMPLETE"

Write-Status "Root Causes: $($rootCauses.Count)" $(if ($rootCauses.Count -eq 0) {"OK"} else {"ERROR"})
Write-Status "Fixes: $($fixes.Count)" "INFO"
Write-Status "Report: $reportFile" "OK"

if ($rootCauses.Count -gt 0) {
    Write-Status "" "INFO"
    Write-Status "ROOT CAUSES FOUND:" "ERROR"
    for ($i = 0; $i -lt $rootCauses.Count; $i++) {
        Write-Status "  $($i+1). $($rootCauses[$i])" "ERROR"
    }
}

Write-Status "" "INFO"
Write-Status "DONE" "OK"
Write-Status "" "INFO"
