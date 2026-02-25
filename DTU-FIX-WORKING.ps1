param([switch]$AutoFix)

$ReportPath = "C:\Temp\SQL_DTU_Reports"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

Write-Host "Installing modules..." -ForegroundColor Cyan
@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue }
    Import-Module $_ -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

Write-Host "Connected: $($ctx.Account.Id)" -ForegroundColor Green
Write-Host ""

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant }

Write-Host "Scanning $($subscriptions.Count) subscriptions" -ForegroundColor Cyan
Write-Host ""

$allDatabases = @()
$changedDatabases = @()
$totalScanned = 0

foreach ($sub in $subscriptions) {
    Write-Host "[$($sub.Name)]" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { Write-Host "  No SQL servers" -ForegroundColor Gray; continue }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  $totalScanned. $($db.DatabaseName)" -ForegroundColor White
            
            $currentDTU = 0
            $tier = $db.SkuName
            $currentMaxSizeBytes = $db.MaxSizeBytes
            
            if ($db.CurrentServiceObjectiveName -match '(\d+)') { $currentDTU = [int]$matches[1] }
            elseif ($tier -eq 'Basic') { $currentDTU = 5 }
            elseif ($tier -match 'S0') { $currentDTU = 10 }
            elseif ($tier -match 'S1') { $currentDTU = 20 }
            elseif ($tier -match 'S2') { $currentDTU = 50 }
            elseif ($tier -match 'S3') { $currentDTU = 100 }
            elseif ($tier -match 'S4') { $currentDTU = 200 }
            elseif ($tier -match 'S6') { $currentDTU = 400 }
            
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
            
            $status = if ($maxDTU -gt 95) { "Critical" } elseif ($avgDTU -gt 85) { "High" } elseif ($avgDTU -gt 80) { "Medium" } elseif ($avgDTU -gt 0) { "Healthy" } else { "No Data" }
            
            $recDTU = $currentDTU
            $recTier = $tier
            
            if ($maxDTU -gt 95) { $recDTU = $currentDTU * 2 }
            elseif ($avgDTU -gt 85) { $recDTU = [math]::Ceiling($currentDTU * 1.5) }
            elseif ($avgDTU -gt 80) { $recDTU = [math]::Ceiling($currentDTU * 1.25) }
            
            if ($recDTU -ne $currentDTU) {
                $recTier = if ($recDTU -le 5) { "Basic" } elseif ($recDTU -le 10) { "S0" } elseif ($recDTU -le 20) { "S1" } elseif ($recDTU -le 50) { "S2" } elseif ($recDTU -le 100) { "S3" } elseif ($recDTU -le 200) { "S4" } elseif ($recDTU -le 400) { "S6" } else { "S9" }
            }
            
            $info = [PSCustomObject]@{
                Subscription = $sub.Name
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                CurrentTier = $tier
                CurrentDTU = $currentDTU
                AvgDTU = $avgDTU
                MaxDTU = $maxDTU
                Status = $status
                RecommendedTier = $recTier
                RecommendedDTU = $recDTU
                Changed = $false
                Error = ""
            }
            
            $allDatabases += $info
            
            if ($AutoFix -and $recDTU -ne $currentDTU) {
                Write-Host "    Updating $($db.DatabaseName) to $recTier (keeping current size)..." -ForegroundColor Yellow
                try {
                    Set-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName `
                                    -ServerName $server.ServerName `
                                    -DatabaseName $db.DatabaseName `
                                    -RequestedServiceObjectiveName $recTier `
                                    -MaxSizeBytes $currentMaxSizeBytes `
                                    -ErrorAction Stop | Out-Null
                    
                    $info.Changed = $true
                    $changedDatabases += $info
                    Write-Host "    SUCCESS!" -ForegroundColor Green
                } catch {
                    $errorMsg = $_.Exception.Message
                    Write-Host "    ERROR: $errorMsg" -ForegroundColor Red
                    $info.Error = $errorMsg
                }
            }
        }
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "Total databases: $totalScanned" -ForegroundColor White
Write-Host "Need optimization: $(($allDatabases | Where-Object { $_.RecommendedDTU -ne $_.CurrentDTU }).Count)" -ForegroundColor Yellow
if ($AutoFix) { 
    Write-Host "Successfully changed: $($changedDatabases.Count)" -ForegroundColor Green 
    $failed = ($allDatabases | Where-Object { $_.Error -ne "" }).Count
    if ($failed -gt 0) { Write-Host "Failed: $failed" -ForegroundColor Red }
}
Write-Host ""

$allDatabases | Export-Csv -Path (Join-Path $ReportPath "All_Databases_$timestamp.csv") -NoTypeInformation
if ($changedDatabases.Count -gt 0) {
    $changedDatabases | Export-Csv -Path (Join-Path $ReportPath "Changed_$timestamp.csv") -NoTypeInformation
}

$needs = $allDatabases | Where-Object { $_.RecommendedDTU -ne $_.CurrentDTU }

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1400px;margin:0 auto;background:white;padding:30px;box-shadow:0 0 10px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:3px solid #1e40af;padding-bottom:10px}
.summary{background:#e0e7ff;padding:20px;margin:20px 0;display:grid;grid-template-columns:repeat(3,1fr);gap:15px}
.stat{background:white;padding:15px;border-radius:5px;text-align:center}
.stat-label{font-size:14px;color:#64748b}
.stat-value{font-size:28px;font-weight:bold;color:#1e40af}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#1e40af;color:white;padding:10px;text-align:left}
td{padding:8px;border:1px solid #ddd}
tr:nth-child(even){background:#f9f9f9}
.critical{background:#fee2e2}.high{background:#fef3c7}.healthy{background:#d1fae5}.changed{background:#d1fae5;font-weight:bold}
</style></head><body><div class="container">
<h1>SQL Database DTU Analysis</h1>
<p><strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<div class="summary">
<div class="stat"><div class="stat-label">Total Databases</div><div class="stat-value">$totalScanned</div></div>
<div class="stat"><div class="stat-label">Need Optimization</div><div class="stat-value" style="color:#dc2626">$($needs.Count)</div></div>
$(if($AutoFix){"<div class='stat'><div class='stat-label'>Changed</div><div class='stat-value' style='color:#059669'>$($changedDatabases.Count)</div></div>"}else{""})
</div>
<h2>All Databases</h2>
<table><tr><th>Subscription</th><th>Database</th><th>Server</th><th>Current</th><th>Avg%</th><th>Max%</th><th>Status</th><th>Recommended</th>$(if($AutoFix){"<th>Result</th>"}else{""})</tr>
"@

foreach ($db in ($allDatabases | Sort-Object MaxDTU -Descending)) {
    $class = if($db.Changed){"changed"}else{switch($db.Status){"Critical"{"critical"}"High"{"high"}"Healthy"{"healthy"}default{""}}}
    $html += "<tr class='$class'><td>$($db.Subscription)</td><td>$($db.Database)</td><td>$($db.Server)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.Status)</td>"
    $html += if($db.RecommendedDTU -ne $db.CurrentDTU){"<td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td>"}else{"<td>OK</td>"}
    if($AutoFix){
        if($db.Changed){$html += "<td style='color:#059669;font-weight:bold'>SUCCESS</td>"}
        elseif($db.Error -ne ""){$html += "<td style='color:#dc2626'>ERROR</td>"}
        else{$html += "<td>-</td>"}
    }
    $html += "</tr>"
}

$html += "</table>"

if($changedDatabases.Count -gt 0){
    $html += "<h2>Successfully Changed</h2><table><tr><th>Database</th><th>Before</th><th>After</th><th>Increase</th></tr>"
    foreach($c in $changedDatabases){
        $increase = $c.RecommendedDTU - $c.CurrentDTU
        $html += "<tr class='changed'><td>$($c.Database)</td><td>$($c.CurrentTier) ($($c.CurrentDTU))</td><td>$($c.RecommendedTier) ($($c.RecommendedDTU))</td><td style='color:#059669;font-weight:bold'>+$increase DTU</td></tr>"
    }
    $html += "</table>"
}

if(!$AutoFix -and $needs.Count -gt 0){$html += "<p><strong>To apply changes:</strong> <code>.\DTU-FIX-WORKING.ps1 -AutoFix</code></p>"}
$html += "</div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""

if ($changedDatabases.Count -gt 0) {
    Write-Host "EMAIL TO TONY:" -ForegroundColor Cyan
    Write-Host "==============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Hi Tony," -ForegroundColor White
    Write-Host ""
    Write-Host "I've completed the SQL DTU analysis and optimization:" -ForegroundColor White
    Write-Host ""
    Write-Host "Results:" -ForegroundColor White
    Write-Host "- Total databases scanned: $totalScanned" -ForegroundColor White
    Write-Host "- Databases optimized: $($changedDatabases.Count)" -ForegroundColor Green
    foreach ($c in $changedDatabases) {
        Write-Host "  • $($c.Database): $($c.CurrentTier) → $($c.RecommendedTier) (+$($c.RecommendedDTU - $c.CurrentDTU) DTU)" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Detailed report attached." -ForegroundColor White
    Write-Host ""
    Write-Host "Syed" -ForegroundColor White
}
