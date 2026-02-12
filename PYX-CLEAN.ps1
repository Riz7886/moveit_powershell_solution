# PYX HEALTH - ULTIMATE AZURE AUDIT
# No errors version - clean syntax

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("AUDIT","FIX","DELETE")]
    [string]$Mode = "AUDIT"
)

Clear-Host
Write-Host "PYX HEALTH - ULTIMATE AUDIT" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host ""

# Connect
Write-Host "Connecting..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR" -ForegroundColor Red
    exit
}

Write-Host ""

# Get subscriptions
$subs = Get-AzSubscription
Write-Host "Subscriptions: $($subs.Count)" -ForegroundColor Green
Write-Host ""

# Data
$allRGs = @()
$allDatabricks = @()
$namingIssues = @()
$idleResources = @()
$duplicates = @()

# Process
foreach ($sub in $subs) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Cyan
    
    # Detect sub environment
    $subEnv = "Unknown"
    if ($sub.Name -match "preprod") {
        $subEnv = "PreProd"
    }
    elseif ($sub.Name -match "prod") {
        $subEnv = "Production"
    }
    elseif ($sub.Name -match "test") {
        $subEnv = "Test"
    }
    elseif ($sub.Name -match "dev") {
        $subEnv = "Development"
    }
    elseif ($sub.Name -match "sandbox") {
        $subEnv = "Sandbox"
    }
    
    Write-Host "  Environment: $subEnv" -ForegroundColor White
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  Cannot access" -ForegroundColor Red
        continue
    }
    
    # Get RGs
    $rgs = Get-AzResourceGroup
    Write-Host "  Resource Groups: $($rgs.Count)" -ForegroundColor White
    
    foreach ($rg in $rgs) {
        $rgName = $rg.ResourceGroupName
        
        # Detect RG environment
        $rgEnv = $subEnv
        
        if ($rgName -match "preprod") {
            $rgEnv = "PreProd"
        }
        elseif ($rgName -match "prod") {
            $rgEnv = "Production"
        }
        elseif ($rgName -match "poc") {
            $rgEnv = "POC"
        }
        elseif ($rgName -match "dev") {
            $rgEnv = "Development"
        }
        elseif ($rgName -match "test") {
            $rgEnv = "Test"
        }
        
        Write-Host "    $rgName ($rgEnv)" -ForegroundColor Gray
        
        # Get resources
        $resources = Get-AzResource -ResourceGroupName $rgName -ErrorAction SilentlyContinue
        
        if (-not $resources) {
            Write-Host "      Empty RG" -ForegroundColor Yellow
            
            $idleResources += [PSCustomObject]@{
                Type = "Empty Resource Group"
                Name = $rgName
                ResourceGroup = $rgName
                Subscription = $sub.Name
                Environment = $rgEnv
                Reason = "No resources in RG"
                Savings = "0"
                Action = "Delete RG"
            }
            continue
        }
        
        # Track RG
        $allRGs += [PSCustomObject]@{
            Subscription = $sub.Name
            SubEnv = $subEnv
            ResourceGroup = $rgName
            RGEnv = $rgEnv
            Location = $rg.Location
            ResourceCount = $resources.Count
        }
        
        # Check resources
        foreach ($r in $resources) {
            
            # DATABRICKS
            if ($r.ResourceType -eq "Microsoft.Databricks/workspaces") {
                
                $allDatabricks += [PSCustomObject]@{
                    Subscription = $sub.Name
                    ResourceGroup = $rgName
                    Name = $r.Name
                    Location = $r.Location
                }
                
                Write-Host "      DATABRICKS: $($r.Name)" -ForegroundColor Green
                
                # Check for duplicates
                $existing = $allDatabricks | Where-Object {$_.Name -eq $r.Name -and $_.ResourceGroup -ne $rgName}
                if ($existing) {
                    $duplicates += [PSCustomObject]@{
                        Type = "Databricks"
                        Name = $r.Name
                        Location1 = "$($existing.Subscription) / $($existing.ResourceGroup)"
                        Location2 = "$($sub.Name) / $rgName"
                        Issue = "Duplicate workspace"
                    }
                    Write-Host "        DUPLICATE!" -ForegroundColor Red
                }
                
                # Check naming
                if ($rgEnv -eq "POC" -and $r.Name -match "prod") {
                    $newName = $r.Name -replace "prod", "poc"
                    $namingIssues += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rgName
                        Type = "Databricks"
                        OldName = $r.Name
                        NewName = $newName
                        Environment = $rgEnv
                        Issue = "POC RG has prod-named resource"
                    }
                    Write-Host "        NAMING ISSUE" -ForegroundColor Yellow
                }
                elseif ($rgEnv -eq "PreProd" -and $r.Name -match "-prod") {
                    $newName = $r.Name -replace "-prod", "-preprod"
                    $namingIssues += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rgName
                        Type = "Databricks"
                        OldName = $r.Name
                        NewName = $newName
                        Environment = $rgEnv
                        Issue = "PreProd RG has prod-named resource"
                    }
                    Write-Host "        NAMING ISSUE" -ForegroundColor Yellow
                }
            }
            
            # VMs
            elseif ($r.ResourceType -eq "Microsoft.Compute/virtualMachines") {
                $vm = Get-AzVM -ResourceGroupName $rgName -Name $r.Name -Status -ErrorAction SilentlyContinue
                
                if ($vm) {
                    $vmStatus = $vm.Statuses | Where-Object {$_.Code -like "PowerState/*"}
                    
                    if ($vmStatus.Code -eq "PowerState/deallocated" -or $vmStatus.Code -eq "PowerState/stopped") {
                        
                        $idleResources += [PSCustomObject]@{
                            Type = "VM"
                            Name = $r.Name
                            ResourceGroup = $rgName
                            Subscription = $sub.Name
                            Environment = $rgEnv
                            Reason = "VM stopped"
                            Savings = "50"
                            Action = "Delete or deallocate"
                        }
                        
                        Write-Host "      IDLE VM: $($r.Name)" -ForegroundColor Yellow
                    }
                }
            }
            
            # Storage
            elseif ($r.ResourceType -eq "Microsoft.Storage/storageAccounts") {
                $storage = Get-AzStorageAccount -ResourceGroupName $rgName -Name $r.Name -ErrorAction SilentlyContinue
                
                if ($storage) {
                    $containers = Get-AzStorageContainer -Context $storage.Context -ErrorAction SilentlyContinue
                    
                    if (-not $containers) {
                        $idleResources += [PSCustomObject]@{
                            Type = "Storage"
                            Name = $r.Name
                            ResourceGroup = $rgName
                            Subscription = $sub.Name
                            Environment = $rgEnv
                            Reason = "No containers"
                            Savings = "10"
                            Action = "Delete if unused"
                        }
                        Write-Host "      IDLE STORAGE: $($r.Name)" -ForegroundColor Yellow
                    }
                }
            }
        }
    }
    
    Write-Host ""
}

# Calculate total savings
$totalSavings = 0
foreach ($idle in $idleResources) {
    if ($idle.Savings -match "\d+") {
        $totalSavings += [int]$idle.Savings
    }
}

# Generate Report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportFile = "PYX-AUDIT-$timestamp.html"

# Build tables
$rgRows = ""
foreach ($rg in $allRGs) {
    $match = if ($rg.SubEnv -eq $rg.RGEnv) {"OK"} else {"MISMATCH"}
    $color = if ($rg.SubEnv -eq $rg.RGEnv) {"green"} else {"red"}
    $rgRows += "<tr><td>$($rg.Subscription)</td><td><b>$($rg.ResourceGroup)</b></td><td>$($rg.SubEnv)</td><td>$($rg.RGEnv)</td><td style='color:$color'>$match</td><td>$($rg.Location)</td><td>$($rg.ResourceCount)</td></tr>"
}

$dbRows = ""
foreach ($db in $allDatabricks) {
    $dbRows += "<tr><td>$($db.Subscription)</td><td>$($db.ResourceGroup)</td><td><b>$($db.Name)</b></td><td>$($db.Location)</td></tr>"
}
if (-not $dbRows) {
    $dbRows = "<tr><td colspan='4' style='text-align:center'>No Databricks found</td></tr>"
}

$namingRows = ""
foreach ($issue in $namingIssues) {
    $namingRows += "<tr><td>$($issue.Subscription)</td><td>$($issue.ResourceGroup)</td><td>$($issue.Type)</td><td style='background:#ffe6e6;padding:8px'><b>$($issue.OldName)</b></td><td style='background:#e6ffe6;padding:8px'><b>$($issue.NewName)</b></td><td>$($issue.Environment)</td><td>$($issue.Issue)</td></tr>"
}
if (-not $namingRows) {
    $namingRows = "<tr><td colspan='7' style='text-align:center;color:green'><b>No naming issues!</b></td></tr>"
}

$idleRows = ""
foreach ($idle in $idleResources) {
    $savingsText = "`$$($idle.Savings)/mo"
    $idleRows += "<tr><td>$($idle.Type)</td><td><b>$($idle.Name)</b></td><td>$($idle.ResourceGroup)</td><td>$($idle.Subscription)</td><td>$($idle.Reason)</td><td style='color:green'><b>$savingsText</b></td><td>$($idle.Action)</td></tr>"
}
if (-not $idleRows) {
    $idleRows = "<tr><td colspan='7' style='text-align:center;color:green'><b>No idle resources!</b></td></tr>"
}

$dupRows = ""
foreach ($dup in $duplicates) {
    $dupRows += "<tr><td>$($dup.Type)</td><td><b>$($dup.Name)</b></td><td>$($dup.Location1)</td><td>$($dup.Location2)</td><td style='color:red'>$($dup.Issue)</td></tr>"
}
if (-not $dupRows) {
    $dupRows = "<tr><td colspan='5' style='text-align:center;color:green'><b>No duplicates!</b></td></tr>"
}

# HTML
$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Pyx Health Azure Audit</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:Arial,sans-serif;background:#f5f5f5;padding:20px}
.header{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:40px;border-radius:10px;margin-bottom:30px}
h1{font-size:36px;margin-bottom:10px}
.subtitle{font-size:16px;opacity:0.9}
.container{max-width:1800px;margin:0 auto}
.summary{display:grid;grid-template-columns:repeat(6,1fr);gap:20px;margin-bottom:30px}
.box{background:white;padding:25px;border-radius:10px;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
.val{font-size:40px;font-weight:bold;color:#667eea;margin-bottom:8px}
.label{color:#666;font-size:13px}
.card{background:white;padding:30px;border-radius:10px;margin-bottom:25px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
h2{color:#333;font-size:24px;margin-bottom:20px;padding-bottom:10px;border-bottom:3px solid #667eea}
table{width:100%;border-collapse:collapse;margin:20px 0}
thead{background:#667eea}
th{color:white;padding:15px;text-align:left;font-size:12px}
td{padding:12px;border-bottom:1px solid #ddd;font-size:13px}
tr:hover{background:#f8f9fa}
.footer{background:#2c3e50;color:white;padding:25px;border-radius:10px;text-align:center;margin-top:30px}
.savings{background:#28a745;color:white;padding:30px;border-radius:10px;text-align:center;margin:20px 0}
.savings-amt{font-size:50px;font-weight:bold}
</style>
</head>
<body>
<div class='container'>

<div class='header'>
<h1>PYX HEALTH - Azure Audit Report</h1>
<div class='subtitle'>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Account: $($context.Account.Id)</div>
</div>

<div class='summary'>
<div class='box'><div class='val'>$($subs.Count)</div><div class='label'>Subscriptions</div></div>
<div class='box'><div class='val'>$($allRGs.Count)</div><div class='label'>Resource Groups</div></div>
<div class='box'><div class='val'>$($allDatabricks.Count)</div><div class='label'>Databricks</div></div>
<div class='box'><div class='val'>$($namingIssues.Count)</div><div class='label'>Naming Issues</div></div>
<div class='box'><div class='val'>$($idleResources.Count)</div><div class='label'>Idle Resources</div></div>
<div class='box'><div class='val'>$($duplicates.Count)</div><div class='label'>Duplicates</div></div>
</div>

<div class='savings'>
<div class='savings-amt'>`$$totalSavings/month</div>
<div>Potential Monthly Savings</div>
</div>

<div class='card'>
<h2>ALL RESOURCE GROUPS</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Sub Env</th><th>RG Env</th><th>Match</th><th>Location</th><th>Resources</th></tr></thead>
<tbody>$rgRows</tbody>
</table>
</div>

<div class='card'>
<h2>DATABRICKS WORKSPACES</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Name</th><th>Location</th></tr></thead>
<tbody>$dbRows</tbody>
</table>
</div>

<div class='card'>
<h2>NAMING ISSUES - OLD vs NEW</h2>
<table>
<thead><tr><th>Subscription</th><th>Resource Group</th><th>Type</th><th>OLD NAME</th><th>NEW NAME</th><th>Env</th><th>Issue</th></tr></thead>
<tbody>$namingRows</tbody>
</table>
</div>

<div class='card'>
<h2>IDLE RESOURCES</h2>
<table>
<thead><tr><th>Type</th><th>Name</th><th>Resource Group</th><th>Subscription</th><th>Reason</th><th>Savings</th><th>Action</th></tr></thead>
<tbody>$idleRows</tbody>
</table>
</div>

<div class='card'>
<h2>DUPLICATES</h2>
<table>
<thead><tr><th>Type</th><th>Name</th><th>Location 1</th><th>Location 2</th><th>Issue</th></tr></thead>
<tbody>$dupRows</tbody>
</table>
</div>

<div class='footer'>
<b>PYX HEALTH - Azure Infrastructure Audit</b><br>
Subscriptions: $($subs.Count) | Resource Groups: $($allRGs.Count) | Databricks: $($allDatabricks.Count)<br>
Issues: $($namingIssues.Count) naming, $($idleResources.Count) idle, $($duplicates.Count) duplicates<br>
Monthly Savings: `$$totalSavings
</div>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Subscriptions: $($subs.Count)" -ForegroundColor White
Write-Host "Resource Groups: $($allRGs.Count)" -ForegroundColor White
Write-Host "Databricks: $($allDatabricks.Count)" -ForegroundColor Green
Write-Host "Naming Issues: $($namingIssues.Count)" -ForegroundColor Yellow
Write-Host "Idle Resources: $($idleResources.Count)" -ForegroundColor Yellow
Write-Host "Duplicates: $($duplicates.Count)" -ForegroundColor Red
Write-Host "Monthly Savings: `$$totalSavings" -ForegroundColor Green
Write-Host ""
Write-Host "Report: $reportFile" -ForegroundColor Green
Write-Host ""

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
