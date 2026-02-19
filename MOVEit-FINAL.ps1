$ResourceGroupName = "rg-moveit"
$SubscriptionId = "730dd182-eb99-4f54-8f4c-698a5388013f"
$MoveitCloudCost = 2500
$OutputFolder = "Reports"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  MOVEIT COST ANALYSIS" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking Azure connection..." -ForegroundColor Cyan

$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context) {
    Write-Host ""
    Write-Host "You are not connected to Azure!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run these commands first:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Connect-AzAccount" -ForegroundColor Cyan
    Write-Host "  2. Set-AzContext -SubscriptionId $SubscriptionId" -ForegroundColor Cyan
    Write-Host "  3. Then run this script again" -ForegroundColor Cyan
    Write-Host ""
    exit
}

Write-Host "  Already connected as: $($context.Account.Id)" -ForegroundColor Green

if ($context.Subscription.Id -ne $SubscriptionId) {
    Write-Host ""
    Write-Host "Setting subscription to: $SubscriptionId..." -ForegroundColor Cyan
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        $context = Get-AzContext
        Write-Host "  Subscription set: $($context.Subscription.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: Cannot set subscription" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Available subscriptions:" -ForegroundColor Yellow
        Get-AzSubscription | ForEach-Object {
            Write-Host "    $($_.Name) - $($_.Id)" -ForegroundColor White
        }
        exit
    }
} else {
    Write-Host "  Active subscription: $($context.Subscription.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Looking for resource group: $ResourceGroupName..." -ForegroundColor Cyan

$allRGs = Get-AzResourceGroup
Write-Host "  Found $($allRGs.Count) resource groups in subscription" -ForegroundColor Gray

$rg = $null
foreach ($group in $allRGs) {
    if ($group.ResourceGroupName -eq $ResourceGroupName) {
        $rg = $group
        break
    }
}

if (-not $rg) {
    Write-Host ""
    Write-Host "  ERROR: '$ResourceGroupName' not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Available resource groups:" -ForegroundColor Yellow
    foreach ($g in $allRGs) {
        Write-Host "    $($g.ResourceGroupName)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Edit line 1 of script with correct name" -ForegroundColor Yellow
    exit
}

Write-Host "  Found: $($rg.ResourceGroupName)" -ForegroundColor Green
Write-Host "  Location: $($rg.Location)" -ForegroundColor Green

Write-Host ""
Write-Host "Getting resources..." -ForegroundColor Cyan

$resources = Get-AzResource -ResourceGroupName $ResourceGroupName
Write-Host "  Found $($resources.Count) resources" -ForegroundColor Green

$inventory = @()
$totalInfraCost = 0

foreach ($resource in $resources) {
    $cost = 0
    $type = $resource.ResourceType
    
    if ($type -like "*virtualMachines*") { $cost = 100 }
    elseif ($type -like "*disks*") { $cost = 20 }
    elseif ($type -like "*storageAccounts*") { $cost = 50 }
    elseif ($type -like "*publicIPAddresses*") { $cost = 4 }
    else { $cost = 5 }
    
    $totalInfraCost += $cost
    
    $item = [PSCustomObject]@{
        Name = $resource.Name
        Type = $type
        Location = $resource.Location
        Cost = $cost
    }
    
    $inventory += $item
}

Write-Host ""
Write-Host "Calculating costs..." -ForegroundColor Cyan

$maintenanceCost = [math]::Round($totalInfraCost * 0.15, 2)
$monitoringCost = 50
$backupCost = 100
$securityCost = 75
$laborCost = 500

$totalCurrentCost = $totalInfraCost + $maintenanceCost + $monitoringCost + $backupCost + $securityCost + $laborCost

$monthlySavings = $totalCurrentCost - $MoveitCloudCost
$yearlySavings = $monthlySavings * 12
$fiveYearSavings = $yearlySavings * 5

$savingsPercent = [math]::Round(($monthlySavings / $totalCurrentCost) * 100, 1)

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  COST ANALYSIS RESULTS" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "CURRENT COSTS:" -ForegroundColor Cyan
Write-Host "  Infrastructure: `$$totalInfraCost/mo" -ForegroundColor White
Write-Host "  Maintenance: `$$maintenanceCost/mo" -ForegroundColor White
Write-Host "  Monitoring: `$$monitoringCost/mo" -ForegroundColor White
Write-Host "  Backup: `$$backupCost/mo" -ForegroundColor White
Write-Host "  Security: `$$securityCost/mo" -ForegroundColor White
Write-Host "  Labor: `$$laborCost/mo" -ForegroundColor White
Write-Host "  --------------------------------" -ForegroundColor Gray
Write-Host "  TOTAL: `$$totalCurrentCost/month" -ForegroundColor Cyan
Write-Host ""
Write-Host "MOVEIT CLOUD:" -ForegroundColor Green
Write-Host "  Monthly Cost: `$$MoveitCloudCost/month" -ForegroundColor White
Write-Host ""
Write-Host "SAVINGS:" -ForegroundColor Yellow
Write-Host "  Monthly: `$$monthlySavings" -ForegroundColor Green
Write-Host "  Yearly: `$$yearlySavings" -ForegroundColor Green
Write-Host "  5-Year Total: `$$fiveYearSavings" -ForegroundColor Green
Write-Host "  Savings: $savingsPercent%" -ForegroundColor Green
Write-Host ""

Write-Host "Creating CSV report..." -ForegroundColor Cyan
$csvPath = Join-Path $OutputFolder "MOVEit_Analysis_$timestamp.csv"

$csvData = @()
foreach ($item in $inventory) {
    $csvData += $item
}

$csvData += [PSCustomObject]@{
    Name = "--- SUMMARY ---"
    Type = ""
    Location = ""
    Cost = ""
}

$csvData += [PSCustomObject]@{
    Name = "Current Total"
    Type = "Monthly"
    Location = ""
    Cost = $totalCurrentCost
}

$csvData += [PSCustomObject]@{
    Name = "MOVEit Cloud"
    Type = "Monthly"
    Location = ""
    Cost = $MoveitCloudCost
}

$csvData += [PSCustomObject]@{
    Name = "Monthly Savings"
    Type = ""
    Location = ""
    Cost = $monthlySavings
}

$csvData += [PSCustomObject]@{
    Name = "5-Year Savings"
    Type = ""
    Location = ""
    Cost = $fiveYearSavings
}

$csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "  CSV saved: $csvPath" -ForegroundColor Green

Write-Host ""
Write-Host "Creating HTML dashboard..." -ForegroundColor Cyan
$htmlPath = Join-Path $OutputFolder "MOVEit_Dashboard_$timestamp.html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>MOVEit Cost Analysis</title>
<style>
body{font-family:Arial;background:#667eea;padding:20px;margin:0}
.container{max-width:1400px;margin:0 auto;background:white;border-radius:10px;padding:40px}
h1{color:#667eea;text-align:center;font-size:42px}
.summary{display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;margin:30px 0}
.box{background:#f8f9fa;padding:25px;border-radius:8px;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
.box h2{margin:0;color:#667eea;font-size:48px}
.box p{margin:10px 0 0 0;color:#666;font-size:16px}
.savings{background:#28a745;color:white;padding:40px;border-radius:8px;text-align:center;margin:30px 0}
.savings h2{margin:0;font-size:42px}
.savings p{font-size:20px;margin-top:15px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#667eea;color:white;padding:15px;text-align:left;font-size:14px}
td{padding:12px;border-bottom:1px solid #ddd;font-size:14px}
tr:hover{background:#f8f9fa}
h2{color:#667eea;margin-top:40px}
</style>
</head>
<body>
<div class="container">
<h1>MOVEit Cost Analysis Report</h1>
<p style="text-align:center;color:#666;font-size:18px">Resource Group: $ResourceGroupName | Generated: $(Get-Date -Format 'MMMM dd, yyyy')</p>

<div class="summary">
<div class="box">
<h2>`$$totalCurrentCost</h2>
<p>Current Monthly Cost</p>
</div>
<div class="box">
<h2>`$$MoveitCloudCost</h2>
<p>MOVEit Cloud Cost</p>
</div>
<div class="box">
<h2>`$$monthlySavings</h2>
<p>Monthly Savings</p>
</div>
</div>

<div class="savings">
<h2>5-YEAR SAVINGS: `$$fiveYearSavings</h2>
<p>Save $savingsPercent% by moving to MOVEit Cloud</p>
</div>

<h2>Resource Inventory ($($resources.Count) Resources)</h2>
<table>
<tr><th>Resource Name</th><th>Type</th><th>Location</th><th>Est. Monthly Cost</th></tr>
"@

foreach ($item in $inventory) {
    $html += "<tr><td><strong>$($item.Name)</strong></td><td>$($item.Type)</td><td>$($item.Location)</td><td>`$$($item.Cost)</td></tr>"
}

$html += @"
</table>

<h2>Cost Breakdown</h2>
<table>
<tr><td><strong>Infrastructure (Azure Resources)</strong></td><td><strong>`$$totalInfraCost/mo</strong></td></tr>
<tr><td>Maintenance & Support (15%)</td><td>`$$maintenanceCost/mo</td></tr>
<tr><td>Monitoring & Alerts</td><td>`$$monitoringCost/mo</td></tr>
<tr><td>Backup & Disaster Recovery</td><td>`$$backupCost/mo</td></tr>
<tr><td>Security & Compliance</td><td>`$$securityCost/mo</td></tr>
<tr><td>IT Labor & Management</td><td>`$$laborCost/mo</td></tr>
<tr style="border-top:3px solid #667eea;background:#f8f9fa"><td><strong>TOTAL CURRENT MONTHLY COST</strong></td><td><strong>`$$totalCurrentCost/mo</strong></td></tr>
<tr style="background:#d4edda"><td><strong>MOVEit Cloud (Fully Managed)</strong></td><td><strong>`$$MoveitCloudCost/mo</strong></td></tr>
<tr style="background:#fff3cd"><td><strong>MONTHLY SAVINGS</strong></td><td><strong>`$$monthlySavings</strong></td></tr>
<tr style="background:#d1ecf1"><td><strong>YEARLY SAVINGS</strong></td><td><strong>`$$yearlySavings</strong></td></tr>
<tr style="background:#28a745;color:white"><td><strong>5-YEAR SAVINGS</strong></td><td><strong>`$$fiveYearSavings</strong></td></tr>
</table>

<div style="background:#fff3cd;padding:20px;border-radius:8px;margin-top:30px;border-left:4px solid #ffc107">
<h3 style="color:#856404;margin-top:0">Recommendation</h3>
<p style="color:#856404;line-height:1.6">
Moving to MOVEit Cloud will save PYX Health <strong>`$$fiveYearSavings over 5 years</strong> while eliminating infrastructure management overhead, 
improving security posture, and providing 99.9% uptime SLA. The migration delivers immediate cost reduction of <strong>$savingsPercent%</strong> 
with enhanced compliance, automated backups, and 24/7 expert support.
</p>
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $htmlPath -Encoding UTF8
Write-Host "  HTML saved: $htmlPath" -ForegroundColor Green

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Reports created:" -ForegroundColor White
Write-Host "  CSV:  $csvPath" -ForegroundColor Cyan
Write-Host "  HTML: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Open the HTML file in your browser!" -ForegroundColor Yellow
Write-Host ""
