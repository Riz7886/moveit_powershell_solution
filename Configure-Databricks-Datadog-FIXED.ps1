param(
    [Parameter(Mandatory=$true)]
    [string]$DatadogApiKey,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabricksWorkspaceUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabricksToken,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogSite = "datadoghq.com",
    
    [Parameter(Mandatory=$false)]
    [string[]]$ClusterIds = @()
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DATABRICKS DATADOG CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$DatabricksWorkspaceUrl = $DatabricksWorkspaceUrl.TrimEnd('/')

Write-Host "Workspace: $DatabricksWorkspaceUrl" -ForegroundColor Yellow
Write-Host "Datadog Site: $DatadogSite" -ForegroundColor Yellow

Write-Host "[STEP 1] Creating Datadog init script..." -ForegroundColor Cyan

$initScriptContent = @"
#!/bin/bash
set -e

echo "Installing Datadog Agent on Databricks"

export DD_API_KEY="$DatadogApiKey"
export DD_SITE="$DatadogSite"

DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=`$DD_API_KEY DD_SITE=`$DD_SITE bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"

sleep 10

echo "Configuring Spark integration..."
cat <<EOF > /etc/datadog-agent/conf.d/spark.d/conf.yaml
init_config:

instances:
  - spark_url: http://`${DB_DRIVER_IP}:40001
    spark_cluster_mode: spark_driver_mode
    cluster_name: `${DB_CLUSTER_NAME}
    streaming_metrics: true
EOF

sudo systemctl restart datadog-agent

sleep 5
if systemctl is-active --quiet datadog-agent; then
    echo "SUCCESS: Datadog agent is running!"
else
    echo "WARNING: Datadog agent may not be running."
fi

echo "Datadog Agent Installation Complete"
"@

Write-Host "Init script created successfully!" -ForegroundColor Green

Write-Host "[STEP 2] Uploading init script to DBFS..." -ForegroundColor Cyan

$dbfsPath = "/databricks/datadog/install-datadog-agent.sh"
$apiUrl = "$DatabricksWorkspaceUrl/api/2.0"
$headers = @{
    "Authorization" = "Bearer $DatabricksToken"
    "Content-Type" = "application/json"
}

try {
    $mkdirBody = @{
        path = "/databricks/datadog"
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "$apiUrl/dbfs/mkdirs" -Method Post -Headers $headers -Body $mkdirBody | Out-Null
    Write-Host "Created DBFS directory: /databricks/datadog" -ForegroundColor Green
} catch {
    Write-Host "Directory may already exist (this is OK)" -ForegroundColor Yellow
}

try {
    $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($initScriptContent)
    $scriptBase64 = [System.Convert]::ToBase64String($scriptBytes)
    
    $putBody = @{
        path = $dbfsPath
        contents = $scriptBase64
        overwrite = $true
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri "$apiUrl/dbfs/put" -Method Post -Headers $headers -Body $putBody | Out-Null
    Write-Host "Uploaded init script to: dbfs:$dbfsPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR uploading init script: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP 3] Getting Databricks clusters..." -ForegroundColor Cyan

try {
    $clustersResponse = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers
    $allClusters = $clustersResponse.clusters
    
    if ($null -eq $allClusters -or $allClusters.Count -eq 0) {
        Write-Host "No clusters found in workspace!" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($allClusters.Count) cluster(s)" -ForegroundColor Green
    
    if ($ClusterIds.Count -gt 0) {
        $clustersToUpdate = $allClusters | Where-Object { $ClusterIds -contains $_.cluster_id }
        Write-Host "Will configure $($clustersToUpdate.Count) specified cluster(s)" -ForegroundColor Yellow
    } else {
        $clustersToUpdate = $allClusters
        Write-Host "Will configure ALL clusters" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "ERROR getting clusters: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP 4] Configuring clusters with Datadog init script..." -ForegroundColor Cyan

$results = @{
    Updated = 0
    Skipped = 0
    Failed = 0
}

foreach ($cluster in $clustersToUpdate) {
    Write-Host "Processing: $($cluster.cluster_name) [$($cluster.cluster_id)]" -ForegroundColor White
    
    try {
        $getUrl = "$apiUrl/clusters/get?cluster_id=$($cluster.cluster_id)"
        $currentConfig = Invoke-RestMethod -Uri $getUrl -Method Get -Headers $headers
        
        $hasDatadogScript = $false
        if ($currentConfig.init_scripts) {
            $hasDatadogScript = $currentConfig.init_scripts | Where-Object { 
                $_.dbfs.destination -eq "dbfs:$dbfsPath" 
            }
        }
        
        if ($hasDatadogScript) {
            Write-Host "  Datadog init script already configured - Skipping" -ForegroundColor Yellow
            $results.Skipped++
            continue
        }
        
        $initScripts = @()
        if ($currentConfig.init_scripts) {
            $initScripts = $currentConfig.init_scripts
        }
        
        $initScripts += @{
            dbfs = @{
                destination = "dbfs:$dbfsPath"
            }
        }
        
        $editBody = @{
            cluster_id = $cluster.cluster_id
            spark_version = $currentConfig.spark_version
            node_type_id = $currentConfig.node_type_id
            init_scripts = $initScripts
        }
        
        if ($currentConfig.num_workers) { $editBody.num_workers = $currentConfig.num_workers }
        if ($currentConfig.autoscale) { $editBody.autoscale = $currentConfig.autoscale }
        if ($currentConfig.spark_conf) { $editBody.spark_conf = $currentConfig.spark_conf }
        if ($currentConfig.spark_env_vars) { $editBody.spark_env_vars = $currentConfig.spark_env_vars }
        if ($currentConfig.custom_tags) { $editBody.custom_tags = $currentConfig.custom_tags }
        if ($currentConfig.cluster_log_conf) { $editBody.cluster_log_conf = $currentConfig.cluster_log_conf }
        if ($currentConfig.driver_node_type_id) { $editBody.driver_node_type_id = $currentConfig.driver_node_type_id }
        
        $editBodyJson = $editBody | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri "$apiUrl/clusters/edit" -Method Post -Headers $headers -Body $editBodyJson -ContentType "application/json" | Out-Null
        
        Write-Host "  Successfully updated cluster configuration" -ForegroundColor Green
        $results.Updated++
        
        if ($currentConfig.state -eq "RUNNING") {
            Write-Host "  Cluster is running. Restart to apply changes." -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  Failed to update cluster: $_" -ForegroundColor Red
        $results.Failed++
    }
    
    Start-Sleep -Seconds 1
}

Write-Host "" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CONFIGURATION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Clusters Updated: $($results.Updated)" -ForegroundColor Green
Write-Host "Clusters Skipped: $($results.Skipped)" -ForegroundColor Yellow
Write-Host "Clusters Failed: $($results.Failed)" -ForegroundColor Red

Write-Host "" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. Start or restart your Databricks clusters" -ForegroundColor Yellow
Write-Host "2. The Datadog agent will install automatically on cluster startup" -ForegroundColor Yellow
Write-Host "3. Wait 5-10 minutes after cluster starts" -ForegroundColor Yellow
Write-Host "4. Check Datadog Infrastructure Host Map for your cluster nodes" -ForegroundColor Yellow

Write-Host "" -ForegroundColor White
Write-Host "Configuration complete!" -ForegroundColor Green
Write-Host "Init script location: dbfs:$dbfsPath" -ForegroundColor Cyan
