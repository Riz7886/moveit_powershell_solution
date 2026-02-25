# SQL DTU Weekly Optimizer
# Maintains optimal performance and cost for all databases
# Priority: Production databases first, only if needed
# Author: Syed Rizvi

param([switch]$AutoFix)

$LogPath = "C:\Temp\SQL_DTU_Optimizer"
$ReportPath = Join-Path $LogPath "Reports"
$ChangeHistoryFile = Join-Path $LogPath "Change_History.csv"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

Write-Host "SQL DTU Weekly Optimizer" -ForegroundColor Cyan
Write-Host "Syed Rizvi - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
if ($AutoFix) { Write-Host "Mode: Automatic fixes enabled" -ForegroundColor Yellow }
else { Write-Host "Mode: Analysis only" -ForegroundColor Green }
Write-Host ""

$modules = @('Az.Accounts','Az.Sql','Az.Monitor')
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) { 
        Write-Host "Installing $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
    }
    Import-Module $module -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

$changeHistory = @()
if (Test-Path $ChangeHistoryFile) {
    $changeHistory = Import-Csv $ChangeHistoryFile
}

function Test-RecentlyChanged {
    param($DatabaseName)
    $recent = $changeHistory | Where-Object { 
        $_.Database -eq $DatabaseName -and 
        (try { ([DateTime]$_.ChangeDate) -gt (Get-Date).AddHours(-48) } catch { $false })
    }
    return ($recent.Count -gt 0)
}

function Get-OptimalDTU {
    param($CurrentDTU, $MaxPercent, $AvgPercent, $IsProd)
    if ($MaxPercent -eq 0 -or $AvgPercent -eq 0) { return $CurrentDTU }
    $actualUsed = ($CurrentDTU * $MaxPercent) / 100
    $target = if ($IsProd) { 0.50 } else { 0.60 }
    $needed = [math]::Ceiling($actualUsed / $target)
    
    if ($needed -le 10) { return 10 }
    elseif ($needed -le 20) { return 20 }
    elseif ($needed -le 50) { return 50 }
    elseif ($needed -le 100) { return 100 }
    elseif ($needed -le 200) { return 200 }
    elseif ($needed -le 400) { return 400 }
    elseif ($needed -le 800) { return 800 }
    elseif ($needed -le 1600) { return 1600 }
    else { return 3000 }
}

function Get-TierName {
    param($DTU)
    switch ($DTU) {
        10 { return "S0" }; 20 { return "S1" }; 50 { return "S2" }
        100 { return "S3" }; 200 { return "S4" }; 400 { return "S6" }
        800 { return "S7" }; 1600 { return "S9" }; 3000 { return "S12" }
        default { return "S0" }
    }
}

function Get-MonthlyCost {
    param($DTU)
    switch ($DTU) {
        10 { return 15 }; 20 { return 30 }; 50 { return 75 }
        100 { return 150 }; 200 { return 300 }; 400 { return 600 }
        800 { return 1200 }; 1600 { return 2400 }; 3000 { return 4500 }
        default { return 15 }
    }
}

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { 
    $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant 
}

$allDatabases = @()
$changesSaved = @()
$totalScanned = 0
$totalCurrentCost = 0
$totalOptimalCost = 0

Write-Host "Phase 1: Analyzing all databases..." -ForegroundColor Cyan
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
            $currentSizeGB = [math]::Round($db.MaxSizeBytes / 1GB, 2)
            
            $currentDTU = switch -Regex ($currentTier) {
                'S0' { 10 }; 'S1' { 20 }; 'S2' { 50 }; 'S3' { 100 }
                'S4' { 200 }; 'S6' { 400 }; 'S7' { 800 }
                'S9' { 1600 }; 'S12' { 3000 }; 'Standard' { 10 }
                default { 10 }
            }
            
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
            
            $optimalDTU = Get-OptimalDTU -CurrentDTU $currentDTU -MaxPercent $maxDTU -AvgPercent $avgDTU -IsProd $isProd
            $optimalTier = Get-TierName -DTU $optimalDTU
            $projectedUtil = if ($optimalDTU -gt 0) { [math]::Round((($currentDTU * $maxDTU) / $optimalDTU), 2) } else { 0 }
            
            $urgency = "Normal"
            $action = "Keep"
            
            if ($maxDTU -gt 90) { $urgency = "Critical"; $action = "Increase" }
            elseif ($maxDTU -gt 80) { $urgency = "High"; $action = "Increase" }
            elseif ($maxDTU -gt 70) { $urgency = "Medium"; $action = "Increase" }
            elseif ($avgDTU -gt 65) { $urgency = "Medium"; $action = "Increase" }
            elseif ($maxDTU -lt 30 -and $avgDTU -lt 20 -and $currentDTU -gt 10) { $action = "Decrease" }
            
            $currentCost = Get-MonthlyCost -DTU $currentDTU
            $optimalCost = Get-MonthlyCost -DTU $optimalDTU
            
            $totalCurrentCost += $currentCost
            $totalOptimalCost += $optimalCost
            
            $canChange = !(Test-RecentlyChanged -DatabaseName $db.DatabaseName)
            $needsChange = ($optimalDTU -ne $currentDTU -and $canChange)
            
            $dbInfo = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                IsProd = $isProd
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                SizeGB = $currentSizeGB
                MaxPercent = $maxDTU
                AvgPercent = $avgDTU
                OptimalTier = $optimalTier
                OptimalDTU = $optimalDTU
                ProjectedUtil = $projectedUtil
                Action = $action
                Urgency = $urgency
                CurrentCost = $currentCost
                OptimalCost = $optimalCost
                CanChange = $canChange
                NeedsChange = $needsChange
                MaxSizeBytes = $db.MaxSizeBytes
            }
            
            $allDatabases += $dbInfo
        }
    }
}

$prodNeedingFix = $allDatabases | Where-Object { $_.IsProd -and $_.NeedsChange }
$nonProdNeedingFix = $allDatabases | Where-Object { !$_.IsProd -and $_.NeedsChange }

Write-Host ""
Write-Host "Analysis Complete:" -ForegroundColor Green
Write-Host "  Total: $totalScanned databases" -ForegroundColor White
Write-Host "  Production: $($allDatabases | Where-Object {$_.IsProd} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red
Write-Host "  Production needing fix: $($prodNeedingFix.Count)" -ForegroundColor Yellow
Write-Host "  Non-production needing fix: $($nonProdNeedingFix.Count)" -ForegroundColor Yellow
Write-Host ""

if ($AutoFix) {
    if ($prodNeedingFix.Count -gt 0) {
        Write-Host "Phase 2: Fixing PRODUCTION databases..." -ForegroundColor Red
        Write-Host ""
        
        foreach ($db in ($prodNeedingFix | Sort-Object MaxPercent -Descending)) {
            if ($db.Action -eq "Decrease" -and $db.SizeGB -gt 250) { continue }
            
            Write-Host "  PROD: $($db.Database) - $($db.CurrentTier) -> $($db.OptimalTier)" -ForegroundColor Yellow
            
            try {
                Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup `
                                -ServerName $db.Server `
                                -DatabaseName $db.Database `
                                -Edition "Standard" `
                                -RequestedServiceObjectiveName $db.OptimalTier `
                                -MaxSizeBytes ([long]$db.MaxSizeBytes) `
                                -ErrorAction Stop | Out-Null
                
                Write-Host "    SUCCESS" -ForegroundColor Green
                
                $changeLog = [PSCustomObject]@{
                    ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Database = $db.Database
                    Server = $db.Server
                    FromTier = $db.CurrentTier
                    ToTier = $db.OptimalTier
                    FromDTU = $db.CurrentDTU
                    ToDTU = $db.OptimalDTU
                    MaxUsage = $db.MaxPercent
                    AvgUsage = $db.AvgPercent
                    IsProd = "YES"
                }
                $changesSaved += $changeLog
            } catch {
                Write-Host "    FAILED" -ForegroundColor Red
            }
        }
    }
    
    if ($nonProdNeedingFix.Count -gt 0) {
        Write-Host ""
        Write-Host "Phase 3: Fixing non-production databases..." -ForegroundColor Green
        Write-Host ""
        
        foreach ($db in ($nonProdNeedingFix | Sort-Object MaxPercent -Descending)) {
            if ($db.Action -eq "Decrease" -and $db.SizeGB -gt 250) { continue }
            
            Write-Host "  $($db.Database) - $($db.CurrentTier) -> $($db.OptimalTier)" -ForegroundColor Yellow
            
            try {
                Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup `
                                -ServerName $db.Server `
                                -DatabaseName $db.Database `
                                -Edition "Standard" `
                                -RequestedServiceObjectiveName $db.OptimalTier `
                                -MaxSizeBytes ([long]$db.MaxSizeBytes) `
                                -ErrorAction Stop | Out-Null
                
                Write-Host "    SUCCESS" -ForegroundColor Green
                
                $changeLog = [PSCustomObject]@{
                    ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Database = $db.Database
                    Server = $db.Server
                    FromTier = $db.CurrentTier
                    ToTier = $db.OptimalTier
                    FromDTU = $db.CurrentDTU
                    ToDTU = $db.OptimalDTU
                    MaxUsage = $db.MaxPercent
                    AvgUsage = $db.AvgPercent
                    IsProd = "NO"
                }
                $changesSaved += $changeLog
            } catch {
                Write-Host "    FAILED" -ForegroundColor Red
            }
        }
    }
    
    if ($changesSaved.Count -gt 0) {
        $changesSaved | Export-Csv -Path $ChangeHistoryFile -NoTypeInformation -Append
    }
}

$changesApplied = $changesSaved
$critical = ($allDatabases | Where-Object { $_.Urgency -eq "Critical" }).Count
$high = ($allDatabases | Where-Object { $_.Urgency -eq "High" }).Count
$needIncrease = ($allDatabases | Where-Object { $_.Action -eq "Increase" }).Count
$needDecrease = ($allDatabases | Where-Object { $_.Action -eq "Decrease" }).Count
$prodCount = ($allDatabases | Where-Object { $_.IsProd }).Count
$savings = [math]::Round($totalCurrentCost - $totalOptimalCost, 0)

$html = @"
<!DOCTYPE html>
<html>
<head>
<style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1800px;margin:0 auto;background:white;padding:40px}
h1{color:#1e40af;border-bottom:3px solid #1e40af;padding-bottom:10px}
h2{color:#1e40af;margin-top:30px}
.summary{display:grid;grid-template-columns:repeat(5,1fr);gap:20px;margin:30px 0}
.stat{padding:20px;border-radius:8px;text-align:center}
.stat-label{font-size:12px;color:#64748b;font-weight:600}
.stat-value{font-size:36px;font-weight:bold;margin-top:8px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#1e40af;color:white;padding:10px;text-align:left}
td{padding:8px;border-bottom:1px solid #e5e7eb}
tr:hover{background:#f8fafc}
.critical{background:#fee2e2}
.high{background:#fef3c7}
.prod{font-weight:bold;color:#dc2626}
</style>
</head>
<body>
<div class="container">

<h1>Weekly SQL DTU Report</h1>
<p><strong>Week Ending:</strong> $(Get-Date -Format 'yyyy-MM-dd')</p>
<p><strong>For:</strong> Tony Schlak</p>
<p><strong>By:</strong> Syed Rizvi</p>

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
<div class="stat" style="background:#dcfce7">
<div class="stat-label">Potential Savings</div>
<div class="stat-value" style="color:#059669">$savings</div>
</div>
</div>

<h2>Summary</h2>
<p>Current monthly cost: $([math]::Round($totalCurrentCost,0)) USD</p>
<p>Optimal monthly cost: $([math]::Round($totalOptimalCost,0)) USD</p>
<p>Critical databases: $critical</p>
<p>High priority: $high</p>
<p>Changes applied this week: $($changesApplied.Count)</p>

<p><strong>Sweet Spot Strategy:</strong> Target 50-60% DTU utilization</p>
<p>Production databases: 50% target (maximum safety)</p>
<p>Non-production: 60% target (efficient use)</p>

"@

if ($critical -gt 0 -or $high -gt 0) {
$html += @"
<h2>Urgent Attention Required</h2>
<table>
<tr><th>Database</th><th>Type</th><th>Current</th><th>Max %</th><th>Optimal</th><th>Urgency</th></tr>
"@
foreach($db in ($allDatabases | Where-Object {$_.Urgency -eq "Critical" -or $_.Urgency -eq "High"} | Sort-Object MaxPercent -Descending)){
$class = if($db.Urgency -eq "Critical"){"critical"}else{"high"}
$type = if($db.IsProd){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
$html += "<tr class='$class'><td>$($db.Database)</td><td>$type</td><td>$($db.CurrentTier)</td><td>$($db.MaxPercent)%</td><td>$($db.OptimalTier)</td><td>$($db.Urgency)</td></tr>"
}
$html += "</table>"
}

if ($changesApplied.Count -gt 0) {
$html += @"
<h2>Changes Applied This Week</h2>
<table>
<tr><th>Database</th><th>Type</th><th>Before</th><th>After</th><th>Projected %</th></tr>
"@
foreach($c in ($changesApplied | Sort-Object {if($_.IsProd -eq "YES"){0}else{1}})){
$type = if($c.IsProd -eq "YES"){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
$proj = ($allDatabases | Where-Object {$_.Database -eq $c.Database}).ProjectedUtil
$html += "<tr><td>$($c.Database)</td><td>$type</td><td>$($c.FromTier)</td><td>$($c.ToTier)</td><td>$proj%</td></tr>"
}
$html += "</table>"
}

$html += @"
<h2>All Databases</h2>
<table>
<tr><th>Database</th><th>Type</th><th>Current</th><th>Max %</th><th>Avg %</th><th>Optimal</th><th>Action</th></tr>
"@

foreach($db in ($allDatabases | Sort-Object {if($_.IsProd){0}else{1}}, MaxPercent -Descending)){
$type = if($db.IsProd){"<span class='prod'>PROD</span>"}else{"Non-Prod"}
$html += "<tr><td>$($db.Database)</td><td>$type</td><td>$($db.CurrentTier)</td><td>$($db.MaxPercent)%</td><td>$($db.AvgPercent)%</td><td>$($db.OptimalTier)</td><td>$($db.Action)</td></tr>"
}

$html += @"
</table>

<p style="margin-top:30px;padding-top:20px;border-top:2px solid #e5e7eb;color:#64748b">
Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
Analysis period: 7 days<br>
Syed Rizvi
</p>

</div>
</body>
</html>
"@

$htmlPath = Join-Path $ReportPath "Weekly_Report_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8

try {
    $emailBody = @"
Tony,

Weekly SQL DTU optimization report.

Summary:
Total databases: $totalScanned
Production: $prodCount
Critical issues: $critical
High priority: $high
Need increase: $needIncrease
Changes applied: $($changesApplied.Count)

Current cost: $([math]::Round($totalCurrentCost,0)) USD/month
Optimal cost: $([math]::Round($totalOptimalCost,0)) USD/month
Potential savings: $savings USD/month

Sweet Spot: 50-60% utilization
Production: 50% target (fixed first)
Non-production: 60% target

Detailed report attached.

Syed Rizvi
"@

    Send-MailMessage -To "tony.schlak@pyxhealth.com" -From "srizvi@pyxhealth.com" `
                    -Subject "Weekly SQL DTU Report - $(Get-Date -Format 'yyyy-MM-dd')" `
                    -Body $emailBody `
                    -Attachments $htmlPath `
                    -SmtpServer "smtp.office365.com" `
                    -Port 587 `
                    -UseSsl `
                    -ErrorAction Stop
    
    Write-Host "Email sent to Tony" -ForegroundColor Green
} catch {
    Write-Host "Email not configured - report saved locally" -ForegroundColor Yellow
}

Start-Process $htmlPath

Write-Host ""
Write-Host "Complete" -ForegroundColor Green
Write-Host "Scanned: $totalScanned databases" -ForegroundColor White
Write-Host "Production fixed: $($changesSaved | Where-Object {$_.IsProd -eq 'YES'} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red
Write-Host "Non-production fixed: $($changesSaved | Where-Object {$_.IsProd -eq 'NO'} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Green
Write-Host "Report: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Syed Rizvi" -ForegroundColor White
