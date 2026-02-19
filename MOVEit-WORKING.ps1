$ResourceGroupName = "rg-moveit"
$SubscriptionId = "730dd182-eb99-4f54-8f4c-698a5338013f"
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

Write-Host "Step 1: Connecting to Azure..." -ForegroundColor Cyan
try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Write-Host "  Opening browser to sign in..." -ForegroundColor Yellow
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }
    Write-Host "  Connected as: $((Get-AzContext).Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Cannot connect to Azure" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Step 2: Setting subscription..." -ForegroundColor Cyan
Write-Host "  Target: $SubscriptionId" -ForegroundColor Gray
try {
    $sub = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
    Write-Host "  Active subscription: $($sub.Subscription.Name)" -ForegroundColor Green
    Write-Host "  Subscription ID: $($sub.Subscription.Id)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Cannot set subscription" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Available subscriptions:" -ForegroundColor Yellow
    $allSubs = Get-AzSubscription
    foreach ($s in $allSubs) {
        Write-Host "    $($s.Name) - $($s.Id)" -ForegroundColor White
    }
    exit
}

Write-Host ""
Write-Host "Step 3: Looking for resource group: $ResourceGroupName..." -ForegroundColor Cyan

$allRGs = Get-AzResourceGroup
Write-Host "  Total resource groups in subscription: $($allRGs.Count)" -ForegroundColor Gray

$rg = $null
foreach ($group in $allRGs) {
    if ($group.ResourceGroupName -eq $ResourceGroupName) {
        $rg = $group
        break
    }
}

if (-not $rg) {
    Write-Host "  ERROR: Resource group '$ResourceGroupName' not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Available resource groups in this subscription:" -ForegroundColor Yellow
    foreach ($g in $allRGs) {
        Write-Host "    - $($g.ResourceGroupName)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Copy the correct name and edit the script line 1:" -ForegroundColor Yellow
    Write-Host "  Change: `$ResourceGroupName = `"rg-moveit`"" -ForegroundColor Yellow
    Write-Host "  To:     `$ResourceGroupName = `"actual-name-here`"" -ForegroundColor Yellow
    exit
}

Write-Host "  FOUND: $($rg.ResourceGroupName)" -ForegroundColor Green
Write-Host "  Location: $($rg.Location)" -ForegroundColor Green

Write-Host ""
Write-Host "Step 4: Getting all resources..." -ForegroundColor Cyan

$resources = Get-AzResource -ResourceGroupName $ResourceGroupName
Write-Host "  Found $($resources.Count) resources in $ResourceGroupName" -ForegroundColor Green
Write-Host ""

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

Write-Host "Step 5: Calculating costs and savings..." -ForegroundColor Cyan

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

Write-Host "Step 6: Exporting reports..." -ForegroundColor Cyan
Write-Host "  Creating CSV..." -ForegroundColor Gray
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

Write-Host "  CSV: $csvPath" -ForegroundColor Green

Write-Host ""
Write-Host "  Creating HTML dashboard..." -ForegroundColor Gray
$htmlPath = Join-Path $OutputFolder "MOVEit_Dashboard_$timestamp.html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<title>MOVEit Cost Analysis</title>
<style>
body{font-family:Arial;background:#667eea;padding:20px;margin:0}
.container{max-width:1400px;margin:0 auto;background:white;border-radius:10px;padding:40px}
h1{color:#667eea;text-align:center}
.summary{display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;margin:30px 0}
.box{background:#f8f9fa;padding:20px;border-radius:8px;text-align:center}
.box h2{margin:0;color:#667eea;font-size:48px}
.box p{margin:10px 0 0 0;color:#666}
.savings{background:#28a745;color:white;padding:30px;border-radius:8px;text-align:center;margin:30px 0}
.savings h2{margin:0;font-size:36px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#667eea;color:white;padding:12px;text-align:left}
td{padding:10px;border-bottom:1px solid #ddd}
</style>
</head>
<body>
<div class="container">
<h1>MOVEit Cost Analysis Report</h1>
<p style="text-align:center">Resource Group: $ResourceGroupName | Generated: $(Get-Date -Format 'MMMM dd, yyyy')</p>

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
<h2>5-Year Savings: `$$fiveYearSavings</h2>
<p>Save $savingsPercent% by moving to MOVEit Cloud</p>
</div>

<h2>Resource Inventory ($($resources.Count) Resources)</h2>
<table>
<tr><th>Resource Name</th><th>Type</th><th>Location</th><th>Est. Cost</th></tr>
"@

foreach ($item in $inventory) {
    $html += "<tr><td>$($item.Name)</td><td>$($item.Type)</td><td>$($item.Location)</td><td>`$$($item.Cost)</td></tr>"
}

$html += @"
</table>

<h2>Cost Breakdown</h2>
<table>
<tr><td>Infrastructure</td><td>`$$totalInfraCost/mo</td></tr>
<tr><td>Maintenance (15%)</td><td>`$$maintenanceCost/mo</td></tr>
<tr><td>Monitoring</td><td>`$$monitoringCost/mo</td></tr>
<tr><td>Backup & DR</td><td>`$$backupCost/mo</td></tr>
<tr><td>Security</td><td>`$$securityCost/mo</td></tr>
<tr><td>IT Labor</td><td>`$$laborCost/mo</td></tr>
<tr style="border-top:2px solid #667eea"><td><strong>TOTAL CURRENT</strong></td><td><strong>`$$totalCurrentCost/mo</strong></td></tr>
<tr style="background:#28a745;color:white"><td><strong>MOVEit Cloud</strong></td><td><strong>`$$MoveitCloudCost/mo</strong></td></tr>
<tr style="background:#ffc107"><td><strong>MONTHLY SAVINGS</strong></td><td><strong>`$$monthlySavings</strong></td></tr>
</table>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $htmlPath -Encoding UTF8

Write-Host "  HTML: $htmlPath" -ForegroundColor Green

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Files created:" -ForegroundColor White
Write-Host "  $csvPath" -ForegroundColor Cyan
Write-Host "  $htmlPath" -ForegroundColor Cyan
Write-Host ""

Disconnect-AzAccount | Out-Null
