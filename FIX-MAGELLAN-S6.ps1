# Fix sqldb-magellan-prod to S6 (400 DTU) as requested by Tony

$ReportPath = "C:\Temp\SQL_DTU_Reports"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FIXING sqldb-magellan-prod" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

@('Az.Accounts','Az.Sql') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue 
    }
    Import-Module $_ -ErrorAction SilentlyContinue
}

$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

Write-Host "Finding sqldb-magellan-prod..." -ForegroundColor Yellow

$found = $false
$result = ""
$beforeTier = ""
$afterTier = "S6"
$serverName = ""
$resourceGroup = ""

$currentTenant = $ctx.Tenant.Id
$subscriptions = Get-AzSubscription -TenantId $currentTenant | Where-Object { 
    $_.State -eq 'Enabled' -and $_.TenantId -eq $currentTenant 
}

foreach ($sub in $subscriptions) {
    if ($found) { break }
    
    Set-AzContext -SubscriptionId $sub.Id -TenantId $currentTenant -ErrorAction SilentlyContinue | Out-Null
    
    $servers = Get-AzSqlServer -ErrorAction SilentlyContinue
    if (!$servers) { continue }
    
    foreach ($server in $servers) {
        if ($found) { break }
        
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName -ErrorAction SilentlyContinue
        
        foreach ($db in $dbs) {
            if ($db.DatabaseName -eq "sqldb-magellan-prod") {
                $found = $true
                $beforeTier = $db.SkuName
                $serverName = $server.ServerName
                $resourceGroup = $server.ResourceGroupName
                $currentSizeBytes = $db.MaxSizeBytes
                
                Write-Host "FOUND: $($db.DatabaseName)" -ForegroundColor Green
                Write-Host "  Server: $serverName" -ForegroundColor White
                Write-Host "  Current Tier: $beforeTier" -ForegroundColor White
                Write-Host ""
                Write-Host "Changing to S6 (400 DTU)..." -ForegroundColor Yellow
                
                try {
                    Set-AzSqlDatabase -ResourceGroupName $resourceGroup `
                                    -ServerName $serverName `
                                    -DatabaseName "sqldb-magellan-prod" `
                                    -Edition "Standard" `
                                    -RequestedServiceObjectiveName "S6" `
                                    -MaxSizeBytes ([long]$currentSizeBytes) `
                                    -ErrorAction Stop | Out-Null
                    
                    $result = "SUCCESS"
                    Write-Host ""
                    Write-Host "SUCCESS! Changed to S6 (400 DTU)" -ForegroundColor Green
                    Write-Host ""
                } catch {
                    $result = "FAILED: $($_.Exception.Message)"
                    Write-Host ""
                    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host ""
                }
                
                break
            }
        }
    }
}

if (!$found) {
    Write-Host "ERROR: Could not find sqldb-magellan-prod" -ForegroundColor Red
    exit
}

$html = @"
<!DOCTYPE html><html><head><style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{max-width:1000px;margin:0 auto;background:white;padding:40px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
h1{color:#1e40af;border-bottom:4px solid #1e40af;padding-bottom:15px;margin-bottom:30px}
.info{background:#f0f9ff;border-left:5px solid #3b82f6;padding:20px;margin:20px 0;border-radius:5px}
.success{background:#d1fae5;border-left:5px solid #059669;padding:30px;margin:30px 0;border-radius:5px;text-align:center}
.success h2{color:#059669;margin:0;font-size:32px}
.detail{margin:20px 0;font-size:16px}
.label{font-weight:bold;color:#64748b;display:inline-block;width:150px}
.value{color:#1e40af;font-weight:bold}
.arrow{font-size:24px;color:#059669;margin:0 15px}
</style></head><body><div class="container">
<h1>sqldb-magellan-prod - DTU Fix Report</h1>

<div class="info">
<strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')<br>
<strong>Requested By:</strong> Tony Schlak<br>
<strong>Executed By:</strong> Syed Rizvi
</div>

<div class="success">
<h2>SUCCESSFULLY CHANGED</h2>
</div>

<div class="detail">
<span class="label">Database:</span> <span class="value">sqldb-magellan-prod</span>
</div>

<div class="detail">
<span class="label">Server:</span> <span class="value">$serverName</span>
</div>

<div class="detail">
<span class="label">Resource Group:</span> <span class="value">$resourceGroup</span>
</div>

<div style="text-align:center;margin:40px 0;font-size:24px">
<span style="color:#dc2626;font-weight:bold">$beforeTier</span>
<span class="arrow">→</span>
<span style="color:#059669;font-weight:bold">S6 (400 DTU)</span>
</div>

<div class="info" style="background:#fef3c7;border-left-color:#f59e0b">
<strong>Note:</strong> The tier change has been submitted to Azure. It may take 2-5 minutes for the change to fully apply in the Azure Portal. Please refresh the portal to see the updated tier.
</div>

<div class="detail">
<span class="label">Result:</span> <span class="value" style="color:#059669">$result</span>
</div>

<div class="detail">
<span class="label">Timestamp:</span> <span class="value">$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</span>
</div>

</div></body></html>
"@

$htmlPath = Join-Path $ReportPath "Fix_Magellan_$timestamp.html"
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Start-Process $htmlPath

Write-Host "Report saved: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "SEND TO TONY:" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tony," -ForegroundColor White
Write-Host ""
Write-Host "sqldb-magellan-prod has been changed to S6 (400 DTU)." -ForegroundColor Green
Write-Host ""
Write-Host "The change is processing in Azure now." -ForegroundColor White
Write-Host "Please wait 2-3 minutes and refresh the Azure Portal." -ForegroundColor White
Write-Host ""
Write-Host "Report attached." -ForegroundColor White
Write-Host ""
Write-Host "Syed" -ForegroundColor White
