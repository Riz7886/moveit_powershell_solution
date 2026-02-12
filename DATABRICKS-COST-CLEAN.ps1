# DATABRICKS COST ANALYSIS AND CONTROL
# Professional cost monitoring and optimization tool

param(
    [Parameter(Mandatory=$false)]
    [int]$MonthlyBudget = 5000,
    
    [Parameter(Mandatory=$false)]
    [int]$AlertThreshold = 80
)

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS COST ANALYSIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monthly Budget: `$$MonthlyBudget" -ForegroundColor Yellow
Write-Host "Alert Threshold: $AlertThreshold%" -ForegroundColor Yellow
Write-Host ""

# Azure connection
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot connect to Azure" -ForegroundColor Red
    exit
}

Write-Host ""

$subs = Get-AzSubscription
$allDatabricks = @()
$totalCurrentCost = 0
$totalMaxCost = 0

Write-Host "Scanning for Databricks workspaces..." -ForegroundColor Yellow
Write-Host ""

foreach ($sub in $subs) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  Cannot access" -ForegroundColor Red
        continue
    }
    
    $workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces" -ErrorAction SilentlyContinue
    
    if ($workspaces) {
        Write-Host "  Found $($workspaces.Count) Databricks workspace(s)" -ForegroundColor Green
        
        foreach ($ws in $workspaces) {
            Write-Host "    Workspace: $($ws.Name)" -ForegroundColor White
            
            $workspace = Get-AzDatabricksWorkspace -ResourceGroupName $ws.ResourceGroupName -Name $ws.Name -ErrorAction SilentlyContinue
            
            $startDate = (Get-Date -Day 1).ToString("yyyy-MM-dd")
            $endDate = (Get-Date).ToString("yyyy-MM-dd")
            
            try {
                $costs = Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue | 
                    Where-Object {$_.InstanceId -like "*$($ws.ResourceId)*"}
                
                $currentCost = ($costs | Measure-Object -Property PretaxCost -Sum).Sum
                if (-not $currentCost) { $currentCost = 0 }
                
                Write-Host "      Current month cost: `$$([math]::Round($currentCost, 2))" -ForegroundColor $(if($currentCost -gt 500){"Red"}else{"Green"})
            } catch {
                $currentCost = 0
                Write-Host "      Current cost: Unable to fetch" -ForegroundColor Yellow
            }
            
            $maxMonthlyCost = 195 * 10
            
            Write-Host "      MAX potential cost (24/7): `$$maxMonthlyCost" -ForegroundColor Red
            Write-Host ""
            
            $allDatabricks += [PSCustomObject]@{
                Subscription = $sub.Name
                ResourceGroup = $ws.ResourceGroupName
                Workspace = $ws.Name
                Location = $ws.Location
                SKU = if($workspace.Sku.Name){$workspace.Sku.Name}else{"Standard"}
                CurrentCost = [math]::Round($currentCost, 2)
                MaxCost = $maxMonthlyCost
            }
            
            $totalCurrentCost += $currentCost
            $totalMaxCost += $maxMonthlyCost
        }
    } else {
        Write-Host "  No Databricks workspaces found" -ForegroundColor Gray
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total workspaces: $($allDatabricks.Count)" -ForegroundColor White
Write-Host "Current month cost: `$$([math]::Round($totalCurrentCost, 2))" -ForegroundColor $(if($totalCurrentCost -gt ($MonthlyBudget * 0.5)){"Red"}else{"Green"})
Write-Host "MAX potential (24/7): `$$totalMaxCost" -ForegroundColor Red
Write-Host "Monthly budget: `$$MonthlyBudget" -ForegroundColor Yellow
Write-Host ""

$budgetUsed = ($totalCurrentCost / $MonthlyBudget) * 100
Write-Host "Budget used: $([math]::Round($budgetUsed, 1))%" -ForegroundColor $(if($budgetUsed -gt $AlertThreshold){"Red"}elseif($budgetUsed -gt 50){"Yellow"}else{"Green"})

if ($budgetUsed -gt $AlertThreshold) {
    Write-Host "WARNING: Over $AlertThreshold% of budget used!" -ForegroundColor Red
}

Write-Host ""
Write-Host "Generating report..." -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = "DATABRICKS-COST-REPORT-$timestamp.html"

$tableRows = ""
foreach ($db in $allDatabricks) {
    $costColor = if($db.CurrentCost -gt 500){"red"}elseif($db.CurrentCost -gt 200){"orange"}else{"green"}
    $tableRows += "<tr>
        <td>$($db.Subscription)</td>
        <td>$($db.ResourceGroup)</td>
        <td><b>$($db.Workspace)</b></td>
        <td>$($db.Location)</td>
        <td>$($db.SKU)</td>
        <td style='color:$costColor;font-weight:bold'>`$$($db.CurrentCost)</td>
        <td style='color:red;font-weight:bold'>`$$($db.MaxCost)</td>
    </tr>"
}

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Databricks Cost Analysis Report</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f5f5f5;padding:20px}
.header{background:linear-gradient(135deg,#FF3621,#FF8A00);color:white;padding:50px;border-radius:12px;margin-bottom:30px;text-align:center}
h1{font-size:42px;margin-bottom:15px;font-weight:600}
.subtitle{font-size:18px;opacity:0.95}
.container{max-width:1400px;margin:0 auto}
.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:25px;margin-bottom:35px}
.box{background:white;padding:35px;border-radius:12px;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,0.1)}
.val{font-size:48px;font-weight:bold;margin-bottom:12px}
.label{color:#666;font-size:15px;text-transform:uppercase;letter-spacing:1px;font-weight:500}
.card{background:white;padding:40px;border-radius:12px;margin-bottom:30px;box-shadow:0 4px 20px rgba(0,0,0,0.1)}
h2{color:#333;font-size:28px;margin-bottom:25px;padding-bottom:15px;border-bottom:4px solid #FF3621;font-weight:600}
table{width:100%;border-collapse:collapse;margin:25px 0}
thead{background:#FF3621}
th{color:white;padding:18px;text-align:left;font-size:13px;font-weight:600;text-transform:uppercase}
td{padding:15px;border-bottom:1px solid #e0e0e0;font-size:14px}
tr:hover{background:#fff5f5}
.status{color:white;padding:25px;border-radius:10px;margin:25px 0;text-align:center;font-size:20px;font-weight:600}
.warning{background:#dc3545}
.success{background:#28a745}
.info{background:#17a2b8}
.recommendation{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:15px 0;border-radius:8px}
.rec-title{font-weight:600;font-size:16px;margin-bottom:8px;color:#856404}
.rec-text{color:#856404;font-size:14px;line-height:1.6}
.rec-savings{color:#28a745;font-weight:600;font-size:15px;margin-top:8px}
.rec-action{color:#0056b3;font-weight:500;margin-top:5px}
ul{margin:15px 0;padding-left:25px;line-height:2}
li{color:#333;font-size:14px}
.footer{background:#2c3e50;color:white;padding:30px;border-radius:12px;text-align:center;margin-top:35px;font-size:14px}
</style>
</head>
<body>
<div class='container'>

<div class='header'>
<h1>DATABRICKS COST ANALYSIS</h1>
<div class='subtitle'>Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm')</div>
</div>

<div class='summary'>
<div class='box'>
<div class='val' style='color:#FF3621'>$($allDatabricks.Count)</div>
<div class='label'>Total Workspaces</div>
</div>
<div class='box'>
<div class='val' style='color:$(if($totalCurrentCost -gt ($MonthlyBudget * 0.8)){"#dc3545"}elseif($totalCurrentCost -gt ($MonthlyBudget * 0.5)){"#ffc107"}else{"#28a745"})'>`$$([math]::Round($totalCurrentCost, 2))</div>
<div class='label'>Current Month Cost</div>
</div>
<div class='box'>
<div class='val' style='color:#dc3545'>`$$totalMaxCost</div>
<div class='label'>Max Potential (24/7)</div>
</div>
</div>

$(if($budgetUsed -gt $AlertThreshold){
"<div class='status warning'>
WARNING: $([math]::Round($budgetUsed, 1))% OF BUDGET USED<br>
Current: `$$([math]::Round($totalCurrentCost, 2)) / Budget: `$$MonthlyBudget
</div>"
}elseif($budgetUsed -gt 50){
"<div class='status info'>
ATTENTION: $([math]::Round($budgetUsed, 1))% OF BUDGET USED<br>
Monitor spending closely
</div>"
}else{
"<div class='status success'>
BUDGET STATUS: HEALTHY<br>
$([math]::Round($budgetUsed, 1))% of budget used
</div>"
})

<div class='card'>
<h2>ALL DATABRICKS WORKSPACES</h2>
<table>
<thead>
<tr>
<th>Subscription</th>
<th>Resource Group</th>
<th>Workspace</th>
<th>Location</th>
<th>SKU</th>
<th>Current Cost</th>
<th>Max Cost (24/7)</th>
</tr>
</thead>
<tbody>
$tableRows
</tbody>
</table>
</div>

<div class='card'>
<h2>COST BREAKDOWN (Estimated)</h2>
<p><b>Current Month Costs:</b></p>
<ul>
<li>Databricks Compute (VMs): 70-80% of total</li>
<li>Databricks DBUs (processing units): 15-20%</li>
<li>Storage (ADLS/Blob): 5-10%</li>
</ul>

<p style='margin-top:25px'><b>Key Cost Drivers:</b></p>
<ul>
<li><b>Are costs from Azure?</b> YES - Databricks runs on Azure VMs</li>
<li><b>Normal cost:</b> `$$([math]::Round($totalCurrentCost, 2)) this month so far</li>
<li><b>Max if scaled up:</b> Up to `$$totalMaxCost if all clusters run 24/7</li>
<li><b>Prevention:</b> Auto-termination + Cost alerts + Cluster policies</li>
</ul>
</div>

<div class='card'>
<h2>COST SAVING RECOMMENDATIONS</h2>

<div class='recommendation'>
<div class='rec-title'>1. AUTO-TERMINATION (Highest Impact)</div>
<div class='rec-text'>
Configure all clusters to auto-terminate after 30 minutes of inactivity.
</div>
<div class='rec-savings'>Potential Savings: 60-80% of compute costs</div>
<div class='rec-action'>Action: Set in cluster configuration - Auto Termination - 30 minutes</div>
</div>

<div class='recommendation'>
<div class='rec-title'>2. CLUSTER SIZE POLICIES</div>
<div class='rec-text'>
Limit maximum cluster size to prevent runaway costs.
</div>
<div class='rec-action'>Action: Create cluster policy limiting max workers to 5-10 nodes</div>
<div class='rec-text' style='margin-top:8px'>Prevents users accidentally creating 50-node clusters</div>
</div>

<div class='recommendation'>
<div class='rec-title'>3. USE SPOT/PREEMPTIBLE INSTANCES</div>
<div class='rec-text'>
Use Azure Spot VMs for development and non-critical workloads.
</div>
<div class='rec-savings'>Potential Savings: 60-90% on compute</div>
<div class='rec-action'>Action: Enable Spot instances in cluster configuration</div>
</div>

<div class='recommendation'>
<div class='rec-title'>4. SCHEDULE-BASED SHUTDOWN</div>
<div class='rec-text'>
Stop all clusters outside business hours (e.g., 7 PM - 7 AM).
</div>
<div class='rec-savings'>Potential Savings: 50% of costs</div>
<div class='rec-action'>Action: Use Azure Automation to stop/start clusters on schedule</div>
</div>

<div class='recommendation'>
<div class='rec-title'>5. SET UP AZURE COST ALERTS</div>
<div class='rec-text'>
Get email alerts when spending hits 80% of budget.
</div>
<div class='rec-action'>Action: Azure Portal - Cost Management - Budgets - Create Alert</div>
<div class='rec-text' style='margin-top:8px'>Prevents surprise bills at end of month</div>
</div>

</div>

<div class='footer'>
<b>DATABRICKS COST CONTROL REPORT</b><br><br>
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
Total Workspaces: $($allDatabricks.Count) | Current Cost: `$$([math]::Round($totalCurrentCost, 2)) | Budget: `$$MonthlyBudget<br>
Status: $(if($budgetUsed -gt $AlertThreshold){"OVER BUDGET"}elseif($budgetUsed -gt 50){"MONITOR CLOSELY"}else{"HEALTHY"})
</div>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "Report generated: $reportFile" -ForegroundColor Green
Write-Host ""
Write-Host "Current cost: `$$([math]::Round($totalCurrentCost, 2))" -ForegroundColor White
Write-Host "Max potential: `$$totalMaxCost" -ForegroundColor White
Write-Host ""

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
