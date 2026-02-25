param([switch]$AutoFix)

$ReportPath = "C:\Temp\SQL_DTU_Reports"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue }
    Import-Module $_ -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

Write-Host "Connected: $($ctx.Account.Id)" -ForegroundColor Green

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant }

Write-Host "Scanning $($subscriptions.Count) subscriptions" -ForegroundColor Cyan
Write-Host ""

$allDatabases = @()
$changedDatabases = @()
$failedDatabases = @()
$totalScanned = 0

foreach ($sub in $subscriptions) {
    Write-Host "[$($sub.Name)]" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { continue }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  $totalScanned. $($db.DatabaseName)" -ForegroundColor White
            
            $currentTier = $db.SkuName
            $currentSizeBytes = $db.MaxSizeBytes
            $currentSizeGB = [math]::Round($currentSizeBytes / 1GB, 2)
            $currentDTU = 0
            
            switch -Regex ($currentTier) {
                'Basic' { $currentDTU = 5 }
                'S0' { $currentDTU = 10 }
                'S1' { $currentDTU = 20 }
                'S2' { $currentDTU = 50 }
                'S3' { $currentDTU = 100 }
                'S4' { $currentDTU = 200 }
                'S6' { $currentDTU = 400 }
                'S7' { $currentDTU = 800 }
                'S9' { $currentDTU = 1600 }
                'S12' { $currentDTU = 3000 }
                'Standard' { $currentDTU = 10 }
                default { $currentDTU = 10 }
            }
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime (Get-Date).AddHours(-24) -EndTime (Get-Date) -TimeGrain 01:00:00 -AggregationType Average -ErrorAction SilentlyContinue
            
            $avgDTU = 0
            $maxDTU = 0
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $avgDTU = [math]::Round(($valid | Measure-Object -Property Average -Average).Average, 2)
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                }
            }
            
            $recommendedTier = $currentTier
            $recommendedDTU = $currentDTU
            $action = "Keep current - optimal"
            $actionType = "KEEP"
            $reason = "Usage is normal (20-60%)"
            
            if ($maxDTU -gt 90) {
                $recommendedDTU = $currentDTU * 2
                $actionType = "INCREASE"
                $action = "INCREASE performance"
                $reason = "Critical: Max usage $maxDTU% (>90%)"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $actionType = "INCREASE"
                $action = "INCREASE performance"
                $reason = "High: Avg usage $avgDTU% (>80%)"
            } elseif ($avgDTU -gt 60) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $action = "INCREASE performance"
                $reason = "Moderate: Avg usage $avgDTU% (>60%)"
            } elseif ($maxDTU -lt 20 -and $maxDTU -gt 0 -and $currentDTU -gt 10) {
                $recommendedDTU = [math]::Ceiling($currentDTU / 2)
                if ($recommendedDTU -lt 10) { $recommendedDTU = 10 }
                $actionType = "DECREASE"
                $action = "DECREASE to save money"
                $reason = "Underutilized: Max usage only $maxDTU% (<20%)"
            }
            
            if ($recommendedDTU -ne $currentDTU) {
                $recommendedTier = switch ($recommendedDTU) {
                    {$_ -le 10} { "S0" }
                    {$_ -le 20} { "S1" }
                    {$_ -le 50} { "S2" }
                    {$_ -le 100} { "S3" }
                    {$_ -le 200} { "S4" }
                    {$_ -le 400} { "S6" }
                    {$_ -le 800} { "S7" }
                    {$_ -le 1600} { "S9" }
                    default { "S12" }
                }
            }
            
            $info = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                Subscription = $sub.Name
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                SizeGB = $currentSizeGB
                AvgDTU = $avgDTU
                MaxDTU = $maxDTU
                RecommendedTier = $recommendedTier
                RecommendedDTU = $recommendedDTU
                ActionType = $actionType
                Action = $action
                Reason = $reason
                Changed = $false
                NewTier = ""
                NewDTU = 0
                Result = ""
                ErrorDetails = ""
            }
            
            $allDatabases += $info
            
            if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
                Write-Host "    $action from $currentTier to $recommendedTier..." -ForegroundColor Yellow
                try {
                    $params = @{
                        ResourceGroupName = $server.ResourceGroupName
                        ServerName = $server.ServerName
                        DatabaseName = $db.DatabaseName
                        Edition = "Standard"
                        RequestedServiceObjectiveName = $recommendedTier
                        MaxSizeBytes = $currentSizeBytes
                        ErrorAction = "Stop"
                    }
                    
                    Set-AzSqlDatabase @params | Out-Null
                    
                    $info.Changed = $true
                    $info.NewTier = $recommendedTier
                    $info.NewDTU = $recommendedDTU
                    $info.Result = "SUCCESS"
                    $changedDatabases += $info
                    Write-Host "    ✓ SUCCESS! Changed from $currentTier ($currentDTU DTU) to $recommendedTier ($recommendedDTU DTU)" -ForegroundColor Green
                } catch {
                    $errorMsg = $_.Exception.Message
                    $info.Result = "FAILED"
                    $info.ErrorDetails = $errorMsg
                    $failedDatabases += $info
                    Write-Host "    ✗ FAILED: $errorMsg" -ForegroundColor Red
                }
            }
        }
    }
}

$needIncrease = ($allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }).Count
$needDecrease = ($allDatabases | Where-Object { $_.ActionType -eq "DECREASE" }).Count  
$keepSame = ($allDatabases | Where-Object { $_.ActionType -eq "KEEP" }).Count
$successCount = $changedDatabases.Count
$failedCount = $failedDatabases.Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "           ANALYSIS COMPLETE            " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Total databases scanned: $totalScanned" -ForegroundColor White
Write-Host "  Need INCREASE (slow): $needIncrease" -ForegroundColor Red
Write-Host "  Can DECREASE (save $): $needDecrease" -ForegroundColor Yellow
Write-Host "  Keep same (optimal): $keepSame" -ForegroundColor Green
Write-Host ""
if ($AutoFix) { 
    Write-Host "CHANGES APPLIED:" -ForegroundColor Cyan
    Write-Host "  Successfully changed: $successCount" -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Host "  Failed to change: $failedCount" -ForegroundColor Red
    }
    Write-Host ""
}

$allDatabases | Export-Csv -Path (Join-Path $ReportPath "All_Databases_$timestamp.csv") -NoTypeInformation
if ($changedDatabases.Count -gt 0) {
    $changedDatabases | Export-Csv -Path (Join-Path $ReportPath "Changed_$timestamp.csv") -NoTypeInformation
}

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial,sans-serif;margin:0;padding:20px;background:#f5f5f5}
.container{max-width:1800px;margin:0 auto;background:white;padding:30px;box-shadow:0 2px 10px rgba(0,0,0,0.1);border-radius:8px}
h1{color:#1e40af;border-bottom:4px solid #1e40af;padding-bottom:15px;margin-bottom:25px}
h2{color:#1e40af;margin-top:35px;padding-bottom:10px;border-bottom:2px solid #e5e7eb}
.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:20px;margin:25px 0}
.stat{padding:25px;border-radius:8px;text-align:center;box-shadow:0 2px 5px rgba(0,0,0,0.1)}
.stat-label{font-size:14px;color:#64748b;font-weight:600;text-transform:uppercase;margin-bottom:10px}
.stat-value{font-size:42px;font-weight:bold;margin-top:8px}
.info-box{background:#f0f9ff;border-left:5px solid#3b82f6;padding:20px;margin:20px 0;border-radius:5px}
table{width:100%;border-collapse:collapse;margin:25px 0;box-shadow:0 2px 5px rgba(0,0,0,0.1);font-size:13px}
th{background:#1e40af;color:white;padding:14px 10px;text-align:left;font-weight:600;position:sticky;top:0}
td{padding:12px 10px;border-bottom:1px solid #e5e7eb}
tr:hover{background:#f8fafc}
.increase{background:#fee2e2;border-left:4px solid #dc2626}
.decrease{background:#fef3c7;border-left:4px solid #f59e0b}
.keep{background:#d1fae5;border-left:4px solid #059669}
.changed{background:#bbf7d0;font-weight:600;border-left:4px solid #059669}
.failed{background:#fecaca;font-weight:600;border-left:4px solid #dc2626}
.badge{padding:5px 12px;border-radius:12px;font-size:11px;font-weight:700;display:inline-block}
.badge-success{background:#059669;color:white}
.badge-failed{background:#dc2626;color:white}
.badge-increase{background:#dc2626;color:white}
.badge-decrease{background:#f59e0b;color:white}
.badge-keep{background:#059669;color:white}
.change-detail{background:#fafafa;border-radius:5px;padding:8px;margin:5px 0;font-size:12px}
.arrow{font-size:18px;color:#64748b;font-weight:bold;margin:0 8px}
</style></head><body><div class="container">
<h1>🎯 MyCareLoop SQL Database DTU Optimization Report</h1>

<div class="info-box">
<strong>📅 Report Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')<br>
<strong>📊 Analysis Period:</strong> Last 24 hours<br>
<strong>👤 Analyzed By:</strong> $($ctx.Account.Id)<br>
$(if($AutoFix){"<strong>✅ Mode:</strong> Changes Applied"}else{"<strong>📋 Mode:</strong> Analysis Only (use -AutoFix to apply changes)"})
</div>

<div class="summary">
<div class="stat" style="background:#e0e7ff">
<div class="stat-label">Total Databases</div>
<div class="stat-value" style="color:#1e40af">$totalScanned</div>
</div>
<div class="stat" style="background:#fee2e2">
<div class="stat-label">Need INCREASE</div>
<div class="stat-value" style="color:#dc2626">$needIncrease</div>
<div style="font-size:12px;color:#64748b;margin-top:8px">Performance Issues</div>
</div>
<div class="stat" style="background:#fef3c7">
<div class="stat-label">Can DECREASE</div>
<div class="stat-value" style="color:#f59e0b">$needDecrease</div>
<div style="font-size:12px;color:#64748b;margin-top:8px">Cost Savings</div>
</div>
<div class="stat" style="background:#d1fae5">
<div class="stat-label">Keep Same</div>
<div class="stat-value" style="color:#059669">$keepSame</div>
<div style="font-size:12px;color:#64748b;margin-top:8px">Already Optimal</div>
</div>
</div>
"@

if ($AutoFix) {
    $html += @"
<div class="summary" style="grid-template-columns:repeat(2,1fr)">
<div class="stat" style="background:#bbf7d0">
<div class="stat-label">Successfully Changed</div>
<div class="stat-value" style="color:#059669">$successCount</div>
</div>
"@
    if ($failedCount -gt 0) {
        $html += @"
<div class="stat" style="background:#fecaca">
<div class="stat-label">Failed to Change</div>
<div class="stat-value" style="color:#dc2626">$failedCount</div>
</div>
"@
    }
    $html += "</div>"
}

if ($changedDatabases.Count -gt 0) {
    $increased = $changedDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
    $decreased = $changedDatabases | Where-Object { $_.ActionType -eq "DECREASE" }
    
    $html += "<h2>✅ CHANGES SUCCESSFULLY APPLIED ($($changedDatabases.Count) Databases)</h2>"
    
    if ($increased.Count -gt 0) {
        $html += @"
<h3 style="color:#dc2626">⬆️ INCREASED - Performance Improvements ($($increased.Count) databases)</h3>
<table>
<tr>
<th>Database Name</th>
<th>Server</th>
<th>Before</th>
<th>After</th>
<th>DTU Change</th>
<th>Usage (Avg/Max)</th>
<th>Reason</th>
</tr>
"@
        foreach ($c in $increased) {
            $dtuChange = $c.NewDTU - $c.CurrentDTU
            $html += @"
<tr class="changed">
<td><strong>$($c.Database)</strong></td>
<td>$($c.Server)</td>
<td>$($c.CurrentTier) ($($c.CurrentDTU) DTU)</td>
<td><strong>$($c.NewTier) ($($c.NewDTU) DTU)</strong></td>
<td><span class="badge badge-increase">+$dtuChange DTU</span></td>
<td>$($c.AvgDTU)% / $($c.MaxDTU)%</td>
<td>$($c.Reason)</td>
</tr>
"@
        }
        $html += "</table>"
    }
    
    if ($decreased.Count -gt 0) {
        $html += @"
<h3 style="color:#f59e0b">⬇️ DECREASED - Cost Savings ($($decreased.Count) databases)</h3>
<table>
<tr>
<th>Database Name</th>
<th>Server</th>
<th>Before</th>
<th>After</th>
<th>DTU Reduction</th>
<th>Usage (Avg/Max)</th>
<th>Reason</th>
</tr>
"@
        foreach ($c in $decreased) {
            $dtuChange = $c.CurrentDTU - $c.NewDTU
            $html += @"
<tr class="changed">
<td><strong>$($c.Database)</strong></td>
<td>$($c.Server)</td>
<td>$($c.CurrentTier) ($($c.CurrentDTU) DTU)</td>
<td><strong>$($c.NewTier) ($($c.NewDTU) DTU)</strong></td>
<td><span class="badge badge-decrease">-$dtuChange DTU (save money)</span></td>
<td>$($c.AvgDTU)% / $($c.MaxDTU)%</td>
<td>$($c.Reason)</td>
</tr>
"@
        }
        $html += "</table>"
    }
}

if ($failedDatabases.Count -gt 0) {
    $html += @"
<h2>❌ FAILED CHANGES ($($failedDatabases.Count) Databases)</h2>
<table>
<tr>
<th>Database Name</th>
<th>Attempted Change</th>
<th>Error Details</th>
</tr>
"@
    foreach ($f in $failedDatabases) {
        $html += @"
<tr class="failed">
<td><strong>$($f.Database)</strong></td>
<td>$($f.CurrentTier) → $($f.RecommendedTier)</td>
<td>$($f.ErrorDetails)</td>
</tr>
"@
    }
    $html += "</table>"
}

$html += @"
<h2>📊 ALL DATABASES - COMPLETE ANALYSIS ($totalScanned databases)</h2>
<table>
<tr>
<th>Database</th>
<th>Server</th>
<th>Current Tier</th>
<th>Size</th>
<th>Avg DTU %</th>
<th>Max DTU %</th>
<th>Recommended</th>
<th>Action Type</th>
<th>Reason</th>
$(if($AutoFix){"<th>Status</th>"}else{""})
</tr>
"@

foreach ($db in ($allDatabases | Sort-Object ActionType,MaxDTU -Descending)) {
    $class = if($db.Changed){"changed"}elseif($db.Result -eq "FAILED"){"failed"}else{switch($db.ActionType){"INCREASE"{"increase"}"DECREASE"{"decrease"}"KEEP"{"keep"}}}
    $badgeClass = "badge-" + $db.ActionType.ToLower()
    
    $html += @"
<tr class="$class">
<td><strong>$($db.Database)</strong></td>
<td>$($db.Server)</td>
<td>$($db.CurrentTier) ($($db.CurrentDTU) DTU)</td>
<td>$($db.SizeGB) GB</td>
<td>$($db.AvgDTU)%</td>
<td>$($db.MaxDTU)%</td>
<td>$($db.RecommendedTier) ($($db.RecommendedDTU) DTU)</td>
<td><span class="badge $badgeClass">$($db.ActionType)</span></td>
<td>$($db.Reason)</td>
"@
    if ($AutoFix) {
        if ($db.Changed) {
            $html += "<td><span class='badge badge-success'>✓ SUCCESS</span></td>"
        } elseif ($db.Result -eq "FAILED") {
            $html += "<td><span class='badge badge-failed'>✗ FAILED</span></td>"
        } else {
            $html += "<td>-</td>"
        }
    }
    $html += "</tr>"
}

$html += @"
</table>

<h2>📖 Methodology & Criteria</h2>
<div class="info-box">
<h3 style="margin-top:0">Decision Criteria:</h3>
<ul style="margin:10px 0">
<li><strong>INCREASE DTUs:</strong> When Max usage > 90% (Critical) OR Avg usage > 80% (High) OR Avg usage > 60% (Moderate)</li>
<li><strong>DECREASE DTUs:</strong> When Max usage < 20% (Underutilized) - saves money while maintaining performance</li>
<li><strong>KEEP SAME:</strong> When usage is between 20-60% (Optimal range)</li>
</ul>
<h3>Analysis Details:</h3>
<ul style="margin:10px 0">
<li>Analyzed DTU consumption over past 24 hours</li>
<li>Evaluated both average and peak usage patterns</li>
<li>Ensured database size compatibility with target tier</li>
<li>Preserved existing database storage size during tier changes</li>
<li>Minimum recommended tier: S0 (10 DTU) for Standard edition</li>
</ul>
</div>

$(if(!$AutoFix){"<div class='info-box' style='background:#fef3c7;border-left-color:#f59e0b'><strong>⚠️ Note:</strong> This was an analysis run. To apply these changes, run the script with <code>-AutoFix</code> parameter:<br><code style='background:#fff;padding:5px 10px;display:inline-block;margin-top:10px;border-radius:3px'>.\DTU-FINAL-DETAILED.ps1 -AutoFix</code></div>"}else{""})

<div style="margin-top:40px;padding-top:20px;border-top:2px solid #e5e7eb;color:#64748b;font-size:12px">
<p><strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Generated By:</strong> MyCareLoop DTU Optimization Script v2.0</p>
</div>

</div></body></html>
"@

$htmlPath = Join-Path $ReportPath "DTU_Complete_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "📄 Detailed report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""

if ($changedDatabases.Count -gt 0) {
    $increased = $changedDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
    $decreased = $changedDatabases | Where-Object { $_.ActionType -eq "DECREASE" }
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "       EMAIL FOR TONY" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Hi Tony," -ForegroundColor White
    Write-Host ""
    Write-Host "Completed the MyCareLoop SQL DTU optimization analysis and applied changes." -ForegroundColor White
    Write-Host ""
    Write-Host "EXECUTIVE SUMMARY:" -ForegroundColor Cyan
    Write-Host "  • Total databases analyzed: $totalScanned" -ForegroundColor White
    Write-Host "  • Changes successfully applied: $successCount" -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Host "  • Changes that failed: $failedCount (see report for details)" -ForegroundColor Red
    }
    Write-Host ""
    
    if ($increased.Count -gt 0) {
        Write-Host "PERFORMANCE IMPROVEMENTS ($($increased.Count) databases):" -ForegroundColor Red
        Write-Host "Fixed slow databases by increasing DTUs:" -ForegroundColor White
        foreach ($c in $increased | Select-Object -First 5) {
            $change = $c.NewDTU - $c.CurrentDTU
            Write-Host "  • $($c.Database): $($c.CurrentTier) → $($c.NewTier) (+$change DTU)" -ForegroundColor Red
        }
        if ($increased.Count -gt 5) {
            Write-Host "  • ... and $($increased.Count - 5) more (see full report)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    if ($decreased.Count -gt 0) {
        Write-Host "COST SAVINGS ($($decreased.Count) databases):" -ForegroundColor Yellow
        Write-Host "Reduced DTUs on underutilized databases:" -ForegroundColor White
        foreach ($c in $decreased | Select-Object -First 5) {
            $savings = $c.CurrentDTU - $c.NewDTU
            Write-Host "  • $($c.Database): $($c.CurrentTier) → $($c.NewTier) (-$savings DTU)" -ForegroundColor Yellow
        }
        if ($decreased.Count -gt 5) {
            Write-Host "  • ... and $($decreased.Count - 5) more (see full report)" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "RESULT:" -ForegroundColor Cyan
    Write-Host "  ✅ Fixed $($increased.Count) performance issues" -ForegroundColor Green
    Write-Host "  💰 Optimized $($decreased.Count) databases for cost savings" -ForegroundColor Green
    Write-Host "  📊 $keepSame databases already running optimally" -ForegroundColor Green
    Write-Host ""
    Write-Host "Detailed HTML report attached showing all changes and analysis." -ForegroundColor White
    Write-Host ""
    Write-Host "Syed Rizvi" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}
