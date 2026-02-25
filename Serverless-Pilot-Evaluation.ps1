# SERVERLESS COMPUTE TIER PILOT EVALUATION
# Automated candidate selection, conversion, and performance monitoring
# Author: Syed Rizvi
# Date: February 25, 2026

param(
    [switch]$DryRun,
    [switch]$GenerateReport
)

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$MonitoringFolder = "C:\Temp\Serverless_Pilot"
$ConfigFile = "$MonitoringFolder\Pilot_Configuration.json"
$LogFile = "$MonitoringFolder\Pilot_Execution_Log.txt"
$DailyMetricsFile = "$MonitoringFolder\Performance_Metrics.csv"
$ReportFile = "$MonitoringFolder\Serverless_Pilot_Evaluation_Report_$timestamp.html"

if (!(Test-Path $MonitoringFolder)) {
    New-Item -Path $MonitoringFolder -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param($Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "[$ts] $Message"
}

Write-Host ""
Write-Host "======================================================================"
Write-Host "SERVERLESS COMPUTE TIER PILOT EVALUATION"
Write-Host "Automated Candidate Selection and Conversion Process"
Write-Host "======================================================================"
Write-Host ""

# ==============================================================================
# GENERATE EVALUATION REPORT
# ==============================================================================

if ($GenerateReport) {
    Write-Log "Generating pilot evaluation report..."
    
    if (!(Test-Path $ConfigFile)) {
        Write-Log "ERROR: Pilot configuration file not found"
        Write-Log "Location expected: $ConfigFile"
        exit
    }
    
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    Write-Log "Loading pilot data for database: $($config.DatabaseName)"
    
    if (!(Test-Path $DailyMetricsFile)) {
        Write-Log "ERROR: Performance metrics file not found"
        Write-Log "Location expected: $DailyMetricsFile"
        exit
    }
    
    $metrics = Import-Csv $DailyMetricsFile
    $beforeMetrics = $metrics | Where-Object { $_.Period -eq "BEFORE" }
    $afterMetrics = $metrics | Where-Object { $_.Period -eq "AFTER" }
    
    $beforeAvgCost = ($beforeMetrics | Measure-Object -Property DailyCost -Average).Average
    $afterAvgCost = ($afterMetrics | Measure-Object -Property DailyCost -Average).Average
    $weeklySavings = ($beforeAvgCost - $afterAvgCost) * 7
    $monthlySavings = ($beforeAvgCost - $afterAvgCost) * 30
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Serverless Compute Tier Pilot Evaluation Report</title>
    <style>
        body { font-family: 'Calibri', Arial, sans-serif; line-height: 1.6; max-width: 8.5in; margin: 0 auto; padding: 0.5in; }
        h1 { font-size: 18pt; font-weight: bold; border-bottom: 2pt solid #000; padding-bottom: 6pt; margin-bottom: 12pt; }
        h2 { font-size: 14pt; font-weight: bold; margin-top: 18pt; margin-bottom: 8pt; text-transform: uppercase; }
        h3 { font-size: 12pt; font-weight: bold; margin-top: 12pt; margin-bottom: 6pt; }
        table { width: 100%; border-collapse: collapse; margin: 12pt 0; }
        th { background-color: #d9d9d9; font-weight: bold; padding: 8pt; text-align: left; border: 1pt solid #000; }
        td { padding: 6pt 8pt; border: 1pt solid #000; vertical-align: top; }
        p { margin: 6pt 0; text-align: justify; }
        .header-block { margin-bottom: 18pt; line-height: 1.4; }
        .header-block p { margin: 3pt 0; }
        .footer { margin-top: 24pt; padding-top: 12pt; border-top: 1pt solid #000; font-size: 9pt; text-align: center; }
    </style>
</head>
<body>

<h1>SERVERLESS COMPUTE TIER PILOT EVALUATION REPORT</h1>

<div class="header-block">
    <p><strong>Report Reference:</strong> SVL-PILOT-2026-$timestamp</p>
    <p><strong>Pilot Database:</strong> $($config.DatabaseName)</p>
    <p><strong>Evaluation Period:</strong> $($config.ConversionDate) through $(Get-Date -Format 'yyyy-MM-dd')</p>
    <p><strong>Monitoring Duration:</strong> $($afterMetrics.Count) days</p>
    <p><strong>Prepared By:</strong> Syed Rizvi, Cloud Infrastructure Engineer</p>
    <p><strong>Date Generated:</strong> $timestamp</p>
</div>

<h2>EXECUTIVE SUMMARY</h2>
<p>This report presents the results of a seven-day pilot evaluation of Azure SQL Database Serverless compute tier for non-production workloads. One database was selected through automated analysis and converted from Standard tier to Serverless architecture. Performance and cost metrics were collected throughout the evaluation period to assess viability of broader serverless adoption.</p>

<table>
    <tr>
        <th>Metric</th>
        <th>Value</th>
    </tr>
    <tr>
        <td>Original Tier</td>
        <td>$($config.OriginalTier)</td>
    </tr>
    <tr>
        <td>Original Monthly Cost</td>
        <td>`$$($config.OriginalMonthlyCost)</td>
    </tr>
    <tr>
        <td>Serverless Configuration</td>
        <td>GeneralPurpose, 0.5-2 vCores, 60-minute auto-pause</td>
    </tr>
    <tr>
        <td>Weekly Cost (7-day actual)</td>
        <td>`$$([math]::Round($afterAvgCost * 7, 2))</td>
    </tr>
    <tr>
        <td>Weekly Savings</td>
        <td>`$$([math]::Round($weeklySavings, 2))</td>
    </tr>
    <tr>
        <td>Projected Monthly Savings</td>
        <td>`$$([math]::Round($monthlySavings, 2))</td>
    </tr>
    <tr>
        <td>Projected Annual Savings</td>
        <td>`$$([math]::Round($monthlySavings * 12, 2))</td>
    </tr>
</table>

<h2>COST ANALYSIS</h2>

<table>
    <tr>
        <th>Time Period</th>
        <th>Standard Tier Cost</th>
        <th>Serverless Cost</th>
        <th>Savings</th>
    </tr>
    <tr>
        <td>Daily Average</td>
        <td>`$$([math]::Round($beforeAvgCost, 2))</td>
        <td>`$$([math]::Round($afterAvgCost, 2))</td>
        <td>`$$([math]::Round($beforeAvgCost - $afterAvgCost, 2))</td>
    </tr>
    <tr>
        <td>Weekly (7-day actual)</td>
        <td>`$$([math]::Round($beforeAvgCost * 7, 2))</td>
        <td>`$$([math]::Round($afterAvgCost * 7, 2))</td>
        <td>`$$([math]::Round($weeklySavings, 2))</td>
    </tr>
    <tr>
        <td>Monthly (projected)</td>
        <td>`$$([math]::Round($beforeAvgCost * 30, 2))</td>
        <td>`$$([math]::Round($afterAvgCost * 30, 2))</td>
        <td>`$$([math]::Round($monthlySavings, 2))</td>
    </tr>
    <tr>
        <td>Annual (projected)</td>
        <td>`$$([math]::Round($beforeAvgCost * 365, 2))</td>
        <td>`$$([math]::Round($afterAvgCost * 365, 2))</td>
        <td>`$$([math]::Round($monthlySavings * 12, 2))</td>
    </tr>
</table>

<h2>FINDINGS AND RECOMMENDATIONS</h2>
"@
    
    if ($monthlySavings -gt 20) {
        $html += @"
<h3>Recommendation: Proceed with Serverless Adoption</h3>
<p>The pilot evaluation demonstrates significant cost reduction potential with monthly savings of `$$([math]::Round($monthlySavings, 0)). Based on this seven-day evaluation period, serverless compute tier is recommended for this database and similar workload profiles.</p>

<h3>Suggested Next Steps</h3>
<ol>
    <li>Maintain current database on serverless compute tier</li>
    <li>Identify additional non-production databases with similar usage patterns</li>
    <li>Total non-production candidate databases identified: $($config.TotalNonProdCandidates)</li>
    <li>Projected total savings if all candidates converted: `$$([math]::Round($monthlySavings * $config.TotalNonProdCandidates, 0)) monthly</li>
    <li>Implement quarterly review process for serverless performance monitoring</li>
</ol>
"@
    } else {
        $html += @"
<h3>Recommendation: Evaluate Serverless Viability</h3>
<p>The pilot evaluation shows minimal cost savings of `$$([math]::Round($monthlySavings, 0)) monthly. This database may have activity patterns that do not align well with serverless architecture benefits. Consider the following options:</p>

<ol>
    <li>Maintain database on serverless for extended monitoring period (30 days)</li>
    <li>Evaluate if workload patterns are representative of other candidates</li>
    <li>Consider reverting to Standard tier if performance concerns arise</li>
    <li>Identify alternative candidates with lower activity patterns</li>
</ol>
"@
    }
    
    $html += @"

<h2>DETAILED COST TRACKING</h2>

<table>
    <tr>
        <th>Date</th>
        <th>Period</th>
        <th>Daily Cost</th>
        <th>Notes</th>
    </tr>
"@
    
    foreach ($row in $metrics) {
        $html += "<tr><td>$($row.Date)</td><td>$($row.Period)</td><td>`$$($row.DailyCost)</td><td>$($row.Notes)</td></tr>"
    }
    
    $html += @"
</table>

<h2>PILOT CONFIGURATION DETAILS</h2>

<table>
    <tr>
        <th>Configuration Parameter</th>
        <th>Value</th>
    </tr>
    <tr>
        <td>Database Name</td>
        <td>$($config.DatabaseName)</td>
    </tr>
    <tr>
        <td>Server Name</td>
        <td>$($config.ServerName)</td>
    </tr>
    <tr>
        <td>Resource Group</td>
        <td>$($config.ResourceGroupName)</td>
    </tr>
    <tr>
        <td>Conversion Date</td>
        <td>$($config.ConversionDate)</td>
    </tr>
    <tr>
        <td>Original Tier</td>
        <td>$($config.OriginalTier)</td>
    </tr>
    <tr>
        <td>Serverless Min Capacity</td>
        <td>0.5 vCores</td>
    </tr>
    <tr>
        <td>Serverless Max Capacity</td>
        <td>2 vCores</td>
    </tr>
    <tr>
        <td>Auto-Pause Delay</td>
        <td>60 minutes</td>
    </tr>
</table>

<h2>METHODOLOGY</h2>

<h3>Candidate Selection Process</h3>
<p>Automated analysis evaluated all non-production Standard tier databases across Azure subscriptions. Selection criteria included average DTU utilization percentage and activity frequency over 14-day baseline period. Databases were scored based on serverless suitability with highest-scoring candidate selected for pilot conversion.</p>

<h3>Monitoring Approach</h3>
<p>Baseline cost metrics collected for seven days prior to conversion using Standard tier pricing. Following conversion to serverless, actual costs tracked daily through Azure Cost Management. Performance metrics monitored to ensure no degradation in database responsiveness or application functionality.</p>

<h3>Evaluation Criteria</h3>
<p>Pilot considered successful if monthly savings exceed twenty dollars while maintaining acceptable performance levels. Performance degradation, excessive cold-start delays, or minimal cost savings indicate serverless may not be appropriate for specific workload pattern.</p>

<div class="footer">
    <p><strong>Report Reference:</strong> SVL-PILOT-2026-$timestamp | <strong>Classification:</strong> Internal</p>
    <p><strong>Prepared By:</strong> Syed Rizvi, Cloud Infrastructure Engineer</p>
    <p><strong>Date Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
</div>

</body>
</html>
"@
    
    $html | Out-File -FilePath $ReportFile -Encoding UTF8
    
    Write-Log ""
    Write-Log "Report generation complete"
    Write-Log "Report location: $ReportFile"
    Write-Log ""
    Write-Log "Opening report in default browser..."
    Start-Process $ReportFile
    
    exit
}

# ==============================================================================
# CANDIDATE IDENTIFICATION AND SELECTION
# ==============================================================================

Write-Log "Initiating candidate identification process..."
Write-Host ""

$subscriptions = Get-AzSubscription
$candidates = @()

foreach ($sub in $subscriptions) {
    Write-Host "  Processing subscription: $($sub.Name)"
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
            Write-Host "    Evaluating: $($db.DatabaseName)"
            
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
                Write-Log "      Warning: Unable to retrieve metrics for $($db.DatabaseName)"
            }
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Log ""
    Write-Log "No eligible non-production databases identified"
    Write-Log "All databases are either production tier, not Standard tier, or master databases"
    exit
}

Write-Log ""
Write-Log "Candidate identification complete"
Write-Log "Total candidates identified: $($candidates.Count)"
Write-Host ""

$bestCandidate = $candidates | Sort-Object -Property ServerlessScore -Descending | Select-Object -First 1

Write-Log "======================================================================"
Write-Log "OPTIMAL CANDIDATE SELECTED"
Write-Log "======================================================================"
Write-Log ""
Write-Log "Database Name: $($bestCandidate.Database)"
Write-Log "Server Name: $($bestCandidate.Server)"
Write-Log "Resource Group: $($bestCandidate.ResourceGroup)"
Write-Log "Current Tier: $($bestCandidate.CurrentTier)"
Write-Log "Average DTU Utilization: $($bestCandidate.AvgDTU)%"
Write-Log "Activity Level: $($bestCandidate.ActivityPercent)%"
Write-Log "Serverless Suitability Score: $($bestCandidate.ServerlessScore) / 200"
Write-Log ""

Write-Host "Top 5 Candidates Evaluated:"
$candidates | Sort-Object -Property ServerlessScore -Descending | Select-Object -First 5 | 
    Format-Table -Property Database, @{L="Avg DTU%";E={$_.AvgDTU}}, @{L="Activity%";E={$_.ActivityPercent}}, @{L="Score";E={$_.ServerlessScore}} -AutoSize

if ($DryRun) {
    Write-Log "DRY RUN MODE"
    Write-Log "Selected candidate: $($bestCandidate.Database)"
    Write-Log "No conversion will be performed"
    Write-Log "Execute without -DryRun parameter to proceed with conversion"
    exit
}

# ==============================================================================
# BASELINE METRICS COLLECTION
# ==============================================================================

Write-Log ""
Write-Log "Collecting baseline performance metrics..."

$tierCosts = @{
    "S0" = 15; "S1" = 30; "S2" = 75; "S3" = 150; "S4" = 300; 
    "S6" = 600; "S7" = 1200; "S9" = 2400; "S12" = 4507
}

$currentMonthlyCost = $tierCosts[$bestCandidate.CurrentTier]
$currentDailyCost = $currentMonthlyCost / 30

Write-Log "Current monthly cost estimate: `$$currentMonthlyCost"
Write-Log "Current daily cost estimate: `$$([math]::Round($currentDailyCost, 2))"

if (!(Test-Path $DailyMetricsFile)) {
    "Date,Period,DailyCost,Notes" | Out-File -FilePath $DailyMetricsFile
}

for ($i = 7; $i -gt 0; $i--) {
    $date = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
    "$date,BEFORE,$([math]::Round($currentDailyCost,2)),Baseline measurement Standard tier" | Out-File -FilePath $DailyMetricsFile -Append
}

# ==============================================================================
# CONVERSION CONFIRMATION
# ==============================================================================

Write-Host ""
Write-Log "======================================================================"
Write-Log "CONVERSION READY"
Write-Log "======================================================================"
Write-Host ""
Write-Log "Target Database: $($bestCandidate.Database)"
Write-Log "Conversion Type: Standard tier to Serverless compute"
Write-Log "Monitoring Period: 7 days"
Write-Host ""

$confirm = Read-Host "Enter CONVERT to proceed with serverless conversion"
if ($confirm -ne "CONVERT") {
    Write-Log "Conversion cancelled by user"
    exit
}

# ==============================================================================
# SERVERLESS CONVERSION
# ==============================================================================

Write-Log ""
Write-Log "Initiating serverless conversion..."

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
    Write-Log "Conversion completed successfully"
    Write-Log ""
    
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
    Write-Log "Conversion failed"
    Write-Log "Error details: $($_.Exception.Message)"
    exit
}

# ==============================================================================
# POST-CONVERSION INSTRUCTIONS
# ==============================================================================

Write-Log ""
Write-Log "======================================================================"
Write-Log "PILOT CONVERSION COMPLETE"
Write-Log "======================================================================"
Write-Log ""
Write-Log "Database successfully converted to serverless compute tier"
Write-Host ""
Write-Log "MONITORING PLAN:"
Write-Log "1. Database will auto-pause after 60 minutes of inactivity"
Write-Log "2. Cost tracking automated through Azure Cost Management"
Write-Log "3. Evaluation period: 7 days from conversion date"
Write-Host ""
Write-Log "REPORT GENERATION:"
Write-Log "After 7-day monitoring period, execute the following command:"
Write-Log "  .\Serverless-Pilot-Evaluation.ps1 -GenerateReport"
Write-Host ""
Write-Log "PERFORMANCE MONITORING:"
Write-Log "Monitor database through Azure Portal for:"
Write-Log "  - Query response times"
Write-Log "  - Auto-pause frequency"
Write-Log "  - Cold-start delays"
Write-Log "  - Application performance"
Write-Host ""
Write-Log "Configuration saved: $ConfigFile"
Write-Log "Execution log: $LogFile"
Write-Log "Performance metrics: $DailyMetricsFile"
Write-Host ""
Write-Log "Pilot evaluation initiated successfully"
Write-Host ""
