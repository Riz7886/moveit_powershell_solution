# ==============================================================================
# COMPREHENSIVE SQL DTU ANALYZER & OPTIMIZER
# ==============================================================================
# Purpose: 
# 1. Analyze all 170 databases RIGHT NOW
# 2. Show what changed in last 24 hours
# 3. Calculate SWEET SPOT (50-60% utilization)
# 4. Auto-adjust UP and DOWN to save money + prevent downtime
# 5. Create detailed report for Tony
# ==============================================================================

param(
    [switch]$AutoFix,
    [switch]$ReportOnly
)

$LogPath = "C:\Temp\SQL_DTU_Reports"
$ChangeHistoryFile = Join-Path $LogPath "Change_History.csv"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SQL DTU COMPREHENSIVE ANALYZER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
if ($AutoFix) { Write-Host "MODE: AUTO-FIX (making changes)" -ForegroundColor Yellow }
else { Write-Host "MODE: ANALYSIS ONLY" -ForegroundColor Green }
Write-Host ""

@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue 
    }
    Import-Module $_ -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

# Load change history from last 24 hours
$changeHistory = @()
$last24HourChanges = @()
if (Test-Path $ChangeHistoryFile) {
    $allHistory = Import-Csv $ChangeHistoryFile
    $yesterday = (Get-Date).AddHours(-24)
    $last24HourChanges = $allHistory | Where-Object { 
        try {
            ([DateTime]$_.ChangeDate) -gt $yesterday
        } catch {
            $false
        }
    }
    $changeHistory = $allHistory
}

Write-Host "Found $($last24HourChanges.Count) changes in last 24 hours" -ForegroundColor Yellow
Write-Host ""

function Get-SweetSpotDTU {
    param($CurrentDTU, $MaxUsagePercent, $AvgUsagePercent)
    
    # Target: 50-60% utilization (sweet spot)
    # Too low = waste money
    # Too high = risk downtime
    
    if ($MaxUsagePercent -eq 0 -or $AvgUsagePercent -eq 0) { 
        return $CurrentDTU 
    }
    
    # Calculate actual DTU being used
    $actualUsed = ($CurrentDTU * $MaxUsagePercent) / 100
    
    # Sweet spot: aim for 55% utilization
    $targetUtilization = 0.55
    $idealDTU = [math]::Ceiling($actualUsed / $targetUtilization)
    
    # Map to actual tiers
    if ($idealDTU -le 10) { return 10 }
    elseif ($idealDTU -le 20) { return 20 }
    elseif ($idealDTU -le 50) { return 50 }
    elseif ($idealDTU -le 100) { return 100 }
    elseif ($idealDTU -le 200) { return 200 }
    elseif ($idealDTU -le 400) { return 400 }
    elseif ($idealDTU -le 800) { return 800 }
    elseif ($idealDTU -le 1600) { return 1600 }
    else { return 3000 }
}

function Get-TierName {
    param($DTU)
    switch ($DTU) {
        10 { return "S0" }
        20 { return "S1" }
        50 { return "S2" }
        100 { return "S3" }
        200 { return "S4" }
        400 { return "S6" }
        800 { return "S7" }
        1600 { return "S9" }
        3000 { return "S12" }
        default { return "S0" }
    }
}

function Get-MonthlyCost {
    param($DTU)
    # Approximate monthly costs (USD)
    switch ($DTU) {
        10 { return 15 }
        20 { return 30 }
        50 { return 75 }
        100 { return 150 }
        200 { return 300 }
        400 { return 600 }
        800 { return 1200 }
        1600 { return 2400 }
        3000 { return 4500 }
        default { return 15 }
    }
}

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { 
    $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant 
}

$allDatabases = @()
$changesApplied = @()
$changesSaved = @()
$totalScanned = 0
$totalCurrentCost = 0
$totalRecommendedCost = 0
$totalPotentialSavings = 0

Write-Host "Analyzing all databases (7-day usage data)..." -ForegroundColor Cyan
Write-Host ""

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { continue }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | 
               Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  [$totalScanned] $($db.DatabaseName)" -ForegroundColor Gray
            
            $isProd = $db.DatabaseName -like "*prod*" -or $db.DatabaseName -like "*prd*"
            $currentTier = $db.SkuName
            $currentSizeBytes = $db.MaxSizeBytes
            $currentSizeGB = [math]::Round($currentSizeBytes / 1GB, 2)
            
            $currentDTU = switch -Regex ($currentTier) {
                'S0' { 10 }
                'S1' { 20 }
                'S2' { 50 }
                'S3' { 100 }
                'S4' { 200 }
                'S6' { 400 }
                'S7' { 800 }
                'S9' { 1600 }
                'S12' { 3000 }
                'Standard' { 10 }
                default { 10 }
            }
            
            # Get 7-day metrics
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-7)
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" `
                      -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 `
                      -AggregationType Average -ErrorAction SilentlyContinue
            
            $avgDTU = 0
            $maxDTU = 0
            
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $avgDTU = [math]::Round(($valid | Measure-Object -Property Average -Average).Average, 2)
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                }
            }
            
            # Calculate SWEET SPOT
            $sweetSpotDTU = Get-SweetSpotDTU -CurrentDTU $currentDTU -MaxUsagePercent $maxDTU -AvgUsagePercent $avgDTU
            $sweetSpotTier = Get-TierName -DTU $sweetSpotDTU
            
            # Calculate projected utilization at sweet spot
            $projectedUtilization = if ($sweetSpotDTU -gt 0) {
                [math]::Round((($currentDTU * $maxDTU) / $sweetSpotDTU), 2)
            } else { 0 }
            
            # Determine action
            $action = "KEEP"
            $reason = "Already optimal (50-60% range)"
            $urgency = "Normal"
            
            if ($maxDTU -gt 90) {
                $action = "INCREASE"
                $reason = "CRITICAL: Max $maxDTU% - risk of downtime"
                $urgency = "CRITICAL"
            }
            elseif ($maxDTU -gt 80) {
                $action = "INCREASE"
                $reason = "HIGH: Max $maxDTU% - performance issues likely"
                $urgency = "HIGH"
            }
            elseif ($avgDTU -gt 70) {
                $action = "INCREASE"
                $reason = "Sustained high: Avg $avgDTU%"
                $urgency = "MEDIUM"
            }
            elseif ($maxDTU -lt 30 -and $avgDTU -lt 20 -and $currentDTU -gt 10) {
                $action = "DECREASE"
                $reason = "Underutilized: Max $maxDTU%, Avg $avgDTU% - wasting money"
                $urgency = "LOW"
            }
            
            # Cost calculations
            $currentCost = Get-MonthlyCost -DTU $currentDTU
            $recommendedCost = Get-MonthlyCost -DTU $sweetSpotDTU
            $monthlySavings = $currentCost - $recommendedCost
            
            $totalCurrentCost += $currentCost
            $totalRecommendedCost += $recommendedCost
            if ($monthlySavings -gt 0) {
                $totalPotentialSavings += $monthlySavings
            }
            
            # Check if changed in last 24 hours
            $recentChange = $last24HourChanges | Where-Object { $_.Database -eq $db.DatabaseName } | Select-Object -First 1
            
            $dbInfo = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                IsProd = $isProd
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                SizeGB = $currentSizeGB
                AvgUsagePercent = $avgDTU
                MaxUsagePercent = $maxDTU
                SweetSpotTier = $sweetSpotTier
                SweetSpotDTU = $sweetSpotDTU
                ProjectedUtilization = $projectedUtilization
                Action = $action
                Urgency = $urgency
                Reason = $reason
                CurrentMonthlyCost = $currentCost
                RecommendedMonthlyCost = $recommendedCost
                MonthlySavings = $monthlySavings
                ChangedLast24h = ($null -ne $recentChange)
                Last24hChange = if ($recentChange) { "$($recentChange.FromTier) -> $($recentChange.ToTier)" } else { "" }
                ServerObject = $server
                DatabaseObject = $db
            }
            
            $allDatabases += $dbInfo
            
            # Auto-fix if requested
            if ($AutoFix -and $sweetSpotDTU -ne $currentDTU -and !$dbInfo.ChangedLast24h) {
                if ($currentSizeGB -le 250 -or $sweetSpotDTU -gt $currentDTU) {
                    try {
                        Set-AzSqlDatabase -ResourceGroupName $server.ResourceGroupName `
                                        -ServerName $server.ServerName `
                                        -DatabaseName $db.DatabaseName `
                                        -Edition "Standard" `
                                        -RequestedServiceObjectiveName $sweetSpotTier `
                                        -MaxSizeBytes ([long]$currentSizeBytes) `
                                        -ErrorAction Stop | Out-Null
                        
                        $dbInfo | Add-Member -NotePropertyName "Changed" -NotePropertyValue $true -Force
                        $dbInfo | Add-Member -NotePropertyName "Result" -NotePropertyValue "SUCCESS" -Force
                        $changesApplied += $dbInfo
                        
                        $changeLog = [PSCustomObject]@{
                            ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                            Database = $db.DatabaseName
                            Server = $server.ServerName
                            FromTier = $currentTier
                            ToTier = $sweetSpotTier
                            FromDTU = $currentDTU
                            ToDTU = $sweetSpotDTU
                            Action = $action
                            Reason = $reason
                            IsProd = if($isProd){"YES"}else{"NO"}
                        }
                        $changesSaved += $changeLog
                        
                        Write-Host "    CHANGED: $currentTier -> $sweetSpotTier" -ForegroundColor Green
                    } catch {
                        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }
}

if ($changesSaved.Count -gt 0 -and $AutoFix) {
    $changesSaved | Export-Csv -Path $ChangeHistoryFile -NoTypeInformation -Append
}

# Calculate summary statistics
$critical = ($allDatabases | Where-Object { $_.Urgency -eq "CRITICAL" }).Count
$high = ($allDatabases | Where-Object { $_.Urgency -eq "HIGH" }).Count
$needIncrease = ($allDatabases | Where-Object { $_.Action -eq "INCREASE" }).Count
$needDecrease = ($allDatabases | Where-Object { $_.Action -eq "DECREASE" }).Count
$optimal = ($allDatabases | Where-Object { $_.Action -eq "KEEP" }).Count
$prodCount = ($allDatabases | Where-Object { $_.IsProd }).Count
$changed24h = ($allDatabases | Where-Object { $_.ChangedLast24h }).Count

# CREATE COMPREHENSIVE HTML REPORT FOR TONY
$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:0;padding:20px;background:#f5f5f5}
.container{max-width:2000px;margin:0 auto;background:white;padding:40px;box-shadow:0 4px 20px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:4px solid #1e40af;padding-bottom:15px;margin-bottom:30px}
h2{color:#1e40af;margin-top:40px;border-bottom:2px solid #e5e7eb;padding-bottom:10px}
.alert{background:#fee2e2;border-left:5px solid #dc2626;padding:20px;margin:20px 0;border-radius:5px}
.info{background:#f0f9ff;border-left:5px solid #3b82f6;padding:20px;margin:20px 0;border-radius:5px}
.success{background:#d1fae5;border-left:5px solid #059669;padding:20px;margin:20px 0;border-radius:5px}
.summary{display:grid;grid-template-columns:repeat(6,1fr);gap:20px;margin:30px 0}
.stat{padding:25px;border-radius:10px;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
.stat-label{font-size:12px;color:#64748b;font-weight:600;text-transform:uppercase}
.stat-value{font-size:42px;font-weight:bold;margin-top:10px}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#1e40af;color:white;padding:12px;text-align:left;position:sticky;top:0}
td{padding:10px;border-bottom:1px solid #e5e7eb}
tr:hover{background:#f8fafc}
.critical{background:#fee2e2;border-left:4px solid #dc2626}
.high{background:#fef3c7;border-left:4px solid #f59e0b}
.increase{background:#fef3c7}
.decrease{background:#d1fae5}
.prod{font-weight:bold;color:#dc2626}
.changed{background:#dbeafe;border-left:4px solid #3b82f6}
</style></head><body><div class="container">

<h1>Comprehensive SQL DTU Analysis Report</h1>

<div class="info">
<strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Analysis Period:</strong> Past 7 days of usage data<br>
<strong>Total Databases Analyzed:</strong> $totalScanned<br>
<strong>Prepared For:</strong> Tony Schlak<br>
<strong>Prepared By:</strong> Syed Rizvi
</div>

$(if($critical -gt 0 -or $high -gt 0){
"<div class='alert'>
<h3 style='margin-top:0;color:#dc2626'>⚠️ URGENT ATTENTION REQUIRED</h3>
<p><strong>CRITICAL Issues:</strong> $critical database(s) at risk of downtime (>90% DTU)</p>
<p><strong>HIGH Priority:</strong> $high database(s) experiencing performance issues (>80% DTU)</p>
<p><strong>Action Required:</strong> These databases should be scaled up immediately to prevent service disruption and potential revenue loss.</p>
</div>"
}else{""})

<h2>Executive Summary</h2>

<div class="summary">
<div class="stat" style="background:#e0e7ff">
<div class="stat-label">Total Databases</div>
<div class="stat-value" style="color:#1e40af">$totalScanned</div>
</div>
<div class="stat" style="background:#fee2e2">
<div class="stat-label">Production</div>
<div class="stat-value" style="color:#dc2626">$prodCount</div>
</div>
<div class="stat" style="background:#fef3c7">
<div class="stat-label">Need Increase</div>
<div class="stat-value" style="color:#f59e0b">$needIncrease</div>
</div>
<div class="stat" style="background:#d1fae5">
<div class="stat-label">Can Decrease</div>
<div class="stat-value" style="color:#059669">$needDecrease</div>
</div>
<div class="stat" style="background:#f0fdf4">
<div class="stat-label">Already Optimal</div>
<div class="stat-value" style="color:#059669">$optimal</div>
</div>
<div class="stat" style="background:#dbeafe">
<div class="stat-label">Changed 24h</div>
<div class="stat-value" style="color:#3b82f6">$changed24h</div>
</div>
</div>

<h2>Cost Analysis</h2>

<div class="summary" style="grid-template-columns:repeat(3,1fr)">
<div class="stat" style="background:#fef3c7">
<div class="stat-label">Current Monthly Cost</div>
<div class="stat-value" style="color:#f59e0b">$([math]::Round($totalCurrentCost, 0))</div>
<div style="font-size:12px;margin-top:10px;color:#64748b">USD/month</div>
</div>
<div class="stat" style="background:#d1fae5">
<div class="stat-label">Recommended Cost</div>
<div class="stat-value" style="color:#059669">$([math]::Round($totalRecommendedCost, 0))</div>
<div style="font-size:12px;margin-top:10px;color:#64748b">USD/month</div>
</div>
<div class="stat" style="background:#dcfce7">
<div class="stat-label">Potential Savings</div>
<div class="stat-value" style="color:#059669">$([math]::Round($totalPotentialSavings, 0))</div>
<div style="font-size:12px;margin-top:10px;color:#64748b">USD/month</div>
</div>
</div>

<div class="success">
<h3 style='margin-top:0;color:#059669'>💡 Sweet Spot Strategy</h3>
<p><strong>Target:</strong> 50-60% DTU utilization - the perfect balance between performance and cost</p>
<p><strong>Benefits:</strong></p>
<ul style="margin:10px 0">
<li>Enough headroom to handle traffic spikes (prevents downtime)</li>
<li>Not over-provisioned (saves money)</li>
<li>Optimal performance for users</li>
<li>Estimated savings: $([math]::Round($totalPotentialSavings, 0)) USD/month</li>
</ul>
</div>

$(if($changed24h -gt 0){
"<h2>Changes Made in Last 24 Hours ($changed24h databases)</h2>
<table>
<tr><th>Database</th><th>Type</th><th>Change</th><th>When</th></tr>"
$last24hHtml = ""
foreach($change in $last24HourChanges | Sort-Object {[DateTime]$_.ChangeDate} -Descending){
$isProdLabel = if($change.IsProd -eq "YES"){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
$last24hHtml += "<tr class='changed'><td>$($change.Database)</td><td>$isProdLabel</td><td>$($change.FromTier) ($($change.FromDTU)) → $($change.ToTier) ($($change.ToDTU))</td><td>$($change.ChangeDate)</td></tr>"
}
$html += $last24hHtml
$html += "</table>"
}else{
"<h2>Changes Made in Last 24 Hours</h2>
<p>No changes made in the last 24 hours.</p>"
})

$(if($critical -gt 0 -or $high -gt 0){
"<h2>⚠️ URGENT: Databases Requiring Immediate Attention</h2>
<table>
<tr><th>Database</th><th>Type</th><th>Current</th><th>Max Usage</th><th>Avg Usage</th><th>Sweet Spot</th><th>Projected</th><th>Urgency</th><th>Reason</th></tr>"
$urgentHtml = ""
foreach($db in ($allDatabases | Where-Object {$_.Urgency -eq "CRITICAL" -or $_.Urgency -eq "HIGH"} | Sort-Object {if($_.Urgency -eq "CRITICAL"){0}else{1}}, MaxUsagePercent -Descending)){
$class = if($db.Urgency -eq "CRITICAL"){"critical"}else{"high"}
$isProdLabel = if($db.IsProd){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
$urgentHtml += "<tr class='$class'><td><strong>$($db.Database)</strong></td><td>$isProdLabel</td><td>$($db.CurrentTier) ($($db.CurrentDTU))</td><td>$($db.MaxUsagePercent)%</td><td>$($db.AvgUsagePercent)%</td><td>$($db.SweetSpotTier) ($($db.SweetSpotDTU))</td><td>$($db.ProjectedUtilization)%</td><td>$($db.Urgency)</td><td>$($db.Reason)</td></tr>"
}
$html += $urgentHtml
$html += "</table>"
})

<h2>Complete Database Analysis (All $totalScanned Databases)</h2>
<table>
<tr>
<th>Database</th>
<th>Type</th>
<th>Current Tier</th>
<th>Current DTU</th>
<th>Size GB</th>
<th>Avg %</th>
<th>Max %</th>
<th>Sweet Spot</th>
<th>Sweet DTU</th>
<th>Projected %</th>
<th>Action</th>
<th>Monthly $</th>
<th>Savings</th>
</tr>
"@

foreach($db in ($allDatabases | Sort-Object {if($_.IsProd){0}else{1}}, {if($_.Urgency -eq "CRITICAL"){0}elseif($_.Urgency -eq "HIGH"){1}else{2}}, MaxUsagePercent -Descending)){
    $class = ""
    if($db.Urgency -eq "CRITICAL"){ $class = "critical" }
    elseif($db.Urgency -eq "HIGH"){ $class = "high" }
    elseif($db.ChangedLast24h){ $class = "changed" }
    elseif($db.Action -eq "INCREASE"){ $class = "increase" }
    elseif($db.Action -eq "DECREASE"){ $class = "decrease" }
    
    $isProdLabel = if($db.IsProd){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
    $savingsDisplay = if($db.MonthlySavings -gt 0){"+$([math]::Round($db.MonthlySavings, 0))"}elseif($db.MonthlySavings -lt 0){"$([math]::Round($db.MonthlySavings, 0))"}else{"-"}
    
    $html += "<tr class='$class'>"
    $html += "<td><strong>$($db.Database)</strong></td>"
    $html += "<td>$isProdLabel</td>"
    $html += "<td>$($db.CurrentTier)</td>"
    $html += "<td>$($db.CurrentDTU)</td>"
    $html += "<td>$($db.SizeGB)</td>"
    $html += "<td>$($db.AvgUsagePercent)%</td>"
    $html += "<td>$($db.MaxUsagePercent)%</td>"
    $html += "<td>$($db.SweetSpotTier)</td>"
    $html += "<td>$($db.SweetSpotDTU)</td>"
    $html += "<td>$($db.ProjectedUtilization)%</td>"
    $html += "<td>$($db.Action)</td>"
    $html += "<td>$($db.CurrentMonthlyCost)</td>"
    $html += "<td>$savingsDisplay</td>"
    $html += "</tr>"
}

$html += @"
</table>

<h2>Recommendations</h2>

<div class="info">
<h3 style="margin-top:0">Immediate Actions:</h3>
<ol>
<li><strong>CRITICAL ($critical):</strong> Scale up immediately to prevent downtime</li>
<li><strong>HIGH ($high):</strong> Scale up within 24 hours to prevent performance degradation</li>
<li><strong>Decrease ($needDecrease):</strong> Scale down to save $([math]::Round($totalPotentialSavings, 0)) USD/month</li>
</ol>
</div>

<div class="success">
<h3 style="margin-top:0">Automation Options:</h3>
<p><strong>Option 1: Weekly Automatic Optimization</strong></p>
<ul>
<li>Script runs every Saturday at 6 AM</li>
<li>Auto-scales all databases to sweet spot (50-60% utilization)</li>
<li>Production databases prioritized</li>
<li>Estimated savings: $([math]::Round($totalPotentialSavings, 0)) USD/month</li>
</ul>
<p><strong>Option 2: Manual Review & Approve</strong></p>
<ul>
<li>Weekly report sent to Tony</li>
<li>Changes reviewed and approved manually</li>
<li>Applied after approval</li>
</ul>
</div>

<div style="margin-top:40px;padding-top:20px;border-top:2px solid #e5e7eb;color:#64748b;font-size:12px">
<p><strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
<p><strong>Analysis Period:</strong> 7 days of DTU consumption data</p>
<p><strong>Methodology:</strong> Sweet Spot calculation targets 50-60% utilization for optimal performance and cost</p>
</div>

</div></body></html>
"@

$htmlPath = Join-Path $LogPath "Comprehensive_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

# Console Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "  Total Databases: $totalScanned" -ForegroundColor White
Write-Host "  Production: $prodCount" -ForegroundColor Red
Write-Host "  CRITICAL (>90%): $critical" -ForegroundColor Red
Write-Host "  HIGH (>80%): $high" -ForegroundColor Yellow
Write-Host "  Need Increase: $needIncrease" -ForegroundColor Yellow
Write-Host "  Can Decrease: $needDecrease" -ForegroundColor Green
Write-Host "  Already Optimal: $optimal" -ForegroundColor Green
Write-Host "  Changed Last 24h: $changed24h" -ForegroundColor Cyan
Write-Host ""
Write-Host "COST ANALYSIS:" -ForegroundColor Cyan
Write-Host "  Current Monthly: $([math]::Round($totalCurrentCost, 0)) USD" -ForegroundColor White
Write-Host "  Recommended: $([math]::Round($totalRecommendedCost, 0)) USD" -ForegroundColor White
Write-Host "  Potential Savings: $([math]::Round($totalPotentialSavings, 0)) USD/month" -ForegroundColor Green
Write-Host ""
Write-Host "Report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""

if($AutoFix -and $changesApplied.Count -gt 0){
    Write-Host "CHANGES APPLIED: $($changesApplied.Count)" -ForegroundColor Green
} elseif(!$AutoFix){
    Write-Host "RUN WITH -AutoFix TO APPLY CHANGES" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "SEND TO TONY:" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
Write-Host "Subject: SQL DTU Analysis - Immediate Attention Required" -ForegroundColor White
Write-Host ""
Write-Host "Tony," -ForegroundColor White
Write-Host ""
if($critical -gt 0 -or $high -gt 0){
    Write-Host "URGENT: Found $critical CRITICAL and $high HIGH priority databases" -ForegroundColor Red
    Write-Host "These are at risk of downtime and need immediate attention." -ForegroundColor Red
    Write-Host ""
}
Write-Host "Complete analysis of all $totalScanned SQL databases:" -ForegroundColor White
Write-Host ""
Write-Host "FINDINGS:" -ForegroundColor White
Write-Host "  - $needIncrease databases need DTU increases (performance)" -ForegroundColor White
Write-Host "  - $needDecrease databases can be reduced (save money)" -ForegroundColor White
Write-Host "  - $optimal databases are already at sweet spot" -ForegroundColor White
Write-Host "  - $changed24h databases were changed in last 24 hours" -ForegroundColor White
Write-Host ""
Write-Host "COST IMPACT:" -ForegroundColor White
Write-Host "  - Current: $([math]::Round($totalCurrentCost, 0)) USD/month" -ForegroundColor White
Write-Host "  - Recommended: $([math]::Round($totalRecommendedCost, 0)) USD/month" -ForegroundColor White
Write-Host "  - Potential Savings: $([math]::Round($totalPotentialSavings, 0)) USD/month" -ForegroundColor Green
Write-Host ""
Write-Host "SWEET SPOT:" -ForegroundColor White
Write-Host "  Target: 50-60% DTU utilization" -ForegroundColor White
Write-Host "  Benefits: Optimal performance + Cost savings" -ForegroundColor White
Write-Host ""
Write-Host "Detailed report attached." -ForegroundColor White
Write-Host ""
Write-Host "Ready to implement changes with your approval." -ForegroundColor White
Write-Host ""
Write-Host "Syed" -ForegroundColor White
