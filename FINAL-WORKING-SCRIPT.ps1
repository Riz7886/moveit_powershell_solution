param(
    [string]$DatadogApiKey,
    [string]$DatabricksWorkspaceUrl,
    [string]$DatabricksToken,
    [string]$DatadogSite = "datadoghq.com"
)

$ErrorActionPreference = "Stop"

Write-Host "Starting Databricks Datadog Configuration" -ForegroundColor Cyan

$DatabricksWorkspaceUrl = $DatabricksWorkspaceUrl.TrimEnd('/')
$workspacePath = "/Shared/datadog-init-script.sh"
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

Write-Host "Uploading script to workspace" -ForegroundColor Yellow

$importBody = @{
    path = $workspacePath
    content = $scriptBase64
    language = "PYTHON"
    overwrite = $true
    format = "SOURCE"
} | ConvertTo-Json

Invoke-RestMethod -Uri "$apiUrl/workspace/import" -Method Post -Headers $headers -Body $importBody | Out-Null

Write-Host "Script uploaded to: $workspacePath" -ForegroundColor Green

Write-Host "Getting clusters" -ForegroundColor Yellow

$response = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers
$clusters = $response.clusters

if ($null -eq $clusters -or $clusters.Count -eq 0) {
    Write-Host "No clusters found" -ForegroundColor Red
    exit
}

Write-Host "Found $($clusters.Count) clusters" -ForegroundColor Green

$updated = 0
$failed = 0

foreach ($cluster in $clusters) {
    Write-Host "Configuring: $($cluster.cluster_name)" -ForegroundColor White
    
    try {
        $getUrl = "$apiUrl/clusters/get?cluster_id=$($cluster.cluster_id)"
        $config = Invoke-RestMethod -Uri $getUrl -Method Get -Headers $headers
        
        $scripts = @()
        if ($config.init_scripts) {
            $scripts = $config.init_scripts
        }
        
        $scripts += @{
            workspace = @{
                destination = $workspacePath
            }
        }
        
        $body = @{
            cluster_id = $cluster.cluster_id
            spark_version = $config.spark_version
            node_type_id = $config.node_type_id
            init_scripts = $scripts
        }
        
        if ($config.num_workers) { $body.num_workers = $config.num_workers }
        if ($config.autoscale) { $body.autoscale = $config.autoscale }
        if ($config.spark_conf) { $body.spark_conf = $config.spark_conf }
        if ($config.spark_env_vars) { $body.spark_env_vars = $config.spark_env_vars }
        if ($config.custom_tags) { $body.custom_tags = $config.custom_tags }
        if ($config.driver_node_type_id) { $body.driver_node_type_id = $config.driver_node_type_id }
        
        $json = $body | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri "$apiUrl/clusters/edit" -Method Post -Headers $headers -Body $json -ContentType "application/json" | Out-Null
        
        $updated++
        Write-Host "  Updated successfully" -ForegroundColor Green
        
    } catch {
        $failed++
        Write-Host "  Failed: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Updated: $updated clusters" -ForegroundColor Green
Write-Host "Failed: $failed clusters" -ForegroundColor Red
Write-Host ""
Write-Host "DONE! Restart clusters to apply changes" -ForegroundColor Green
Write-Host "Init script location: $workspacePath" -ForegroundColor Yellow
