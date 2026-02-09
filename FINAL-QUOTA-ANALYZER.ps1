#Requires -Version 5.1
<#
.SYNOPSIS
    COMPLETE Databricks Quota Root Cause Analyzer - FINAL VERSION
    Everything embedded - just run it
#>

$ErrorActionPreference = "Continue"

# ============================================================================
# HARDCODED SETTINGS - NO INPUT NEEDED
# ============================================================================
$workspace = "https://adb-324884819348686.6.azuredatabricks.net"
$token = "dapi9abaad71d0865d1a32a08cba05a318b7"
$location = "eastus"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$rootCauses = @()
$recommendations = @()

# ============================================================================
# LOGGING
# ============================================================================
$logFile = ".\QuotaAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Msg"
    
    switch ($Level) {
        "ERROR"     { Write-Host $line -ForegroundColor Red }
        "WARN"      { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS"   { Write-Host $line -ForegroundColor Green }
        "CRITICAL"  { Write-Host $line -ForegroundColor Magenta }
        "ROOTCAUSE" { Write-Host $line -ForegroundColor Cyan }
        default     { Write-Host $line }
    }
    
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Write-Banner {
    param([string]$Title)
    $line = "=" * 80
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# START
# ============================================================================
Write-Banner "DATABRICKS QUOTA ROOT CAUSE ANALYZER - FINAL"
Write-Log "Workspace: $workspace" "SUCCESS"
Write-Log "Analysis started" "SUCCESS"

# ============================================================================
# STEP 1: CHECK CLUSTERS
# ============================================================================
Write-Banner "ANALYZING CLUSTERS"

try {
    $clustersResp = Invoke-RestMethod -Uri "$workspace/api/2.0/clusters/list" -Headers $headers -Method Get -ErrorAction Stop
    
    if ($clustersResp.clusters) {
        $clusters = $clustersResp.clusters
        Write-Log "Found $($clusters.Count) clusters" "SUCCESS"
        
        foreach ($cluster in $clusters) {
            $name = $cluster.cluster_name
            $state = $cluster.state
            
            Write-Log ""
            Write-Log "Cluster: $name (State: $state)" "INFO"
            
            # CHECK 1: Autoscaling
            if (-not $cluster.autoscale) {
                $workers = if ($cluster.num_workers) { $cluster.num_workers } else { "Unknown" }
                Write-Log "  ⚠ NO AUTOSCALING - Fixed at $workers workers" "WARN"
                $rootCauses += "Cluster '$name' has NO AUTOSCALING (fixed workers = resource waste)"
                $recommendations += "Enable autoscaling on cluster '$name' with min=1, max=8 workers"
            }
            else {
                $minW = $cluster.autoscale.min_workers
                $maxW = $cluster.autoscale.max_workers
                Write-Log "  ✓ Autoscale: $minW to $maxW workers" "SUCCESS"
                
                if ($maxW -gt 20) {
                    Write-Log "  ⚠ MAX WORKERS TOO HIGH: $maxW (quota risk!)" "ERROR"
                    $rootCauses += "Cluster '$name' max workers = $maxW (can cause quota breach)"
                    $recommendations += "Reduce max workers on cluster '$name' from $maxW to 12"
                }
            }
            
            # CHECK 2: Auto-termination
            $autoTerm = $cluster.autotermination_minutes
            if (-not $autoTerm -or $autoTerm -eq 0) {
                Write-Log "  ⚠ NO AUTO-TERMINATION (runs forever!)" "ERROR"
                $rootCauses += "Cluster '$name' has NO AUTO-TERMINATION (wastes resources continuously)"
                $recommendations += "Enable auto-termination on cluster '$name' (30 minutes recommended)"
            }
            elseif ($autoTerm -gt 120) {
                Write-Log "  ⚠ Auto-terminate too long: $autoTerm min" "WARN"
                $recommendations += "Reduce auto-termination on cluster '$name' from $autoTerm to 60 minutes"
            }
            else {
                Write-Log "  ✓ Auto-terminate: $autoTerm min" "SUCCESS"
            }
            
            # CHECK 3: Node type (vCPU count)
            if ($cluster.node_type_id) {
                Write-Log "  Node type: $($cluster.node_type_id)" "INFO"
            }
        }
    }
    else {
        Write-Log "No clusters found" "WARN"
    }
}
catch {
    Write-Log "Failed to get clusters: $($_.Exception.Message)" "ERROR"
}

# ============================================================================
# STEP 2: CHECK SQL WAREHOUSES
# ============================================================================
Write-Banner "ANALYZING SQL WAREHOUSES"

try {
    $warehousesResp = Invoke-RestMethod -Uri "$workspace/api/2.0/sql/warehouses" -Headers $headers -Method Get -ErrorAction Stop
    
    if ($warehousesResp.warehouses) {
        $warehouses = $warehousesResp.warehouses
        Write-Log "Found $($warehouses.Count) SQL warehouses" "SUCCESS"
        
        foreach ($wh in $warehouses) {
            Write-Log ""
            Write-Log "SQL Warehouse: $($wh.name)" "INFO"
            Write-Log "  State: $($wh.state)" "INFO"
            Write-Log "  Size: $($wh.cluster_size)" "INFO"
            Write-Log "  Auto-stop: $($wh.auto_stop_mins) min" "INFO"
            Write-Log "  Num clusters: $($wh.num_clusters)" "INFO"
            
            if ($wh.num_clusters -gt 5) {
                Write-Log "  ⚠ Many clusters: $($wh.num_clusters)" "WARN"
                $rootCauses += "SQL Warehouse '$($wh.name)' has $($wh.num_clusters) clusters (high resource usage)"
            }
        }
    }
    else {
        Write-Log "No SQL warehouses found" "INFO"
    }
}
catch {
    Write-Log "Failed to get SQL warehouses: $($_.Exception.Message)" "ERROR"
}

# ============================================================================
# STEP 3: CHECK AZURE QUOTA
# ============================================================================
Write-Banner "CHECKING AZURE QUOTA"

try {
    # Install Az modules if needed
    $modules = @("Az.Accounts", "Az.Compute")
    foreach ($mod in $modules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Log "Installing $mod..." "WARN"
            Install-Module $mod -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
        }
    }
    
    Import-Module Az.Accounts -Force -ErrorAction SilentlyContinue
    Import-Module Az.Compute -Force -ErrorAction SilentlyContinue
    
    # Check if logged in
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        Write-Log "Connecting to Azure..." "WARN"
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }
    
    Write-Log "Checking quota in region: $location" "INFO"
    $usages = Get-AzVMUsage -Location $location -ErrorAction Stop
    
    $topUsages = $usages | Where-Object {
        $_.Limit -gt 0 -and $_.CurrentValue -gt 0
    } | Sort-Object { $_.CurrentValue / $_.Limit } -Descending | Select-Object -First 10
    
    Write-Log ""
    Write-Log ("{0,-50} {1,10} {2,10} {3,10}" -f "VM Family", "Used", "Limit", "Usage%") "INFO"
    Write-Log ("-" * 85) "INFO"
    
    foreach ($usage in $topUsages) {
        $pct = [math]::Round(($usage.CurrentValue / $usage.Limit) * 100, 1)
        $level = if ($pct -gt 90) { "CRITICAL" } elseif ($pct -gt 80) { "ERROR" } elseif ($pct -gt 60) { "WARN" } else { "SUCCESS" }
        
        Write-Log ("{0,-50} {1,10} {2,10} {3,9}%" -f $usage.Name.LocalizedValue, $usage.CurrentValue, $usage.Limit, $pct) $level
        
        if ($pct -gt 90) {
            $rootCauses += "QUOTA BREACH: $($usage.Name.LocalizedValue) at $pct% ($($usage.CurrentValue)/$($usage.Limit) vCPUs)"
            $newLimit = [int]([Math]::Max($usage.Limit * 2, $usage.CurrentValue * 2.5))
            $recommendations += "REQUEST QUOTA INCREASE for $($usage.Name.LocalizedValue): $($usage.Limit) → $newLimit vCPUs"
        }
        elseif ($pct -gt 80) {
            $recommendations += "Monitor $($usage.Name.LocalizedValue) quota - at $pct% usage"
        }
    }
}
catch {
    Write-Log "Could not check Azure quota: $($_.Exception.Message)" "WARN"
    Write-Log "You may need to run 'Connect-AzAccount' first" "WARN"
}

# ============================================================================
# STEP 4: ROOT CAUSE SUMMARY
# ============================================================================
Write-Banner "ROOT CAUSE ANALYSIS - SUMMARY"

if ($rootCauses.Count -eq 0) {
    Write-Log "✓ No critical root causes identified" "SUCCESS"
    Write-Log "Your quota breach may have been temporary or already resolved" "INFO"
}
else {
    Write-Log "=== IDENTIFIED ROOT CAUSES ===" "CRITICAL"
    for ($i = 0; $i -lt $rootCauses.Count; $i++) {
        Write-Log "$($i + 1). $($rootCauses[$i])" "ROOTCAUSE"
    }
}

Write-Log ""

if ($recommendations.Count -gt 0) {
    Write-Log "=== RECOMMENDATIONS ===" "SUCCESS"
    for ($i = 0; $i -lt $recommendations.Count; $i++) {
        Write-Log "$($i + 1). $($recommendations[$i])" "SUCCESS"
    }
}

# ============================================================================
# STEP 5: NEXT STEPS
# ============================================================================
Write-Banner "NEXT STEPS"

Write-Log "1. Review the root causes identified above" "INFO"
Write-Log "2. If quota increase needed, submit request in Azure Portal:" "INFO"
Write-Log "   https://portal.azure.com/#view/Microsoft_Azure_Capacity/QuotaMenuBlade/~/myQuotas" "INFO"
Write-Log "3. Reply to Databricks Support ticket with findings" "INFO"
Write-Log "4. Enable autoscaling and auto-termination on problematic clusters" "INFO"
Write-Log "5. Monitor for 24-48 hours to ensure no new alerts" "INFO"

Write-Log ""
Write-Log "=== ANALYSIS COMPLETE ===" "SUCCESS"
Write-Log "Log file saved: $logFile" "SUCCESS"
Write-Log ""

# Export summary to file
$summaryFile = ".\QuotaSummary_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$summary = @"
DATABRICKS QUOTA ROOT CAUSE ANALYSIS
=====================================
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Workspace: $workspace

ROOT CAUSES IDENTIFIED ($($rootCauses.Count)):
$(if ($rootCauses.Count -eq 0) { "None - quota breach may have been temporary" } else { ($rootCauses | ForEach-Object { "  - $_" }) -join "`n" })

RECOMMENDATIONS ($($recommendations.Count)):
$(if ($recommendations.Count -eq 0) { "None" } else { ($recommendations | ForEach-Object { "  - $_" }) -join "`n" })

NEXT STEPS:
  1. Review root causes above
  2. Submit quota increase if needed (Azure Portal)
  3. Update Databricks Support ticket
  4. Enable autoscaling and auto-termination
  5. Monitor for 24-48 hours

Full log: $logFile
"@

Set-Content -Path $summaryFile -Value $summary
Write-Log "Summary exported: $summaryFile" "SUCCESS"
