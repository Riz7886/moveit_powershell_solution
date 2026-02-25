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
            $action = "Keep current"
            $actionType = "KEEP"
            $reason = "Normal usage"
            
            if ($maxDTU -gt 90) {
                $recommendedDTU = $currentDTU * 2
                $actionType = "INCREASE"
                $reason = "Critical: Max $maxDTU%"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $actionType = "INCREASE"
                $reason = "High: Avg $avgDTU%"
            } elseif ($avgDTU -gt 60) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
                $reason = "Moderate: Avg $avgDTU%"
            } elseif ($maxDTU -lt 20 -and $maxDTU -gt 0 -and $currentDTU -gt 10) {
                $recommendedDTU = [math]::Ceiling($currentDTU / 2)
                if ($recommendedDTU -lt 10) { $recommendedDTU = 10 }
                $actionType = "DECREASE"
                $reason = "Underutilized: Max $maxDTU%"
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
                AvgDTU = $avgDTU
                MaxDTU = $maxDTU
                RecommendedTier = $recommendedTier
                RecommendedDTU = $recommendedDTU
                ActionType = $actionType
                Reason = $reason
                Changed = $false
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
                    $info.Result = "SUCCESS"
                    $changedDatabases += $info
                    Write-Host "    SUCCESS: $currentTier -> $recommendedTier" -ForegroundColor Green
                } catch {
                    $info.Result = "FAILED: $($_.Exception.Message)"
                    $failedDatabases += $info
                    Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
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
Write-Host "Total: $totalScanned | Increase: $needIncrease | Decrease: $needDecrease | Keep: $keepSame" -ForegroundColor White
if ($AutoFix) { 
    Write-Host "Success: $($changedDatabases.Count) | Failed: $($failedDatabases.Count)" -ForegroundColor $(if($failedDatabases.Count -gt 0){"Red"}else{"Green"})
}

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px}
.container{max-width:1600px;margin:0 auto;background:white;padding:30px}
h1{color:#1e40af;border-bottom:3px solid #1e40af}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#1e40af;color:white;padding:10px}
td{padding:8px;border:1px solid #ddd}
.changed{background:#bbf7d0;font-weight:bold}
.failed{background:#fecaca}
</style></head><body><div class="container">
<h1>MyCareLoop DTU Report</h1>
<p>Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p>Total: $totalScanned | Increase: $needIncrease | Decrease: $needDecrease | Keep: $keepSame</p>
"@

if ($changedDatabases.Count -gt 0) {
    $html += "<h2>SUCCESSFULLY CHANGED ($($changedDatabases.Count))</h2><table><tr><th>Database</th><th>Before</th><th>After</th><th>Reason</th></tr>"
    foreach ($c in $changedDatabases) {
        $html += "<tr class='changed'><td>$($c.Database)</td><td>$($c.CurrentTier)</td><td>$($c.RecommendedTier)</td><td>$($c.Reason)</td></tr>"
    }
    $html += "</table>"
}

if ($failedDatabases.Count -gt 0) {
    $html += "<h2>FAILED ($($failedDatabases.Count))</h2><table><tr><th>Database</th><th>Change</th><th>Error</th></tr>"
    foreach ($f in $failedDatabases) {
        $html += "<tr class='failed'><td>$($f.Database)</td><td>$($f.CurrentTier) to $($f.RecommendedTier)</td><td>$($f.Result)</td></tr>"
    }
    $html += "</table>"
}

$html += "<h2>ALL DATABASES</h2><table><tr><th>Database</th><th>Current</th><th>Avg%</th><th>Max%</th><th>Recommended</th><th>Action</th></tr>"
foreach ($db in $allDatabases) {
    $html += "<tr><td>$($db.Database)</td><td>$($db.CurrentTier)</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.RecommendedTier)</td><td>$($db.ActionType)</td></tr>"
}
$html += "</table></div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report: $htmlPath" -ForegroundColor Cyan

if ($changedDatabases.Count -gt 0) {
    Write-Host ""
    Write-Host "SEND TO TONY:" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    Write-Host "Changed $($changedDatabases.Count) databases successfully" -ForegroundColor Green
    Write-Host "Report attached" -ForegroundColor White
}
