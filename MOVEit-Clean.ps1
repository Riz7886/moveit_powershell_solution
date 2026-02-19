param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-moveit",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "730dd182-eb99-4f54-8f4c-698a5338013f",
    
    [Parameter(Mandatory=$false)]
    [decimal]$MoveitCloudMonthlyCost = 2500,
    
    [Parameter(Mandatory=$false)]
    [int]$LookbackMonths = 3,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFolder = "Reports"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  MOVEIT COST ANALYSIS REPORT" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "Subscription: $SubscriptionId" -ForegroundColor White
Write-Host ""

function Install-Modules {
    Write-Host "Checking Azure modules..." -ForegroundColor Cyan
    
    $modules = @("Az.Accounts", "Az.Resources", "Az.Compute")
    
    foreach ($module in $modules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "  Installing $module..." -ForegroundColor Yellow
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  Modules OK" -ForegroundColor Green
    Write-Host ""
}

function Connect-Azure {
    Write-Host "Connecting to Azure..." -ForegroundColor Cyan
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        
        Write-Host "  Connected successfully" -ForegroundColor Green
        Write-Host ""
        return $true
    } catch {
        Write-Host "  Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-Resources {
    Write-Host "Getting resources from $ResourceGroupName..." -ForegroundColor Cyan
    
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        Write-Host "  Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Green
        Write-Host "  Location: $($rg.Location)" -ForegroundColor Green
        Write-Host ""
        
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        Write-Host "  Found $($resources.Count) resources" -ForegroundColor Green
        Write-Host ""
        
        $inventory = @()
        
        foreach ($resource in $resources) {
            $cost = 0
            
            if ($resource.ResourceType -like "*virtualMachines*") {
                $cost = 100
            } elseif ($resource.ResourceType -like "*disks*") {
                $cost = 20
            } elseif ($resource.ResourceType -like "*storageAccounts*") {
                $cost = 50
            } elseif ($resource.ResourceType -like "*publicIPAddresses*") {
                $cost = 4
            } else {
                $cost = 5
            }
            
            $item = [PSCustomObject]@{
                Name = $resource.Name
                Type = $resource.ResourceType
                Location = $resource.Location
                EstimatedCost = $cost
            }
            
            $inventory += $item
        }
        
        return $inventory
        
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        Write-Host ""
        Write-Host "  Listing all resource groups..." -ForegroundColor Yellow
        try {
            $allRGs = Get-AzResourceGroup
            foreach ($g in $allRGs) {
                Write-Host "    - $($g.ResourceGroupName)" -ForegroundColor White
            }
        } catch {}
        
        return @()
    }
}

function Calculate-Costs {
    param($Inventory)
    
    Write-Host "Calculating costs..." -ForegroundColor Cyan
    
    $infraCost = ($Inventory | Measure-Object -Property EstimatedCost -Sum).Sum
    $maintenanceCost = [math]::Round($infraCost * 0.15, 2)
    $monitoringCost = 50
    $backupCost = 100
    $securityCost = 75
    $laborCost = 500
    
    $totalCurrent = $infraCost + $maintenanceCost + $monitoringCost + $backupCost + $securityCost + $laborCost
    
    $monthlySavings = $totalCurrent - $MoveitCloudMonthlyCost
    $yearlySavings = $monthlySavings * 12
    $threeYearSavings = $yearlySavings * 3
    $fiveYearSavings = $yearlySavings * 5
    
    $savingsPercent = [math]::Round(($monthlySavings / $totalCurrent) * 100, 1)
    
    Write-Host ""
    Write-Host "  Infrastructure: `$$infraCost/mo" -ForegroundColor White
    Write-Host "  Maintenance: `$$maintenanceCost/mo" -ForegroundColor White
    Write-Host "  Monitoring: `$$monitoringCost/mo" -ForegroundColor White
    Write-Host "  Backup: `$$backupCost/mo" -ForegroundColor White
    Write-Host "  Security: `$$securityCost/mo" -ForegroundColor White
    Write-Host "  Labor: `$$laborCost/mo" -ForegroundColor White
    Write-Host "  -------------------------------" -ForegroundColor Gray
    Write-Host "  TOTAL CURRENT: `$$totalCurrent/mo" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  MOVEit Cloud: `$$MoveitCloudMonthlyCost/mo" -ForegroundColor Green
    Write-Host ""
    Write-Host "  MONTHLY SAVINGS: `$$monthlySavings" -ForegroundColor Green
    Write-Host "  YEARLY SAVINGS: `$$yearlySavings" -ForegroundColor Green
    Write-Host "  5-YEAR SAVINGS: `$$fiveYearSavings" -ForegroundColor Green
    Write-Host "  SAVINGS PERCENT: $savingsPercent%" -ForegroundColor Green
    Write-Host ""
    
    return @{
        InfraCost = $infraCost
        MaintenanceCost = $maintenanceCost
        MonitoringCost = $monitoringCost
        BackupCost = $backupCost
        SecurityCost = $securityCost
        LaborCost = $laborCost
        TotalCurrent = $totalCurrent
        CloudCost = $MoveitCloudMonthlyCost
        MonthlySavings = $monthlySavings
        YearlySavings = $yearlySavings
        ThreeYearSavings = $threeYearSavings
        FiveYearSavings = $fiveYearSavings
        SavingsPercent = $savingsPercent
    }
}

function Export-CSV {
    param($Inventory, $Costs)
    
    $csvPath = Join-Path $OutputFolder "MOVEit_Analysis_$timestamp.csv"
    
    $data = @()
    
    foreach ($item in $Inventory) {
        $data += $item
    }
    
    $data += [PSCustomObject]@{
        Name = "CURRENT TOTAL"
        Type = ""
        Location = ""
        EstimatedCost = $Costs.TotalCurrent
    }
    
    $data += [PSCustomObject]@{
        Name = "MOVEIT CLOUD"
        Type = ""
        Location = ""
        EstimatedCost = $Costs.CloudCost
    }
    
    $data += [PSCustomObject]@{
        Name = "MONTHLY SAVINGS"
        Type = ""
        Location = ""
        EstimatedCost = $Costs.MonthlySavings
    }
    
    $data | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "  CSV: $csvPath" -ForegroundColor Green
    
    return $csvPath
}

function Export-HTML {
    param($Inventory, $Costs)
    
    $htmlPath = Join-Path $OutputFolder "MOVEit_Dashboard_$timestamp.html"
    
    $resourceCount = $Inventory.Count
    $reportDate = Get-Date -Format "MMMM dd, yyyy HH:mm:ss"
    
    $html = "<!DOCTYPE html><html><head><title>MOVEit Cost Analysis</title><meta charset=`"UTF-8`"><style>"
    $html += "body{font-family:Arial;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px;margin:0}"
    $html += ".container{max-width:1600px;margin:0 auto;background:white;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}"
    $html += ".header{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:40px;text-align:center}"
    $html += ".header h1{font-size:42px;margin:0 0 10px 0}"
    $html += ".stats{display:grid;grid-template-columns:repeat(4,1fr);gap:20px;padding:40px;background:#f8f9fa}"
    $html += ".stat{background:white;padding:25px;border-radius:8px;text-align:center}"
    $html += ".stat-num{font-size:48px;font-weight:bold;color:#667eea}"
    $html += ".stat-label{font-size:14px;color:#666;text-transform:uppercase}"
    $html += ".comparison{padding:40px}"
    $html += ".cost-row{display:flex;justify-content:space-between;padding:15px;border-bottom:1px solid #ddd}"
    $html += ".savings{background:#28a745;color:white;padding:40px;text-align:center;margin:40px}"
    $html += ".savings h2{font-size:36px;margin:0}"
    $html += "table{width:100%;border-collapse:collapse;margin:20px 0}"
    $html += "th{background:#667eea;color:white;padding:15px;text-align:left}"
    $html += "td{padding:12px;border-bottom:1px solid #ddd}"
    $html += "</style></head><body><div class=`"container`">"
    
    $html += "<div class=`"header`"><h1>MOVEIT COST ANALYSIS</h1><p>Resource Group: $ResourceGroupName</p><p>Generated: $reportDate</p></div>"
    
    $html += "<div class=`"stats`">"
    $html += "<div class=`"stat`"><div class=`"stat-num`">$resourceCount</div><div class=`"stat-label`">Resources</div></div>"
    $html += "<div class=`"stat`"><div class=`"stat-num`" style=`"color:#dc3545`">`$$($Costs.TotalCurrent)</div><div class=`"stat-label`">Current Cost</div></div>"
    $html += "<div class=`"stat`"><div class=`"stat-num`" style=`"color:#28a745`">`$$($Costs.CloudCost)</div><div class=`"stat-label`">Cloud Cost</div></div>"
    $html += "<div class=`"stat`"><div class=`"stat-num`" style=`"color:#ffc107`">`$$($Costs.MonthlySavings)</div><div class=`"stat-label`">Monthly Savings</div></div>"
    $html += "</div>"
    
    $html += "<div class=`"comparison`"><h2>Cost Breakdown</h2>"
    $html += "<div class=`"cost-row`"><span>Infrastructure</span><span>`$$($Costs.InfraCost)</span></div>"
    $html += "<div class=`"cost-row`"><span>Maintenance</span><span>`$$($Costs.MaintenanceCost)</span></div>"
    $html += "<div class=`"cost-row`"><span>Monitoring</span><span>`$$($Costs.MonitoringCost)</span></div>"
    $html += "<div class=`"cost-row`"><span>Backup</span><span>`$$($Costs.BackupCost)</span></div>"
    $html += "<div class=`"cost-row`"><span>Security</span><span>`$$($Costs.SecurityCost)</span></div>"
    $html += "<div class=`"cost-row`"><span>Labor</span><span>`$$($Costs.LaborCost)</span></div>"
    $html += "<div class=`"cost-row`" style=`"border-top:2px solid #667eea`"><strong>TOTAL</strong><strong>`$$($Costs.TotalCurrent)</strong></div>"
    $html += "</div>"
    
    $html += "<div class=`"savings`"><h2>5-YEAR SAVINGS: `$$($Costs.FiveYearSavings)</h2><p>Save $($Costs.SavingsPercent)% by moving to MOVEit Cloud</p></div>"
    
    $html += "<div style=`"padding:40px`"><h2>Resource Inventory</h2><table><thead><tr><th>Name</th><th>Type</th><th>Location</th><th>Cost</th></tr></thead><tbody>"
    
    foreach ($item in $Inventory) {
        $html += "<tr><td>$($item.Name)</td><td>$($item.Type)</td><td>$($item.Location)</td><td>`$$($item.EstimatedCost)</td></tr>"
    }
    
    $html += "</tbody></table></div></div></body></html>"
    
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "  HTML: $htmlPath" -ForegroundColor Green
    
    return $htmlPath
}

Install-Modules

if (-not (Connect-Azure)) {
    Write-Host "Cannot connect to Azure. Exiting." -ForegroundColor Red
    exit 1
}

$inventory = Get-Resources

if ($inventory.Count -eq 0) {
    Write-Host "No resources found. Exiting." -ForegroundColor Red
    exit 1
}

$costs = Calculate-Costs -Inventory $inventory

Write-Host "Generating reports..." -ForegroundColor Cyan
$csvPath = Export-CSV -Inventory $inventory -Costs $costs
$htmlPath = Export-HTML -Inventory $inventory -Costs $costs

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  COMPLETE!" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Reports saved:" -ForegroundColor White
Write-Host "  $csvPath" -ForegroundColor Cyan
Write-Host "  $htmlPath" -ForegroundColor Cyan
Write-Host ""

Disconnect-AzAccount | Out-Null
