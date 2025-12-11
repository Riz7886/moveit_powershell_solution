param(
    [string]$DatabricksWorkspaceUrl,
    [string]$DatabricksToken
)

$ErrorActionPreference = "Stop"

Write-Host "SAFE RESTART MODE — CLEAN VERSION" -ForegroundColor Cyan

$DatabricksWorkspaceUrl = $DatabricksWorkspaceUrl.TrimEnd('/')
$apiUrl = "$DatabricksWorkspaceUrl/api/2.0"

$headers = @{
    "Authorization" = "Bearer $DatabricksToken"
    "Content-Type"  = "application/json"
}

Write-Host "Getting clusters..." -ForegroundColor Yellow
$response = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers

$clusters = $response.clusters
if (-not $clusters) {
    Write-Host "No clusters found" -ForegroundColor Red
    exit
}

Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green

foreach ($cluster in $clusters) {

    Write-Host "Restarting cluster: $($cluster.cluster_name)" -ForegroundColor Cyan

    $body = @{ cluster_id = $cluster.cluster_id } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$apiUrl/clusters/restart" -Method Post -Headers $headers -Body $body
        Write-Host " → Restart triggered" -ForegroundColor Green
    }
    catch {
        Write-Host " → ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "SAFE RESTART COMPLETE — NO NAMES CHANGED. NO CONFIG MODIFIED." -ForegroundColor Green
