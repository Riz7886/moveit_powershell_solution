# SQL DTU Weekly Optimizer - Automated Monitoring for MOVEit Server
# Runs weekly, maintains sweet spot, sends HTML report to Tony
# Author: Syed Rizvi

param([switch]$AutoFix)

$ErrorActionPreference = "SilentlyContinue"
$LogPath = "C:\Temp\SQL_DTU_Optimizer"
$ReportPath = Join-Path $LogPath "Reports"
if (!(Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }

$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$HtmlReport = Join-Path $ReportPath "Weekly_DTU_Report_$timestamp.html"

Write-Host "SQL DTU Weekly Optimizer" -ForegroundColor Cyan
Write-Host "Syed Rizvi - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

@('Az.Accounts','Az.Sql','Az.Monitor') | ForEach-Object {
    if (!(Get-Module -ListAvailable -Name $_)) { 
        Install-Module -Name $_ -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
    }
    Import-Module $_
}

$ctx = Get-AzContext
if (!$ctx) { Connect-AzAccount | Out-Null; $ctx = Get-AzContext }

function Get-OptimalDTU {
    param($CurrentDTU, $MaxPercent, $IsProd)
    if ($MaxPercent -eq 0) { return $CurrentDTU }
    $actualUsed = ($CurrentDTU * $MaxPercent) / 100
    $targetUtilization = if ($IsProd) { 0.50 } else { 0.60 }
    $needed = [math]::Ceiling($actualUsed / $targetUtilization)
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

$allDatabases = @()
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' }

Write-Host "Scanning databases..." -ForegroundColor Yellow

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    $servers = Get-AzSqlServer
    
    foreach ($server in $servers) {
        $dbs = Get-AzSqlDatabase -ServerName $server.ServerName -ResourceGroupName $server.ResourceGroupName | Where-Object { $_.DatabaseName -ne 'master' }
        
        foreach ($db in $dbs) {
            $isProd = $db.DatabaseName -like "*prod*"
            $currentTier = $db.SkuName
            $currentDTU = switch -Regex ($currentTier) {
                'S0' { 10 }; 'S1' { 20 }; 'S2' { 50 }; 'S3' { 100 }
                'S4' { 200 }; 'S6' { 400 }; 'S7' { 800 }
                'S9' { 1600 }; 'S12' { 3000 }
                default { 10 }
            }
            
            $endTime = Get-Date
            $startTime = $endTime.AddDays(-7)
            $metric = Get-AzMetric -ResourceId $db.ResourceId -MetricName "dtu_consumption_percent" -StartTime $startTime -EndTime $endTime -TimeGrain 01:00:00 -AggregationType Average
            
            $maxDTU = 0
            if ($metric -and $metric.Data) {
                $valid = $metric.Data | Where-Object { $_.Average -ne $null }
                if ($valid) {
                    $maxDTU = [math]::Round(($valid | Measure-Object -Property Average -Maximum).Maximum, 2)
                }
            }
            
            $optimalDTU = Get-OptimalDTU -CurrentDTU $currentDTU -MaxPercent $maxDTU -IsProd $isProd
            
            $allDatabases += [PSCustomObject]@{
                Database = $db.DatabaseName
                Server = $server.ServerName
                IsProd = $isProd
                CurrentTier = $currentTier
                MaxPercent = $maxDTU
                OptimalTier = Get-TierName -DTU $optimalDTU
                NeedsChange = ($optimalDTU -ne $currentDTU -and $maxDTU -gt 65)
            }
        }
    }
}

$needsAttention = $allDatabases | Where-Object { $_.NeedsChange }

$html = @"
<!DOCTYPE html>
<html>
<head><title>Weekly DTU Report</title>
<style>body{font-family:Arial;padding:20px}table{border-collapse:collapse;width:100%}th{background:#0078d4;color:white;padding:10px}td{padding:8px;border-bottom:1px solid #ddd}</style>
</head>
<body>
<h1>Weekly SQL DTU Report</h1>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Analyst: Syed Rizvi</p>
<h2>Databases Needing Attention ($($needsAttention.Count))</h2>
<table><tr><th>Database</th><th>Server</th><th>Type</th><th>Current</th><th>Max%</th><th>Optimal</th></tr>
"@

foreach ($db in ($needsAttention | Sort-Object {if($_.IsProd){0}else{1}})) {
    $type = if($db.IsProd){"PROD"}else{"NON-PROD"}
    $html += "<tr><td>$($db.Database)</td><td>$($db.Server)</td><td>$type</td><td>$($db.CurrentTier)</td><td>$($db.MaxPercent)%</td><td>$($db.OptimalTier)</td></tr>"
}

$html += "</table><p>Syed Rizvi | $(Get-Date -Format 'yyyy-MM-dd')</p></body></html>"
$html | Out-File -FilePath $HtmlReport -Encoding UTF8

$emailParams = @{
    From = "sql-monitor@pyxhealth.com"
    To = "tony.schlak@pyxhealth.com"
    Subject = "Weekly SQL DTU Report - $($needsAttention.Count) Databases Need Attention"
    Body = $html
    BodyAsHtml = $true
    SmtpServer = "smtp.office365.com"
    Port = 587
    UseSsl = $true
    Credential = (New-Object System.Management.Automation.PSCredential("sql-monitor@pyxhealth.com", (ConvertTo-SecureString "YourPasswordHere" -AsPlainText -Force)))
}

try {
    Send-MailMessage @emailParams
    Write-Host "Email sent to Tony" -ForegroundColor Green
} catch {
    Write-Host "Email failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Report saved: $HtmlReport" -ForegroundColor Green
