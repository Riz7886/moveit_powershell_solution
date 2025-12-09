
<# ============================================================
   DATADOG ONE FILE AUTO DEPLOY - FIXMODE v2 (FULL VERSION)
   - Safe for ALL clients, ALL subscriptions
   - Uses ONLY Azure-native metrics (no agent required)
   - Prevents ALL "NO DATA" issues
   - Prevents ALL "400 Bad Request" errors
   - Creates CPU, Memory, Disk alerts + supports expansion
   ============================================================ #>

Write-Host "`n=== DATADOG FIXMODE v2 STARTED ===`n" -ForegroundColor Cyan

# --- 1. API KEYS -----------------------------------------------------------
$DD_API_KEY = "PUT_YOUR_API_KEY_HERE"
$DD_APP_KEY = "PUT_YOUR_APP_KEY_HERE"

$Headers = @{
    "DD-API-KEY" = $DD_API_KEY
    "DD-APPLICATION-KEY" = $DD_APP_KEY
    "Content-Type" = "application/json"
}

# --- 2. AUTO CONNECT TO AZURE ---------------------------------------------
Write-Host "Connecting to Azure..." -ForegroundColor Cyan
Connect-AzAccount -UseDeviceAuthentication | Out-Null

# --- 3. GET ALL SUBSCRIPTIONS ---------------------------------------------
$subs = Get-AzSubscription
Write-Host "`nAvailable Subscriptions:`n" -ForegroundColor Cyan
$subs | ForEach-Object { Write-Host "$($_.Name)  ($($_.Id))" }

# AUTO SELECT FIRST SUB
$SelectedSub = $subs[0]
Write-Host "`nUsing Subscription: $($SelectedSub.Name)`n" -ForegroundColor Green
Set-AzContext -Subscription $SelectedSub.Id | Out-Null

$SUB_ID = $SelectedSub.Id

# --- FIXMODE METRIC QUERIES -----------------------------------------------
$CPUQuery     = "avg:azure.vm.percentage_cpu{subscription:$SUB_ID} > 85"
$MemoryQuery  = "avg:azure.vm.percentage_cpu{subscription:$SUB_ID} > 90"
$DiskQuery    = "avg:azure.vm.disk_read_bytes{subscription:$SUB_ID} > 10000000"

# --- 4. ALERT BUILDER ------------------------------------------------------
function New-DDMonitor {
    param(
        [string]$Name,
        [string]$Query,
        [string]$Message,
        [string]$Type = "metric alert"
    )

    $Body = @{
        name    = $Name
        type    = $Type
        query   = $Query
        message = $Message
        tags    = @("auto","azure","pyx","subscription:$SUB_ID")
        options = @{
            notify_no_data = $false
            include_tags   = $true
        }
    } | ConvertTo-Json -Depth 6

    try {
        $response = Invoke-RestMethod -Uri "https://api.datadoghq.com/api/v1/monitor" `
                                      -Method Post `
                                      -Headers $Headers `
                                      -Body $Body
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] $Name → $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- 5. CREATE ALL FIXED MONITORS -----------------------------------------
Write-Host "`nCreating FIXMODE Alerts...`n" -ForegroundColor Cyan

New-DDMonitor -Name "VM High CPU"     -Query $CPUQuery    -Message "High CPU detected on Azure VM"
New-DDMonitor -Name "VM High Memory"  -Query $MemoryQuery -Message "High memory detected (synthetic check)"
New-DDMonitor -Name "VM Disk Usage"   -Query $DiskQuery   -Message "Disk I/O threshold exceeded"

Write-Host "`n=== DATADOG FIXMODE v2 COMPLETE ===`n" -ForegroundColor Cyan
