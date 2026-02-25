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
            
            if ($maxDTU -gt 90) {
                $recommendedDTU = $currentDTU * 2
                $actionType = "INCREASE"
            } elseif ($avgDTU -gt 80) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.5)
                $actionType = "INCREASE"
            } elseif ($avgDTU -gt 60) {
                $recommendedDTU = [math]::Ceiling($currentDTU * 1.25)
                $actionType = "INCREASE"
            } elseif ($maxDTU -lt 20 -and $maxDTU -gt 0 -and $currentDTU -gt 10) {
                $recommendedDTU = [math]::Ceiling($currentDTU / 2)
                if ($recommendedDTU -lt 10) { $recommendedDTU = 10 }
                $actionType = "DECREASE"
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
                
                if ($actionType -eq "INCREASE") {
                    $action = "INCREASE $currentTier -> $recommendedTier"
                } else {
                    $action = "DECREASE $currentTier -> $recommendedTier (save money)"
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
                Action = $action
                Changed = $false
                Result = ""
            }
            
            $allDatabases += $info
            
            if ($AutoFix -and $recommendedDTU -ne $currentDTU) {
                Write-Host "    $action..." -ForegroundColor Yellow
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
                    $info.Result = "SUCCESS"
                    $changedDatabases += $info
                    Write-Host "    SUCCESS!" -ForegroundColor Green
                } catch {
                    $info.Result = "Failed: $($_.Exception.Message)"
                    Write-Host "    $($info.Result)" -ForegroundColor Red
                }
            }
        }
    }
}

$needIncrease = ($allDatabases | Where-Object { $_.ActionType -eq "INCREASE" }).Count
$needDecrease = ($allDatabases | Where-Object { $_.ActionType -eq "DECREASE" }).Count  
$keepSame = ($allDatabases | Where-Object { $_.ActionType -eq "KEEP" }).Count

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "Total: $totalScanned" -ForegroundColor White
Write-Host "Need INCREASE: $needIncrease" -ForegroundColor Red
Write-Host "Can DECREASE: $needDecrease" -ForegroundColor Yellow
Write-Host "Keep same: $keepSame" -ForegroundColor Green
if ($AutoFix) { Write-Host "Changed: $($changedDatabases.Count)" -ForegroundColor Green }

$allDatabases | Export-Csv -Path (Join-Path $ReportPath "All_$timestamp.csv") -NoTypeInformation

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px}
.container{max-width:1600px;margin:0 auto;background:white;padding:30px}
h1{color:#1e40af}
.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:15px;margin:20px 0}
.stat{padding:20px;border-radius:5px;text-align:center}
.stat-value{font-size:32px;font-weight:bold}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#1e40af;color:white;padding:10px}
td{padding:8px;border:1px solid #ddd}
tr:nth-child(even){background:#f9f9f9}
.increase{background:#fee2e2}.decrease{background:#fef3c7}.keep{background:#d1fae5}.changed{background:#bbf7d0;font-weight:bold}
</style></head><body><div class="container">
<h1>MyCareLoop SQL DTU Analysis</h1>
<p>Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<div class="summary">
<div class="stat" style="background:#e0e7ff"><div>Total</div><div class="stat-value">$totalScanned</div></div>
<div class="stat" style="background:#fee2e2"><div>Need INCREASE</div><div class="stat-value" style="color:#dc2626">$needIncrease</div></div>
<div class="stat" style="background:#fef3c7"><div>Can DECREASE</div><div class="stat-value" style="color:#f59e0b">$needDecrease</div></div>
<div class="stat" style="background:#d1fae5"><div>Keep Same</div><div class="stat-value" style="color:#059669">$keepSame</div></div>
</div>
<table><tr><th>Database</th><th>Current</th><th>Size</th><th>Avg%</th><th>Max%</th><th>Recommended</th><th>Action</th>$(if($AutoFix){"<th>Result</th>"}else{""})</tr>
"@

foreach ($db in ($allDatabases | Sort-Object ActionType,MaxDTU -Descending)) {
    $class = if($db.Changed){"changed"}else{switch($db.ActionType){"INCREASE"{"increase"}"DECREASE"{"decrease"}"KEEP"{"keep"}}}
    $html += "<tr class='$class'><td>$($db.Database)</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.SizeGB) GB</td><td>$($db.AvgDTU)%</td><td>$($db.MaxDTU)%</td><td>$($db.RecommendedTier) ($($db.RecommendedDTU))</td><td>$($db.Action)</td>"
    if($AutoFix){$html += "<td>$($db.Result)</td>"}
    $html += "</tr>"
}

$html += "</table>"

if($changedDatabases.Count -gt 0){
    $increased = $changedDatabases | Where-Object { $_.ActionType -eq "INCREASE" }
    $decreased = $changedDatabases | Where-Object { $_.ActionType -eq "DECREASE" }
    
    if($increased.Count -gt 0){
        $html += "<h2>Increased (Performance Fixes)</h2><table><tr><th>Database</th><th>Before</th><th>After</th></tr>"
        foreach($c in $increased){
            $html += "<tr class='increase'><td>$($c.Database)</td><td>$($c.CurrentTier)</td><td>$($c.RecommendedTier)</td></tr>"
        }
        $html += "</table>"
    }
    
    if($decreased.Count -gt 0){
        $html += "<h2>Decreased (Cost Savings)</h2><table><tr><th>Database</th><th>Before</th><th>After</th></tr>"
        foreach($c in $decreased){
            $html += "<tr class='decrease'><td>$($c.Database)</td><td>$($c.CurrentTier)</td><td>$($c.RecommendedTier)</td></tr>"
        }
        $html += "</table>"
    }
}

$html += "</div></body></html>"

$htmlPath = Join-Path $ReportPath "DTU_Final_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report: $htmlPath" -ForegroundColor Cyan
