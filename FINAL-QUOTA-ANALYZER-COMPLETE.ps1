#Requires -Version 5.1
<#
.SYNOPSIS
    Databricks Quota Root Cause Analyzer & Fixer
    
.DESCRIPTION
    Analyzes why quota went from 10 to 64 vCPUs
    Generates professional HTML report for management
    Can apply fixes to prevent future issues
    
.PARAMETER Mode
    analyze - Just analyze and report (default)
    fix     - Analyze and apply fixes
    
.EXAMPLE
    .\QuotaAnalyzer.ps1 -Mode analyze
    .\QuotaAnalyzer.ps1 -Mode fix
#>

param(
    [ValidateSet("analyze", "fix")]
    [string]$Mode = "analyze"
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$workspace = "https://adb-324884819348686.6.azuredatabricks.net"
$token = "dapi9abaad71d0865d1a32a08cba05a318b7"
$location = "eastus"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$rootCauses = @()
$recommendations = @()
$fixesApplied = @()

# ============================================================================
# MAIN ANALYSIS
# ============================================================================
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  DATABRICKS QUOTA ROOT CAUSE ANALYZER" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# STEP 1: Get Clusters
Write-Host "[1/4] Analyzing Clusters..." -ForegroundColor Yellow

$clusterIssues = @()
try {
    $clusters = (Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/list" -Headers $headers).clusters
    
    foreach ($c in $clusters) {
        $issue = @{
            Name = $c.cluster_name
            State = $c.state
            NoAutoscale = (-not $c.autoscale)
            NoAutoTerminate = (-not $c.autotermination_minutes)
            HighMaxWorkers = $false
            MaxWorkers = 0
        }
        
        if ($c.autoscale) {
            $issue.MaxWorkers = $c.autoscale.max_workers
            if ($c.autoscale.max_workers -gt 20) {
                $issue.HighMaxWorkers = $true
                $rootCauses += "Cluster '$($c.cluster_name)' max workers = $($c.autoscale.max_workers) (QUOTA RISK)"
            }
        } else {
            $rootCauses += "Cluster '$($c.cluster_name)' has NO AUTOSCALING"
        }
        
        if (-not $c.autotermination_minutes) {
            $rootCauses += "Cluster '$($c.cluster_name)' has NO AUTO-TERMINATION (runs forever)"
        }
        
        $clusterIssues += $issue
    }
    
    Write-Host "  Found $($clusters.Count) clusters" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# STEP 2: Get SQL Warehouses
Write-Host "[2/4] Analyzing SQL Warehouses..." -ForegroundColor Yellow

$warehouseIssues = @()
try {
    $warehouses = (Invoke-RestMethod -Uri "$workspace/api/2.0/sql/warehouses" -Headers $headers).warehouses
    
    foreach ($w in $warehouses) {
        $warehouseIssues += @{
            Name = $w.name
            State = $w.state
            Size = $w.cluster_size
            NumClusters = $w.num_clusters
        }
        
        if ($w.num_clusters -gt 3) {
            $rootCauses += "SQL Warehouse '$($w.name)' has $($w.num_clusters) clusters (HIGH USAGE)"
        }
    }
    
    Write-Host "  Found $($warehouses.Count) SQL warehouses" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# STEP 3: Check Azure Quota
Write-Host "[3/4] Checking Azure Quota..." -ForegroundColor Yellow

$quotaInfo = @()
try {
    if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
        Install-Module Az.Compute -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
    }
    Import-Module Az.Compute -ErrorAction SilentlyContinue
    
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Connect-AzAccount -ErrorAction SilentlyContinue | Out-Null
    }
    
    $usages = Get-AzVMUsage -Location $location -ErrorAction Stop
    $top = $usages | Where-Object { $_.Limit -gt 0 } | Sort-Object { $_.CurrentValue / $_.Limit } -Descending | Select-Object -First 10
    
    foreach ($u in $top) {
        $pct = [math]::Round(($u.CurrentValue / $u.Limit) * 100, 1)
        $quotaInfo += @{
            Family = $u.Name.LocalizedValue
            Used = $u.CurrentValue
            Limit = $u.Limit
            Percentage = $pct
        }
        
        if ($pct -gt 90) {
            $rootCauses += "QUOTA BREACH: $($u.Name.LocalizedValue) at $pct% usage"
        }
    }
    
    Write-Host "  Quota check complete" -ForegroundColor Green
} catch {
    Write-Host "  Could not check quota (skipping)" -ForegroundColor Yellow
}

# STEP 4: Generate HTML Report
Write-Host "[4/4] Generating HTML Report..." -ForegroundColor Yellow

$reportFile = ".\DatabricksQuotaReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

$clusterTable = ""
foreach ($c in $clusterIssues) {
    $autoscaleStatus = if ($c.NoAutoscale) { "<span class='bad'>NO AUTOSCALE</span>" } else { "<span class='good'>$($c.MaxWorkers) max</span>" }
    $autoTermStatus = if ($c.NoAutoTerminate) { "<span class='bad'>NO AUTO-STOP</span>" } else { "<span class='good'>Enabled</span>" }
    
    $clusterTable += @"
    <tr>
        <td>$($c.Name)</td>
        <td>$($c.State)</td>
        <td>$autoscaleStatus</td>
        <td>$autoTermStatus</td>
    </tr>
"@
}

$warehouseTable = ""
foreach ($w in $warehouseIssues) {
    $warehouseTable += @"
    <tr>
        <td>$($w.Name)</td>
        <td>$($w.State)</td>
        <td>$($w.Size)</td>
        <td>$($w.NumClusters)</td>
    </tr>
"@
}

$quotaTable = ""
foreach ($q in $quotaInfo) {
    $color = if ($q.Percentage -gt 90) { "bad" } elseif ($q.Percentage -gt 80) { "warn" } else { "good" }
    $quotaTable += @"
    <tr>
        <td>$($q.Family)</td>
        <td>$($q.Used)</td>
        <td>$($q.Limit)</td>
        <td class='$color'>$($q.Percentage)%</td>
    </tr>
"@
}

$rootCauseList = ""
if ($rootCauses.Count -eq 0) {
    $rootCauseList = "<p class='good'>✓ No critical issues identified</p>"
} else {
    $rootCauseList = "<ul>"
    foreach ($rc in $rootCauses) {
        $rootCauseList += "<li>$rc</li>"
    }
    $rootCauseList += "</ul>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Databricks Quota Analysis Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: #f0f2f5; 
            padding: 20px;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white; 
            padding: 40px; 
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #FF3621; 
            margin-bottom: 10px;
            font-size: 32px;
        }
        h2 { 
            color: #1B3139; 
            margin: 30px 0 15px 0; 
            padding-bottom: 10px;
            border-bottom: 3px solid #FF3621;
            font-size: 24px;
        }
        .timestamp { 
            color: #666; 
            font-size: 14px; 
            margin-bottom: 20px;
        }
        .summary-box {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
            border-left: 4px solid #FF3621;
        }
        .summary-box p {
            margin: 10px 0;
            font-size: 16px;
        }
        table { 
            width: 100%; 
            border-collapse: collapse; 
            margin: 20px 0;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        th { 
            background: #1B3139; 
            color: white; 
            padding: 15px; 
            text-align: left;
            font-weight: 600;
        }
        td { 
            padding: 12px 15px; 
            border-bottom: 1px solid #e0e0e0;
        }
        tr:hover { 
            background: #f5f5f5;
        }
        .good { 
            color: #28a745; 
            font-weight: bold;
        }
        .bad { 
            color: #dc3545; 
            font-weight: bold;
        }
        .warn { 
            color: #ffc107; 
            font-weight: bold;
        }
        ul {
            margin: 15px 0 15px 30px;
        }
        li {
            margin: 8px 0;
            line-height: 1.6;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            color: #666;
            font-size: 14px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Databricks Quota Analysis Report</h1>
        <p class="timestamp">Generated: $(Get-Date -Format 'MMMM dd, yyyy - HH:mm:ss')</p>
        <p class="timestamp">Workspace: $workspace</p>
        
        <div class="summary-box">
            <h2 style="border:none; margin:0 0 15px 0;">📊 Executive Summary</h2>
            <p><strong>Total Clusters:</strong> $($clusterIssues.Count)</p>
            <p><strong>Total SQL Warehouses:</strong> $($warehouseIssues.Count)</p>
            <p><strong>Root Causes Identified:</strong> <span class='bad'>$($rootCauses.Count)</span></p>
            <p><strong>Status:</strong> $(if ($rootCauses.Count -eq 0) { "<span class='good'>Healthy</span>" } else { "<span class='bad'>Issues Found</span>" })</p>
        </div>
        
        <h2>🚨 Root Causes Identified</h2>
        $rootCauseList
        
        <h2>💻 Cluster Analysis</h2>
        <table>
            <tr>
                <th>Cluster Name</th>
                <th>State</th>
                <th>Autoscaling</th>
                <th>Auto-Termination</th>
            </tr>
            $clusterTable
        </table>
        
        <h2>🗄️ SQL Warehouse Analysis</h2>
        <table>
            <tr>
                <th>Warehouse Name</th>
                <th>State</th>
                <th>Size</th>
                <th>Num Clusters</th>
            </tr>
            $warehouseTable
        </table>
        
        <h2>📈 Azure vCPU Quota Status</h2>
        <table>
            <tr>
                <th>VM Family</th>
                <th>Used</th>
                <th>Limit</th>
                <th>Usage %</th>
            </tr>
            $quotaTable
        </table>
        
        <h2>✅ Recommended Actions</h2>
        <ul>
            <li>Enable autoscaling on all clusters (prevents over-provisioning)</li>
            <li>Enable auto-termination (30-60 minutes recommended)</li>
            <li>Cap max workers at 12 per cluster (prevents quota spikes)</li>
            <li>Monitor SQL warehouse usage patterns</li>
            <li>Request quota increase if sustained high usage</li>
        </ul>
        
        <div class="footer">
            <p>Report generated by Databricks Quota Analyzer</p>
            <p>For questions, contact your Databricks administrator</p>
        </div>
    </div>
</body>
</html>
"@

Set-Content -Path $reportFile -Value $html
Write-Host "  Report saved: $reportFile" -ForegroundColor Green

# Open report
Start-Process $reportFile

# Summary
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Root Causes Found: $($rootCauses.Count)" -ForegroundColor $(if ($rootCauses.Count -eq 0) { "Green" } else { "Red" })
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host ""

if ($rootCauses.Count -gt 0) {
    Write-Host "TOP ROOT CAUSES:" -ForegroundColor Yellow
    for ($i = 0; $i -lt [Math]::Min(5, $rootCauses.Count); $i++) {
        Write-Host "  $($i+1). $($rootCauses[$i])" -ForegroundColor Red
    }
    Write-Host ""
}

# Apply fixes if requested
if ($Mode -eq "fix") {
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host "  APPLYING FIXES" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Type 'YES' to apply fixes: " -NoNewline -ForegroundColor Red
    $confirm = Read-Host
    
    if ($confirm -eq "YES") {
        foreach ($c in $clusters) {
            if (-not $c.autoscale -or (-not $c.autotermination_minutes)) {
                $edit = @{
                    cluster_id = $c.cluster_id
                    cluster_name = $c.cluster_name
                    spark_version = $c.spark_version
                    node_type_id = $c.node_type_id
                }
                
                if (-not $c.autoscale) {
                    $edit["autoscale"] = @{
                        min_workers = 1
                        max_workers = 8
                    }
                    $fixesApplied += "Enabled autoscaling on '$($c.cluster_name)'"
                }
                
                if (-not $c.autotermination_minutes) {
                    $edit["autotermination_minutes"] = 30
                    $fixesApplied += "Enabled auto-termination on '$($c.cluster_name)'"
                }
                
                try {
                    Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/edit" -Headers $headers -Method Post -Body ($edit | ConvertTo-Json -Depth 10) | Out-Null
                    Write-Host "  ✓ Fixed: $($c.cluster_name)" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed: $($c.cluster_name)" -ForegroundColor Red
                }
            }
        }
        
        Write-Host ""
        Write-Host "Fixes Applied: $($fixesApplied.Count)" -ForegroundColor Green
    } else {
        Write-Host "Cancelled" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host ""
