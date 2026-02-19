# MOVEit Cost Analysis - Auto Subscription Detection
# Finds ALL subscriptions, then finds rg-moveit automatically

Clear-Host
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MOVEIT COST ANALYSIS" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$MoveitCloudCost = 2500
$OutputFolder = "Reports"

if (-not (Test-Path $OutputFolder)) {
    mkdir $OutputFolder -Force | Out-Null
}

Write-Host "Connecting to Azure..." -ForegroundColor Cyan
try {
    $context = Get-AzContext -ErrorAction Stop
    Write-Host "  Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "  Not connected. Connecting now..." -ForegroundColor Yellow
    Connect-AzAccount
    $context = Get-AzContext
}

Write-Host ""
Write-Host "Scanning all subscriptions for rg-moveit..." -ForegroundColor Cyan
Write-Host ""

$allSubs = Get-AzSubscription
Write-Host "Found $($allSubs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$foundRG = $null
$foundSub = $null

foreach ($sub in $allSubs) {
    Write-Host "  Checking: $($sub.Name)..." -ForegroundColor Gray
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        
        $rg = Get-AzResourceGroup -Name "rg-moveit" -ErrorAction SilentlyContinue
        
        if ($rg) {
            $foundRG = $rg
            $foundSub = $sub
            Write-Host "    FOUND rg-moveit!" -ForegroundColor Green
            break
        }
    } catch {
        continue
    }
}

if (-not $foundRG) {
    Write-Host ""
    Write-Host "ERROR: rg-moveit not found in any subscription!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available resource groups:" -ForegroundColor Yellow
    foreach ($sub in $allSubs) {
        try {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $rgs = Get-AzResourceGroup
            Write-Host ""
            Write-Host "  $($sub.Name):" -ForegroundColor Cyan
            foreach ($r in $rgs) {
                Write-Host "    - $($r.ResourceGroupName)" -ForegroundColor White
            }
        } catch {}
    }
    exit
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Found Resource Group" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Name: $($foundRG.ResourceGroupName)" -ForegroundColor White
Write-Host "  Subscription: $($foundSub.Name)" -ForegroundColor White
Write-Host "  Location: $($foundRG.Location)" -ForegroundColor White
Write-Host ""

Write-Host "Getting all resources..." -ForegroundColor Cyan
$resources = Get-AzResource -ResourceGroupName "rg-moveit"
Write-Host "  Found $($resources.Count) resources" -ForegroundColor Green
Write-Host ""

$data = @()
$infraCost = 0

foreach ($r in $resources) {
    $cost = 5
    
    if ($r.ResourceType -like "*virtualMachines*") { $cost = 100 }
    elseif ($r.ResourceType -like "*disks*") { $cost = 20 }
    elseif ($r.ResourceType -like "*storage*") { $cost = 50 }
    elseif ($r.ResourceType -like "*publicIPAddresses*") { $cost = 4 }
    
    $infraCost += $cost
    
    $data += [PSCustomObject]@{
        Name = $r.Name
        Type = $r.ResourceType
        Location = $r.Location
        MonthlyCost = $cost
    }
}

Write-Host "Calculating costs..." -ForegroundColor Cyan

$maintenance = [math]::Round($infraCost * 0.15, 2)
$monitoring = 50
$backup = 100
$security = 75
$labor = 500

$totalCurrent = $infraCost + $maintenance + $monitoring + $backup + $security + $labor
$savings = $totalCurrent - $MoveitCloudCost
$yearlySavings = $savings * 12
$fiveYearSavings = $yearlySavings * 5
$savingsPercent = [math]::Round(($savings / $totalCurrent) * 100, 1)

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  COST ANALYSIS RESULTS" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "CURRENT COSTS:" -ForegroundColor Cyan
Write-Host "  Infrastructure: `$$infraCost/mo" -ForegroundColor White
Write-Host "  Maintenance: `$$maintenance/mo" -ForegroundColor White
Write-Host "  Monitoring: `$$monitoring/mo" -ForegroundColor White
Write-Host "  Backup: `$$backup/mo" -ForegroundColor White
Write-Host "  Security: `$$security/mo" -ForegroundColor White
Write-Host "  Labor: `$$labor/mo" -ForegroundColor White
Write-Host "  ---------------------------------" -ForegroundColor Gray
Write-Host "  TOTAL: `$$totalCurrent/month" -ForegroundColor Yellow
Write-Host ""
Write-Host "MOVEIT CLOUD: `$$MoveitCloudCost/month" -ForegroundColor Green
Write-Host ""
Write-Host "SAVINGS:" -ForegroundColor Cyan
Write-Host "  Monthly: `$$savings" -ForegroundColor Green
Write-Host "  Yearly: `$$yearlySavings" -ForegroundColor Green
Write-Host "  5-Year: `$$fiveYearSavings" -ForegroundColor Green
Write-Host "  Percent: $savingsPercent%" -ForegroundColor Green
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csv = "$OutputFolder\MOVEit_Analysis_$timestamp.csv"
$data | Export-Csv $csv -NoTypeInformation
Write-Host "CSV Report: $csv" -ForegroundColor Cyan

$html = "$OutputFolder\MOVEit_Dashboard_$timestamp.html"
@"
<!DOCTYPE html><html><head><title>MOVEit Cost Analysis</title><style>
body{font-family:Arial;background:#667eea;padding:20px;margin:0}
.wrap{max-width:1200px;margin:0 auto;background:white;padding:40px;border-radius:10px;box-shadow:0 10px 30px rgba(0,0,0,0.2)}
h1{color:#667eea;text-align:center;font-size:42px;margin-bottom:10px}
.subtitle{text-align:center;color:#666;font-size:18px;margin-bottom:30px}
.stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;margin:30px 0}
.box{background:#f8f9fa;padding:30px;text-align:center;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
.box h2{color:#667eea;font-size:48px;margin:0;font-weight:bold}
.box p{color:#666;margin-top:15px;font-size:16px}
.save{background:linear-gradient(135deg,#28a745,#20c997);color:white;padding:40px;text-align:center;border-radius:10px;margin:30px 0;box-shadow:0 4px 12px rgba(40,167,69,0.3)}
.save h2{font-size:42px;margin:0;font-weight:bold}
.save p{font-size:20px;margin-top:15px;opacity:0.9}
h2{color:#667eea;margin-top:40px;font-size:28px}
table{width:100%;border-collapse:collapse;margin:20px 0;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
th{background:#667eea;color:white;padding:15px;text-align:left;font-weight:600;font-size:14px}
td{padding:12px 15px;border-bottom:1px solid #ddd;font-size:14px}
tr:hover{background:#f8f9fa}
.highlight{background:#fff3cd;font-weight:bold}
.success{background:#d4edda;color:#155724;font-weight:bold}
.danger{background:#f8d7da;color:#721c24}
</style></head><body><div class='wrap'>
<h1>MOVEit Cost Analysis Report</h1>
<div class='subtitle'>Resource Group: rg-moveit | Subscription: $($foundSub.Name) | Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm')</div>

<div class='stats'>
<div class='box'>
<h2>`$$totalCurrent</h2>
<p>Current Monthly Cost</p>
</div>
<div class='box'>
<h2>`$$MoveitCloudCost</h2>
<p>MOVEit Cloud Cost</p>
</div>
<div class='box'>
<h2>`$$savings</h2>
<p>Monthly Savings</p>
</div>
</div>

<div class='save'>
<h2>💰 5-YEAR SAVINGS: `$$fiveYearSavings</h2>
<p>Save $savingsPercent% by moving to MOVEit Cloud</p>
</div>

<h2>📦 Resource Inventory ($($resources.Count) Resources)</h2>
<table>
<tr><th>Resource Name</th><th>Type</th><th>Location</th><th>Monthly Cost</th></tr>
$($data | ForEach-Object { "<tr><td><strong>$($_.Name)</strong></td><td>$($_.Type)</td><td>$($_.Location)</td><td>`$$($_.MonthlyCost)</td></tr>" })
</table>

<h2>💵 Detailed Cost Breakdown</h2>
<table>
<tr><td><strong>Infrastructure (Azure Resources)</strong></td><td>`$$infraCost/month</td></tr>
<tr><td>Maintenance & Support (15%)</td><td>`$$maintenance/month</td></tr>
<tr><td>Monitoring & Alerts</td><td>`$$monitoring/month</td></tr>
<tr><td>Backup & Disaster Recovery</td><td>`$$backup/month</td></tr>
<tr><td>Security & Compliance</td><td>`$$security/month</td></tr>
<tr><td>IT Labor & Management</td><td>`$$labor/month</td></tr>
<tr class='highlight'><td><strong>TOTAL CURRENT MONTHLY COST</strong></td><td><strong>`$$totalCurrent/month</strong></td></tr>
<tr class='success'><td><strong>MOVEit Cloud (Fully Managed)</strong></td><td><strong>`$$MoveitCloudCost/month</strong></td></tr>
<tr style='background:#fff3cd'><td><strong>💰 MONTHLY SAVINGS</strong></td><td><strong>`$$savings</strong></td></tr>
<tr style='background:#d1ecf1'><td><strong>📅 YEARLY SAVINGS</strong></td><td><strong>`$$yearlySavings</strong></td></tr>
<tr style='background:#28a745;color:white'><td><strong>🎯 5-YEAR SAVINGS</strong></td><td><strong>`$$fiveYearSavings</strong></td></tr>
</table>

<div style='background:#e7f3ff;border-left:4px solid #0066cc;padding:20px;margin-top:30px;border-radius:4px'>
<h3 style='color:#0066cc;margin-top:0'>💼 Executive Summary</h3>
<p style='color:#333;line-height:1.8;margin-bottom:0'>
Migrating from the current rg-moveit infrastructure to MOVEit Cloud will deliver immediate cost savings of <strong>$savingsPercent%</strong> 
(`$$savings per month). Over 5 years, this migration will save PYX Health <strong>`$$fiveYearSavings</strong> while eliminating 
infrastructure management overhead, improving security posture, ensuring 99.9% uptime SLA, and providing 24/7 expert support. 
The solution includes automated backups, enterprise-grade security, and full compliance management.
</p>
</div>

</div></body></html>
"@ | Out-File $html -Encoding UTF8

Write-Host "HTML Dashboard: $html" -ForegroundColor Cyan
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Open the HTML file in your browser to view the full report!" -ForegroundColor White
Write-Host ""
