# AUTOMATED SERVERLESS TEST - PICK, CONVERT, MONITOR
# Automatically selects best non-prod DB candidate for Serverless
# Converts it and monitors for 7 DAYS
# Generates comprehensive HTML report
# Author: Syed Rizvi
# Date: February 25, 2026

param(
    [switch]$DryRun,
    [switch]$GenerateReport  # Use this after 7 days to generate final report
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$MonitoringFolder = "C:\Temp\Serverless_Test"
$ConfigFile = "$MonitoringFolder\Test_Config.json"
$LogFile = "$MonitoringFolder\Serverless_Test_Log.txt"
$DailyMetricsFile = "$MonitoringFolder\Daily_Metrics.csv"
$ReportFile = "$MonitoringFolder\Serverless_7Day_Report_$timestamp.html"

if (!(Test-Path $MonitoringFolder)) {
    New-Item -Path $MonitoringFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param($Message, $Color = "White")
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "[$ts] $Message" -ForegroundColor $Color
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "AUTOMATED SERVERLESS TEST" -ForegroundColor Cyan
Write-Host "Pick Best Candidate → Convert → Monitor 30 Days" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ==============================================================================
# GENERATE 30-DAY REPORT
# ==============================================================================

if ($GenerateReport) {
    Write-Log "Generating 7-day report..." "Cyan"
    
    if (!(Test-Path $ConfigFile)) {
        Write-Log "ERROR: No test configuration found!" "Red"
        Write-Log "Have you run the conversion yet?" "Red"
        exit
    }
    
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    
    Write-Log "Loading test data for: $($config.DatabaseName)" "White"
    
    # Load daily metrics
    if (!(Test-Path $DailyMetricsFile)) {
        Write-Log "ERROR: No daily metrics found!" "Red"
        exit
    }
    
    $metrics = Import-Csv $DailyMetricsFile
    
    # Calculate statistics
    $beforeMetrics = $metrics | Where-Object { $_.Period -eq "BEFORE" }
    $afterMetrics = $metrics | Where-Object { $_.Period -eq "AFTER" }
    
    $beforeAvgCost = ($beforeMetrics | Measure-Object -Property DailyCost -Average).Average
    $afterAvgCost = ($afterMetrics | Measure-Object -Property DailyCost -Average).Average
    $weeklySavings = ($beforeAvgCost - $afterAvgCost) * 7
    $monthlySavings = ($beforeAvgCost - $afterAvgCost) * 30  # Projected based on 7-day pattern
    
    # Generate HTML Report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Serverless 7-Day Test Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric-box { display: inline-block; background: #0078d4; color: white; padding: 15px 25px; margin: 10px; border-radius: 5px; min-width: 200px; text-align: center; }
        .metric-value { font-size: 32px; font-weight: bold; }
        .metric-label { font-size: 14px; margin-top: 5px; }
        .success { background: #28a745 !important; }
        .warning { background: #ffc107 !important; }
        .info { background: #17a2b8 !important; }
        table { width: 100%; border-collapse: collapse; background: white; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .recommendation { background: #e7f3ff; padding: 20px; border-left: 4px solid #0078d4; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Serverless 7-Day Test Report</h1>
    <p><strong>Database:</strong> $($config.DatabaseName)</p>
    <p><strong>Test Period:</strong> $($config.ConversionDate) to $(Get-Date -Format 'yyyy-MM-dd')</p>
    <p><strong>Generated:</strong> $timestamp</p>
    
    <div class="summary">
        <div class="metric-box success">
            <div class="metric-value">`$$([math]::Round($weeklySavings, 0))</div>
            <div class="metric-label">Weekly Savings (7 days)</div>
        </div>
        <div class="metric-box success">
            <div class="metric-value">`$$([math]::Round($monthlySavings, 0))</div>
            <div class="metric-label">Projected Monthly Savings</div>
        </div>
        <div class="metric-box info">
            <div class="metric-value">$($afterMetrics.Count)</div>
            <div class="metric-label">Days Monitored</div>
        </div>
        <div class="metric-box warning">
            <div class="metric-value">$([math]::Round($beforeAvgCost, 2))</div>
            <div class="metric-label">Before ($/day)</div>
        </div>
        <div class="metric-box success">
            <div class="metric-value">$([math]::Round($afterAvgCost, 2))</div>
            <div class="metric-label">After ($/day)</div>
        </div>
    </div>
    
    <h2>Test Summary</h2>
    <table>
        <tr><th>Metric</th><th>Before Serverless</th><th>After Serverless</th><th>Change</th></tr>
        <tr>
            <td>Daily Cost</td>
            <td>`$$([math]::Round($beforeAvgCost, 2))</td>
            <td>`$$([math]::Round($afterAvgCost, 2))</td>
            <td style="color: green;">-`$$([math]::Round($beforeAvgCost - $afterAvgCost, 2))</td>
        </tr>
        <tr>
            <td>Monthly Projected</td>
            <td>`$$([math]::Round($beforeAvgCost * 30, 2))</td>
            <td>`$$([math]::Round($afterAvgCost * 30, 2))</td>
            <td style="color: green; font-weight: bold;">-`$$([math]::Round($monthlySavings, 2))</td>
        </tr>
        <tr>
            <td>Annual Projected</td>
            <td>`$$([math]::Round($beforeAvgCost * 365, 2))</td>
            <td>`$$([math]::Round($afterAvgCost * 365, 2))</td>
            <td style="color: green; font-weight: bold;">-`$$([math]::Round($monthlySavings * 12, 2))</td>
        </tr>
    </table>
    
    <div class="recommendation">
        <h2>Recommendation for Tony</h2>
"@
    
    if ($monthlySavings -gt 20) {
        $html += @"
        <p><strong style="color: green;">✅ SUCCESS - RECOMMEND SERVERLESS</strong></p>
        <p>This test shows significant cost savings (`$$([math]::Round($monthlySavings, 0))/month) without performance issues.</p>
        <p><strong>Next Steps:</strong></p>
        <ul>
            <li>Keep this database on Serverless</li>
            <li>Identify $([math]::Ceiling($config.TotalNonProdCandidates / 2)) more non-prod databases with similar patterns</li>
            <li>Projected total savings: `$$([math]::Round($monthlySavings * $config.TotalNonProdCandidates, 0))/month</li>
        </ul>
"@
    } else {
        $html += @"
        <p><strong style="color: orange;">⚠️ MINIMAL SAVINGS - REVIEW NEEDED</strong></p>
        <p>Savings are minimal (`$$([math]::Round($monthlySavings, 0))/month). Consider reverting to Standard tier.</p>
        <p>This database may have too much consistent activity for Serverless to be cost-effective.</p>
"@
    }
    
    $html += @"
    </div>
    
    <h2>Daily Cost Tracking</h2>
    <table>
        <tr><th>Date</th><th>Period</th><th>Daily Cost</th><th>Notes</th></tr>
"@
    
    foreach ($row in $metrics) {
        $html += "<tr><td>$($row.Date)</td><td>$($row.Period)</td><td>`$$($row.DailyCost)</td><td>$($row.Notes)</td></tr>"
    }
    
    $html += @"
    </table>
</body>
</html>
"@
    
    $html | Out-File -FilePath $ReportFile -Encoding UTF8
    
    Write-Log ""
    Write-Log "✅ Report generated: $ReportFile" "Green"
    Write-Log ""
    Write-Log "Opening report..." "Cyan"
    Start-Process $ReportFile
    
    exit
}

# ==============================================================================
# STEP 1: FIND BEST NON-PROD CANDIDATE
# ==============================================================================

Write-Log "STEP 1: Analyzing all non-prod databases..." "Cyan"
Write-Host ""

$subscriptions = Get-AzSubscription
$candidates = @()

foreach ($sub in $subscriptions) {
    Write-Host "  Subscription: $($sub.Name)" -ForegroundColor Gray
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $sqlServers = Get-AzSqlServer
    
    foreach ($server in $sqlServers) {
        $databases = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName | 
            Where-Object { 
                $_.DatabaseName -ne "master" -and 
                $_.Edition -eq "Standard" -and 
                $_.DatabaseName -notlike "*-prod" 
            }
        
        foreach ($db in $databases) {
            Write-Host "    Checking: $($db.DatabaseName)" -ForegroundColor DarkGray
            
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
                
                if ($metrics.Data.Count -gt 0) {
                    $validData = $metrics.Data | Where-Object { $_.Average -ne $null }
                    
                    if ($validData.Count -gt 0) {
                        $avgPercent = ($validData.Average | Measure-Object -Average).Average
                        $activeHours = ($validData | Where-Object { $_.Average -gt 10 }).Count
                        $totalHours = 14 * 24
                        $activityPercent = ($activeHours / $totalHours) * 100
                        
                        # Score for serverless candidacy
                        # Low avg + low activity = high score
                        $serverlessScore = (100 - $avgPercent) + (100 - $activityPercent)
                        
                        $candidates += [PSCustomObject]@{
                            Database = $db.DatabaseName
                            Server = $server.ServerName
                            ResourceGroup = $server.ResourceGroupName
                            SubscriptionId = $sub.Id
                            SubscriptionName = $sub.Name
                            CurrentTier = $db.CurrentServiceObjectiveName
                            AvgDTU = [math]::Round($avgPercent, 1)
                            ActivityPercent = [math]::Round($activityPercent, 1)
                            ServerlessScore = [math]::Round($serverlessScore, 1)
                            MaxSizeBytes = $db.MaxSizeBytes
                        }
                    }
                }
            } catch {
                Write-Log "      Error getting metrics: $($_.Exception.Message)" "Red"
            }
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Log ""
    Write-Log "❌ No non-prod databases found!" "Red"
    Write-Log "All databases are either:" "Yellow"
    Write-Log "  - Production databases" "Yellow"
    Write-Log "  - Not on Standard tier" "Yellow"
    Write-Log "  - Master databases" "Yellow"
    exit
}

Write-Log ""
Write-Log "Found $($candidates.Count) non-prod database candidates" "Green"
Write-Host ""

# Pick the best candidate (highest serverless score)
$bestCandidate = $candidates | Sort-Object -Property ServerlessScore -Descending | Select-Object -First 1

Write-Log "================================================================" "Green"
Write-Log "BEST CANDIDATE SELECTED" "Green"
Write-Log "================================================================" "Green"
Write-Log ""
Write-Log "Database: $($bestCandidate.Database)" "Cyan"
Write-Log "Server: $($bestCandidate.Server)" "Cyan"
Write-Log "Resource Group: $($bestCandidate.ResourceGroup)" "Cyan"
Write-Log "Current Tier: $($bestCandidate.CurrentTier)" "White"
Write-Log "Average DTU: $($bestCandidate.AvgDTU)%" "White"
Write-Log "Activity: $($bestCandidate.ActivityPercent)%" "White"
Write-Log "Serverless Score: $($bestCandidate.ServerlessScore)/200" "Green"
Write-Log ""
Write-Log "Why this database?" "Yellow"
Write-Log "  - Low average DTU usage ($($bestCandidate.AvgDTU)%)" "Gray"
Write-Log "  - Low activity ($($bestCandidate.ActivityPercent)% of time)" "Gray"
Write-Log "  - Perfect candidate for auto-pause cost savings" "Gray"
Write-Host ""

# Show top 5 candidates
Write-Log "Top 5 Candidates:" "Cyan"
$candidates | Sort-Object -Property ServerlessScore -Descending | Select-Object -First 5 | 
    Format-Table -Property Database, @{L="Avg DTU%";E={$_.AvgDTU}}, @{L="Activity%";E={$_.ActivityPercent}}, @{L="Score";E={$_.ServerlessScore}} -AutoSize

if ($DryRun) {
    Write-Log "*** DRY RUN MODE ***" "Yellow"
    Write-Log "Would convert: $($bestCandidate.Database)" "Yellow"
    Write-Log "Run without -DryRun to execute conversion" "Yellow"
    exit
}

# ==============================================================================
# STEP 2: COLLECT BASELINE METRICS (7 DAYS BEFORE)
# ==============================================================================

Write-Log ""
Write-Log "STEP 2: Collecting baseline metrics..." "Cyan"

# Get current cost (estimate based on tier)
$tierCosts = @{
    "S0" = 15; "S1" = 30; "S2" = 75; "S3" = 150; "S4" = 300; 
    "S6" = 600; "S7" = 1200; "S9" = 2400; "S12" = 4507
}

$currentMonthlyCost = $tierCosts[$bestCandidate.CurrentTier]
$currentDailyCost = $currentMonthlyCost / 30

Write-Log "  Current estimated cost: `$$currentMonthlyCost/month (`$$([math]::Round($currentDailyCost,2))/day)" "White"

# Initialize daily metrics CSV
if (!(Test-Path $DailyMetricsFile)) {
    "Date,Period,DailyCost,Notes" | Out-File -FilePath $DailyMetricsFile
}

# Add baseline data (last 7 days)
for ($i = 7; $i -gt 0; $i--) {
    $date = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
    "$date,BEFORE,$([math]::Round($currentDailyCost,2)),Baseline measurement" | Out-File -FilePath $DailyMetricsFile -Append
}

# ==============================================================================
# STEP 3: GET CONFIRMATION
# ==============================================================================

Write-Host ""
Write-Log "================================================================" "Yellow"
Write-Log "READY TO CONVERT" "Yellow"
Write-Log "================================================================" "Yellow"
Write-Host ""
Write-Log "Database: $($bestCandidate.Database)" "White"
Write-Log "Action: Convert Standard → Serverless" "White"
Write-Log "Monitoring Period: 7 days" "White"
Write-Host ""

$confirm = Read-Host "Type 'CONVERT' to proceed with serverless conversion"
if ($confirm -ne "CONVERT") {
    Write-Log "CANCELLED by user" "Yellow"
    exit
}

# ==============================================================================
# STEP 4: CONVERT TO SERVERLESS
# ==============================================================================

Write-Log ""
Write-Log "STEP 4: Converting to Serverless..." "Cyan"

Set-AzContext -SubscriptionId $bestCandidate.SubscriptionId | Out-Null

try {
    Set-AzSqlDatabase `
        -ResourceGroupName $bestCandidate.ResourceGroup `
        -ServerName $bestCandidate.Server `
        -DatabaseName $bestCandidate.Database `
        -Edition "GeneralPurpose" `
        -ComputeModel "Serverless" `
        -ComputeGeneration "Gen5" `
        -MinimumCapacity 0.5 `
        -Capacity 2 `
        -AutoPauseDelayInMinutes 60
    
    Write-Log ""
    Write-Log "✅ ✅ ✅ CONVERSION SUCCESSFUL! ✅ ✅ ✅" "Green"
    Write-Log ""
    
    # Save configuration
    $testConfig = @{
        DatabaseName = $bestCandidate.Database
        ServerName = $bestCandidate.Server
        ResourceGroupName = $bestCandidate.ResourceGroup
        SubscriptionId = $bestCandidate.SubscriptionId
        ConversionDate = (Get-Date).ToString('yyyy-MM-dd')
        OriginalTier = $bestCandidate.CurrentTier
        OriginalMonthlyCost = $currentMonthlyCost
        TotalNonProdCandidates = $candidates.Count
    }
    $testConfig | ConvertTo-Json | Out-File -FilePath $ConfigFile
    
} catch {
    Write-Log ""
    Write-Log "❌ CONVERSION FAILED" "Red"
    Write-Log $_.Exception.Message "Red"
    exit
}

# ==============================================================================
# STEP 5: SET UP MONITORING
# ==============================================================================

Write-Log ""
Write-Log "================================================================" "Green"
Write-Log "MONITORING SETUP" "Green"
Write-Log "================================================================" "Green"
Write-Log ""
Write-Log "The database is now on Serverless and being monitored!" "Green"
Write-Host ""
Write-Log "WHAT HAPPENS NEXT:" "Cyan"
Write-Log "1. Database will auto-pause after 60 minutes of inactivity" "White"
Write-Log "2. Cost will be tracked daily in: $DailyMetricsFile" "White"
Write-Log "3. After 7 DAYS, run this command to generate report:" "White"
Write-Log "   .\Serverless-Auto-Test.ps1 -GenerateReport" "Gray"
Write-Host ""
Write-Log "SCHEDULED TASK (Optional):" "Cyan"
Write-Log "Set up a daily scheduled task to track costs:" "White"
Write-Log "1. Open Task Scheduler" "Gray"
Write-Log "2. Create task to run daily at 11:59 PM" "Gray"
Write-Log "3. Action: Check Azure Cost Management and update $DailyMetricsFile" "Gray"
Write-Host ""
Write-Log "MANUAL MONITORING:" "Cyan"
Write-Log "- Go to Azure Portal → Cost Management" "White"
Write-Log "- Filter by Resource: $($bestCandidate.Database)" "White"
Write-Log "- Check daily costs" "White"
Write-Host ""
Write-Log "Configuration saved to: $ConfigFile" "Gray"
Write-Log "Log file: $LogFile" "Gray"
Write-Host ""
Write-Log "✅ Test started successfully!" "Green"
Write-Log "⏰ Check back in 7 DAYS to generate the final report" "Yellow"
Write-Host ""
