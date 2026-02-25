# SQL DTU Optimizer - Emergency Fix with Full HTML Report
# Scans all 170 databases, fixes PROD FIRST (only if needed), generates complete HTML report
# Author: Syed Rizvi

param([switch]$DryRun)

$ErrorActionPreference = "SilentlyContinue"
$LogPath = "C:\Temp\SQL_DTU_Optimizer"
$ReportPath = Join-Path $LogPath "Reports"
if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

$ChangeHistoryFile = Join-Path $LogPath "Change_History.csv"
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$HtmlReport = Join-Path $ReportPath "SQL_DTU_Fix_$timestamp.html"

Write-Host "SQL DTU Optimizer - Emergency Fix" -ForegroundColor Cyan
Write-Host "Syed Rizvi - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - No changes will be made" -ForegroundColor Yellow
    Write-Host ""
}

@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Write-Host "Installing $_..." -ForegroundColor Yellow
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
    }
    Import-Module $_ -ErrorAction Stop
}

$ctx = Get-AzContext
if (!$ctx) { 
    Write-Host "Logging in to Azure..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
    $ctx = Get-AzContext 
}

Write-Host "Connected: $($ctx.Account.Id)" -ForegroundColor Green
Write-Host ""

function Get-OptimalDTU {
    param($CurrentDTU, $MaxPercent, $IsProd)
    if ($MaxPercent -eq 0) { return $CurrentDTU }
    $actualUsed = ($CurrentDTU * $MaxPercent) / 100
    $targetUtilization = if ($IsProd) { 0.50 } else { 0.60 }
    $needed = [math]::Ceiling($actualUsed / $targetUtilization)
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

function Get-DTUCost {
    param($DTU)
    switch ($DTU) {
        10 { return 15.00 }; 20 { return 30.00 }; 50 { return 75.00 }
        100 { return 150.00 }; 200 { return 300.00 }; 400 { return 600.00 }
        800 { return 1200.00 }; 1600 { return 2400.00 }; 3000 { return 4507.00 }
        default { return 15.00 }
    }
}

$protectedDatabases = @("sqldb-magellan-prod")

$changeHistory = @()
if (Test-Path $ChangeHistoryFile) { $changeHistory = Import-Csv $ChangeHistoryFile }

$recentChanges = $changeHistory | Where-Object {
    try { ([DateTime]$_.ChangeDate) -gt (Get-Date).AddHours(-48) } catch { $false }
}

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { 
    $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant 
}

Write-Host "Found $($subscriptions.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$allDatabases = @()
$totalScanned = 0

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 1: ANALYZING ALL DATABASES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($sub in $subscriptions) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { 
        Write-Host "  No SQL servers found" -ForegroundColor Gray
        continue 
    }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  [$totalScanned] $($db.DatabaseName)" -ForegroundColor Gray
            
            $isProd = $db.DatabaseName -like "*prod*" -or $db.DatabaseName -like "*prd*"
            $currentTier = $db.SkuName
            $isProtected = $protectedDatabases -contains $db.DatabaseName
            
            $currentDTU = switch -Regex ($currentTier) {
                'S0' { 10 }; 'S1' { 20 }; 'S2' { 50 }; 'S3' { 100 }
                'S4' { 200 }; 'S6' { 400 }; 'S7' { 800 }
                'S9' { 1600 }; 'S12' { 3000 }; 'Standard' { 10 }
                default { 10 }
            }
            
            $recentChange = $recentChanges | Where-Object { $_.Database -eq $db.DatabaseName }
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-14)
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 -AggregationType Average -ErrorAction SilentlyContinue
            
            $maxDTU = 0
            $avgDTU = 0
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                    $avgDTU = [math]::Round(($valid | Measure-Object -Property Average -Average).Average, 2)
                }
            }
            
            $optimalDTU = Get-OptimalDTU -CurrentDTU $currentDTU -MaxPercent $maxDTU -IsProd $isProd
            $needsChange = ($optimalDTU -ne $currentDTU -and $maxDTU -gt 65 -and !$recentChange -and !$isProtected)
            
            $currentCost = Get-DTUCost -DTU $currentDTU
            $optimalCost = Get-DTUCost -DTU $optimalDTU
            
            $allDatabases += [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                Subscription = $sub.Name
                IsProd = $isProd
                IsProtected = $isProtected
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                MaxPercent = $maxDTU
                AvgPercent = $avgDTU
                OptimalDTU = $optimalDTU
                OptimalTier = Get-TierName -DTU $optimalDTU
                NeedsChange = $needsChange
                RecentlyChanged = ($null -ne $recentChange)
                CurrentCost = $currentCost
                OptimalCost = $optimalCost
                MonthlySavings = ($currentCost - $optimalCost)
                MaxSizeBytes = $db.MaxSizeBytes
            }
        }
    }
}

$prodDatabases = $allDatabases | Where-Object { $_.IsProd }
$prodNeedingFix = $prodDatabases | Where-Object { $_.NeedsChange }
$nonProdNeedingFix = $allDatabases | Where-Object { !$_.IsProd -and $_.NeedsChange }

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Total databases: $totalScanned" -ForegroundColor White
Write-Host "  Production: $($prodDatabases.Count)" -ForegroundColor Red
Write-Host "  Production needing fix: $($prodNeedingFix.Count)" -ForegroundColor Yellow
Write-Host "  Non-production needing fix: $($nonProdNeedingFix.Count)" -ForegroundColor Yellow
Write-Host "  Protected (skipped): $($allDatabases | Where-Object {$_.IsProtected} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Cyan
Write-Host ""

$fixed = @()

if ($prodNeedingFix.Count -gt 0) {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "PHASE 2: FIXING PRODUCTION FIRST" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    
    foreach ($db in ($prodNeedingFix | Sort-Object MaxPercent -Descending)) {
        Write-Host "  PROD: $($db.Database) -> $($db.OptimalTier) (Max: $($db.MaxPercent)%)" -ForegroundColor Yellow
        
        if ($DryRun) {
            Write-Host "    DRY RUN" -ForegroundColor Cyan
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "YES"
                Status = "DRY_RUN"
            }
            continue
        }
        
        try {
            $subContext = $subscriptions | Where-Object { $_.Name -eq $db.Subscription }
            Set-AzContext -SubscriptionId $subContext.Id -TenantId $currentTenant | Out-Null
            Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup -ServerName $db.Server -DatabaseName $db.Database -Edition "Standard" -RequestedServiceObjectiveName $db.OptimalTier -MaxSizeBytes ([long]$db.MaxSizeBytes) | Out-Null
            Write-Host "    SUCCESS" -ForegroundColor Green
            
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "YES"
                Status = "SUCCESS"
            }
        } catch {
            Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "YES"
                Status = "FAILED"
            }
        }
    }
}

if ($nonProdNeedingFix.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "PHASE 3: FIXING NON-PRODUCTION" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    foreach ($db in ($nonProdNeedingFix | Sort-Object MaxPercent -Descending)) {
        Write-Host "  $($db.Database) -> $($db.OptimalTier) (Max: $($db.MaxPercent)%)" -ForegroundColor Yellow
        
        if ($DryRun) {
            Write-Host "    DRY RUN" -ForegroundColor Cyan
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "NO"
                Status = "DRY_RUN"
            }
            continue
        }
        
        try {
            $subContext = $subscriptions | Where-Object { $_.Name -eq $db.Subscription }
            Set-AzContext -SubscriptionId $subContext.Id -TenantId $currentTenant | Out-Null
            Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup -ServerName $db.Server -DatabaseName $db.Database -Edition "Standard" -RequestedServiceObjectiveName $db.OptimalTier -MaxSizeBytes ([long]$db.MaxSizeBytes) | Out-Null
            Write-Host "    SUCCESS" -ForegroundColor Green
            
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "NO"
                Status = "SUCCESS"
            }
        } catch {
            Write-Host "    FAILED" -ForegroundColor Red
            $fixed += [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                MaxUsage = $db.MaxPercent
                IsProd = "NO"
                Status = "FAILED"
            }
        }
    }
}

if ($fixed.Count -gt 0 -and !$DryRun) {
    $fixed | Export-Csv -Path $ChangeHistoryFile -NoTypeInformation -Append
}

Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Cyan

$totalSavings = ($allDatabases | Measure-Object -Property MonthlySavings -Sum).Sum

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>SQL DTU Report - $timestamp</title>
<style>
body{font-family:Arial;background:#f5f5f5;margin:0;padding:20px}
.container{max-width:1400px;margin:0 auto;background:white;padding:30px;border-radius:8px}
h1{color:#333;border-bottom:3px solid #0078d4;padding-bottom:10px}
h2{color:#0078d4;margin-top:30px}
table{width:100%;border-collapse:collapse;margin:20px 0;font-size:13px}
th{background:#0078d4;color:white;padding:12px 8px;text-align:left}
td{padding:10px 8px;border-bottom:1px solid #ddd}
tr:hover{background:#f8f9fa}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0}
.box{background:#667eea;color:white;padding:20px;border-radius:8px;text-align:center}
.box h3{margin:0;font-size:14px}
.box .val{font-size:32px;font-weight:bold;margin:10px 0}
</style>
</head>
<body>
<div class='container'>
<h1>SQL DTU Optimization Report</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Analyst: Syed Rizvi</p>

<div class='summary'>
<div class='box'><h3>Total Databases</h3><div class='val'>$totalScanned</div></div>
<div class='box'><h3>Changes Made</h3><div class='val'>$($fixed.Count)</div></div>
<div class='box'><h3>Monthly Savings</h3><div class='val'>`$$([math]::Round($totalSavings,2))</div></div>
</div>

<h2>All Databases</h2>
<table>
<tr><th>Database</th><th>Server</th><th>Type</th><th>Current</th><th>Max%</th><th>Optimal</th><th>Savings</th></tr>
"@

foreach ($db in ($allDatabases | Sort-Object {if($_.IsProd){0}else{1}}, MaxPercent -Descending)) {
    $type = if($db.IsProd){"PROD"}else{"NON-PROD"}
    $html += "<tr><td>$($db.Database)</td><td>$($db.Server)</td><td>$type</td><td>$($db.CurrentTier)</td><td>$($db.MaxPercent)%</td><td>$($db.OptimalTier)</td><td>`$$($db.MonthlySavings)</td></tr>"
}

$html += @"
</table>

<h2>Changes Made</h2>
<table>
<tr><th>Timestamp</th><th>Database</th><th>From</th><th>To</th><th>Status</th></tr>
"@

if ($fixed.Count -gt 0) {
    foreach ($c in $fixed) {
        $html += "<tr><td>$($c.ChangeDate)</td><td>$($c.Database)</td><td>$($c.FromTier)</td><td>$($c.ToTier)</td><td>$($c.Status)</td></tr>"
    }
} else {
    $html += "<tr><td colspan='5' style='text-align:center'>No changes made</td></tr>"
}

$html += @"
</table>
<p style='margin-top:30px;text-align:center;color:#666'>Syed Rizvi | $(Get-Date -Format 'yyyy-MM-dd')</p>
</div>
</body>
</html>
"@

$html | Out-File -FilePath $HtmlReport -Encoding UTF8

Write-Host "COMPLETE!" -ForegroundColor Green
Write-Host "Report: $HtmlReport" -ForegroundColor Cyan
Write-Host ""

Start-Process $HtmlReport
