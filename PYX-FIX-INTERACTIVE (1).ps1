# PYX HEALTH - INTERACTIVE FIX SCRIPT
# Like DTU script - presents options, user selects, executes fixes

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PYX HEALTH - AZURE FIX TOOL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Connect
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected" -ForegroundColor Green
} catch {
    Write-Host "ERROR" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "Scanning environment..." -ForegroundColor Yellow
Write-Host ""

# Get data
$subs = Get-AzSubscription
$emptyRGs = @()
$idleStorage = @()
$stoppedVMs = @()
$namingIssues = @()
$duplicateDatabricks = @()
$allDatabricks = @()
$wrongNames = @()

# Scan
foreach ($sub in $subs) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    
    $rgs = Get-AzResourceGroup -ErrorAction SilentlyContinue
    
    foreach ($rg in $rgs) {
        $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
        
        # Detect RG environment
        $rgEnv = "Production"
        if ($rg.ResourceGroupName -match "preprod") { $rgEnv = "PreProd" }
        elseif ($rg.ResourceGroupName -match "poc") { $rgEnv = "POC" }
        elseif ($rg.ResourceGroupName -match "prod") { $rgEnv = "Production" }
        elseif ($rg.ResourceGroupName -match "dev") { $rgEnv = "Development" }
        elseif ($rg.ResourceGroupName -match "test") { $rgEnv = "Test" }
        elseif ($rg.ResourceGroupName -match "sandbox") { $rgEnv = "Sandbox" }
        
        if (-not $resources) {
            $emptyRGs += [PSCustomObject]@{
                Subscription = $sub.Name
                ResourceGroup = $rg.ResourceGroupName
                Location = $rg.Location
            }
        } else {
            foreach ($r in $resources) {
                
                # Check naming mismatches
                $hasNamingIssue = $false
                $suggestedName = $r.Name
                $issue = ""
                
                if ($rgEnv -eq "POC" -and $r.Name -match "prod" -and $r.Name -notmatch "preprod") {
                    $hasNamingIssue = $true
                    $suggestedName = $r.Name -replace "prod", "poc"
                    $issue = "POC RG has prod-named resource"
                }
                elseif ($rgEnv -eq "PreProd" -and $r.Name -match "\-prod" -and $r.Name -notmatch "preprod") {
                    $hasNamingIssue = $true
                    $suggestedName = $r.Name -replace "\-prod", "-preprod"
                    $issue = "PreProd RG has prod-named resource"
                }
                elseif ($rgEnv -eq "Production" -and $r.Name -match "test") {
                    $hasNamingIssue = $true
                    $suggestedName = $r.Name -replace "test", "prod"
                    $issue = "Production RG has test-named resource"
                }
                
                if ($hasNamingIssue) {
                    $wrongNames += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rg.ResourceGroupName
                        Environment = $rgEnv
                        ResourceType = $r.ResourceType
                        OldName = $r.Name
                        SuggestedName = $suggestedName
                        Issue = $issue
                        ResourceId = $r.ResourceId
                    }
                }
                
                # Databricks
                if ($r.ResourceType -eq "Microsoft.Databricks/workspaces") {
                    $existing = $allDatabricks | Where-Object {$_.Name -eq $r.Name -and $_.ResourceGroup -ne $rg.ResourceGroupName}
                    if ($existing) {
                        $duplicateDatabricks += [PSCustomObject]@{
                            Name = $r.Name
                            Location1 = "$($existing.Subscription)/$($existing.ResourceGroup)"
                            Location2 = "$($sub.Name)/$($rg.ResourceGroupName)"
                        }
                    }
                    $allDatabricks += [PSCustomObject]@{
                        Subscription = $sub.Name
                        ResourceGroup = $rg.ResourceGroupName
                        Name = $r.Name
                    }
                }
                
                # VMs
                if ($r.ResourceType -eq "Microsoft.Compute/virtualMachines") {
                    try {
                        $vm = Get-AzVM -ResourceGroupName $rg.ResourceGroupName -Name $r.Name -Status -ErrorAction Stop
                        $vmStatus = $vm.Statuses | Where-Object {$_.Code -like "PowerState/*"}
                        if ($vmStatus.Code -eq "PowerState/deallocated" -or $vmStatus.Code -eq "PowerState/stopped") {
                            $stoppedVMs += [PSCustomObject]@{
                                Subscription = $sub.Name
                                ResourceGroup = $rg.ResourceGroupName
                                Name = $r.Name
                                Status = $vmStatus.Code
                            }
                        }
                    } catch {}
                }
                
                # Storage
                if ($r.ResourceType -eq "Microsoft.Storage/storageAccounts") {
                    try {
                        $storage = Get-AzStorageAccount -ResourceGroupName $rg.ResourceGroupName -Name $r.Name -ErrorAction Stop
                        try {
                            $containers = Get-AzStorageContainer -Context $storage.Context -ErrorAction Stop
                            if (-not $containers) {
                                $idleStorage += [PSCustomObject]@{
                                    Subscription = $sub.Name
                                    ResourceGroup = $rg.ResourceGroupName
                                    Name = $r.Name
                                }
                            }
                        } catch {}
                    } catch {}
                }
            }
        }
    }
}

# Show results
Write-Host "SCAN COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Found:" -ForegroundColor Cyan
Write-Host "  Empty Resource Groups: $($emptyRGs.Count)" -ForegroundColor Yellow
Write-Host "  Idle Storage Accounts: $($idleStorage.Count)" -ForegroundColor Yellow
Write-Host "  Stopped VMs: $($stoppedVMs.Count)" -ForegroundColor Yellow
Write-Host "  Wrong Named Resources: $($wrongNames.Count)" -ForegroundColor Yellow
Write-Host "  Duplicate Databricks: $($duplicateDatabricks.Count)" -ForegroundColor Red
Write-Host ""

# Main menu
$continue = $true

while ($continue) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  WHAT DO YOU WANT TO FIX?" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Delete Empty Resource Groups ($($emptyRGs.Count) found)" -ForegroundColor White
    Write-Host "2. Delete Idle Storage Accounts ($($idleStorage.Count) found)" -ForegroundColor White
    Write-Host "3. Delete Stopped VMs ($($stoppedVMs.Count) found)" -ForegroundColor White
    Write-Host "4. Fix Wrong Named Resources ($($wrongNames.Count) found)" -ForegroundColor White
    Write-Host "5. Show Duplicate Databricks ($($duplicateDatabricks.Count) found)" -ForegroundColor White
    Write-Host "6. Generate Updated Report" -ForegroundColor White
    Write-Host "7. FIX EVERYTHING (All of the above)" -ForegroundColor Yellow
    Write-Host "8. Exit" -ForegroundColor Red
    Write-Host ""
    $choice = Read-Host "Enter choice (1-8)"
    
    switch ($choice) {
        "1" {
            # Delete empty RGs
            if ($emptyRGs.Count -eq 0) {
                Write-Host "No empty resource groups found" -ForegroundColor Green
                Start-Sleep -Seconds 2
                continue
            }
            
            Write-Host ""
            Write-Host "Empty Resource Groups:" -ForegroundColor Yellow
            for ($i=0; $i -lt $emptyRGs.Count; $i++) {
                Write-Host "  $($i+1). $($emptyRGs[$i].Subscription) / $($emptyRGs[$i].ResourceGroup)" -ForegroundColor White
            }
            Write-Host ""
            
            $confirm = Read-Host "Delete ALL empty RGs? (yes/no)"
            if ($confirm -eq "yes") {
                $deleted = 0
                foreach ($rg in $emptyRGs) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $rg.Subscription}).Id | Out-Null
                        Remove-AzResourceGroup -Name $rg.ResourceGroup -Force | Out-Null
                        Write-Host "  DELETED: $($rg.ResourceGroup)" -ForegroundColor Green
                        $deleted++
                    } catch {
                        Write-Host "  ERROR: $($rg.ResourceGroup) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host ""
                Write-Host "Deleted $deleted resource groups" -ForegroundColor Green
                $emptyRGs = @()
            }
            Write-Host ""
            Start-Sleep -Seconds 2
        }
        
        "2" {
            # Delete idle storage
            if ($idleStorage.Count -eq 0) {
                Write-Host "No idle storage accounts found" -ForegroundColor Green
                Start-Sleep -Seconds 2
                continue
            }
            
            Write-Host ""
            Write-Host "Idle Storage Accounts:" -ForegroundColor Yellow
            for ($i=0; $i -lt $idleStorage.Count; $i++) {
                Write-Host "  $($i+1). $($idleStorage[$i].Name) in $($idleStorage[$i].ResourceGroup)" -ForegroundColor White
            }
            Write-Host ""
            
            $confirm = Read-Host "Delete ALL idle storage? (yes/no)"
            if ($confirm -eq "yes") {
                $deleted = 0
                foreach ($storage in $idleStorage) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $storage.Subscription}).Id | Out-Null
                        Remove-AzStorageAccount -ResourceGroupName $storage.ResourceGroup -Name $storage.Name -Force | Out-Null
                        Write-Host "  DELETED: $($storage.Name)" -ForegroundColor Green
                        $deleted++
                    } catch {
                        Write-Host "  ERROR: $($storage.Name) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host ""
                Write-Host "Deleted $deleted storage accounts" -ForegroundColor Green
                $idleStorage = @()
            }
            Write-Host ""
            Start-Sleep -Seconds 2
        }
        
        "3" {
            # Delete stopped VMs
            if ($stoppedVMs.Count -eq 0) {
                Write-Host "No stopped VMs found" -ForegroundColor Green
                Start-Sleep -Seconds 2
                continue
            }
            
            Write-Host ""
            Write-Host "Stopped VMs:" -ForegroundColor Yellow
            for ($i=0; $i -lt $stoppedVMs.Count; $i++) {
                Write-Host "  $($i+1). $($stoppedVMs[$i].Name) in $($stoppedVMs[$i].ResourceGroup) - $($stoppedVMs[$i].Status)" -ForegroundColor White
            }
            Write-Host ""
            
            $confirm = Read-Host "Delete ALL stopped VMs? (yes/no)"
            if ($confirm -eq "yes") {
                $deleted = 0
                foreach ($vm in $stoppedVMs) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $vm.Subscription}).Id | Out-Null
                        Remove-AzVM -ResourceGroupName $vm.ResourceGroup -Name $vm.Name -Force | Out-Null
                        Write-Host "  DELETED: $($vm.Name)" -ForegroundColor Green
                        $deleted++
                    } catch {
                        Write-Host "  ERROR: $($vm.Name) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host ""
                Write-Host "Deleted $deleted VMs" -ForegroundColor Green
                $stoppedVMs = @()
            }
            Write-Host ""
            Start-Sleep -Seconds 2
        }
        
        "4" {
            # Fix naming issues
            if ($wrongNames.Count -eq 0) {
                Write-Host "No naming issues found" -ForegroundColor Green
                Start-Sleep -Seconds 2
                continue
            }
            
            Write-Host ""
            Write-Host "NAMING ISSUES:" -ForegroundColor Yellow
            Write-Host ""
            for ($i=0; $i -lt $wrongNames.Count; $i++) {
                Write-Host "  $($i+1). $($wrongNames[$i].ResourceGroup)" -ForegroundColor Cyan
                Write-Host "      Type: $($wrongNames[$i].ResourceType)" -ForegroundColor White
                Write-Host "      OLD NAME: $($wrongNames[$i].OldName)" -ForegroundColor Red
                Write-Host "      SUGGESTED: $($wrongNames[$i].SuggestedName)" -ForegroundColor Green
                Write-Host "      Issue: $($wrongNames[$i].Issue)" -ForegroundColor Yellow
                Write-Host ""
            }
            
            $confirm = Read-Host "Tag ALL resources with correct environment? (yes/no)"
            if ($confirm -eq "yes") {
                $fixed = 0
                foreach ($item in $wrongNames) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $item.Subscription}).Id | Out-Null
                        
                        $resource = Get-AzResource -ResourceId $item.ResourceId -ErrorAction Stop
                        $tags = $resource.Tags
                        if (-not $tags) { $tags = @{} }
                        
                        $tags["PYX-Environment"] = $item.Environment.ToUpper()
                        $tags["PYX-NamingIssue"] = "TRUE"
                        $tags["PYX-SuggestedName"] = $item.SuggestedName
                        $tags["PYX-FixedDate"] = (Get-Date -Format "yyyy-MM-dd")
                        
                        Set-AzResource -ResourceId $item.ResourceId -Tag $tags -Force | Out-Null
                        
                        Write-Host "  TAGGED: $($item.OldName) with Environment=$($item.Environment)" -ForegroundColor Green
                        $fixed++
                    } catch {
                        Write-Host "  ERROR: $($item.OldName) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host ""
                Write-Host "Tagged $fixed resources" -ForegroundColor Green
                $wrongNames = @()
            }
            Write-Host ""
            Start-Sleep -Seconds 2
        }
        
        "5" {
            # Show duplicates
            if ($duplicateDatabricks.Count -eq 0) {
                Write-Host "No duplicate Databricks found" -ForegroundColor Green
                Start-Sleep -Seconds 2
                continue
            }
            
            Write-Host ""
            Write-Host "DUPLICATE DATABRICKS WORKSPACES:" -ForegroundColor Red
            foreach ($dup in $duplicateDatabricks) {
                Write-Host ""
                Write-Host "  Workspace: $($dup.Name)" -ForegroundColor Yellow
                Write-Host "    Location 1: $($dup.Location1)" -ForegroundColor White
                Write-Host "    Location 2: $($dup.Location2)" -ForegroundColor White
                Write-Host "    ACTION: Manually review and consolidate" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "Databricks workspaces cannot be automatically deleted" -ForegroundColor Yellow
            Write-Host "Please review manually and decide which to keep" -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        
        "6" {
            # Generate report
            Write-Host ""
            Write-Host "Generating updated report..." -ForegroundColor Yellow
            
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $reportFile = "PYX-UPDATED-AUDIT-$timestamp.html"
            
            $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<title>Pyx Health - Updated Audit Report</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:Arial,sans-serif;background:#f5f5f5;padding:20px}
.header{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:50px;border-radius:12px;margin-bottom:30px}
h1{font-size:40px;margin-bottom:10px}
.subtitle{font-size:16px;opacity:0.9}
.container{max-width:1400px;margin:0 auto}
.summary{display:grid;grid-template-columns:repeat(5,1fr);gap:20px;margin-bottom:30px}
.box{background:white;padding:30px;border-radius:10px;text-align:center;box-shadow:0 4px 15px rgba(0,0,0,0.1)}
.val{font-size:45px;font-weight:bold;color:#667eea;margin-bottom:10px}
.label{color:#666;font-size:14px}
.card{background:white;padding:35px;border-radius:12px;margin-bottom:25px;box-shadow:0 4px 15px rgba(0,0,0,0.1)}
h2{color:#333;font-size:26px;margin-bottom:20px;padding-bottom:12px;border-bottom:4px solid #667eea}
.success{background:#28a745;color:white;padding:20px;border-radius:10px;margin:20px 0;text-align:center;font-size:20px}
</style>
</head>
<body>
<div class='container'>

<div class='header'>
<h1>PYX HEALTH - Updated Audit Report</h1>
<div class='subtitle'>After Cleanup | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
</div>

<div class='summary'>
<div class='box'><div class='val'>$($emptyRGs.Count)</div><div class='label'>Empty RGs Remaining</div></div>
<div class='box'><div class='val'>$($idleStorage.Count)</div><div class='label'>Idle Storage Remaining</div></div>
<div class='box'><div class='val'>$($stoppedVMs.Count)</div><div class='label'>Stopped VMs Remaining</div></div>
<div class='box'><div class='val'>$($wrongNames.Count)</div><div class='label'>Naming Issues Remaining</div></div>
<div class='box'><div class='val'>$($duplicateDatabricks.Count)</div><div class='label'>Duplicate Databricks</div></div>
</div>

<div class='success'>
Cleanup Complete! Resources have been optimized.
</div>

</div>
</body>
</html>
"@
            
            $html | Out-File $reportFile -Encoding UTF8
            Start-Process $reportFile
            
            Write-Host "Report generated: $reportFile" -ForegroundColor Green
            Write-Host ""
            Start-Sleep -Seconds 2
        }
        
        "7" {
            # Fix everything
            Write-Host ""
            Write-Host "FIX EVERYTHING MODE" -ForegroundColor Red
            Write-Host ""
            $confirm = Read-Host "This will delete ALL idle resources and fix naming. Type DELETE to confirm"
            
            if ($confirm -eq "DELETE") {
                # Delete empty RGs
                Write-Host ""
                Write-Host "Deleting empty resource groups..." -ForegroundColor Yellow
                foreach ($rg in $emptyRGs) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $rg.Subscription}).Id | Out-Null
                        Remove-AzResourceGroup -Name $rg.ResourceGroup -Force | Out-Null
                        Write-Host "  DELETED: $($rg.ResourceGroup)" -ForegroundColor Green
                    } catch {
                        Write-Host "  ERROR: $($rg.ResourceGroup)" -ForegroundColor Red
                    }
                }
                $emptyRGs = @()
                
                # Delete idle storage
                Write-Host ""
                Write-Host "Deleting idle storage..." -ForegroundColor Yellow
                foreach ($storage in $idleStorage) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $storage.Subscription}).Id | Out-Null
                        Remove-AzStorageAccount -ResourceGroupName $storage.ResourceGroup -Name $storage.Name -Force | Out-Null
                        Write-Host "  DELETED: $($storage.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "  ERROR: $($storage.Name)" -ForegroundColor Red
                    }
                }
                $idleStorage = @()
                
                # Delete stopped VMs
                Write-Host ""
                Write-Host "Deleting stopped VMs..." -ForegroundColor Yellow
                foreach ($vm in $stoppedVMs) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $vm.Subscription}).Id | Out-Null
                        Remove-AzVM -ResourceGroupName $vm.ResourceGroup -Name $vm.Name -Force | Out-Null
                        Write-Host "  DELETED: $($vm.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "  ERROR: $($vm.Name)" -ForegroundColor Red
                    }
                }
                $stoppedVMs = @()
                
                # Fix naming issues
                Write-Host ""
                Write-Host "Fixing naming issues..." -ForegroundColor Yellow
                foreach ($item in $wrongNames) {
                    try {
                        Set-AzContext -SubscriptionId ($subs | Where-Object {$_.Name -eq $item.Subscription}).Id | Out-Null
                        $resource = Get-AzResource -ResourceId $item.ResourceId -ErrorAction Stop
                        $tags = $resource.Tags
                        if (-not $tags) { $tags = @{} }
                        $tags["PYX-Environment"] = $item.Environment.ToUpper()
                        $tags["PYX-NamingIssue"] = "TRUE"
                        $tags["PYX-SuggestedName"] = $item.SuggestedName
                        $tags["PYX-FixedDate"] = (Get-Date -Format "yyyy-MM-dd")
                        Set-AzResource -ResourceId $item.ResourceId -Tag $tags -Force | Out-Null
                        Write-Host "  TAGGED: $($item.OldName)" -ForegroundColor Green
                    } catch {
                        Write-Host "  ERROR: $($item.OldName)" -ForegroundColor Red
                    }
                }
                $wrongNames = @()
                
                Write-Host ""
                Write-Host "CLEANUP COMPLETE!" -ForegroundColor Green
                Write-Host ""
            } else {
                Write-Host "Cancelled" -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 2
        }
        
        "8" {
            Write-Host "Exiting..." -ForegroundColor Yellow
            $continue = $false
        }
        
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
    
    Write-Host ""
}

Write-Host "Done!" -ForegroundColor Green
