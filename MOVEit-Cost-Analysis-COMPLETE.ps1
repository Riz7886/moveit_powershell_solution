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
Write-Host "  MOVEIT COST ANALYSIS - CLOUD MIGRATION REPORT" -ForegroundColor Yellow
Write-Host "  Comparing rg-moveit to MOVEit Cloud" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

function Install-RequiredModules {
    Write-Host "[1/6] Checking Azure modules..." -ForegroundColor Cyan
    
    $modules = @(
        "Az.Accounts",
        "Az.Resources",
        "Az.Compute",
        "Az.Storage",
        "Az.Network",
        "Az.CostManagement"
    )
    
    foreach ($module in $modules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "  Installing $module..." -ForegroundColor Yellow
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        } else {
            Write-Host "  $module - OK" -ForegroundColor Green
        }
    }
    
    Write-Host ""
}

function Connect-ToAzure {
    Write-Host "[2/6] Connecting to Azure..." -ForegroundColor Cyan
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Write-Host "  Opening browser for authentication..." -ForegroundColor Yellow
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        
        $context = Get-AzContext
        Write-Host "  Connected as: $($context.Account.Id)" -ForegroundColor Green
        
        Write-Host "  Setting subscription: $SubscriptionId" -ForegroundColor White
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        
        Write-Host "  Subscription set: sub-product-prod" -ForegroundColor Green
        Write-Host ""
        return $true
    } catch {
        Write-Host "  ERROR: Failed to connect to Azure" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-ResourceGroupDetails {
    Write-Host "[3/6] Getting rg-moveit resource group details..." -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        Write-Host "  Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Green
        Write-Host "  Location: $($rg.Location)" -ForegroundColor White
        Write-Host "  Subscription: sub-product-prod" -ForegroundColor White
        Write-Host ""
        
        return $rg
    } catch {
        Write-Host "  ERROR: Could not find resource group $ResourceGroupName" -ForegroundColor Red
        return $null
    }
}

function Get-AllResources {
    Write-Host "[4/6] Inventorying all resources in rg-moveit..." -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        Write-Host "  Total resources found: $($resources.Count)" -ForegroundColor Green
        Write-Host ""
        
        $inventory = @()
        
        foreach ($resource in $resources) {
            Write-Host "  Processing: $($resource.Name)" -ForegroundColor Gray
            
            $resourceDetails = [PSCustomObject]@{
                Name = $resource.Name
                Type = $resource.ResourceType
                Location = $resource.Location
                SKU = "N/A"
                Size = "N/A"
                State = "N/A"
                EstimatedMonthlyCost = 0
            }
            
            switch -Wildcard ($resource.ResourceType) {
                "*virtualMachines*" {
                    try {
                        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $resource.Name -ErrorAction SilentlyContinue
                        if ($vm) {
                            $resourceDetails.Size = $vm.HardwareProfile.VmSize
                            $resourceDetails.State = $vm.PowerState
                            
                            switch ($vm.HardwareProfile.VmSize) {
                                "Standard_D2s_v3" { $resourceDetails.EstimatedMonthlyCost = 70 }
                                "Standard_D4s_v3" { $resourceDetails.EstimatedMonthlyCost = 140 }
                                "Standard_D8s_v3" { $resourceDetails.EstimatedMonthlyCost = 280 }
                                "Standard_D16s_v3" { $resourceDetails.EstimatedMonthlyCost = 560 }
                                "Standard_E4s_v3" { $resourceDetails.EstimatedMonthlyCost = 175 }
                                "Standard_E8s_v3" { $resourceDetails.EstimatedMonthlyCost = 350 }
                                default { $resourceDetails.EstimatedMonthlyCost = 100 }
                            }
                        }
                    } catch {}
                }
                "*disks*" {
                    try {
                        $disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $resource.Name -ErrorAction SilentlyContinue
                        if ($disk) {
                            $resourceDetails.SKU = $disk.Sku.Name
                            $resourceDetails.Size = "$($disk.DiskSizeGB) GB"
                            
                            $sizeGB = $disk.DiskSizeGB
                            if ($disk.Sku.Name -like "*Premium*") {
                                $resourceDetails.EstimatedMonthlyCost = [math]::Round($sizeGB * 0.135, 2)
                            } else {
                                $resourceDetails.EstimatedMonthlyCost = [math]::Round($sizeGB * 0.05, 2)
                            }
                        }
                    } catch {}
                }
                "*publicIPAddresses*" {
                    $resourceDetails.EstimatedMonthlyCost = 3.65
                }
                "*networkInterfaces*" {
                    $resourceDetails.EstimatedMonthlyCost = 0
                }
                "*storageAccounts*" {
                    $resourceDetails.EstimatedMonthlyCost = 50
                }
                "*automation*" {
                    $resourceDetails.EstimatedMonthlyCost = 10
                }
                "*workbooks*" {
                    $resourceDetails.EstimatedMonthlyCost = 0
                }
                "*encryption*" {
                    $resourceDetails.EstimatedMonthlyCost = 5
                }
                "*networkSecurityGroups*" {
                    $resourceDetails.EstimatedMonthlyCost = 0
                }
                default {
                    $resourceDetails.EstimatedMonthlyCost = 5
                }
            }
            
            $inventory += $resourceDetails
        }
        
        Write-Host ""
        Write-Host "  Inventory complete: $($inventory.Count) resources cataloged" -ForegroundColor Green
        Write-Host ""
        
        return $inventory
    } catch {
        Write-Host "  ERROR: Failed to inventory resources" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Get-ActualCosts {
    Write-Host "[5/6] Getting actual Azure costs (last $LookbackMonths months)..." -ForegroundColor Cyan
    Write-Host ""
    
    try {
        $endDate = Get-Date
        $startDate = $endDate.AddMonths(-$LookbackMonths)
        
        Write-Host "  Querying costs from $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
        
        $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
        $scope = "/subscriptions/$($subscription.Id)/resourceGroups/$ResourceGroupName"
        
        $costData = Get-AzCostManagementUsageDetail -Scope $scope `
            -StartDate $startDate.ToString('yyyy-MM-dd') `
            -EndDate $endDate.ToString('yyyy-MM-dd') `
            -ErrorAction SilentlyContinue
        
        if ($costData) {
            $totalCost = ($costData | Measure-Object -Property Cost -Sum).Sum
            $avgMonthlyCost = [math]::Round($totalCost / $LookbackMonths, 2)
            
            Write-Host "  Total cost (last $LookbackMonths months): `$$totalCost" -ForegroundColor Green
            Write-Host "  Average monthly cost: `$$avgMonthlyCost" -ForegroundColor Green
            Write-Host ""
            
            return $avgMonthlyCost
        } else {
            Write-Host "  Could not retrieve actual cost data from Azure Cost Management" -ForegroundColor Yellow
            Write-Host "  Will use estimated costs instead" -ForegroundColor Yellow
            Write-Host ""
            return $null
        }
    } catch {
        Write-Host "  Could not retrieve cost data: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Will use estimated costs instead" -ForegroundColor Yellow
        Write-Host ""
        return $null
    }
}

function Calculate-TotalCosts {
    param($Inventory, $ActualMonthlyCost)
    
    Write-Host "[6/6] Calculating total costs and savings..." -ForegroundColor Cyan
    Write-Host ""
    
    $estimatedInfrastructureCost = ($Inventory | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
    
    if ($ActualMonthlyCost) {
        $currentMonthlyCost = $ActualMonthlyCost
        Write-Host "  Using ACTUAL cost data from Azure" -ForegroundColor Green
    } else {
        $currentMonthlyCost = $estimatedInfrastructureCost
        Write-Host "  Using ESTIMATED cost data" -ForegroundColor Yellow
    }
    
    $maintenanceCost = [math]::Round($currentMonthlyCost * 0.15, 2)
    $monitoringCost = 50
    $backupCost = 100
    $securityCost = 75
    $laborCost = 500
    
    $totalCurrentMonthlyCost = $currentMonthlyCost + $maintenanceCost + $monitoringCost + $backupCost + $securityCost + $laborCost
    
    $monthlySavings = $totalCurrentMonthlyCost - $MoveitCloudMonthlyCost
    $yearlySavings = $monthlySavings * 12
    $threeYearSavings = $yearlySavings * 3
    $fiveYearSavings = $yearlySavings * 5
    
    $savingsPercentage = [math]::Round(($monthlySavings / $totalCurrentMonthlyCost) * 100, 1)
    
    Write-Host "  Current Infrastructure Cost: `$$currentMonthlyCost/month" -ForegroundColor White
    Write-Host "  + Maintenance (15%): `$$maintenanceCost/month" -ForegroundColor White
    Write-Host "  + Monitoring: `$$monitoringCost/month" -ForegroundColor White
    Write-Host "  + Backup: `$$backupCost/month" -ForegroundColor White
    Write-Host "  + Security: `$$securityCost/month" -ForegroundColor White
    Write-Host "  + Labor (IT management): `$$laborCost/month" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor Gray
    Write-Host "  TOTAL CURRENT COST: `$$totalCurrentMonthlyCost/month" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  MOVEit Cloud Cost: `$$MoveitCloudMonthlyCost/month" -ForegroundColor Green
    Write-Host ""
    Write-Host "  MONTHLY SAVINGS: `$$monthlySavings ($savingsPercentage%)" -ForegroundColor Green
    Write-Host "  YEARLY SAVINGS: `$$yearlySavings" -ForegroundColor Green
    Write-Host "  3-YEAR SAVINGS: `$$threeYearSavings" -ForegroundColor Green
    Write-Host "  5-YEAR SAVINGS: `$$fiveYearSavings" -ForegroundColor Green
    Write-Host ""
    
    return @{
        CurrentInfrastructureCost = $currentMonthlyCost
        MaintenanceCost = $maintenanceCost
        MonitoringCost = $monitoringCost
        BackupCost = $backupCost
        SecurityCost = $securityCost
        LaborCost = $laborCost
        TotalCurrentMonthlyCost = $totalCurrentMonthlyCost
        MoveitCloudMonthlyCost = $MoveitCloudMonthlyCost
        MonthlySavings = $monthlySavings
        YearlySavings = $yearlySavings
        ThreeYearSavings = $threeYearSavings
        FiveYearSavings = $fiveYearSavings
        SavingsPercentage = $savingsPercentage
    }
}

function Export-ToCSV {
    param($Inventory, $CostAnalysis)
    
    $csvPath = Join-Path $OutputFolder "MOVEit_Cost_Analysis_$timestamp.csv"
    
    $reportData = @()
    
    foreach ($item in $Inventory) {
        $reportData += [PSCustomObject]@{
            ResourceName = $item.Name
            ResourceType = $item.Type
            Location = $item.Location
            Size = $item.Size
            SKU = $item.SKU
            State = $item.State
            EstimatedMonthlyCost = $item.EstimatedMonthlyCost
        }
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "--- COST SUMMARY ---"
        ResourceType = ""
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = ""
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "Current Infrastructure"
        ResourceType = "Azure Resources"
        Location = "West US"
        Size = "$($Inventory.Count) resources"
        SKU = ""
        State = "Active"
        EstimatedMonthlyCost = $CostAnalysis.CurrentInfrastructureCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "Maintenance & Support"
        ResourceType = "Operational Cost"
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.MaintenanceCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "Monitoring & Alerts"
        ResourceType = "Operational Cost"
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.MonitoringCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "Backup & DR"
        ResourceType = "Operational Cost"
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.BackupCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "Security & Compliance"
        ResourceType = "Operational Cost"
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.SecurityCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "IT Labor & Management"
        ResourceType = "Operational Cost"
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.LaborCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "TOTAL CURRENT COST"
        ResourceType = ""
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.TotalCurrentMonthlyCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "MOVEit Cloud Cost"
        ResourceType = "Cloud Solution"
        Location = "Multi-Region"
        Size = "Managed"
        SKU = "Cloud"
        State = "Proposed"
        EstimatedMonthlyCost = $CostAnalysis.MoveitCloudMonthlyCost
    }
    
    $reportData += [PSCustomObject]@{
        ResourceName = "MONTHLY SAVINGS"
        ResourceType = ""
        Location = ""
        Size = ""
        SKU = ""
        State = ""
        EstimatedMonthlyCost = $CostAnalysis.MonthlySavings
    }
    
    $reportData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "  CSV exported: $csvPath" -ForegroundColor Green
    
    return $csvPath
}

function Export-ToHTML {
    param($Inventory, $CostAnalysis, $ResourceGroup)
    
    $htmlPath = Join-Path $OutputFolder "MOVEit_Cost_Analysis_Dashboard_$timestamp.html"
    
    $resourceCount = $Inventory.Count
    $totalVMs = ($Inventory | Where-Object { $_.Type -like "*virtualMachines*" }).Count
    $totalDisks = ($Inventory | Where-Object { $_.Type -like "*disks*" }).Count
    $totalStorage = ($Inventory | Where-Object { $_.Type -like "*storageAccounts*" }).Count
    
$html = @"
<!DOCTYPE html>
<html>
<head>
<title>MOVEit Cost Analysis Report</title>
<meta charset="UTF-8">
<style>
body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);padding:20px;margin:0}
.container{max-width:1800px;margin:0 auto;background:white;border-radius:10px;box-shadow:0 10px 40px rgba(0,0,0,0.2)}
.header{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;padding:40px;text-align:center}
.header h1{font-size:42px;margin:0 0 10px 0}
.header p{font-size:18px;margin:5px 0}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;padding:40px;background:#f8f9fa}
.summary-card{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1);text-align:center}
.summary-number{font-size:48px;font-weight:bold;margin-bottom:10px}
.summary-number.current{color:#dc3545}
.summary-number.cloud{color:#28a745}
.summary-number.savings{color:#ffc107}
.summary-label{font-size:14px;color:#666;text-transform:uppercase}
.comparison{padding:40px;background:white}
.comparison h2{color:#2c3e50;margin-bottom:30px;font-size:32px;text-align:center}
.comparison-table{display:grid;grid-template-columns:1fr 1fr;gap:30px;margin-bottom:40px}
.cost-box{background:#f8f9fa;padding:25px;border-radius:8px;border-left:4px solid #667eea}
.cost-box h3{margin:0 0 20px 0;color:#2c3e50;font-size:24px}
.cost-item{display:flex;justify-content:space-between;padding:12px 0;border-bottom:1px solid #ddd}
.cost-item:last-child{border-bottom:none;padding-top:15px;margin-top:15px;border-top:2px solid #667eea}
.cost-label{font-weight:500;color:#555}
.cost-value{font-weight:bold;color:#2c3e50}
.savings-highlight{background:linear-gradient(135deg,#28a745 0%,#20c997 100%);color:white;padding:40px;text-align:center;margin:40px;border-radius:10px}
.savings-highlight h2{font-size:36px;margin:0 0 20px 0}
.savings-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:20px;margin-top:30px}
.savings-item{text-align:center}
.savings-amount{font-size:32px;font-weight:bold;margin-bottom:5px}
.savings-period{font-size:14px;opacity:0.9}
.resources{padding:40px}
.resources h2{color:#2c3e50;margin-bottom:20px;font-size:28px}
table{width:100%;border-collapse:collapse;background:white;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
thead{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white}
th{padding:15px;text-align:left;font-weight:600;font-size:12px;text-transform:uppercase}
td{padding:12px 15px;border-bottom:1px solid #e0e0e0;font-size:14px}
tbody tr:hover{background:#f8f9fa}
.benefits{padding:40px;background:#f8f9fa}
.benefits h2{color:#2c3e50;margin-bottom:30px;font-size:28px;text-align:center}
.benefits-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:25px}
.benefit-card{background:white;padding:25px;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
.benefit-card h3{color:#667eea;margin:0 0 15px 0;font-size:20px}
.benefit-card ul{margin:0;padding-left:20px}
.benefit-card li{margin:8px 0;color:#555}
.footer{background:#2c3e50;color:white;padding:30px;text-align:center}
.recommendation{background:#fff3cd;border-left:4px solid#ffc107;padding:25px;margin:40px;border-radius:4px}
.recommendation h3{color:#856404;margin:0 0 15px 0;font-size:24px}
.recommendation p{color:#856404;margin:10px 0;font-size:16px;line-height:1.6}
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>MOVEit COST ANALYSIS REPORT</h1>
<p>Current Infrastructure vs MOVEit Cloud Solution</p>
<p>Resource Group: $ResourceGroupName | Subscription: sub-product-prod</p>
<p>Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
</div>

<div class="summary">
<div class="summary-card">
<div class="summary-number">$resourceCount</div>
<div class="summary-label">Total Resources</div>
</div>
<div class="summary-card">
<div class="summary-number">$totalVMs</div>
<div class="summary-label">Virtual Machines</div>
</div>
<div class="summary-card">
<div class="summary-number">$totalDisks</div>
<div class="summary-label">Managed Disks</div>
</div>
<div class="summary-card">
<div class="summary-number">$totalStorage</div>
<div class="summary-label">Storage Accounts</div>
</div>
</div>

<div class="comparison">
<h2>COST COMPARISON: CURRENT vs CLOUD</h2>
<div class="comparison-table">
<div class="cost-box">
<h3>Current Infrastructure (rg-moveit)</h3>
<div class="cost-item">
<span class="cost-label">Azure Resources</span>
<span class="cost-value">`$$($CostAnalysis.CurrentInfrastructureCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label">Maintenance & Support (15%)</span>
<span class="cost-value">`$$($CostAnalysis.MaintenanceCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label">Monitoring & Alerts</span>
<span class="cost-value">`$$($CostAnalysis.MonitoringCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label">Backup & Disaster Recovery</span>
<span class="cost-value">`$$($CostAnalysis.BackupCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label">Security & Compliance</span>
<span class="cost-value">`$$($CostAnalysis.SecurityCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label">IT Labor & Management</span>
<span class="cost-value">`$$($CostAnalysis.LaborCost)/mo</span>
</div>
<div class="cost-item">
<span class="cost-label" style="font-size:18px"><strong>TOTAL MONTHLY COST</strong></span>
<span class="cost-value" style="font-size:20px;color:#dc3545"><strong>`$$($CostAnalysis.TotalCurrentMonthlyCost)</strong></span>
</div>
</div>

<div class="cost-box" style="border-left-color:#28a745">
<h3>MOVEit Cloud Solution</h3>
<div class="cost-item">
<span class="cost-label">Fully Managed Service</span>
<span class="cost-value">Included</span>
</div>
<div class="cost-item">
<span class="cost-label">Maintenance & Updates</span>
<span class="cost-value">Included</span>
</div>
<div class="cost-item">
<span class="cost-label">24/7 Monitoring</span>
<span class="cost-value">Included</span>
</div>
<div class="cost-item">
<span class="cost-label">Automated Backups</span>
<span class="cost-value">Included</span>
</div>
<div class="cost-item">
<span class="cost-label">Enterprise Security</span>
<span class="cost-value">Included</span>
</div>
<div class="cost-item">
<span class="cost-label">Zero IT Overhead</span>
<span class="cost-value">`$0</span>
</div>
<div class="cost-item">
<span class="cost-label" style="font-size:18px"><strong>TOTAL MONTHLY COST</strong></span>
<span class="cost-value" style="font-size:20px;color:#28a745"><strong>`$$($CostAnalysis.MoveitCloudMonthlyCost)</strong></span>
</div>
</div>
</div>
</div>

<div class="savings-highlight">
<h2>PROJECTED SAVINGS</h2>
<p style="font-size:20px">By migrating to MOVEit Cloud, PYX Health will save:</p>
<div class="savings-grid">
<div class="savings-item">
<div class="savings-amount">`$$($CostAnalysis.MonthlySavings)</div>
<div class="savings-period">Monthly</div>
</div>
<div class="savings-item">
<div class="savings-amount">`$$($CostAnalysis.YearlySavings)</div>
<div class="savings-period">Yearly</div>
</div>
<div class="savings-item">
<div class="savings-amount">`$$($CostAnalysis.ThreeYearSavings)</div>
<div class="savings-period">3-Year Total</div>
</div>
<div class="savings-item">
<div class="savings-amount">`$$($CostAnalysis.FiveYearSavings)</div>
<div class="savings-period">5-Year Total</div>
</div>
</div>
<p style="font-size:24px;margin-top:30px">That's a <strong>$($CostAnalysis.SavingsPercentage)%</strong> cost reduction!</p>
</div>

<div class="benefits">
<h2>BENEFITS BEYOND COST SAVINGS</h2>
<div class="benefits-grid">
<div class="benefit-card">
<h3>🔒 Enhanced Security</h3>
<ul>
<li>SOC 2 Type II Certified</li>
<li>HIPAA Compliant</li>
<li>Advanced threat protection</li>
<li>Automatic security patching</li>
<li>Data encryption at rest & transit</li>
</ul>
</div>
<div class="benefit-card">
<h3>⚡ Improved Performance</h3>
<ul>
<li>99.9% uptime SLA</li>
<li>Global CDN for faster transfers</li>
<li>Auto-scaling capabilities</li>
<li>Zero downtime updates</li>
<li>Optimized infrastructure</li>
</ul>
</div>
<div class="benefit-card">
<h3>🛠️ Reduced IT Burden</h3>
<ul>
<li>No server management</li>
<li>No patching required</li>
<li>No backup configuration</li>
<li>24/7 expert support</li>
<li>Focus on core business</li>
</ul>
</div>
<div class="benefit-card">
<h3>📈 Scalability</h3>
<ul>
<li>Pay only for what you use</li>
<li>Instant capacity increases</li>
<li>No hardware procurement</li>
<li>Elastic bandwidth</li>
<li>Global expansion ready</li>
</ul>
</div>
<div class="benefit-card">
<h3>✅ Compliance</h3>
<ul>
<li>Built-in compliance features</li>
<li>Audit trail & reporting</li>
<li>Data residency options</li>
<li>Regular compliance updates</li>
<li>Industry certifications</li>
</ul>
</div>
<div class="benefit-card">
<h3>🚀 Future-Proof</h3>
<ul>
<li>Always latest features</li>
<li>No end-of-life concerns</li>
<li>Continuous improvements</li>
<li>API integrations</li>
<li>Innovation without effort</li>
</ul>
</div>
</div>
</div>

<div class="recommendation">
<h3>💼 EXECUTIVE RECOMMENDATION</h3>
<p><strong>Migration to MOVEit Cloud will deliver:</strong></p>
<p>✅ Immediate cost reduction of $($CostAnalysis.SavingsPercentage)% (`$$($CostAnalysis.MonthlySavings)/month)</p>
<p>✅ Elimination of infrastructure management overhead</p>
<p>✅ Enhanced security posture and compliance</p>
<p>✅ Improved reliability with 99.9% uptime SLA</p>
<p>✅ Freed IT resources to focus on strategic initiatives</p>
<p>✅ Reduced risk of security incidents and downtime</p>
<p><strong>ROI Timeline:</strong> Positive ROI from month 1 with `$$($CostAnalysis.MonthlySavings) in immediate monthly savings. Over 5 years, PYX Health will save `$$($CostAnalysis.FiveYearSavings) while gaining enterprise-grade security, compliance, and performance.</p>
</div>

<div class="resources">
<h2>CURRENT INFRASTRUCTURE INVENTORY ($resourceCount Resources)</h2>
<table>
<thead>
<tr>
<th>Resource Name</th>
<th>Type</th>
<th>Size/SKU</th>
<th>Location</th>
<th>State</th>
<th>Est. Monthly Cost</th>
</tr>
</thead>
<tbody>
"@

foreach ($resource in $Inventory) {
    $html += @"
<tr>
<td><strong>$($resource.Name)</strong></td>
<td>$($resource.Type)</td>
<td>$($resource.Size) $($resource.SKU)</td>
<td>$($resource.Location)</td>
<td>$($resource.State)</td>
<td>`$$($resource.EstimatedMonthlyCost)</td>
</tr>
"@
}

$html += @"
</tbody>
</table>
</div>

<div class="footer">
<h3>MOVEit Cloud Migration - Cost Analysis Report</h3>
<p>Generated for PYX Health IT Security Team</p>
<p>Data Source: Azure Resource Manager | Cost Management API</p>
<p>Report Date: $(Get-Date -Format 'MMMM dd, yyyy')</p>
</div>

</div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "  HTML dashboard exported: $htmlPath" -ForegroundColor Green
    
    return $htmlPath
}

Install-RequiredModules

if (-not (Connect-ToAzure)) {
    Write-Host ""
    Write-Host "Failed to connect to Azure. Exiting..." -ForegroundColor Red
    exit 1
}

$resourceGroup = Get-ResourceGroupDetails
if (-not $resourceGroup) {
    Write-Host ""
    Write-Host "Resource group not found. Exiting..." -ForegroundColor Red
    exit 1
}

$inventory = Get-AllResources

if ($inventory.Count -eq 0) {
    Write-Host ""
    Write-Host "No resources found in resource group. Exiting..." -ForegroundColor Red
    exit 1
}

$actualCosts = Get-ActualCosts

$costAnalysis = Calculate-TotalCosts -Inventory $inventory -ActualMonthlyCost $actualCosts

Write-Host "Generating reports..." -ForegroundColor Cyan
Write-Host ""

$csvPath = Export-ToCSV -Inventory $inventory -CostAnalysis $costAnalysis
$htmlPath = Export-ToHTML -Inventory $inventory -CostAnalysis $costAnalysis -ResourceGroup $resourceGroup

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  ANALYSIS COMPLETE!" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Reports generated:" -ForegroundColor White
Write-Host "  CSV:  $csvPath" -ForegroundColor Cyan
Write-Host "  HTML: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "KEY FINDINGS:" -ForegroundColor Yellow
Write-Host "  Current Monthly Cost: `$$($costAnalysis.TotalCurrentMonthlyCost)" -ForegroundColor White
Write-Host "  MOVEit Cloud Cost: `$$($costAnalysis.MoveitCloudMonthlyCost)" -ForegroundColor White
Write-Host "  Monthly Savings: `$$($costAnalysis.MonthlySavings)" -ForegroundColor Green
Write-Host "  5-Year Savings: `$$($costAnalysis.FiveYearSavings)" -ForegroundColor Green
Write-Host "  Cost Reduction: $($costAnalysis.SavingsPercentage)%" -ForegroundColor Green
Write-Host ""
Write-Host "Open the HTML dashboard in your browser for the full report!" -ForegroundColor Yellow
Write-Host ""

Disconnect-AzAccount | Out-Null
