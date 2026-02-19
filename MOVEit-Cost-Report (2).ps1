# MOVEit Cost Analysis Report
# Run this after: Connect-AzAccount

$RG = "rg-moveit"
$SubId = "730dd182-eb99-4f54-8f4c-698a5338013f"
$CloudCost = 2500
$Output = "Reports"

if (-not (Test-Path $Output)) { mkdir $Output -Force | Out-Null }

Write-Host "`n=== MOVEIT COST ANALYSIS ===" -ForegroundColor Cyan
Write-Host "Resource Group: $RG`n" -ForegroundColor White

Set-AzContext -SubscriptionId $SubId | Out-Null

$resources = Get-AzResource -ResourceGroupName $RG

if (-not $resources) {
    Write-Host "ERROR: No resources found" -ForegroundColor Red
    Get-AzResourceGroup | Select-Object ResourceGroupName | Format-Table -AutoSize
    exit
}

Write-Host "Found $($resources.Count) resources`n" -ForegroundColor Green

$data = @()
$infraCost = 0

foreach ($r in $resources) {
    $cost = 5
    if ($r.ResourceType -like "*virtualMachines*") { $cost = 100 }
    elseif ($r.ResourceType -like "*disks*") { $cost = 20 }
    elseif ($r.ResourceType -like "*storage*") { $cost = 50 }
    
    $infraCost += $cost
    $data += [PSCustomObject]@{
        Name = $r.Name
        Type = $r.ResourceType
        Location = $r.Location
        MonthlyCost = $cost
    }
}

$maintenance = [math]::Round($infraCost * 0.15, 2)
$total = $infraCost + $maintenance + 50 + 100 + 75 + 500
$savings = $total - $CloudCost
$fiveYear = $savings * 60

Write-Host "=== RESULTS ===" -ForegroundColor Green
Write-Host "Current Cost: `$$total/mo" -ForegroundColor Yellow
Write-Host "Cloud Cost: `$$CloudCost/mo" -ForegroundColor Green
Write-Host "Monthly Savings: `$$savings" -ForegroundColor Cyan
Write-Host "5-Year Savings: `$$fiveYear`n" -ForegroundColor Cyan

$csv = "$Output\MOVEit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$data | Export-Csv $csv -NoTypeInformation
Write-Host "Saved: $csv" -ForegroundColor Green

$html = "$Output\MOVEit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
@"
<!DOCTYPE html><html><head><title>MOVEit Analysis</title><style>
body{font-family:Arial;background:#667eea;padding:20px;margin:0}
.wrap{max-width:1200px;margin:0 auto;background:white;padding:40px;border-radius:10px}
h1{color:#667eea;text-align:center}
.stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:20px;margin:30px 0}
.box{background:#f8f9fa;padding:25px;text-align:center;border-radius:8px}
.box h2{color:#667eea;font-size:42px;margin:0}
.box p{color:#666;margin-top:10px}
.save{background:#28a745;color:white;padding:30px;text-align:center;border-radius:8px;margin:30px 0}
.save h2{font-size:36px;margin:0}
table{width:100%;border-collapse:collapse;margin:20px 0}
th{background:#667eea;color:white;padding:12px;text-align:left}
td{padding:10px;border-bottom:1px solid #ddd}
tr:hover{background:#f8f9fa}
</style></head><body><div class='wrap'>
<h1>MOVEit Cost Analysis</h1>
<p style='text-align:center;color:#666'>$RG | $(Get-Date -Format 'MMMM dd, yyyy')</p>
<div class='stats'>
<div class='box'><h2>`$$total</h2><p>Current Monthly</p></div>
<div class='box'><h2>`$$CloudCost</h2><p>Cloud Cost</p></div>
<div class='box'><h2>`$$savings</h2><p>Savings/Month</p></div>
</div>
<div class='save'><h2>5-YEAR SAVINGS: `$$fiveYear</h2></div>
<h2>Resources ($($resources.Count))</h2>
<table><tr><th>Name</th><th>Type</th><th>Cost</th></tr>
$($data | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Type)</td><td>`$$($_.MonthlyCost)</td></tr>" })
</table>
<h2>Cost Breakdown</h2>
<table>
<tr><td>Infrastructure</td><td>`$$infraCost</td></tr>
<tr><td>Maintenance</td><td>`$$maintenance</td></tr>
<tr><td>Monitoring</td><td>`$50</td></tr>
<tr><td>Backup</td><td>`$100</td></tr>
<tr><td>Security</td><td>`$75</td></tr>
<tr><td>Labor</td><td>`$500</td></tr>
<tr style='background:#f8f9fa'><td><strong>TOTAL</strong></td><td><strong>`$$total</strong></td></tr>
<tr style='background:#d4edda'><td><strong>Cloud</strong></td><td><strong>`$$CloudCost</strong></td></tr>
<tr style='background:#28a745;color:white'><td><strong>SAVINGS</strong></td><td><strong>`$$savings/mo</strong></td></tr>
</table></div></body></html>
"@ | Out-File $html -Encoding UTF8

Write-Host "Saved: $html`n" -ForegroundColor Green
Write-Host "DONE!`n" -ForegroundColor Green
