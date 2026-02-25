param([switch]$AutoFix, [int]$DTUThreshold = 80)

$ErrorActionPreference = "SilentlyContinue"
$ReportPath = "C:\Temp\SQL_DTU_Reports"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

Write-Host "Installing required modules..." -ForegroundColor Cyan
'Az.Accounts','Az.Sql','Az.Monitor' | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue 
    }
    Import-Module $_ -ErrorAction SilentlyContinue
}

Write-Host "Connecting to Azure..." -ForegroundColor Cyan
$ctx = Get-AzContext
if (!$ctx) { Connect-AzAccount | Out-Null }
Write-Host "Connected: $($ctx.Account.Id)" -ForegroundColor Green
Write-Host ""

$servers = Get-AzSqlServer
$allDatabases = @()
$changedDatabases = @()
$totalScanned = 0

Write-Host "Scanning SQL Databases..." -ForegroundColor Cyan
Write-Host ""

foreach ($server in $servers) {
    $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName | Where-Object { $_.DatabaseName -ne 'master' }
    
    foreach ($db in $dbs) {
        $totalScanned++
        Write-Host "[$totalScanned] $($db.DatabaseName)" -ForegroundColor Gray
        
        $currentDTU = 0
        $currentTier = $db.SkuName
        
        if ($db.CurrentServiceObjectiveName -match '(\d+)') { 
            $currentDTU = [int]$matches[1] 
        } elseif ($db.SkuName -eq 'Basic') {
            $currentDTU = 5
        }
        
        $endTime = Get-Date
        $startTime = $endTime.AddHours(-24)
        
        $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 -AggregationType Average -ErrorAction SilentlyContinue
        
        $avgDTU = 0
        $maxDTU = 0
        $status = "No Data"
        
        if ($metric -and $metric.Data -and ($metric.Data | Where-Object { $_.Average })) {
            $avgDTU = [math]::Round(($metric.Data | Where-Object { $_.Average } | Measure-Object -Property Average -Average).Average, 2)
            $maxDTU = [math]::Round(($metric.Data | Where-Object { $_.Average } | Measure-Object -Property Average -Maximum).Maximum, 2)
            
            if ($maxDTU -gt 95) {
                $status = "Critical"
            } elseif ($avgDTU -gt 85) {
                $status = "High"
            } elseif ($avgDTU -gt $DTUThreshold) {
                $status = "Medium"
            } else {
                $status = "Healthy"
            }
        }
        
        $recommendedDTU = $currentDTU
        $recommendedTier = $currentTier
        $action = "No change needed"
        
        if ($maxDTU -gt 95) {
            $recommendedDTU = $currentDTU * 2
            $action = "Increase DTU by 100%"
        } elseif ($avgDTU -gt 85) {
            $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
            $action = "Increase DTU by 50%"
        } elseif ($avgDTU -gt $DTUThreshold) {
            $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
            $action = "Increase DTU by 25%"
        }
        
        if ($recommendedDTU -ne $currentDTU) {
            $recommendedTier = switch ($recommendedDTU) {
                {$_ -le 5} { "Basic" }
                {$_ -le 10} { "S0" }
                {$_ -le 20} { "S1" }
                {$_ -le 50} { "S2" }
                {$_ -le 100} { "S3" }
                {$_ -le 200} { "S6" }
                {$_ -le 400} { "S9" }
                default { "S12" }
            }
        }
        
        $dbInfo = [PSCustomObject]@{
            Database = $db.DatabaseName
            Server = $server.ServerName
            ResourceGroup = $server.ResourceGroupName
            CurrentTier = $currentTier
            CurrentDTU = $currentDTU
            AvgDTUPercent = $avgDTU
            MaxDTUPercent = $maxDTU
            Status = $status
            RecommendedTier = $recommendedTier
            RecommendedDTU = $recommendedDTU
            Action = $action
            Changed = $false
            NewTier = ""
        }
        
        $allDatabases += $dbInfo
        
        if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
            Write-Host "  Updating: $currentTier ($currentDTU DTU) -> $recommendedTier ($recommendedDTU DTU)" -ForegroundColor Yellow
            
            try {
                Set-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName `
                                -ServerName $server.ServerName `
                                -DatabaseName $db.DatabaseName `
                                -RequestedServiceObjectiveName $recommendedTier `
                                -ErrorAction Stop | Out-Null
                
                $dbInfo.Changed = $true
                $dbInfo.NewTier = $recommendedTier
                $changedDatabases += $dbInfo
                Write-Host "  SUCCESS!" -ForegroundColor Green
            } catch {
                Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

$issuesCount = ($allDatabases | Where-Object { $_.RecommendedDTU -ne $_.CurrentDTU }).Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Total Databases: $totalScanned" -ForegroundColor White
Write-Host "Databases needing optimization: $issuesCount" -ForegroundColor $(if ($issuesCount -gt 0) { "Red" } else { "Green" })
if ($AutoFix) {
    Write-Host "Databases changed: $($changedDatabases.Count)" -ForegroundColor Green
}
Write-Host ""

$allDatabases | Export-Csv -Path (Join-Path $ReportPath "All_Databases_$timestamp.csv") -NoTypeInformation
if ($changedDatabases.Count -gt 0) {
    $changedDatabases | Export-Csv -Path (Join-Path $ReportPath "Changes_Made_$timestamp.csv") -NoTypeInformation
}

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
<style>
body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5}
.container{max-width:1200px;margin:0 auto;background:white;padding:30px;box-shadow:0 0 10px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:3px solid #1e40af;padding-bottom:10px;margin-bottom:20px}
h2{color:#1e40af;margin-top:30px}
.summary{background:#e0e7ff;border-left:5px solid #1e40af;padding:20px;margin:20px 0}
.summary-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:15px;margin-top:15px}
.summary-item{background:white;padding:15px;border-radius:5px}
.summary-label{font-size:14px;color:#64748b}
.summary-value{font-size:24px;font-weight:bold;color:#1e40af}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:14px}
th{background:#1e40af;color:white;padding:12px;text-align:left;font-weight:600}
td{padding:10px;border:1px solid #cbd5e1}
tr:nth-child(even){background:#f8fafc}
.critical{background:#fee2e2}
.high{background:#fef3c7}
.medium{background:#e0f2fe}
.healthy{background:#d1fae5}
.changed{background:#d1fae5;font-weight:bold}
.status-badge{padding:4px 8px;border-radius:4px;font-size:12px;font-weight:bold}
.status-critical{background:#dc2626;color:white}
.status-high{background:#f59e0b;color:white}
.status-medium{background:#3b82f6;color:white}
.status-healthy{background:#059669;color:white}
</style>
</head>
<body>
<div class="container">
<h1>SQL Database DTU Analysis Report</h1>
<p><strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Analysis Period:</strong> Last 24 hours</p>

<div class="summary">
<h2 style="margin-top:0">Executive Summary</h2>
<div class="summary-grid">
<div class="summary-item">
<div class="summary-label">Total Databases Scanned</div>
<div class="summary-value">$totalScanned</div>
</div>
<div class="summary-item">
<div class="summary-label">Databases Needing Optimization</div>
<div class="summary-value" style="color:$(if($issuesCount -gt 0){'#dc2626'}else{'#059669'})">$issuesCount</div>
</div>
$(if($AutoFix){"<div class='summary-item'><div class='summary-label'>Changes Applied</div><div class='summary-value' style='color:#059669'>$($changedDatabases.Count)</div></div>"}else{""})
</div>
</div>

<h2>All Databases</h2>
<table>
<tr>
<th>Database Name</th>
<th>Server</th>
<th>Current Tier</th>
<th>Avg DTU %</th>
<th>Max DTU %</th>
<th>Status</th>
<th>Recommended</th>
$(if($AutoFix){"<th>Changed</th>"}else{""})
</tr>
"@

foreach ($db in ($allDatabases | Sort-Object MaxDTUPercent -Descending)) {
    $rowClass = switch ($db.Status) {
        "Critical" { "critical" }
        "High" { "high" }
        "Medium" { "medium" }
        "Healthy" { "healthy" }
        default { "" }
    }
    
    if ($db.Changed) { $rowClass = "changed" }
    
    $statusClass = "status-" + $db.Status.ToLower()
    
    $htmlReport += "<tr class='$rowClass'>"
    $htmlReport += "<td>$($db.Database)</td>"
    $htmlReport += "<td>$($db.Server)</td>"
    $htmlReport += "<td>$($db.CurrentTier) ($($db.CurrentDTU) DTU)</td>"
    $htmlReport += "<td>$($db.AvgDTUPercent)%</td>"
    $htmlReport += "<td>$($db.MaxDTUPercent)%</td>"
    $htmlReport += "<td><span class='status-badge $statusClass'>$($db.Status)</span></td>"
    
    if ($db.RecommendedDTU -ne $db.CurrentDTU) {
        $htmlReport += "<td>$($db.RecommendedTier) ($($db.RecommendedDTU) DTU)</td>"
    } else {
        $htmlReport += "<td>No change needed</td>"
    }
    
    if ($AutoFix) {
        $htmlReport += "<td>$(if($db.Changed){'<strong style=color:#059669>YES</strong>'}else{'No'})</td>"
    }
    
    $htmlReport += "</tr>"
}

$htmlReport += "</table>"

if ($changedDatabases.Count -gt 0) {
    $htmlReport += "<h2>Changes Applied</h2><table><tr><th>Database</th><th>Before</th><th>After</th><th>DTU Increase</th></tr>"
    foreach ($change in $changedDatabases) {
        $increase = $change.RecommendedDTU - $change.CurrentDTU
        $htmlReport += "<tr class='changed'>"
        $htmlReport += "<td>$($change.Database)</td>"
        $htmlReport += "<td>$($change.CurrentTier) ($($change.CurrentDTU) DTU)</td>"
        $htmlReport += "<td>$($change.NewTier) ($($change.RecommendedDTU) DTU)</td>"
        $htmlReport += "<td style='color:#059669;font-weight:bold'>+$increase DTU</td>"
        $htmlReport += "</tr>"
    }
    $htmlReport += "</table>"
}

$htmlReport += @"
<h2>Analysis Methodology</h2>
<ul>
<li>Analyzed DTU consumption over the past 24 hours</li>
<li>Critical: Max DTU usage > 95%</li>
<li>High: Average DTU usage > 85%</li>
<li>Medium: Average DTU usage > $DTUThreshold%</li>
<li>Healthy: DTU usage within normal limits</li>
</ul>

$(if(!$AutoFix -and $issuesCount -gt 0){"<h2>Next Steps</h2><p>To apply recommended changes, run:<br><code style='background:#f3f4f6;padding:10px;display:block;margin:10px 0'>.\SQL-DTU-Professional.ps1 -AutoFix</code></p>"}else{""})

</div>
</body>
</html>
"@

$htmlPath = Join-Path $ReportPath "DTU_Report_$timestamp.html"
$htmlReport | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""
