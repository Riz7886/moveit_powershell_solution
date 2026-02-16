$ErrorActionPreference = "Continue"

Write-Host "DATABRICKS DIAGNOSTICS" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1] Azure Login Status" -ForegroundColor Yellow
try {
    $account = az account show | ConvertFrom-Json
    Write-Host "OK: $($account.user.name)" -ForegroundColor Green
    $subId = $account.id
    Write-Host "Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Not logged in" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2] Finding Databricks Workspaces" -ForegroundColor Yellow
try {
    $workspaces = az resource list --resource-type "Microsoft.Databricks/workspaces" --subscription $subId | ConvertFrom-Json
    
    if ($workspaces -and $workspaces.Count -gt 0) {
        Write-Host "Found $($workspaces.Count) workspaces:" -ForegroundColor Green
        foreach ($ws in $workspaces) {
            Write-Host "  - Name: $($ws.name)" -ForegroundColor White
            Write-Host "    RG: $($ws.resourceGroup)" -ForegroundColor Gray
            Write-Host "    URL: $($ws.properties.workspaceUrl)" -ForegroundColor Gray
        }
    } else {
        Write-Host "No workspaces found via az resource list" -ForegroundColor Yellow
        Write-Host "Trying alternative methods..." -ForegroundColor Yellow
        
        $ws1 = az databricks workspace show --name "pyxlake-databricks" --resource-group "rg-adls-poc" 2>$null | ConvertFrom-Json
        $ws2 = az databricks workspace show --name "pyx-warehouse-prod" --resource-group "rg-warehouse-preprod" 2>$null | ConvertFrom-Json
        
        if ($ws1) {
            Write-Host "  Found: pyxlake-databricks" -ForegroundColor Green
            Write-Host "    URL: $($ws1.workspaceUrl)" -ForegroundColor Gray
        }
        if ($ws2) {
            Write-Host "  Found: pyx-warehouse-prod" -ForegroundColor Green
            Write-Host "    URL: $($ws2.workspaceUrl)" -ForegroundColor Gray
        }
        
        $workspaces = @($ws1, $ws2) | Where-Object { $_ -ne $null }
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "[3] Testing Databricks Token" -ForegroundColor Yellow
try {
    $token = az account get-access-token --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" --query accessToken -o tsv
    if ($token) {
        Write-Host "OK: Token acquired (length: $($token.Length))" -ForegroundColor Green
    } else {
        Write-Host "FAILED: No token" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "[4] Testing Workspace Connectivity" -ForegroundColor Yellow

foreach ($ws in $workspaces) {
    if (-not $ws) { continue }
    
    $wsUrl = if ($ws.properties.workspaceUrl) {
        $ws.properties.workspaceUrl
    } elseif ($ws.workspaceUrl) {
        $ws.workspaceUrl
    } else {
        Write-Host "  No URL for $($ws.name)" -ForegroundColor Red
        continue
    }
    
    $fullUrl = "https://$wsUrl"
    Write-Host "  Testing: $fullUrl" -ForegroundColor White
    
    try {
        $headers = @{
            Authorization = "Bearer $token"
        }
        
        $testUrl = "$fullUrl/api/2.0/preview/scim/v2/Me"
        $result = Invoke-RestMethod -Uri $testUrl -Headers $headers -TimeoutSec 10
        Write-Host "    SUCCESS: API is accessible" -ForegroundColor Green
    } catch {
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Message -like "*could not be resolved*") {
            Write-Host "    => DNS RESOLUTION FAILED" -ForegroundColor Red
            Write-Host "    => Testing DNS lookup..." -ForegroundColor Yellow
            try {
                $dns = Resolve-DnsName $wsUrl -ErrorAction Stop
                Write-Host "       DNS OK: $($dns.IPAddress)" -ForegroundColor Green
            } catch {
                Write-Host "       DNS FAILED: Cannot resolve $wsUrl" -ForegroundColor Red
            }
        } elseif ($_.Exception.Message -like "*400*") {
            Write-Host "    => BAD REQUEST (400)" -ForegroundColor Red
        } elseif ($_.Exception.Message -like "*401*") {
            Write-Host "    => UNAUTHORIZED (401) - Token issue" -ForegroundColor Red
        } elseif ($_.Exception.Message -like "*403*") {
            Write-Host "    => FORBIDDEN (403) - Permission issue" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "DIAGNOSTICS COMPLETE" -ForegroundColor Cyan
Write-Host ""
