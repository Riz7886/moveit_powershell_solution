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
Write-Host ""
Write-Host "TONY'S REQUEST: Analyzing MyCareLoop databases over PAST 2 WEEKS" -ForegroundColor Cyan
Write-Host ""

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant }

$allDatabases = @()
$changedDatabases = @()
$totalScanned = 0

foreach ($sub in $subscriptions) {
    Write-Host "[$($sub.Name)]" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { continue }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            if ($db.DatabaseName -notlike "*mycareloop*" -and $db.DatabaseName -notlike "*careloop*") {
                continue
            }
            
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
            
            Write-Host "    Analyzing 2-week usage..." -ForegroundColor Gray
            
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-14)
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 -AggregationType Average -ErrorAction SilentlyContinue
            
            $avgDTU = 0
            $maxDTU = 0
            $peakCount = 0
            
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $avgDTU = [math]::Round(($valid | Measure-Object -Property Average -Average).Average, 2)
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                    $peakCount = ($valid | Where-Object { $_.Average -gt 80 }).Count
                }
            }
            
            $recommendedTier = $currentTier
            $recommendedDTU = $currentDTU
            $actionType = "KEEP"
            $reason = "Normal usage over 2 weeks"
            
            if ($maxDTU -gt 95) {
                $recommendedDTU = $currentDTU * 2
                $actionType = "INCREASE"
                $reason = "Critical: Max $maxDTU% reached (peaked $peakCount times in 2 weeks)"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $actionType = "INCREASE"
                $reason = "High sustained usage: Avg $avgDTU% over 2 weeks"
            } elseif ($peakCount -gt 20) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $reason = "Frequent peaks: >80% DTU occurred $peakCount times in 2 weeks"
            } elseif ($avgDTU -gt 60) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $reason = "Moderate usage: Avg $avgDTU% over 2 weeks"
            }
            
            if ($recommendedDTU -ne $currentDTU) {
                if ($recommendedDTU -le 10) {
                    $recommendedTier = "S0"
                } elseif ($recommendedDTU -le 20) {
                    $recommendedTier = "S1"
                } elseif ($recommendedDTU -le 50) {
                    $recommendedTier = "S2"
                } elseif ($recommendedDTU -le 100) {
                    $recommendedTier = "S3"
                } elseif ($recommendedDTU -le 200) {
                    $recommendedTier = "S4"
                } elseif ($recommendedDTU -le 400) {
                    $recommendedTier = "S6"
                } elseif ($recommendedDTU -le 800) {
                    $recommendedTier = "S7"
                } elseif ($recommendedDTU -le 1600) {
                    $recommendedTier = "S9"
                } else {
                    $recommendedTier = "S12"
                }
            }
            
            $info = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                SizeGB = $currentSizeGB
                AvgDTU_2Week = $avgDTU
                MaxDTU_2Week = $maxDTU
                PeakCount = $peakCount
                RecommendedTier = $recommendedTier
                RecommendedDTU = $recommendedDTU
                ActionType = $actionType
                Reason = $reason
                Changed = $false
                BeforeTier = $currentTier
                BeforeDTU = $currentDTU
                AfterTier = ""
                AfterDTU = 0
                Result = ""
            }
            
            $allDatabases += $info
            
            if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
                Write-Host "    INCREASING: $currentTier ($currentDTU DTU) -> $recommendedTier ($recommendedDTU DTU)" -ForegroundColor Yellow
                try {
                    Set-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName `
                                    -ServerName $server.ServerName `
                                    -DatabaseName $db.DatabaseName `
                                    -Edition "Standard" `
                                    -RequestedServiceObjectiveName ([string]$recommendedTier) `
                                    -MaxSizeBytes ([long]$currentSizeBytes) `
                                    -ErrorAction Stop | Out-Null
                    
                    $info.Changed = $true
                    $info.AfterTier = $recommendedTier
                    $info.AfterDTU = $recommendedDTU
                    $info.Result = "SUCCESS"
                    $changedDatabases += $info
                    Write-Host "    SUCCESS!" -ForegroundColor Green
                } catch {
                    $info.Result = "FAILED: $($_.Exception.Message)"
                    Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

$needIncrease = ($allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }).Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "2-WEEK ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "MyCareLoop databases analyzed: $totalScanned" -ForegroundColor White
Write-Host "Need DTU increase: $needIncrease" -ForegroundColor Red
if ($AutoFix) { Write-Host "Successfully changed: $($changedDatabases.Count)" -ForegroundColor Green }

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1800px;margin:0 auto;background:white;padding:30px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:4px solid #1e40af;padding-bottom:15px}
h2{color:#1e40af;margin-top:30px;border-bottom:2px solid #e5e7eb;padding-bottom:10px}
.info{background:#f0f9ff;border-left:5px solid #3b82f6;padding:20px;margin:20px 0}
.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin:25px 0}
.stat{padding:25px;border-radius:8px;text-align:center}
.stat-label{font-size:14px;color:#64748b;font-weight:600}
.stat-value{font-size:42px;font-weight:bold;margin-top:10px}
table{width:100%;border-collapse:collapse;margin:25px 0;font-size:13px}
th{background:#1e40af;color:white;padding:12px;text-align:left}
td{padding:10px;border-bottom:1px solid #e5e7eb}
tr:hover{background:#f8fafc}
.changed{background:#bbf7d0;font-weight:600}
.increase{background:#fee2e2}
.arrow{font-size:20px;color:#059669;font-weight:bold}
</style></head><body><div class="container">
<h1>MyCareLoop SQL DTU Analysis - 2 Week Review</h1>

<div class="info">
<strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Analysis Period:</strong> Past 14 days (2 weeks)<br>
<strong>Analyzed By:</strong> $($ctx.Account.Id)<br>
<strong>Request:</strong> Tony Schlak - Review MyCareLoop database utilization<br>
$(if($AutoFix){"<strong>Mode:</strong> Changes Applied"}else{"<strong>Mode:</strong> Analysis Only"})
</div>

<div class="summary">
<div class="stat" style="background:#e0e7ff">
<div class="stat-label">MyCareLoop Databases</div>
<div class="stat-value" style="color:#1e40af">$totalScanned</div>
</div>
<div class="stat" style="background:#fee2e2">
<div class="stat-label">Need DTU Increase</div>
<div class="stat-value" style="color:#dc2626">$needIncrease</div>
</div>
$(if($AutoFix){"<div class='stat' style='background:#bbf7d0'><div class='stat-label'>Successfully Changed</div><div class='stat-value' style='color:#059669'>$($changedDatabases.Count)</div></div>"}else{""})
</div>
"@

if ($changedDatabases.Count -gt 0) {
    $html += @"
<h2>CHANGES APPLIED - BEFORE AND AFTER</h2>
<table>
<tr>
<th>Database Name</th>
<th>Server</th>
<th>BEFORE</th>
<th></th>
<th>AFTER</th>
<th>DTU Increase</th>
<th>2-Week Stats</th>
<th>Reason</th>
</tr>
"@
    foreach ($c in $changedDatabases) {
        $dtuIncrease = $c.AfterDTU - $c.BeforeDTU
        $html += @"
<tr class="changed">
<td><strong>$($c.Database)</strong></td>
<td>$($c.Server)</td>
<td>$($c.BeforeTier) ($($c.BeforeDTU) DTU)</td>
<td><span class="arrow">→</span></td>
<td><strong>$($c.AfterTier) ($($c.AfterDTU) DTU)</strong></td>
<td style="color:#059669;font-weight:bold">+$dtuIncrease DTU</td>
<td>Avg: $($c.AvgDTU_2Week)% | Max: $($c.MaxDTU_2Week)% | Peaks: $($c.PeakCount)</td>
<td>$($c.Reason)</td>
</tr>
"@
    }
    $html += "</table>"
}

$needIncreaseDBs = $allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
if ($needIncreaseDBs.Count -gt 0) {
    $html += "<h2>DATABASES NEEDING DTU INCREASE ($($needIncreaseDBs.Count))</h2><table><tr><th>Database</th><th>Current</th><th>2-Week Avg %</th><th>2-Week Max %</th><th>Peak Count</th><th>Recommended</th><th>Reason</th>$(if($AutoFix){"<th>Status</th>"})</tr>"
    foreach ($db in ($needIncreaseDBs | Sort-Object MaxDTU_2Week -Descending)) {
        $class = if($db.Changed){"changed"}else{"increase"}
        $html += "<tr class='$class'><td><strong>$($db.Database)</strong></td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU_2Week)%</td><td>$($db.MaxDTU_2Week)%</td><td>$($db.PeakCount)</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.Reason)</td>"
        if($AutoFix){
            $html += if($db.Changed){"<td style='color:#059669;font-weight:bold'>DONE</td>"}else{"<td>-</td>"}
        }
        $html += "</tr>"
    }
    $html += "</table>"
}

$html += @"
<h2>ALL MYCARELOOP DATABASES - 2 Week Analysis</h2>
<table>
<tr><th>Database</th><th>Server</th><th>Current</th><th>Size</th><th>Avg DTU %</th><th>Max DTU %</th><th>Peak Count</th><th>Recommendation</th><th>Status</th></tr>
"@

foreach ($db in ($allDatabases | Sort-Object MaxDTU_2Week -Descending)) {
    $class = if($db.Changed){"changed"}elseif($db.ActionType -eq "INCREASE"){"increase"}else{""}
    $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.Server)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.SizeGB) GB</td><td>$($db.AvgDTU_2Week)%</td><td>$($db.MaxDTU_2Week)%</td><td>$($db.PeakCount)</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.ActionType)</td></tr>"
}

$html += @"
</table>

<h2>Analysis Methodology</h2>
<div class="info">
<strong>Analysis Period:</strong> 14 days (2 weeks) as requested by Tony<br>
<strong>Data Points:</strong> Hourly DTU consumption metrics<br>
<strong>Criteria for DTU Increase:</strong>
<ul>
<li><strong>Critical:</strong> Max DTU > 95% (database hitting limits)</li>
<li><strong>High Sustained:</strong> Average DTU > 80% over 2 weeks</li>
<li><strong>Frequent Peaks:</strong> DTU > 80% more than 20 times in 2 weeks</li>
<li><strong>Moderate:</strong> Average DTU > 60% over 2 weeks</li>
</ul>
</div>

$(if(!$AutoFix -and $needIncrease -gt 0){"<div class='info' style='background:#fef3c7;border-left-color:#f59e0b'><strong>Note:</strong> To apply these changes, run with -AutoFix flag</div>"}else{""})

<div style="margin-top:30px;padding-top:20px;border-top:2px solid #e5e7eb;color:#64748b;font-size:12px">
<p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>For:</strong> Tony Schlak - MyCareLoop DTU Review</p>
</div>

</div></body></html>
"@

$htmlPath = Join-Path $ReportPath "MyCareLoop_2Week_DTU_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host ""
Write-Host "Report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""

if ($changedDatabases.Count -gt 0) {
    Write-Host "EMAIL FOR TONY:" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Hi Tony," -ForegroundColor White
    Write-Host ""
    Write-Host "Completed 2-week MyCareLoop database analysis as requested:" -ForegroundColor White
    Write-Host ""
    Write-Host "SUMMARY:" -ForegroundColor Cyan
    Write-Host "  MyCareLoop databases analyzed: $totalScanned" -ForegroundColor White
    Write-Host "  DTU increases applied: $($changedDatabases.Count)" -ForegroundColor Green
    Write-Host ""
    Write-Host "DATABASES INCREASED:" -ForegroundColor Yellow
    foreach ($c in $changedDatabases) {
        $increase = $c.AfterDTU - $c.BeforeDTU
        Write-Host "  $($c.Database): $($c.BeforeTier) -> $($c.AfterTier) (+$increase DTU)" -ForegroundColor Yellow
        Write-Host "    Reason: $($c.Reason)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Detailed HTML report attached showing:" -ForegroundColor White
    Write-Host "  - Before/After for all changes" -ForegroundColor White
    Write-Host "  - 2-week usage patterns" -ForegroundColor White
    Write-Host "  - Peak frequency analysis" -ForegroundColor White
    Write-Host ""
    Write-Host "Syed" -ForegroundColor White
} else {
    Write-Host "EMAIL FOR TONY:" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Hi Tony," -ForegroundColor White
    Write-Host ""
    Write-Host "Completed 2-week MyCareLoop database analysis:" -ForegroundColor White
    Write-Host ""
    Write-Host "Found $needIncrease database(s) that need DTU increases based on 2-week usage patterns." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Detailed HTML report attached showing all recommendations." -ForegroundColor White
    Write-Host ""
    Write-Host "Ready to apply changes with your approval." -ForegroundColor White
    Write-Host ""
    Write-Host "Syed" -ForegroundColor White
}
