# SQL DTU Emergency Fix
# Analyzes all databases, fixes PRODUCTION first (only if needed), then others
# Author: Syed Rizvi

$LogPath = "C:\Temp\SQL_DTU_Optimizer"
if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
$ChangeHistoryFile = Join-Path $LogPath "Change_History.csv"

Write-Host "SQL DTU Emergency Fix" -ForegroundColor Cyan
Write-Host "Syed Rizvi - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Write-Host "Installing $_..." -ForegroundColor Yellow
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
    }
    Import-Module $_ -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

function Get-OptimalDTU {
    param($CurrentDTU, $MaxPercent, $IsProd)
    if ($MaxPercent -eq 0) { return $CurrentDTU }
    $actualUsed = ($CurrentDTU * $MaxPercent) / 100
    $target = if ($IsProd) { 0.50 } else { 0.60 }
    $needed = [math]::Ceiling($actualUsed / $target)
    
    if ($needed -le 10) { return 10 }
    elseif ($needed -le 20) { return 20 }
    elseif ($needed -le 50) { return 50 }
    elseif ($needed -le 100) { return 100 }
    elseif ($needed -le 200) { return 200 }
    elseif ($needed -le 400) { return 400 }
    elseif ($needed -le 800) { return 800 }
    elseif ($needed -le 1600) { return 1600 }
    else { return 3000 }
}

function Get-TierName {
    param($DTU)
    switch ($DTU) {
        10 { return "S0" }; 20 { return "S1" }; 50 { return "S2" }
        100 { return "S3" }; 200 { return "S4" }; 400 { return "S6" }
        800 { return "S7" }; 1600 { return "S9" }; 3000 { return "S12" }
        default { return "S0" }
    }
}

$changeHistory = @()
if (Test-Path $ChangeHistoryFile) {
    $changeHistory = Import-Csv $ChangeHistoryFile
}

$recentChanges = $changeHistory | Where-Object {
    try { ([DateTime]$_.ChangeDate) -gt (Get-Date).AddHours(-24) } catch { $false }
}

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { 
    $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant 
}

$allDatabases = @()
$totalScanned = 0

Write-Host "Phase 1: Analyzing all databases..." -ForegroundColor Cyan
Write-Host ""

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { continue }
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue | 
               Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $totalScanned++
            Write-Host "  [$totalScanned] $($db.DatabaseName)" -ForegroundColor Gray
            
            $isProd = $db.DatabaseName -like "*prod*" -or $db.DatabaseName -like "*prd*"
            $currentTier = $db.SkuName
            
            $currentDTU = switch -Regex ($currentTier) {
                'S0' { 10 }; 'S1' { 20 }; 'S2' { 50 }; 'S3' { 100 }
                'S4' { 200 }; 'S6' { 400 }; 'S7' { 800 }
                'S9' { 1600 }; 'S12' { 3000 }; 'Standard' { 10 }
                default { 10 }
            }
            
            $recentChange = $recentChanges | Where-Object { $_.Database -eq $db.DatabaseName }
            
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-7)
            
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" `
                      -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 `
                      -AggregationType Average -ErrorAction SilentlyContinue
            
            $maxDTU = 0
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                }
            }
            
            $optimalDTU = Get-OptimalDTU -CurrentDTU $currentDTU -MaxPercent $maxDTU -IsProd $isProd
            $needsChange = ($optimalDTU -ne $currentDTU -and $maxDTU -gt 65 -and !$recentChange)
            
            $dbInfo = [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                ResourceGroup = $server.ResourceGroupName
                IsProd = $isProd
                CurrentTier = $currentTier
                CurrentDTU = $currentDTU
                MaxPercent = $maxDTU
                OptimalDTU = $optimalDTU
                OptimalTier = Get-TierName -DTU $optimalDTU
                NeedsChange = $needsChange
                RecentlyChanged = ($null -ne $recentChange)
                MaxSizeBytes = $db.MaxSizeBytes
            }
            
            $allDatabases += $dbInfo
        }
    }
}

$prodNeedingFix = $allDatabases | Where-Object { $_.IsProd -and $_.NeedsChange }
$nonProdNeedingFix = $allDatabases | Where-Object { !$_.IsProd -and $_.NeedsChange }

Write-Host ""
Write-Host "Analysis Complete:" -ForegroundColor Green
Write-Host "  Total databases: $totalScanned" -ForegroundColor White
Write-Host "  Production databases: $($allDatabases | Where-Object {$_.IsProd} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red
Write-Host "  Production needing fix: $($prodNeedingFix.Count)" -ForegroundColor Yellow
Write-Host "  Non-production needing fix: $($nonProdNeedingFix.Count)" -ForegroundColor Yellow
Write-Host ""

$fixed = @()

if ($prodNeedingFix.Count -gt 0) {
    Write-Host "Phase 2: Fixing PRODUCTION databases first..." -ForegroundColor Red
    Write-Host ""
    
    foreach ($db in ($prodNeedingFix | Sort-Object MaxPercent -Descending)) {
        Write-Host "  PROD: $($db.Database) - $($db.CurrentTier) -> $($db.OptimalTier) (Max: $($db.MaxPercent)%)" -ForegroundColor Yellow
        
        try {
            Set-AzContext -SubscriptionId ($subscriptions | Where-Object {$_.Id -match $db.ResourceGroup}).Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
            
            Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup `
                            -ServerName $db.Server `
                            -DatabaseName $db.Database `
                            -Edition "Standard" `
                            -RequestedServiceObjectiveName $db.OptimalTier `
                            -MaxSizeBytes ([long]$db.MaxSizeBytes) `
                            -ErrorAction Stop | Out-Null
            
            Write-Host "    SUCCESS" -ForegroundColor Green
            
            $changeLog = [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                FromDTU = $db.CurrentDTU
                ToDTU = $db.OptimalDTU
                MaxUsage = $db.MaxPercent
                IsProd = "YES"
            }
            $fixed += $changeLog
        } catch {
            Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if ($nonProdNeedingFix.Count -gt 0) {
    Write-Host ""
    Write-Host "Phase 3: Fixing non-production databases..." -ForegroundColor Green
    Write-Host ""
    
    foreach ($db in ($nonProdNeedingFix | Sort-Object MaxPercent -Descending)) {
        Write-Host "  $($db.Database) - $($db.CurrentTier) -> $($db.OptimalTier) (Max: $($db.MaxPercent)%)" -ForegroundColor Yellow
        
        try {
            Set-AzContext -SubscriptionId ($subscriptions | Where-Object {$_.Id -match $db.ResourceGroup}).Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
            
            Set-AzSqlDatabase -ResourceGroupName $db.ResourceGroup `
                            -ServerName $db.Server `
                            -DatabaseName $db.Database `
                            -Edition "Standard" `
                            -RequestedServiceObjectiveName $db.OptimalTier `
                            -MaxSizeBytes ([long]$db.MaxSizeBytes) `
                            -ErrorAction Stop | Out-Null
            
            Write-Host "    SUCCESS" -ForegroundColor Green
            
            $changeLog = [PSCustomObject]@{
                ChangeDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Database = $db.Database
                Server = $db.Server
                FromTier = $db.CurrentTier
                ToTier = $db.OptimalTier
                FromDTU = $db.CurrentDTU
                ToDTU = $db.OptimalDTU
                MaxUsage = $db.MaxPercent
                IsProd = "NO"
            }
            $fixed += $changeLog
        } catch {
            Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if ($fixed.Count -gt 0) {
    $fixed | Export-Csv -Path $ChangeHistoryFile -NoTypeInformation -Append
}

Write-Host ""
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total scanned: $totalScanned" -ForegroundColor White
Write-Host "  Production fixed: $($fixed | Where-Object {$_.IsProd -eq 'YES'} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Red
Write-Host "  Non-production fixed: $($fixed | Where-Object {$_.IsProd -eq 'NO'} | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Green
Write-Host "  Total fixed: $($fixed.Count)" -ForegroundColor Green
Write-Host ""

if ($fixed.Count -gt 0) {
    Write-Host "Databases fixed:" -ForegroundColor Cyan
    foreach ($change in $fixed | Sort-Object {if($_.IsProd -eq "YES"){0}else{1}}) {
        $type = if($change.IsProd -eq "YES"){"PROD"}else{"Non-Prod"}
        Write-Host "  [$type] $($change.Database): $($change.FromTier) -> $($change.ToTier)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Changes will apply in 2-3 minutes" -ForegroundColor Yellow
} else {
    Write-Host "No databases needed fixing" -ForegroundColor Green
}

Write-Host ""
Write-Host "Change history: $ChangeHistoryFile" -ForegroundColor Cyan
Write-Host "Syed Rizvi" -ForegroundColor White
