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

Write-Host "Scanning $($subscriptions.Count) subscriptions (2-week analysis)" -ForegroundColor Cyan
Write-Host ""

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
            $reason = "Normal"
            
            if ($maxDTU -gt 95) {
                $recommendedDTU = $currentDTU * 2
                $actionType = "INCREASE"
                $reason = "Critical: Max $maxDTU% (peaked $peakCount times)"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $actionType = "INCREASE"
                $reason = "High: Avg $avgDTU% over 2 weeks"
            } elseif ($peakCount -gt 20) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $reason = "Frequent peaks: $peakCount times >80%"
            } elseif ($avgDTU -gt 60) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $reason = "Moderate: Avg $avgDTU%"
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
                Subscription = $sub.Name
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                SizeGB = $currentSizeGB
                AvgDTU = $avgDTU
                MaxDTU = $maxDTU
                PeakCount = $peakCount
                RecommendedTier = $recommendedTier
                RecommendedDTU = $recommendedDTU
                ActionType = $actionType
                Reason = $reason
                Changed = $false
                BeforeTier = $currentTier
                AfterTier = ""
                Result = ""
            }
            
            $allDatabases += $info
            
            if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
                Write-Host "    Changing $currentTier to $recommendedTier..." -ForegroundColor Yellow
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
                    $info.Result = "SUCCESS"
                    $changedDatabases += $info
                    Write-Host "    SUCCESS: $currentTier -> $recommendedTier" -ForegroundColor Green
                } catch {
                    $info.Result = "FAILED: $($_.Exception.Message)"
                    Write-Host "    FAILED" -ForegroundColor Red
                }
            }
        }
    }
}

$needIncrease = ($allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }).Count
$needDecrease = ($allDatabases | Where-Object { $_.ActionType -eq "DECREASE" }).Count  
$keepSame = ($allDatabases | Where-Object { $_.ActionType -eq "KEEP" }).Count

Write-Host ""
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "Total: $totalScanned | Increase: $needIncrease | Keep: $keepSame" -ForegroundColor White
if ($AutoFix) { Write-Host "Changed: $($changedDatabases.Count)" -ForegroundColor Green }

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px}
.container{max-width:1800px;margin:0 auto;background:white;padding:30px}
h1{color:#1e40af;border-bottom:3px solid #1e40af}
h2{color:#1e40af;margin-top:30px}
.info{background:#f0f9ff;border-left:5px solid #3b82f6;padding:20px;margin:20px 0}
.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin:25px 0}
.stat{padding:25px;border-radius:8px;text-align:center}
.stat-label{font-size:14px;color:#64748b}
.stat-value{font-size:42px;font-weight:bold}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#1e40af;color:white;padding:10px;text-align:left}
td{padding:8px;border:1px solid #ddd}
.changed{background:#bbf7d0;font-weight:bold}
.increase{background:#fee2e2}
</style></head><body><div class="container">
<h1>SQL DTU Analysis - 2 Week Review</h1>
<div class="info">
<strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Analysis Period:</strong> Past 14 days (2 weeks)<br>
<strong>For:</strong> Tony Schlak
</div>
<div class="summary">
<div class="stat" style="background:#e0e7ff">
<div class="stat-label">Total Databases</div>
<div class="stat-value" style="color:#1e40af">$totalScanned</div>
</div>
<div class="stat" style="background:#fee2e2">
<div class="stat-label">Need Increase</div>
<div class="stat-value" style="color:#dc2626">$needIncrease</div>
</div>
<div class="stat" style="background:#d1fae5">
<div class="stat-label">Keep Same</div>
<div class="stat-value" style="color:#059669">$keepSame</div>
</div>
</div>
"@

if ($changedDatabases.Count -gt 0) {
    $html += "<h2>CHANGES APPLIED - BEFORE AND AFTER</h2><table><tr><th>Database</th><th>Server</th><th>BEFORE</th><th>AFTER</th><th>DTU Change</th><th>2-Week Stats</th><th>Reason</th></tr>"
    foreach ($c in $changedDatabases) {
        $change = $c.RecommendedDTU - $c.CurrentDTU
        $html += "<tr class='changed'><td><strong>$($c.Database)</strong></td><td>$($c.Server)</td><td>$($c.BeforeTier) ($($c.CurrentDTU))</td><td><strong>$($c.AfterTier) ($($c.RecommendedDTU))</strong></td><td style='color:#059669;font-weight:bold'>+$change DTU</td><td>Avg: $($c.AvgDTU)% | Max: $($c.MaxDTU)% | Peaks: $($c.PeakCount)</td><td>$($c.Reason)</td></tr>"
    }
    $html += "</table>"
}

$needIncreaseDBs = $allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
if ($needIncreaseDBs.Count -gt 0) {
    $html += "<h2>DATABASES NEEDING INCREASE ($($needIncreaseDBs.Count))</h2><table><tr><th>Database</th><th>Current</th><th>Avg %</th><th>Max %</th><th>Peaks</th><th>Recommended</th><th>Reason</th></tr>"
    foreach ($db in ($needIncreaseDBs | Sort-Object MaxDTU -Descending)) {
        $class = if($db.Changed){"changed"}else{"increase"}
        $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.PeakCount)</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.Reason)</td></tr>"
    }
    $html += "</table>"
}

$html += "<h2>ALL DATABASES - 2 Week Analysis</h2><table><tr><th>Database</th><th>Server</th><th>Current</th><th>Avg %</th><th>Max %</th><th>Peaks</th><th>Recommended</th><th>Action</th></tr>"
foreach ($db in ($allDatabases | Sort-Object MaxDTU -Descending)) {
    $class = if($db.Changed){"changed"}elseif($db.ActionType -eq "INCREASE"){"increase"}else{""}
    $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.Server)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.PeakCount)</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.ActionType)</td></tr>"
}
$html += "</table></div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_2Week_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report: $htmlPath" -ForegroundColor Cyan

if ($changedDatabases.Count -gt 0) {
    Write-Host ""
    Write-Host "SEND TO TONY:" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    Write-Host "Changed $($changedDatabases.Count) databases (2-week analysis)" -ForegroundColor Green
    foreach ($c in $changedDatabases) {
        Write-Host "  $($c.Database): $($c.BeforeTier) -> $($c.AfterTier)" -ForegroundColor Yellow
    }
}
