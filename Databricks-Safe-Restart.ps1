<#
SAFE CLUSTER RESTART SCRIPT FOR DATABRICKS
⚠ DOES NOT CHANGE CLUSTER NAME
⚠ DOES NOT MODIFY ANY CONFIG
⚠ ONLY TRIGGERS A RESTART AUTOMATICALLY
#>

param(
    [string]$DatabricksWorkspaceUrl,
    [string]$DatabricksToken
)

$ErrorActionPreference = "Stop"

Write-Host "SAFE RESTART MODE — NO RENAMES, NO CONFIG CHANGES" -ForegroundColor Cyan

$DatabricksWorkspaceUrl = $DatabricksWorkspaceUrl.TrimEnd('/')
$apiUrl = "$DatabricksWorkspaceUrl/api/2.0"

$headers = @{
    "Authorization" = "Bearer $DatabricksToken"
    "Content-Type"  = "application/json"
}

Write-Host "Fetching clusters…" -ForegroundColor Yellow
$response = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers

$clusters = $response.clusters
if (-not $clusters) {
    Write-Host "No clusters found" -ForegroundColor Red
    exit
}

Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green

foreach ($cluster in $clusters) {

    Write-Host ""
    Write-Host "Restarting cluster: $($cluster.cluster_name)" -ForegroundColor Cyan
    Write-Host "Cluster ID: $($cluster.cluster_id)" -ForegroundColor DarkGray

    $body = @{ cluster_id = $cluster.cluster_id } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$apiUrl/clusters/restart" -Method Post -Headers $headers -Body $body
        Write-Host " → Restart triggered successfully" -ForegroundColor Green
    }
    catch {
        Write-Host " → Restart failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "ALL CLUSTERS HAVE BEEN SENT RESTART SIGNAL." -ForegroundColor Green
Write-Host "NO CONFIGS WERE MODIFIED. NO NAMES WERE CHANGED." -ForegroundColor Green
