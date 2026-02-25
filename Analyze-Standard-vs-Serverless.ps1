# SQL DATABASE COST OPTIMIZATION ANALYSIS
# Standard vs Serverless Recommendation
# READ-ONLY ANALYSIS - NO CHANGES MADE
# Author: Syed Rizvi
# Date: February 25, 2026

param(
    [switch]$ExportToCSV
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$ReportFile = "C:\Temp\SQL_Analysis_Standard_vs_Serverless_$timestamp.html"
$CSVFile = "C:\Temp\SQL_Analysis_$timestamp.csv"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "SQL DATABASE COST OPTIMIZATION ANALYSIS" -ForegroundColor Cyan
Write-Host "Standard Tier vs Serverless Comparison" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "READ-ONLY ANALYSIS - NO CHANGES WILL BE MADE" -ForegroundColor Yellow
Write-Host ""

# ==============================================================================
# METHODOLOGY
# ==============================================================================

Write-Host "METHODOLOGY:" -ForegroundColor Cyan
Write-Host "-------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. SERVERLESS CANDIDATES:" -ForegroundColor White
Write-Host "   - Low average DTU usage (<20%)" -ForegroundColor Gray
Write-Host "   - Intermittent/spiky usage patterns" -ForegroundColor Gray
Write-Host "   - Non-production databases" -ForegroundColor Gray
Write-Host "   - Inactive for extended periods" -ForegroundColor Gray
Write-Host ""
Write-Host "2. KEEP STANDARD TIER:" -ForegroundColor White
Write-Host "   - Consistent high usage (>50%)" -ForegroundColor Gray
Write-Host "   - Production databases with predictable load" -ForegroundColor Gray
Write-Host "   - Databases that spike for many hours daily" -ForegroundColor Gray
Write-Host ""
Write-Host "3. STANDARD TIER OPTIMIZATION:" -ForegroundColor White
Write-Host "   - Databases maxed out (>85%) → Upgrade" -ForegroundColor Gray
Write-Host "   - Databases with good headroom → Keep as-is" -ForegroundColor Gray
Write-Host ""

# ==============================================================================
# DTU TIERS AND SERVERLESS PRICING
# ==============================================================================

$dtuTiers = @(
    @{Name="S0"; DTU=10; MonthlyCost=15},
    @{Name="S1"; DTU=20; MonthlyCost=30},
    @{Name="S2"; DTU=50; MonthlyCost=75},
    @{Name="S3"; DTU=100; MonthlyCost=150},
    @{Name="S4"; DTU=200; MonthlyCost=300},
    @{Name="S6"; DTU=400; MonthlyCost=600},
    @{Name="S7"; DTU=800; MonthlyCost=1200},
    @{Name="S9"; DTU=1600; MonthlyCost=2400},
    @{Name="S12"; DTU=3000; MonthlyCost=4507}
)

# Serverless pricing (approximate)
# Compute: $0.000145/vCore/second when active
# Storage: $0.115/GB/month
# Auto-pause after inactivity

$serverlessBaseStorageCost = 0.115  # per GB per month
$serverlessComputeCostPerVCorePerSecond = 0.000145

Write-Host "Analyzing all databases..." -ForegroundColor Cyan
Write-Host ""

# Get all subscriptions
$subscriptions = Get-AzSubscription
$allAnalysis = @()
$serverlessCandidates = @()
$standardOptimizations = @()

$totalDatabases = 0
$totalScanned = 0

foreach ($sub in $subscriptions) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $sqlServers = Get-AzSqlServer
    
    foreach ($server in $sqlServers) {
        $databases = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName | 
            Where-Object { $_.DatabaseName -ne "master" -and $_.Edition -eq "Standard" }
        
        $totalDatabases += $databases.Count
        
        foreach ($db in $databases) {
            $totalScanned++
            Write-Host "  [$totalScanned/$totalDatabases] $($db.DatabaseName)" -ForegroundColor Gray
            
            # Get 14 days of metrics
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-14)
            
            try {
                $metrics = Get-AzMetric -ResourceId $db.ResourceId `
                    -MetricName "dtu_consumption_percent" `
                    -StartTime $startTime `
                    -EndTime $endTime `
                    -TimeGrain 01:00:00 `
                    -AggregationType Average `
                    -WarningAction SilentlyContinue
                
                $maxPercent = 0
                $avgPercent = 0
                $activeHours = 0
                $spikeCount = 0
                
                if ($metrics.Data.Count -gt 0) {
                    $validData = $metrics.Data | Where-Object { $_.Average -ne $null }
                    
                    if ($validData.Count -gt 0) {
                        $maxPercent = ($validData.Average | Measure-Object -Maximum).Maximum
                        $avgPercent = ($validData.Average | Measure-Object -Average).Average
                        
                        # Count hours with >10% activity
                        $activeHours = ($validData | Where-Object { $_.Average -gt 10 }).Count
                        
                        # Count significant spikes (>50% usage)
                        $spikeCount = ($validData | Where-Object { $_.Average -gt 50 }).Count
                    }
                }
                
                # Determine database type
                $isProd = $db.DatabaseName -like "*-prod"
                $dbType = if ($isProd) { "PROD" } else { "NON-PROD" }
                
                # Get current tier
                $currentTier = $dtuTiers | Where-Object { $_.Name -eq $db.CurrentServiceObjectiveName }
                
                if (!$currentTier) {
                    Write-Host "    ⚠️  Unknown tier: $($db.CurrentServiceObjectiveName)" -ForegroundColor Yellow
                    continue
                }
                
                # Calculate usage patterns
                $totalHours = 14 * 24  # 14 days
                $activityPercentage = ($activeHours / $totalHours) * 100
                
                # Determine recommendation
                $recommendation = ""
                $reasoning = ""
                $estimatedMonthlyCost = 0
                $potentialSavings = 0
                
                # SERVERLESS LOGIC
                if ($avgPercent -lt 20 -and $activityPercentage -lt 30 -and !$isProd) {
                    $recommendation = "SERVERLESS"
                    $reasoning = "Low average usage ($([math]::Round($avgPercent,1))%), active only $([math]::Round($activityPercentage,1))% of time. Serverless will auto-pause during inactivity."
                    
                    # Estimate serverless cost (rough approximation)
                    # Assume 1 vCore = ~50 DTU, charge only for active time
                    $vCores = [math]::Ceiling($currentTier.DTU / 50)
                    $activeSecondsPerMonth = ($activeHours / $totalHours) * 30 * 24 * 3600
                    $computeCost = $vCores * $activeSecondsPerMonth * $serverlessComputeCostPerVCorePerSecond
                    $storageCost = ($db.MaxSizeBytes / 1GB) * $serverlessBaseStorageCost
                    $estimatedMonthlyCost = $computeCost + $storageCost
                    $potentialSavings = $currentTier.MonthlyCost - $estimatedMonthlyCost
                    
                    $serverlessCandidates += [PSCustomObject]@{
                        Database = $db.DatabaseName
                        Server = $server.ServerName
                        Type = $dbType
                        CurrentTier = $currentTier.Name
                        CurrentCost = $currentTier.MonthlyCost
                        AvgDTU = [math]::Round($avgPercent, 1)
                        MaxDTU = [math]::Round($maxPercent, 1)
                        ActiveHours = $activeHours
                        ActivityPercent = [math]::Round($activityPercentage, 1)
                        EstimatedServerlessCost = [math]::Round($estimatedMonthlyCost, 2)
                        PotentialSavings = [math]::Round($potentialSavings, 2)
                        Reasoning = $reasoning
                    }
                }
                # KEEP STANDARD BUT OPTIMIZE
                elseif ($maxPercent -ge 85) {
                    $recommendation = "UPGRADE STANDARD TIER"
                    $reasoning = "Maxed out at $([math]::Round($maxPercent,1))% - needs higher tier for performance"
                    
                    # Calculate optimal tier
                    $actualDTUUsed = ($currentTier.DTU * $maxPercent) / 100
                    $targetUtilization = if ($isProd) { 0.55 } else { 0.65 }
                    $neededDTU = [math]::Ceiling($actualDTUUsed / $targetUtilization)
                    $optimalTier = $dtuTiers | Where-Object { $_.DTU -ge $neededDTU } | Select-Object -First 1
                    
                    if ($optimalTier -and $optimalTier.DTU -gt $currentTier.DTU) {
                        $standardOptimizations += [PSCustomObject]@{
                            Database = $db.DatabaseName
                            Server = $server.ServerName
                            Type = $dbType
                            CurrentTier = $currentTier.Name
                            CurrentCost = $currentTier.MonthlyCost
                            MaxDTU = [math]::Round($maxPercent, 1)
                            AvgDTU = [math]::Round($avgPercent, 1)
                            RecommendedTier = $optimalTier.Name
                            RecommendedCost = $optimalTier.MonthlyCost
                            CostIncrease = $optimalTier.MonthlyCost - $currentTier.MonthlyCost
                            Reasoning = $reasoning
                        }
                    }
                }
                # KEEP AS-IS
                else {
                    $recommendation = "KEEP CURRENT TIER"
                    $reasoning = "Good performance (Max: $([math]::Round($maxPercent,1))%, Avg: $([math]::Round($avgPercent,1))%) - no changes needed"
                }
                
                # Store all analysis
                $allAnalysis += [PSCustomObject]@{
                    Database = $db.DatabaseName
                    Server = $server.ServerName
                    ResourceGroup = $server.ResourceGroupName
                    Subscription = $sub.Name
                    Type = $dbType
                    CurrentTier = $currentTier.Name
                    CurrentDTU = $currentTier.DTU
                    CurrentMonthlyCost = $currentTier.MonthlyCost
                    MaxDTUPercent = [math]::Round($maxPercent, 1)
                    AvgDTUPercent = [math]::Round($avgPercent, 1)
                    ActiveHours = $activeHours
                    ActivityPercent = [math]::Round($activityPercentage, 1)
                    SpikeCount = $spikeCount
                    Recommendation = $recommendation
                    Reasoning = $reasoning
                }
                
            } catch {
                Write-Host "    ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# ==============================================================================
# SUMMARY
# ==============================================================================

Write-Host "SUMMARY:" -ForegroundColor Cyan
Write-Host "--------" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Databases Analyzed: $totalScanned" -ForegroundColor White
Write-Host ""
Write-Host "SERVERLESS CANDIDATES: $($serverlessCandidates.Count)" -ForegroundColor Yellow
Write-Host "STANDARD TIER UPGRADES NEEDED: $($standardOptimizations.Count)" -ForegroundColor Yellow
Write-Host "KEEP AS-IS: $($allAnalysis.Count - $serverlessCandidates.Count - $standardOptimizations.Count)" -ForegroundColor Green
Write-Host ""

# Calculate total potential savings
$totalServerlessSavings = ($serverlessCandidates | Measure-Object -Property PotentialSavings -Sum).Sum
$totalUpgradeCost = ($standardOptimizations | Measure-Object -Property CostIncrease -Sum).Sum
$netSavings = $totalServerlessSavings - $totalUpgradeCost

Write-Host "FINANCIAL IMPACT:" -ForegroundColor Cyan
Write-Host "-----------------" -ForegroundColor Cyan
Write-Host "Potential savings from Serverless: `$$([math]::Round($totalServerlessSavings, 2))/month" -ForegroundColor Green
Write-Host "Cost increase from upgrades: `$$([math]::Round($totalUpgradeCost, 2))/month" -ForegroundColor Yellow
Write-Host "NET MONTHLY SAVINGS: `$$([math]::Round($netSavings, 2))/month" -ForegroundColor $(if($netSavings -gt 0){"Green"}else{"Red"})
Write-Host "NET ANNUAL SAVINGS: `$$([math]::Round($netSavings * 12, 2))/year" -ForegroundColor $(if($netSavings -gt 0){"Green"}else{"Red"})
Write-Host ""

# ==============================================================================
# DETAILED RECOMMENDATIONS
# ==============================================================================

if ($serverlessCandidates.Count -gt 0) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "SERVERLESS CANDIDATES ($($serverlessCandidates.Count) databases)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    $serverlessCandidates | Sort-Object -Property PotentialSavings -Descending | 
        Format-Table -Property Database, Type, CurrentTier, 
            @{L="Avg%";E={$_.AvgDTU}},
            @{L="Active%";E={$_.ActivityPercent}},
            @{L="Current$";E={$_.CurrentCost}},
            @{L="Serverless$";E={$_.EstimatedServerlessCost}},
            @{L="Save$";E={$_.PotentialSavings}} -AutoSize
}

if ($standardOptimizations.Count -gt 0) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "STANDARD TIER UPGRADES NEEDED ($($standardOptimizations.Count) databases)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    $standardOptimizations | Sort-Object -Property MaxDTU -Descending | 
        Format-Table -Property Database, Type, 
            @{L="Max%";E={$_.MaxDTU}},
            CurrentTier, RecommendedTier,
            @{L="Cost+";E={$_.CostIncrease}} -AutoSize
}

# ==============================================================================
# GENERATE HTML REPORT
# ==============================================================================

Write-Host ""
Write-Host "Generating HTML report..." -ForegroundColor Cyan

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SQL Database Cost Optimization Analysis</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; border-left: 4px solid #0078d4; padding-left: 10px; }
        .summary { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin: 20px 0; }
        .metric-box { display: inline-block; background: #0078d4; color: white; padding: 15px 25px; margin: 10px; border-radius: 5px; min-width: 200px; text-align: center; }
        .metric-value { font-size: 32px; font-weight: bold; }
        .metric-label { font-size: 14px; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; background: white; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f9f9f9; }
        .serverless { background-color: #d4edda; }
        .upgrade { background-color: #fff3cd; }
        .optimal { background-color: #e7f3ff; }
        .methodology { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #28a745; }
        .savings { color: #28a745; font-weight: bold; }
        .cost { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
    <h1>SQL Database Cost Optimization Analysis</h1>
    <p>Generated: $timestamp | Analyst: Syed Rizvi</p>
    
    <div class="summary">
        <div class="metric-box" style="background: #28a745;">
            <div class="metric-value">$totalScanned</div>
            <div class="metric-label">Total Databases</div>
        </div>
        <div class="metric-box" style="background: #ffc107;">
            <div class="metric-value">$($serverlessCandidates.Count)</div>
            <div class="metric-label">Serverless Candidates</div>
        </div>
        <div class="metric-box" style="background: #dc3545;">
            <div class="metric-value">$($standardOptimizations.Count)</div>
            <div class="metric-label">Upgrades Needed</div>
        </div>
        <div class="metric-box" style="background: #17a2b8;">
            <div class="metric-value">`$$([math]::Round($netSavings, 0))</div>
            <div class="metric-label">Net Monthly Savings</div>
        </div>
    </div>
    
    <div class="methodology">
        <h2>Methodology: Standard vs Serverless</h2>
        <p><strong>SERVERLESS BEST FOR:</strong></p>
        <ul>
            <li>Databases with low average DTU usage (&lt;20%)</li>
            <li>Intermittent/spiky usage patterns</li>
            <li>Active less than 30% of time</li>
            <li>Non-production environments</li>
        </ul>
        <p><strong>KEEP STANDARD TIER FOR:</strong></p>
        <ul>
            <li>Production databases with predictable load</li>
            <li>Databases with consistent high usage (&gt;50%)</li>
            <li>Databases that spike for extended periods</li>
        </ul>
        <p><strong>UPGRADE STANDARD TIER IF:</strong></p>
        <ul>
            <li>Maximum DTU usage &gt;= 85% (performance risk)</li>
            <li>Frequent timeouts or slow queries</li>
        </ul>
    </div>
"@

if ($serverlessCandidates.Count -gt 0) {
    $html += @"
    <h2>Serverless Candidates ($($serverlessCandidates.Count) databases)</h2>
    <table>
        <tr>
            <th>Database</th>
            <th>Type</th>
            <th>Current Tier</th>
            <th>Avg DTU%</th>
            <th>Activity%</th>
            <th>Current Cost</th>
            <th>Serverless Cost</th>
            <th>Monthly Savings</th>
            <th>Reasoning</th>
        </tr>
"@
    foreach ($db in ($serverlessCandidates | Sort-Object -Property PotentialSavings -Descending)) {
        $html += @"
        <tr class="serverless">
            <td>$($db.Database)</td>
            <td>$($db.Type)</td>
            <td>$($db.CurrentTier)</td>
            <td>$($db.AvgDTU)%</td>
            <td>$($db.ActivityPercent)%</td>
            <td>`$$($db.CurrentCost)</td>
            <td>`$$($db.EstimatedServerlessCost)</td>
            <td class="savings">`$$($db.PotentialSavings)</td>
            <td>$($db.Reasoning)</td>
        </tr>
"@
    }
    $html += "</table>"
}

if ($standardOptimizations.Count -gt 0) {
    $html += @"
    <h2>Standard Tier Upgrades Needed ($($standardOptimizations.Count) databases)</h2>
    <table>
        <tr>
            <th>Database</th>
            <th>Type</th>
            <th>Max DTU%</th>
            <th>Current Tier</th>
            <th>Recommended Tier</th>
            <th>Monthly Cost Increase</th>
            <th>Reasoning</th>
        </tr>
"@
    foreach ($db in ($standardOptimizations | Sort-Object -Property MaxDTU -Descending)) {
        $html += @"
        <tr class="upgrade">
            <td>$($db.Database)</td>
            <td>$($db.Type)</td>
            <td>$($db.MaxDTU)%</td>
            <td>$($db.CurrentTier)</td>
            <td>$($db.RecommendedTier)</td>
            <td class="cost">+`$$($db.CostIncrease)</td>
            <td>$($db.Reasoning)</td>
        </tr>
"@
    }
    $html += "</table>"
}

$html += @"
    <h2>Financial Summary</h2>
    <table>
        <tr>
            <td><strong>Potential Monthly Savings (Serverless)</strong></td>
            <td class="savings">`$$([math]::Round($totalServerlessSavings, 2))</td>
        </tr>
        <tr>
            <td><strong>Monthly Cost Increase (Upgrades)</strong></td>
            <td class="cost">+`$$([math]::Round($totalUpgradeCost, 2))</td>
        </tr>
        <tr style="background: #e7f3ff;">
            <td><strong>NET MONTHLY SAVINGS</strong></td>
            <td style="font-size: 18px; font-weight: bold;">`$$([math]::Round($netSavings, 2))</td>
        </tr>
        <tr style="background: #e7f3ff;">
            <td><strong>NET ANNUAL SAVINGS</strong></td>
            <td style="font-size: 18px; font-weight: bold;">`$$([math]::Round($netSavings * 12, 2))</td>
        </tr>
    </table>
    
    <h2>Next Steps for Tony</h2>
    <ol>
        <li>Review serverless candidates - these can save significant money</li>
        <li>Approve critical upgrades for performance (maxed databases)</li>
        <li>Test serverless with 2-3 non-prod databases first</li>
        <li>Monitor and adjust based on actual usage</li>
    </ol>
</body>
</html>
"@

$html | Out-File -FilePath $ReportFile -Encoding UTF8

Write-Host "✅ HTML Report generated: $ReportFile" -ForegroundColor Green

if ($ExportToCSV) {
    $allAnalysis | Export-Csv -Path $CSVFile -NoTypeInformation
    Write-Host "✅ CSV exported: $CSVFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "REPORT COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Send this report to Tony for review:" -ForegroundColor Cyan
Write-Host "  $ReportFile" -ForegroundColor White
Write-Host ""
Write-Host "Opening report in browser..." -ForegroundColor Cyan
Start-Process $ReportFile

Write-Host ""
Write-Host "RECOMMENDATION FOR TONY:" -ForegroundColor Yellow
Write-Host "------------------------" -ForegroundColor Yellow
Write-Host "1. Move $($serverlessCandidates.Count) low-activity databases to Serverless (save `$$([math]::Round($totalServerlessSavings,0))/mo)" -ForegroundColor White
Write-Host "2. Upgrade $($standardOptimizations.Count) maxed databases for performance (+`$$([math]::Round($totalUpgradeCost,0))/mo)" -ForegroundColor White
Write-Host "3. NET RESULT: Save `$$([math]::Round($netSavings,0))/month (`$$([math]::Round($netSavings*12,0))/year)" -ForegroundColor Green
Write-Host ""
