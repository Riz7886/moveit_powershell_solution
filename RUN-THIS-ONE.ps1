param(
    [string]$DatadogApiKey,
    [string]$DatabricksWorkspaceUrl,
    [string]$DatabricksToken,
    [string]$DatadogSite = "datadoghq.com"
)

$ErrorActionPreference = "Stop"

Write-Host "Starting Databricks Datadog Configuration" -ForegroundColor Cyan

$DatabricksWorkspaceUrl = $DatabricksWorkspaceUrl.TrimEnd('/')
$dbfsPath = "/databricks/datadog/install-datadog-agent.sh"
$apiUrl = "$DatabricksWorkspaceUrl/api/2.0"

$headers = @{
    "Authorization" = "Bearer $DatabricksToken"
    "Content-Type" = "application/json"
}

$bashScript = @"
#!/bin/bash
export DD_API_KEY="$DatadogApiKey"
export DD_SITE="$DatadogSite"
DD_AGENT_MAJOR_VERSION=7 bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl start datadog-agent
"@

Write-Host "Creating init script" -ForegroundColor Yellow

$scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($bashScript)
$scriptBase64 = [System.Convert]::ToBase64String($scriptBytes)

Write-Host "Creating DBFS directory" -ForegroundColor Yellow

$mkdirBody = @{ path = "/databricks/datadog" } | ConvertTo-Json
Invoke-RestMethod -Uri "$apiUrl/dbfs/mkdirs" -Method Post -Headers $headers -Body $mkdirBody -ErrorAction SilentlyContinue | Out-Null

Write-Host "Uploading script to DBFS" -ForegroundColor Yellow

$putBody = @{
    path = $dbfsPath
    contents = $scriptBase64
    overwrite = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "$apiUrl/dbfs/put" -Method Post -Headers $headers -Body $putBody | Out-Null

Write-Host "Getting clusters" -ForegroundColor Yellow

$response = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers
$clusters = $response.clusters

Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green

$updated = 0

foreach ($cluster in $clusters) {
    Write-Host "Configuring: $($cluster.cluster_name)" -ForegroundColor White
    
    $getUrl = "$apiUrl/clusters/get?cluster_id=$($cluster.cluster_id)"
    $config = Invoke-RestMethod -Uri $getUrl -Method Get -Headers $headers
    
    $scripts = @()
    if ($config.init_scripts) {
        $scripts = $config.init_scripts
    }
    
    $scripts += @{ dbfs = @{ destination = "dbfs:$dbfsPath" } }
    
    $body = @{
        cluster_id = $cluster.cluster_id
        spark_version = $config.spark_version
        node_type_id = $config.node_type_id
        init_scripts = $scripts
    }
    
    if ($config.num_workers) { $body.num_workers = $config.num_workers }
    if ($config.autoscale) { $body.autoscale = $config.autoscale }
    
    $json = $body | ConvertTo-Json -Depth 10
    
    Invoke-RestMethod -Uri "$apiUrl/clusters/edit" -Method Post -Headers $headers -Body $json -ContentType "application/json" | Out-Null
    
    $updated++
    Write-Host "  Updated" -ForegroundColor Green
}

Write-Host ""
Write-Host "DONE - Updated $updated clusters" -ForegroundColor Green
Write-Host "Restart clusters to apply changes" -ForegroundColor Yellow
