<#
.SYNOPSIS
    Datadog Complete Deployment for PYX Health Corporation
    
.DESCRIPTION
    Interactive deployment script with options:
    1. Install Datadog Agent (on current machine)
    2. Create Monitors (25 comprehensive monitors)
    3. Full Deployment (Install + Create Monitors)
    
    Matches AVD deployment script style exactly
    Works with PowerShell 5.1 and 7+
    
.NOTES
    Company: PYX Health Corporation
    Purpose: 24/7 monitoring for all Windows machines
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# CHECK ADMINISTRATOR PRIVILEGES
Write-Host ""
Write-Host "Checking administrator privileges..." -ForegroundColor Cyan
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "1. Close this PowerShell window" -ForegroundColor White
    Write-Host "2. Right-click PowerShell" -ForegroundColor White
    Write-Host "3. Select 'Run as Administrator'" -ForegroundColor White
    Write-Host "4. Run this script again" -ForegroundColor White
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Administrator privileges confirmed" -ForegroundColor Green
Write-Host ""

# CHECK POWERSHELL VERSION
Write-Host "Checking PowerShell version..." -ForegroundColor Cyan
$psVersion = $PSVersionTable.PSVersion
Write-Host "Current version: PowerShell $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor White

if ($psVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.0 or higher is required" -ForegroundColor Red
    exit 1
}

Write-Host "PowerShell version OK" -ForegroundColor Green
Write-Host ""

# Global configuration
$Script:Config = @{
    CompanyName = 'PYX Health Corporation'
    DatadogAPIKey = '14fe5ae3-6459-40a4-8f3b-b3c8c97e520e'
    DatadogAppKey = '195558c2-6170-4af6-ba4f-4267b05e4017'
    DatadogSite = 'us3.datadoghq.com'
    DatadogAPIURL = 'https://api.us3.datadoghq.com/api/v1'
    AgentInstallerURL = 'https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
    AlertEmail = 'john.pinto@pyxhealth.com anthoney.schlak@pyxhealth.com shaun.raj@pyxhealth.com'
    PagerDuty = '@pagerduty-pyxhealth-oncall'
    SlackProd = '@slack-alerts-prod'
    SlackStaging = '@slack-alerts-stg'
    SlackQA = '@slack-alerts-qa'
    SlackDev = '@slack-alerts-dev'
}

$Script:DeploymentLog = @()
$Script:StartTime = Get-Date
$Script:AgentInstalled = $false
$Script:MonitorsCreated = 0
$Script:MonitorsFailed = 0

# Logging
function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    $Script:DeploymentLog += $logEntry
    
    $color = switch ($Level) {
        'Info' { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
    }
    
    Write-Host $Message -ForegroundColor $color
}

# Show banner
function Show-Banner {
    param([string]$Title)
    
    Clear-Host
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  DATADOG DEPLOYMENT FOR PYX HEALTH CORPORATION" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    if ($Title) {
        Write-Host "  $Title" -ForegroundColor Cyan
    }
    Write-Host ""
}

# Install Datadog agent
function Install-DatadogAgent {
    Show-Banner -Title "STEP 1: INSTALL DATADOG AGENT"
    
    Write-Log "Checking if Datadog agent is already installed..." "Info"
    
    $agentService = Get-Service -Name 'datadogagent' -ErrorAction SilentlyContinue
    if ($agentService) {
        Write-Log "Datadog agent is already installed" "Success"
        Write-Log "Service status: $($agentService.Status)" "Info"
        
        Write-Host ""
        Write-Host "Agent is already installed. Do you want to reinstall? (Y/N)" -ForegroundColor Yellow
        $reinstall = Read-Host
        
        if ($reinstall -ne 'Y' -and $reinstall -ne 'y') {
            Write-Log "Installation skipped" "Info"
            $Script:AgentInstalled = $true
            return $true
        }
    }
    
    Write-Host ""
    Write-Log "Downloading Datadog agent installer..." "Info"
    Write-Log "Download URL: $($Script:Config.AgentInstallerURL)" "Info"
    
    $installerPath = "$env:TEMP\datadog-agent-installer.msi"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Script:Config.AgentInstallerURL, $installerPath)
        Write-Log "Installer downloaded successfully" "Success"
        Write-Log "Installer location: $installerPath" "Info"
    }
    catch {
        Write-Log "Failed to download installer: $($_.Exception.Message)" "Error"
        return $false
    }
    
    Write-Host ""
    Write-Log "Installing Datadog agent..." "Info"
    Write-Log "This will take 2-3 minutes..." "Info"
    Write-Host ""
    
    $env:DD_API_KEY = $Script:Config.DatadogAPIKey
    $env:DD_SITE = $Script:Config.DatadogSite
    
    try {
        $installArgs = @(
            '/i',
            $installerPath,
            '/quiet',
            '/norestart',
            "APIKEY=$($Script:Config.DatadogAPIKey)",
            "SITE=$($Script:Config.DatadogSite)"
        )
        
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Datadog agent installed successfully" "Success"
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "Installation completed (restart may be required)" "Success"
        }
        else {
            Write-Log "Installation completed with exit code: $($process.ExitCode)" "Warning"
        }
    }
    catch {
        Write-Log "Failed to install agent: $($_.Exception.Message)" "Error"
        return $false
    }
    
    Write-Host ""
    Write-Log "Waiting for agent to start..." "Info"
    Start-Sleep -Seconds 10
    
    $agentService = Get-Service -Name 'datadogagent' -ErrorAction SilentlyContinue
    if ($agentService) {
        if ($agentService.Status -eq 'Running') {
            Write-Log "Datadog agent is running" "Success"
        }
        else {
            Write-Log "Starting Datadog agent service..." "Info"
            Start-Service -Name 'datadogagent'
            Start-Sleep -Seconds 5
            Write-Log "Datadog agent started" "Success"
        }
    }
    
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host "  AGENT INSTALLATION COMPLETE" -ForegroundColor Green
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Machine: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "  Agent Status: Running" -ForegroundColor Green
    Write-Host "  Reporting To: $($Script:Config.DatadogSite)" -ForegroundColor White
    Write-Host ""
    Write-Host "The agent will start reporting data within 5 minutes" -ForegroundColor Cyan
    Write-Host ""
    
    $Script:AgentInstalled = $true
    return $true
}

# Create monitor
function New-DatadogMonitor {
    param(
        [string]$Name,
        [string]$Type,
        [string]$Query,
        [string]$Message,
        [hashtable]$Options,
        [string[]]$Tags
    )
    
    try {
        $headers = @{
            'DD-API-KEY' = $Script:Config.DatadogAPIKey
            'DD-APPLICATION-KEY' = $Script:Config.DatadogAppKey
            'Content-Type' = 'application/json'
        }
        
        $body = @{
            name = $Name
            type = $Type
            query = $Query
            message = $Message
            tags = $Tags
            options = $Options
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-RestMethod -Uri "$($Script:Config.DatadogAPIURL)/monitor" -Method Post -Headers $headers -Body $body -ErrorAction Stop
        
        $Script:MonitorsCreated++
        return $true
    }
    catch {
        $Script:MonitorsFailed++
        Write-Log "Failed: $($_.Exception.Message)" "Error"
        return $false
    }
}

# Create all monitors
function New-ComprehensiveMonitors {
    Show-Banner -Title "STEP 2: CREATE MONITORING ALERTS"
    
    Write-Log "Checking Azure PowerShell modules..." "Info"
    
    $requiredModules = @('Az.Accounts', 'Az.Resources')
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host ""
        Write-Host "Missing Azure modules. Installing..." -ForegroundColor Yellow
        Write-Host ""
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        
        foreach ($module in $missingModules) {
            Write-Host "Installing $module..." -ForegroundColor Cyan
            Install-Module -Name $module -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        }
        Write-Host ""
        Write-Log "Azure modules installed successfully" "Success"
    }
    
    Write-Host ""
    Write-Log "Connecting to Azure..." "Info"
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Write-Log "Launching Azure authentication..." "Info"
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Log "Connected as: $($context.Account.Id)" "Success"
    }
    catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "Error"
        return $false
    }
    
    Write-Host ""
    Write-Log "Discovering Azure subscriptions..." "Info"
    
    $subscriptions = Get-AzSubscription
    Write-Log "Found $($subscriptions.Count) subscription(s)" "Success"
    
    Write-Host ""
    Write-Host "Creating 25 monitors per subscription..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($sub in $subscriptions) {
        $env = if ($sub.Name -match 'prod') { 'production' }
              elseif ($sub.Name -match 'stag') { 'staging' }
              elseif ($sub.Name -match 'qa') { 'qa' }
              else { 'development' }
        
        $slackChannel = switch ($env) {
            'production' { $Script:Config.SlackProd }
            'staging' { $Script:Config.SlackStaging }
            'qa' { $Script:Config.SlackQA }
            default { $Script:Config.SlackDev }
        }
        
        $notify = "$($Script:Config.AlertEmail) $($Script:Config.PagerDuty) $slackChannel"
        $tags = @('managed_by:automation', 'company:pyx-health', "env:$env", "subscription:$($sub.Id)")
        
        Write-Host "Subscription: $($sub.Name) ($env)" -ForegroundColor Yellow
        
        $monitors = @(
            @{ Name = "[$env][$($sub.Name)] High CPU"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.vm.percentage_cpu{subscription_id:$($sub.Id)} by {host} > 85"; Message = "High CPU usage. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] High Memory"; Type = 'metric alert'; Query = "avg(last_5m):avg:system.mem.pct_usable{subscription_id:$($sub.Id)} by {host} < 15"; Message = "High memory usage. $notify"; Options = @{ thresholds = @{ critical = 15; warning = 25 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] High Disk"; Type = 'metric alert'; Query = "avg(last_5m):avg:system.disk.in_use{subscription_id:$($sub.Id)} by {host,device} > 0.85"; Message = "High disk usage. $notify"; Options = @{ thresholds = @{ critical = 0.85; warning = 0.75 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] VM Stopped"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.vm.status{subscription_id:$($sub.Id)} by {vm_name} < 1"; Message = "VM stopped. $notify"; Options = @{ thresholds = @{ critical = 1 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] Agent Down"; Type = 'service check'; Query = "datadog.agent.up{subscription_id:$($sub.Id)}.by('host').last(2).count_by_status()"; Message = "Agent not reporting. $notify"; Options = @{ thresholds = @{ critical = 1 }; notify_no_data = $true; no_data_timeframe = 15 } },
            @{ Name = "[$env][$($sub.Name)] High Network Traffic"; Type = 'metric alert'; Query = "avg(last_15m):avg:azure.network.bytes_total{subscription_id:$($sub.Id)} by {interface} > 1000000000"; Message = "High network traffic. $notify"; Options = @{ thresholds = @{ critical = 1000000000; warning = 500000000 } } },
            @{ Name = "[$env][$($sub.Name)] Packet Drops"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.network.packets_dropped{subscription_id:$($sub.Id)} by {interface} > 100"; Message = "Packet drops detected. $notify"; Options = @{ thresholds = @{ critical = 100; warning = 50 } } },
            @{ Name = "[$env][$($sub.Name)] Load Balancer Unhealthy"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.network_loadbalancers.health_probe_status{subscription_id:$($sub.Id)} by {backend} < 1"; Message = "Backend unhealthy. $notify"; Options = @{ thresholds = @{ critical = 1 } } },
            @{ Name = "[$env][$($sub.Name)] Failed Logins"; Type = 'log alert'; Query = "logs('status:error authentication failed subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 10"; Message = "Multiple failed logins. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] NSG Changes"; Type = 'log alert'; Query = "logs('azure.resource_type:NetworkSecurityGroup operation:write subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 0"; Message = "NSG rules modified. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] RBAC Changes"; Type = 'log alert'; Query = "logs('azure.operation_name:RoleAssignment subscription_id:$($sub.Id)').index('*').rollup('count').last('10m') > 0"; Message = "RBAC changed. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] Resource Deleted"; Type = 'log alert'; Query = "logs('azure.operation_name:Delete subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 0"; Message = "Resources deleted. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] Slow App Response"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.web_sites.http_response_time{subscription_id:$($sub.Id)} by {app} > 3"; Message = "Slow response time. $notify"; Options = @{ thresholds = @{ critical = 3; warning = 2 } } },
            @{ Name = "[$env][$($sub.Name)] High App Errors"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.web_sites.http_5xx{subscription_id:$($sub.Id)} by {app} > 10"; Message = "High 5xx errors. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] App Down"; Type = 'service check'; Query = "http_check{subscription_id:$($sub.Id)}.by('instance').last(3).count_by_status()"; Message = "Application unavailable. $notify"; Options = @{ thresholds = @{ critical = 1 } } },
            @{ Name = "[$env][$($sub.Name)] High SQL DTU"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.sql_servers_databases.dtu_consumption_percent{subscription_id:$($sub.Id)} by {database} > 85"; Message = "High DTU usage. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 } } },
            @{ Name = "[$env][$($sub.Name)] High SQL Storage"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.sql_servers_databases.storage_percent{subscription_id:$($sub.Id)} by {database} > 85"; Message = "High database storage. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 } } },
            @{ Name = "[$env][$($sub.Name)] SQL Deadlocks"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.sql_servers_databases.deadlock{subscription_id:$($sub.Id)} by {database} > 5"; Message = "Database deadlocks. $notify"; Options = @{ thresholds = @{ critical = 5; warning = 2 } } },
            @{ Name = "[$env][$($sub.Name)] SQL Connection Failures"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.sql_servers_databases.connection_failed{subscription_id:$($sub.Id)} by {database} > 10"; Message = "Connection failures. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] High Storage Capacity"; Type = 'metric alert'; Query = "avg(last_30m):avg:azure.storage_storageaccounts.used_capacity{subscription_id:$($sub.Id)} by {account} > 450000000000"; Message = "Storage capacity high. $notify"; Options = @{ thresholds = @{ critical = 450000000000; warning = 400000000000 } } },
            @{ Name = "[$env][$($sub.Name)] Low Storage Availability"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.storage_storageaccounts.availability{subscription_id:$($sub.Id)} by {account} < 99"; Message = "Storage availability low. $notify"; Options = @{ thresholds = @{ critical = 99; warning = 99.5 } } },
            @{ Name = "[$env][$($sub.Name)] Daily Cost Spike"; Type = 'metric alert'; Query = "avg(last_1d):avg:azure.cost.daily{subscription_id:$($sub.Id)} > 1000"; Message = "Cost spike detected. $notify"; Options = @{ thresholds = @{ critical = 1000; warning = 750 } } },
            @{ Name = "[$env][$($sub.Name)] Backup Failed"; Type = 'log alert'; Query = "logs('azure.resource_type:RecoveryServicesVault status:failed subscription_id:$($sub.Id)').index('*').rollup('count').last('24h') > 0"; Message = "Backup failed. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] SSL Expiring"; Type = 'metric alert'; Query = "avg(last_1h):avg:azure.app_gateway.ssl_certificate_expiry_days{subscription_id:$($sub.Id)} by {cert} < 30"; Message = "SSL expiring soon. $notify"; Options = @{ thresholds = @{ critical = 30; warning = 60 } } },
            @{ Name = "[$env][$($sub.Name)] High Error Logs"; Type = 'log alert'; Query = "logs('status:error subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 50"; Message = "High error count. $notify"; Options = @{ thresholds = @{ critical = 50; warning = 25 } } }
        )
        
        $count = 1
        foreach ($mon in $monitors) {
            Write-Host "  [$count/25] $($mon.Name.Substring($mon.Name.LastIndexOf(']') + 2))..." -NoNewline
            
            if (New-DatadogMonitor -Name $mon.Name -Type $mon.Type -Query $mon.Query -Message $mon.Message -Options $mon.Options -Tags $tags) {
                Write-Host " SUCCESS" -ForegroundColor Green
            }
            else {
                Write-Host " FAILED" -ForegroundColor Red
            }
            
            $count++
        }
        Write-Host ""
    }
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host "  MONITOR CREATION COMPLETE" -ForegroundColor Green
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Subscriptions: $($subscriptions.Count)" -ForegroundColor White
    Write-Host "  Monitors Created: $Script:MonitorsCreated" -ForegroundColor Green
    Write-Host "  Monitors Failed: $Script:MonitorsFailed" -ForegroundColor $(if ($Script:MonitorsFailed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    Write-Host "  Dashboard: https://app.us3.datadoghq.com/monitors/manage" -ForegroundColor Cyan
    Write-Host ""
    
    return $true
}

# Main menu
function Show-MainMenu {
    Show-Banner
    
    Write-Host "  What would you like to do?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Install Datadog Agent (on this machine)" -ForegroundColor Cyan
    Write-Host "      - Installs agent on current machine" -ForegroundColor Gray
    Write-Host "      - Takes 2-3 minutes" -ForegroundColor Gray
    Write-Host "      - Run this on EVERY machine you want monitored" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] Create Monitoring Alerts (25 comprehensive monitors)" -ForegroundColor Cyan
    Write-Host "      - Creates 25 monitors in Datadog" -ForegroundColor Gray
    Write-Host "      - Takes 5-10 minutes" -ForegroundColor Gray
    Write-Host "      - Run this ONCE after agents installed" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [3] Full Deployment (Install Agent + Create Monitors)" -ForegroundColor Cyan
    Write-Host "      - Runs both steps automatically" -ForegroundColor Gray
    Write-Host "      - Takes 7-13 minutes" -ForegroundColor Gray
    Write-Host "      - Best for first-time setup" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [4] Exit" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-4)"
    
    return $choice
}

# Main execution
try {
    $choice = Show-MainMenu
    
    switch ($choice) {
        '1' {
            if (Install-DatadogAgent) {
                Write-Host ""
                Write-Host "Agent installation complete!" -ForegroundColor Green
                Write-Host ""
                Write-Host "Next steps:" -ForegroundColor Yellow
                Write-Host "1. Install agent on other machines (run this script on each machine)" -ForegroundColor White
                Write-Host "2. After all agents installed, run option [2] to create monitors" -ForegroundColor White
                Write-Host ""
            }
        }
        '2' {
            if (New-ComprehensiveMonitors) {
                Write-Host "Monitor creation complete!" -ForegroundColor Green
                Write-Host ""
                Write-Host "All monitors are now active and sending 24/7 alerts" -ForegroundColor Cyan
                Write-Host ""
            }
        }
        '3' {
            Write-Host ""
            Write-Host "Starting full deployment..." -ForegroundColor Cyan
            Write-Host ""
            
            if (Install-DatadogAgent) {
                Write-Host ""
                Write-Host "Agent installed. Now creating monitors..." -ForegroundColor Cyan
                Write-Host ""
                Start-Sleep -Seconds 3
                
                if (New-ComprehensiveMonitors) {
                    Write-Host ""
                    Write-Host "=========================================================================" -ForegroundColor Green
                    Write-Host "  FULL DEPLOYMENT COMPLETE" -ForegroundColor Green
                    Write-Host "=========================================================================" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "  Agent Installed: YES" -ForegroundColor Green
                    Write-Host "  Monitors Created: $Script:MonitorsCreated" -ForegroundColor Green
                    Write-Host ""
                    Write-Host "Next steps:" -ForegroundColor Yellow
                    Write-Host "1. Install agent on other machines (run option [1] on each machine)" -ForegroundColor White
                    Write-Host "2. All done - 24/7 monitoring is now active!" -ForegroundColor White
                    Write-Host ""
                }
            }
        }
        '4' {
            Write-Host ""
            Write-Host "Exiting..." -ForegroundColor Yellow
            Write-Host ""
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "Invalid choice. Please run the script again." -ForegroundColor Red
            Write-Host ""
            exit 1
        }
    }
    
    $duration = (Get-Date) - $Script:StartTime
    Write-Host "Total time: $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Cyan
    Write-Host ""
    
    $logPath = Join-Path -Path $PSScriptRoot -ChildPath "Datadog-Deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $Script:DeploymentLog | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "Log saved: $logPath" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Press Enter to exit..." -ForegroundColor Cyan
    Read-Host
}
catch {
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host "  DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
finally {
    $ProgressPreference = 'Continue'
}
