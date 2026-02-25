param([switch]$AutoFix)

$ReportPath = "C:\Temp\SQL_DTU_Reports"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

Write-Host "Installing Azure modules..." -ForegroundColor Cyan
@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) {
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -Repository PSGallery -ErrorAction SilentlyContinue
    }
    Import-Module $_ -ErrorAction SilentlyContinue
}

Write-Host "Connecting to Azure..." -ForegroundColor Cyan
$context = Get-AzContext -ErrorAction SilentlyContinue
if (!$context) {
    Connect-AzAccount -ErrorAction Stop | Out-Null
    $context = Get-AzContext
}
Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' }
Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$allDatabases = @()
$changedDatabases = @()
$totalScanned = 0

foreach ($sub in $subscriptions) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) {
        Write-Host "  No SQL servers" -ForegroundColor Gray
        continue
    }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue |
               Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  [$totalScanned] $($db.DatabaseName)" -ForegroundColor White
            
            $currentDTU = 0
            $currentTier = $db.SkuName
            
            if ($db.CurrentServiceObjectiveName -match '(\d+)') {
                $currentDTU = [int]$matches[1]
            } elseif ($currentTier -eq 'Basic') {
                $currentDTU = 5
            } elseif ($currentTier -match 'S(\d+)') {
                $dtuMap = @{'0'=10;'1'=20;'2'=50;'3'=100;'4'=200;'6'=400;'7'=800;'9'=1600;'12'=3000}
                $currentDTU = $dtuMap[$matches[1]]
            } elseif ($currentTier -match 'P(\d+)') {
                $dtuMap = @{'1'=125;'2'=250;'4'=500;'6'=1000;'11'=1750;'15'=4000}
                $currentDTU = $dtuMap[$matches[1]]
            }
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" `
                                   -StartTime (Get-Date).AddHours(-24) -EndTime (Get-Date) `
                                   -TimeGrain 01:00:00 -AggregationType Average -ErrorAction SilentlyContinue
            
            $avgDTU = 0
            $maxDTU = 0
            if ($metric -and $metric.Data) {
                $validData = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($validData) {
                    $avgDTU = [math]::Round(($validData | Measure-Object -Property Average -Average).Average, 2)
                    $maxDTU = [math]::Round(($validData | Measure-Object -Property Average -Maximum).Maximum, 2)
                }
            }
            
            $status = if ($maxDTU -gt 95) { "Critical" } elseif ($avgDTU -gt 85) { "High" } elseif ($avgDTU -gt 80) { "Medium" } elseif ($avgDTU -gt 0) { "Healthy" } else { "No Data" }
            
            $recommendedDTU = $currentDTU
            $recommendedTier = $currentTier
            $action = "No change needed"
            
            if ($maxDTU -gt 95) {
                $recommendedDTU = $currentDTU * 2
                $action = "Increase 100%"
            } elseif ($avgDTU -gt 85) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $action = "Increase 50%"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $action = "Increase 25%"
            }
            
            if ($recommendedDTU -ne $currentDTU) {
                $recommendedTier = if ($recommendedDTU -le 5) { "Basic" } elseif ($recommendedDTU -le 10) { "S0" } elseif ($recommendedDTU -le 20) { "S1" } elseif ($recommendedDTU -le 50) { "S2" } elseif ($recommendedDTU -le 100) { "S3" } elseif ($recommendedDTU -le 200) { "S4" } elseif ($recommendedDTU -le 400) { "S6" } elseif ($recommendedDTU -le 800) { "S7" } elseif ($recommendedDTU -le 1600) { "S9" } else { "S12" }
            }
            
            $dbInfo = [PSCustomObject]@{
                Subscription = $sub.Name
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                AvgDTU = $avgDTU
                MaxDTU = $maxDTU
                Status = $status
                RecommendedTier = $recommendedTier
                RecommendedDTU = $recommendedDTU
                Action = $action
                Changed = $false
                NewTier = ""
            }
            
            $allDatabases += $dbInfo
            
            if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
                Write-Host "    Updating to $recommendedTier ($recommendedDTU DTU)..." -ForegroundColor Yellow
                try {
                    Set-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName `
                                    -DatabaseName $db.DatabaseName -RequestedServiceObjectiveName $recommendedTier -ErrorAction Stop | Out-Null
                    $dbInfo.Changed = $true
                    $dbInfo.NewTier = $recommendedTier
                    $changedDatabases += $dbInfo
                    Write-Host "    SUCCESS!" -ForegroundColor Green
                } catch {
                    Write-Host "    ERROR: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host ""
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host "Total: $totalScanned databases" -ForegroundColor White
Write-Host "Need optimization: $(($allDatabases | Where-Object { $_.RecommendedDTU -ne $_.CurrentDTU }).Count)" -ForegroundColor Yellow
if ($AutoFix) { Write-Host "Fixed: $($changedDatabases.Count)" -ForegroundColor Green }
Write-Host ""

$allDatabases | Export-Csv -Path (Join-Path $ReportPath "All_Databases_$timestamp.csv") -NoTypeInformation
if ($changedDatabases.Count -gt 0) {
    $changedDatabases | Export-Csv -Path (Join-Path $ReportPath "Changes_$timestamp.csv") -NoTypeInformation
}

$needsOptimization = $allDatabases | Where-Object { $_.RecommendedDTU -ne $_.CurrentDTU }

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1400px;margin:0 auto;background:white;padding:30px;box-shadow:0 0 10px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:3px solid #1e40af;padding-bottom:10px}
.summary{background:#e0e7ff;border-left:5px solid #1e40af;padding:20px;margin:20px 0;display:grid;grid-template-columns:repeat(3,1fr);gap:15px}
.stat{background:white;padding:15px;border-radius:5px;text-align:center}
.stat-label{font-size:14px;color:#64748b}
.stat-value{font-size:28px;font-weight:bold;color:#1e40af}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#1e40af;color:white;padding:10px;text-align:left}
td{padding:8px;border:1px solid #cbd5e1}
tr:nth-child(even){background:#f8fafc}
.critical{background:#fee2e2}.high{background:#fef3c7}.medium{background:#e0f2fe}.healthy{background:#d1fae5}
.changed{background:#d1fae5;font-weight:bold}
.badge{padding:4px 8px;border-radius:4px;font-size:11px;font-weight:bold;display:inline-block}
.badge-critical{background:#dc2626;color:white}.badge-high{background:#f59e0b;color:white}
.badge-medium{background:#3b82f6;color:white}.badge-healthy{background:#059669;color:white}
</style></head><body><div class="container">
<h1>SQL Database DTU Analysis Report</h1>
<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Analysis Period:</strong> Last 24 hours</p>
<div class="summary">
<div class="stat"><div class="stat-label">Total Databases</div><div class="stat-value">$totalScanned</div></div>
<div class="stat"><div class="stat-label">Need Optimization</div><div class="stat-value" style="color:$(if($needsOptimization.Count -gt 0){'#dc2626'}else{'#059669'})">$($needsOptimization.Count)</div></div>
$(if($AutoFix){"<div class='stat'><div class='stat-label'>Changes Applied</div><div class='stat-value' style='color:#059669'>$($changedDatabases.Count)</div></div>"}else{""})
</div>
<h2>All Databases</h2><table><tr><th>Subscription</th><th>Database</th><th>Server</th><th>Current</th><th>Avg DTU%</th><th>Max DTU%</th><th>Status</th><th>Recommended</th>$(if($AutoFix){"<th>Changed</th>"}else{""})</tr>
"@

foreach ($db in ($allDatabases | Sort-Object MaxDTU -Descending)) {
    $rowClass = switch($db.Status){"Critical"{"critical"}"High"{"high"}"Medium"{"medium"}"Healthy"{"healthy"}default{""}}
    if($db.Changed){$rowClass="changed"}
    $badgeClass = "badge-" + $db.Status.ToLower()
    $html += "<tr class='$rowClass'><td>$($db.Subscription)</td><td>$($db.Database)</td><td>$($db.Server)</td><td>$($db.CurrentTier) ($($db.CurrentDTU) DTU)</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td><span class='badge $badgeClass'>$($db.Status)</span></td>"
    $html += if($db.RecommendedDTU -ne $db.CurrentDTU){"<td>$($db.RecommendedTier) ($($db.RecommendedDTU) DTU)</td>"}else{"<td>No change</td>"}
    if($AutoFix){$html += "<td>$(if($db.Changed){'<strong style=color:#059669>YES</strong>'}else{'No'})</td>"}
    $html += "</tr>"
}

$html += "</table>"

if($changedDatabases.Count -gt 0){
    $html += "<h2>Changes Applied</h2><table><tr><th>Database</th><th>Before</th><th>After</th><th>Increase</th></tr>"
    foreach($c in $changedDatabases){
        $increase = $c.RecommendedDTU - $c.CurrentDTU
        $html += "<tr class='changed'><td>$($c.Database)</td><td>$($c.CurrentTier) ($($c.CurrentDTU))</td><td>$($c.NewTier) ($($c.RecommendedDTU))</td><td style='color:#059669;font-weight:bold'>+$increase DTU</td></tr>"
    }
    $html += "</table>"
}

$html += "<h2>Methodology</h2><ul><li>Scanned $($subscriptions.Count) Azure subscriptions</li><li>Analyzed 24-hour DTU consumption</li><li>Critical: Max > 95%, High: Avg > 85%, Medium: Avg > 80%</li></ul>"
if(!$AutoFix -and $needsOptimization.Count -gt 0){$html += "<p><strong>To apply changes:</strong> <code>.\SQL-DTU-FINAL.ps1 -AutoFix</code></p>"}
$html += "</div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report: $htmlPath" -ForegroundColor Cyan
