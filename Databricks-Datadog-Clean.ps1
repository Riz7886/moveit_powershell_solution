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

$initScript = @"
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
    echo "SUCCESS: Datadog agent is running"
else
    echo "WARNING: Datadog agent may not be running"
fi

echo "Datadog Agent Installation Complete"
"@

Write-Host "Init script created!" -ForegroundColor Green

Write-Host "[STEP 2] Uploading to DBFS..." -ForegroundColor Cyan

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
    Write-Host "Created directory" -ForegroundColor Green
} catch {
    Write-Host "Directory exists" -ForegroundColor Yellow
}

try {
    $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($initScript)
    $scriptBase64 = [System.Convert]::ToBase64String($scriptBytes)
    
    $putBody = @{
        path = $dbfsPath
        contents = $scriptBase64
        overwrite = $true
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri "$apiUrl/dbfs/put" -Method Post -Headers $headers -Body $putBody | Out-Null
    Write-Host "Uploaded to: dbfs:$dbfsPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP 3] Getting clusters..." -ForegroundColor Cyan

try {
    $clustersResponse = Invoke-RestMethod -Uri "$apiUrl/clusters/list" -Method Get -Headers $headers
    $allClusters = $clustersResponse.clusters
    
    if ($null -eq $allClusters -or $allClusters.Count -eq 0) {
        Write-Host "No clusters found" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($allClusters.Count) clusters" -ForegroundColor Green
    
    if ($ClusterIds.Count -gt 0) {
        $clustersToUpdate = $allClusters | Where-Object { $ClusterIds -contains $_.cluster_id }
    } else {
        $clustersToUpdate = $allClusters
    }
    
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP 4] Configuring clusters..." -ForegroundColor Cyan

$updated = 0
$skipped = 0
$failed = 0

foreach ($cluster in $clustersToUpdate) {
    Write-Host "Processing: $($cluster.cluster_name)" -ForegroundColor White
    
    try {
        $getUrl = "$apiUrl/clusters/get?cluster_id=$($cluster.cluster_id)"
        $currentConfig = Invoke-RestMethod -Uri $getUrl -Method Get -Headers $headers
        
        $hasScript = $false
        if ($currentConfig.init_scripts) {
            $hasScript = $currentConfig.init_scripts | Where-Object { 
                $_.dbfs.destination -eq "dbfs:$dbfsPath" 
            }
        }
        
        if ($hasScript) {
            Write-Host "  Already configured" -ForegroundColor Yellow
            $skipped++
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
        if ($currentConfig.driver_node_type_id) { $editBody.driver_node_type_id = $currentConfig.driver_node_type_id }
        
        $editJson = $editBody | ConvertTo-Json -Depth 10
        
        Invoke-RestMethod -Uri "$apiUrl/clusters/edit" -Method Post -Headers $headers -Body $editJson -ContentType "application/json" | Out-Null
        
        Write-Host "  Updated successfully" -ForegroundColor Green
        $updated++
        
    } catch {
        Write-Host "  Failed: $_" -ForegroundColor Red
        $failed++
    }
    
    Start-Sleep -Seconds 1
}

Write-Host "" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Updated: $updated" -ForegroundColor Green
Write-Host "Skipped: $skipped" -ForegroundColor Yellow
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "" -ForegroundColor White
Write-Host "DONE! Restart clusters to apply changes." -ForegroundColor Green
