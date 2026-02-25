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

Write-Host "Analyzing ALL databases (2-week analysis)..." -ForegroundColor Cyan
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
            
            if ($maxDTU -gt 90 -or $avgDTU -gt 70) {
                $targetUtilization = 0.50
                
                if ($maxDTU -gt 0) {
                    $actualDTUUsed = ($currentDTU * $maxDTU) / 100
                    $neededDTU = [math]::Ceiling($actualDTUUsed / $targetUtilization)
                } else {
                    $neededDTU = $currentDTU * 2
                }
                
                if ($neededDTU -le 10) {
                    $recommendedTier = "S0"
                    $recommendedDTU = 10
                } elseif ($neededDTU -le 20) {
                    $recommendedTier = "S1"
                    $recommendedDTU = 20
                } elseif ($neededDTU -le 50) {
                    $recommendedTier = "S2"
                    $recommendedDTU = 50
                } elseif ($neededDTU -le 100) {
                    $recommendedTier = "S3"
                    $recommendedDTU = 100
                } elseif ($neededDTU -le 200) {
                    $recommendedTier = "S4"
                    $recommendedDTU = 200
                } elseif ($neededDTU -le 400) {
                    $recommendedTier = "S6"
                    $recommendedDTU = 400
                } elseif ($neededDTU -le 800) {
                    $recommendedTier = "S7"
                    $recommendedDTU = 800
                } elseif ($neededDTU -le 1600) {
                    $recommendedTier = "S9"
                    $recommendedDTU = 1600
                } else {
                    $recommendedTier = "S12"
                    $recommendedDTU = 3000
                }
                
                $actionType = "INCREASE"
                $reason = "Max $maxDTU%, Avg $avgDTU% - needs $recommendedDTU DTU for optimal performance"
            } elseif ($peakCount -gt 20) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                
                if ($recommendedDTU -le 10) {
                    $recommendedTier = "S0"
                    $recommendedDTU = 10
                } elseif ($recommendedDTU -le 20) {
                    $recommendedTier = "S1"
                    $recommendedDTU = 20
                } elseif ($recommendedDTU -le 50) {
                    $recommendedTier = "S2"
                    $recommendedDTU = 50
                } elseif ($recommendedDTU -le 100) {
                    $recommendedTier = "S3"
                    $recommendedDTU = 100
                } elseif ($recommendedDTU -le 200) {
                    $recommendedTier = "S4"
                    $recommendedDTU = 200
                } elseif ($recommendedDTU -le 400) {
                    $recommendedTier = "S6"
                    $recommendedDTU = 400
                } elseif ($recommendedDTU -le 800) {
                    $recommendedTier = "S7"
                    $recommendedDTU = 800
                } else {
                    $recommendedTier = "S9"
                    $recommendedDTU = 1600
                }
                
                $actionType = "INCREASE"
                $reason = "Frequent peaks: $peakCount times >80%"
            }
            
            $info = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
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
                Write-Host "    FIXING: $currentTier ($currentDTU) -> $recommendedTier ($recommendedDTU)" -ForegroundColor Yellow
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
                    Write-Host "    SUCCESS!" -ForegroundColor Green
                } catch {
                    $info.Result = "FAILED: $($_.Exception.Message)"
                    Write-Host "    FAILED" -ForegroundColor Red
                }
            }
        }
    }
}

$needIncrease = ($allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }).Count
$keepSame = ($allDatabases | Where-Object { $_.ActionType -eq "KEEP" }).Count

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "Total: $totalScanned" -ForegroundColor White
Write-Host "Need INCREASE: $needIncrease" -ForegroundColor Red
Write-Host "Keep same: $keepSame" -ForegroundColor Green
if ($AutoFix) { Write-Host "Successfully changed: $($changedDatabases.Count)" -ForegroundColor Green }
Write-Host ""

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px}
.container{max-width:1800px;margin:0 auto;background:white;padding:30px}
h1{color:#1e40af;border-bottom:3px solid #1e40af}
h2{color:#1e40af;margin-top:30px}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#1e40af;color:white;padding:10px;text-align:left}
td{padding:8px;border:1px solid #ddd}
.changed{background:#bbf7d0;font-weight:bold}
.increase{background:#fee2e2}
.arrow{font-size:18px;color:#059669;font-weight:bold}
</style></head><body><div class="container">
<h1>SQL DTU Analysis & Fixes - 2 Week Review</h1>
<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Analysis:</strong> Past 14 days | <strong>For:</strong> Tony Schlak</p>
<p><strong>Total:</strong> $totalScanned | <strong>Need Increase:</strong> $needIncrease | <strong>Keep Same:</strong> $keepSame</p>
"@

if ($changedDatabases.Count -gt 0) {
    $html += "<h2>CHANGES APPLIED - BEFORE AND AFTER ($($changedDatabases.Count) databases)</h2><table><tr><th>Database</th><th>Server</th><th>BEFORE</th><th></th><th>AFTER</th><th>DTU Increase</th><th>2-Week Usage</th><th>Reason</th></tr>"
    foreach ($c in $changedDatabases) {
        $increase = $c.RecommendedDTU - $c.CurrentDTU
        $html += "<tr class='changed'><td><strong>$($c.Database)</strong></td><td>$($c.Server)</td><td>$($c.BeforeTier) ($($c.CurrentDTU) DTU)</td><td><span class='arrow'>→</span></td><td><strong>$($c.AfterTier) ($($c.RecommendedDTU) DTU)</strong></td><td style='color:#059669;font-weight:bold'>+$increase DTU</td><td>Avg: $($c.AvgDTU)% | Max: $($c.MaxDTU)%</td><td>$($c.Reason)</td></tr>"
    }
    $html += "</table>"
}

$needIncreaseDBs = $allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
if ($needIncreaseDBs.Count -gt 0) {
    $html += "<h2>ALL DATABASES NEEDING INCREASE ($($needIncreaseDBs.Count))</h2><table><tr><th>Database</th><th>Current</th><th>Avg %</th><th>Max %</th><th>Peaks</th><th>Recommended</th><th>Reason</th>$(if($AutoFix){"<th>Status</th>"})</tr>"
    foreach ($db in ($needIncreaseDBs | Sort-Object MaxDTU -Descending)) {
        $class = if($db.Changed){"changed"}else{"increase"}
        $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.PeakCount)</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.Reason)</td>"
        if($AutoFix){$html += if($db.Changed){"<td style='color:#059669'>FIXED</td>"}else{"<td>-</td>"}}
        $html += "</tr>"
    }
    $html += "</table>"
}

$html += "<h2>ALL DATABASES</h2><table><tr><th>Database</th><th>Server</th><th>Current</th><th>Avg %</th><th>Max %</th><th>Recommended</th><th>Action</th></tr>"
foreach ($db in ($allDatabases | Sort-Object MaxDTU -Descending)) {
    $class = if($db.Changed){"changed"}elseif($db.ActionType -eq "INCREASE"){"increase"}else{""}
    $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.Server)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.ActionType)</td></tr>"
}
$html += "</table></div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_FINAL_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report: $htmlPath" -ForegroundColor Cyan

if ($changedDatabases.Count -gt 0) {
    Write-Host ""
    Write-Host "FOR TONY:" -ForegroundColor Cyan
    Write-Host "=========" -ForegroundColor Cyan
    Write-Host "Fixed $($changedDatabases.Count) databases:" -ForegroundColor Green
    foreach ($c in $changedDatabases | Select-Object -First 10) {
        Write-Host "  $($c.Database): $($c.BeforeTier) -> $($c.AfterTier)" -ForegroundColor Yellow
    }
    if ($changedDatabases.Count -gt 10) {
        Write-Host "  ... and $($changedDatabases.Count - 10) more" -ForegroundColor Gray
    }
}
