# SIMPLE DATABRICKS QUOTA CHECKER - NO BS VERSION

Write-Host "=== DATABRICKS QUOTA CHECKER ===" -ForegroundColor Cyan
Write-Host ""

# Get inputs
$workspace = Read-Host "Enter Databricks workspace URL (e.g., https://adb-324884819348686.6.azuredatabricks.net)"
$token = Read-Host "Enter your Databricks token"

# Setup
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

Write-Host ""
Write-Host "=== CHECKING CLUSTERS ===" -ForegroundColor Yellow
Write-Host ""

try {
    $clusters = Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/list" -Headers $headers -Method Get
    
    if ($clusters.clusters) {
        foreach ($c in $clusters.clusters) {
            Write-Host "Cluster: $($c.cluster_name)" -ForegroundColor Green
            Write-Host "  State: $($c.state)"
            
            if (-not $c.autoscale) {
                $workers = if ($c.num_workers) { $c.num_workers } else { "Unknown" }
                Write-Host "  ISSUE: NO AUTOSCALING - Fixed at $workers workers" -ForegroundColor Red
            } else {
                Write-Host "  Autoscale: $($c.autoscale.min_workers) to $($c.autoscale.max_workers) workers" -ForegroundColor Green
                if ($c.autoscale.max_workers -gt 20) {
                    Write-Host "  WARNING: Max workers very high ($($c.autoscale.max_workers)) - quota risk!" -ForegroundColor Red
                }
            }
            
            if (-not $c.autotermination_minutes -or $c.autotermination_minutes -eq 0) {
                Write-Host "  ISSUE: NO AUTO-TERMINATION - Runs forever!" -ForegroundColor Red
            } else {
                Write-Host "  Auto-terminate: $($c.autotermination_minutes) minutes" -ForegroundColor Green
            }
            
            Write-Host ""
        }
    } else {
        Write-Host "No clusters found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Could not connect to Databricks" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

Write-Host "=== CHECKING AZURE QUOTA ===" -ForegroundColor Yellow
Write-Host ""

try {
    # Try to get Azure quota
    $location = "eastus"
    $usages = Get-AzVMUsage -Location $location -ErrorAction Stop
    
    $top = $usages | Where-Object { 
        $_.Limit -gt 0 -and $_.CurrentValue -gt 0 
    } | Sort-Object { 
        ($_.CurrentValue / $_.Limit) 
    } -Descending | Select-Object -First 10
    
    Write-Host "Top 10 VM Families by Usage:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("{0,-50} {1,10} {2,10} {3,10}" -f "VM Family", "Used", "Limit", "Usage%")
    Write-Host ("-" * 85)
    
    foreach ($u in $top) {
        $pct = [math]::Round(($u.CurrentValue / $u.Limit) * 100, 1)
        $color = "White"
        if ($pct -gt 90) { $color = "Red" }
        elseif ($pct -gt 80) { $color = "Yellow" }
        elseif ($pct -gt 60) { $color = "Yellow" }
        
        Write-Host ("{0,-50} {1,10} {2,10} {3,9}%" -f $u.Name.LocalizedValue, $u.CurrentValue, $u.Limit, $pct) -ForegroundColor $color
        
        if ($pct -gt 90) {
            Write-Host "  >> QUOTA BREACH! Request increase from $($u.Limit) to $([int]($u.Limit * 2)) vCPUs" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Could not check Azure quota - you may not be logged into Azure" -ForegroundColor Yellow
    Write-Host "Run 'Connect-AzAccount' first if you want quota info" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Check complete. Look for RED warnings above." -ForegroundColor Green
Write-Host ""
