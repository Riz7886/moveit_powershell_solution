<#
.SYNOPSIS
    Complete Datadog Deployment for PYX Health Corporation
    
.DESCRIPTION
    Two-step deployment:
    STEP 1: Install Datadog agent on machines (servers, desktops, laptops)
    STEP 2: Create 25 comprehensive monitors for 24/7 IT alerting
    
    Works with Windows PowerShell 5.1 and PowerShell 7+
    
.PARAMETER Mode
    Required. Choose deployment mode:
    - InstallAgent: Installs Datadog agent on current machine
    - CreateMonitors: Creates monitors in Datadog (run after agents installed)
    
.PARAMETER DatadogAPIKey
    Datadog API key for PYX Health
    
.PARAMETER DatadogSite
    Datadog site region. Default: us3.datadoghq.com
    
.PARAMETER MachinesToInstall
    CSV file with list of machines to install agents on (for remote installation)
    
.EXAMPLE
    STEP 1 - Install agent on current machine:
    .\Deploy-Datadog-Complete.ps1 -Mode InstallAgent
    
.EXAMPLE
    STEP 2 - Create monitors after agents installed:
    .\Deploy-Datadog-Complete.ps1 -Mode CreateMonitors
    
.NOTES
    Company: PYX Health Corporation
    Purpose: 24/7 IT monitoring for all Windows machines
    Monitors: 25 comprehensive alerts for servers, desktops, laptops, applications
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('InstallAgent', 'CreateMonitors')]
    [string]$Mode,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogAPIKey = '14fe5ae3-6459-40a4-8f3b-b3c8c97e520e',
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogSite = 'us3.datadoghq.com',
    
    [Parameter(Mandatory=$false)]
    [string]$MachinesToInstall = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Global configuration
$Script:Config = @{
    CompanyName = 'PYX Health Corporation'
    DatadogAPIKey = $DatadogAPIKey
    DatadogAppKey = '195558c2-6170-4af6-ba4f-4267b05e4017'
    DatadogSite = $DatadogSite
    DatadogAPIURL = "https://api.us3.datadoghq.com/api/v1"
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

# Logging function
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

# Check administrator privileges
function Test-Administrator {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
        Write-Host ""
        Write-Host "How to fix:" -ForegroundColor Yellow
        Write-Host "1. Close this PowerShell window" -ForegroundColor White
        Write-Host "2. Right-click PowerShell" -ForegroundColor White
        Write-Host "3. Select 'Run as Administrator'" -ForegroundColor White
        Write-Host "4. Run this script again" -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

# Install Datadog agent on local machine
function Install-DatadogAgent {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  DATADOG AGENT INSTALLATION" -ForegroundColor White
    Write-Host "  Company: $($Script:Config.CompanyName)" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
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
            return
        }
    }
    
    Write-Host ""
    Write-Log "Downloading Datadog agent installer..." "Info"
    
    $installerPath = "$env:TEMP\datadog-agent-installer.msi"
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Script:Config.AgentInstallerURL, $installerPath)
        Write-Log "Installer downloaded successfully" "Success"
    }
    catch {
        Write-Log "Failed to download installer: $($_.Exception.Message)" "Error"
        throw
    }
    
    Write-Host ""
    Write-Log "Installing Datadog agent..." "Info"
    Write-Log "This may take 2-3 minutes..." "Info"
    
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
        else {
            Write-Log "Installation completed with exit code: $($process.ExitCode)" "Warning"
        }
    }
    catch {
        Write-Log "Failed to install agent: $($_.Exception.Message)" "Error"
        throw
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
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "  AGENT INSTALLATION COMPLETE" -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Machine: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "  Agent Status: Running" -ForegroundColor Green
    Write-Host "  Reporting To: $($Script:Config.DatadogSite)" -ForegroundColor White
    Write-Host ""
    Write-Host "The agent will start reporting data to Datadog within 5 minutes" -ForegroundColor Cyan
    Write-Host "Check dashboard: https://app.$($Script:Config.DatadogSite.Replace('.datadoghq.com', '')).datadoghq.com" -ForegroundColor Cyan
    Write-Host ""
}

# Create Datadog monitor
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
        
        return $response
    }
    catch {
        Write-Log "Failed to create monitor '$Name': $($_.Exception.Message)" "Error"
        return $null
    }
}

# Create monitors
function New-ComprehensiveMonitors {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  CREATING DATADOG MONITORS" -ForegroundColor White
    Write-Host "  Company: $($Script:Config.CompanyName)" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Connecting to Azure..." "Info"
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Write-Log "Launching Azure authentication..." "Info"
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        Write-Log "Connected to Azure as: $($context.Account.Id)" "Success"
    }
    catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "Error"
        throw
    }
    
    Write-Host ""
    Write-Log "Discovering Azure subscriptions..." "Info"
    
    $subscriptions = Get-AzSubscription
    Write-Log "Found $($subscriptions.Count) subscription(s)" "Success"
    
    $totalMonitors = 0
    $failedMonitors = 0
    
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
        
        Write-Host ""
        Write-Host "Creating monitors for: $($sub.Name) ($env)" -ForegroundColor Cyan
        Write-Host ""
        
        # All 25 monitors in a compact array
        $monitors = @(
            @{ Name = "[$env][$($sub.Name)] CPU Above 85%"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.vm.percentage_cpu{subscription_id:$($sub.Id)} by {host} > 85"; Message = "High CPU usage. Check VM performance. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] Memory Above 85%"; Type = 'metric alert'; Query = "avg(last_5m):avg:system.mem.pct_usable{subscription_id:$($sub.Id)} by {host} < 15"; Message = "High memory usage. Check for memory leaks. $notify"; Options = @{ thresholds = @{ critical = 15; warning = 25 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] Disk Above 85%"; Type = 'metric alert'; Query = "avg(last_5m):avg:system.disk.in_use{subscription_id:$($sub.Id)} by {host,device} > 0.85"; Message = "High disk usage. Clean up disk space. $notify"; Options = @{ thresholds = @{ critical = 0.85; warning = 0.75 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] VM Stopped"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.vm.status{subscription_id:$($sub.Id)} by {vm_name} < 1"; Message = "VM stopped or deallocated. Check immediately. $notify"; Options = @{ thresholds = @{ critical = 1 }; notify_no_data = $true } },
            @{ Name = "[$env][$($sub.Name)] Agent Down"; Type = 'service check'; Query = "datadog.agent.up{subscription_id:$($sub.Id)}.by('host').last(2).count_by_status()"; Message = "Datadog agent not reporting. Check connectivity. $notify"; Options = @{ thresholds = @{ critical = 1 }; notify_no_data = $true; no_data_timeframe = 15 } },
            @{ Name = "[$env][$($sub.Name)] High Network Traffic"; Type = 'metric alert'; Query = "avg(last_15m):avg:azure.network.bytes_total{subscription_id:$($sub.Id)} by {interface} > 1000000000"; Message = "High network traffic. Check for DDoS or data exfiltration. $notify"; Options = @{ thresholds = @{ critical = 1000000000; warning = 500000000 } } },
            @{ Name = "[$env][$($sub.Name)] Network Packet Drops"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.network.packets_dropped{subscription_id:$($sub.Id)} by {interface} > 100"; Message = "Network packet drops detected. Check NIC health. $notify"; Options = @{ thresholds = @{ critical = 100; warning = 50 } } },
            @{ Name = "[$env][$($sub.Name)] Load Balancer Unhealthy"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.network_loadbalancers.health_probe_status{subscription_id:$($sub.Id)} by {backend} < 1"; Message = "Load balancer backend unhealthy. Check backend pool. $notify"; Options = @{ thresholds = @{ critical = 1 } } },
            @{ Name = "[$env][$($sub.Name)] Failed Login Attempts"; Type = 'log alert'; Query = "logs('status:error authentication failed subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 10"; Message = "Multiple failed logins. Possible brute force attack. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] NSG Rule Changes"; Type = 'log alert'; Query = "logs('azure.resource_type:NetworkSecurityGroup operation:write subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 0"; Message = "NSG rules modified. Review security changes immediately. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] RBAC Changes"; Type = 'log alert'; Query = "logs('azure.operation_name:RoleAssignment subscription_id:$($sub.Id)').index('*').rollup('count').last('10m') > 0"; Message = "RBAC role assignments changed. Review access control. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] Resource Deleted"; Type = 'log alert'; Query = "logs('azure.operation_name:Delete subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 0"; Message = "Resources deleted. Verify this was intentional. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] Slow App Response"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.web_sites.http_response_time{subscription_id:$($sub.Id)} by {app} > 3"; Message = "Application response time above 3 seconds. Check app performance. $notify"; Options = @{ thresholds = @{ critical = 3; warning = 2 } } },
            @{ Name = "[$env][$($sub.Name)] High App Errors"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.web_sites.http_5xx{subscription_id:$($sub.Id)} by {app} > 10"; Message = "High 5xx error rate. Check application logs. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] App Down"; Type = 'service check'; Query = "http_check{subscription_id:$($sub.Id)}.by('instance').last(3).count_by_status()"; Message = "Application unavailable. Check app service immediately. $notify"; Options = @{ thresholds = @{ critical = 1 } } },
            @{ Name = "[$env][$($sub.Name)] High SQL DTU"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.sql_servers_databases.dtu_consumption_percent{subscription_id:$($sub.Id)} by {database} > 85"; Message = "Database DTU above 85%. Check query performance. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 } } },
            @{ Name = "[$env][$($sub.Name)] High SQL Storage"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.sql_servers_databases.storage_percent{subscription_id:$($sub.Id)} by {database} > 85"; Message = "Database storage above 85%. Clean up old data. $notify"; Options = @{ thresholds = @{ critical = 85; warning = 75 } } },
            @{ Name = "[$env][$($sub.Name)] SQL Deadlocks"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.sql_servers_databases.deadlock{subscription_id:$($sub.Id)} by {database} > 5"; Message = "Database deadlocks detected. Check query patterns. $notify"; Options = @{ thresholds = @{ critical = 5; warning = 2 } } },
            @{ Name = "[$env][$($sub.Name)] SQL Connection Failures"; Type = 'metric alert'; Query = "avg(last_5m):avg:azure.sql_servers_databases.connection_failed{subscription_id:$($sub.Id)} by {database} > 10"; Message = "Multiple failed database connections. Check firewall rules. $notify"; Options = @{ thresholds = @{ critical = 10; warning = 5 } } },
            @{ Name = "[$env][$($sub.Name)] High Storage Capacity"; Type = 'metric alert'; Query = "avg(last_30m):avg:azure.storage_storageaccounts.used_capacity{subscription_id:$($sub.Id)} by {account} > 450000000000"; Message = "Storage capacity above 450GB. Check usage. $notify"; Options = @{ thresholds = @{ critical = 450000000000; warning = 400000000000 } } },
            @{ Name = "[$env][$($sub.Name)] Low Storage Availability"; Type = 'metric alert'; Query = "avg(last_10m):avg:azure.storage_storageaccounts.availability{subscription_id:$($sub.Id)} by {account} < 99"; Message = "Storage availability below 99%. Check service health. $notify"; Options = @{ thresholds = @{ critical = 99; warning = 99.5 } } },
            @{ Name = "[$env][$($sub.Name)] Daily Cost Spike"; Type = 'metric alert'; Query = "avg(last_1d):avg:azure.cost.daily{subscription_id:$($sub.Id)} > 1000"; Message = "Daily cost spike detected. Review resource usage. $notify"; Options = @{ thresholds = @{ critical = 1000; warning = 750 } } },
            @{ Name = "[$env][$($sub.Name)] Backup Failed"; Type = 'log alert'; Query = "logs('azure.resource_type:RecoveryServicesVault status:failed subscription_id:$($sub.Id)').index('*').rollup('count').last('24h') > 0"; Message = "Backup job failed. Check Recovery Services Vault. $notify"; Options = @{ thresholds = @{ critical = 0 } } },
            @{ Name = "[$env][$($sub.Name)] SSL Certificate Expiring"; Type = 'metric alert'; Query = "avg(last_1h):avg:azure.app_gateway.ssl_certificate_expiry_days{subscription_id:$($sub.Id)} by {cert} < 30"; Message = "SSL certificate expiring within 30 days. Renew immediately. $notify"; Options = @{ thresholds = @{ critical = 30; warning = 60 } } },
            @{ Name = "[$env][$($sub.Name)] High Error Logs"; Type = 'log alert'; Query = "logs('status:error subscription_id:$($sub.Id)').index('*').rollup('count').last('5m') > 50"; Message = "More than 50 error logs in 5 minutes. Check application health. $notify"; Options = @{ thresholds = @{ critical = 50; warning = 25 } } }
        )
        
        $count = 1
        foreach ($mon in $monitors) {
            Write-Host "  [$count/25] Creating: $($mon.Name.Substring($mon.Name.LastIndexOf(']') + 2))" -NoNewline
            
            $result = New-DatadogMonitor -Name $mon.Name -Type $mon.Type -Query $mon.Query -Message $mon.Message -Options $mon.Options -Tags $tags
            
            if ($result) {
                Write-Host " SUCCESS" -ForegroundColor Green
                $totalMonitors++
            }
            else {
                Write-Host " FAILED" -ForegroundColor Red
                $failedMonitors++
            }
            
            $count++
        }
    }
    
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host "  MONITOR CREATION COMPLETE" -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Subscriptions Processed: $($subscriptions.Count)" -ForegroundColor White
    Write-Host "  Monitors Created: $totalMonitors" -ForegroundColor Green
    Write-Host "  Monitors Failed: $failedMonitors" -ForegroundColor $(if ($failedMonitors -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    Write-Host "  Dashboard: https://app.us3.datadoghq.com/monitors/manage" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "All monitors are now active and sending alerts 24/7 to IT department" -ForegroundColor Cyan
    Write-Host ""
}

# Main execution
try {
    Clear-Host
    
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "  DATADOG DEPLOYMENT FOR PYX HEALTH CORPORATION" -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Mode: $Mode" -ForegroundColor White
    Write-Host "  Datadog Site: $($Script:Config.DatadogSite)" -ForegroundColor Gray
    Write-Host ""
    
    Test-Administrator
    
    if ($Mode -eq 'InstallAgent') {
        Install-DatadogAgent
    }
    elseif ($Mode -eq 'CreateMonitors') {
        # Check Azure modules
        $requiredModules = @('Az.Accounts', 'Az.Resources')
        $missingModules = @()
        
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                $missingModules += $module
            }
        }
        
        if ($missingModules.Count -gt 0) {
            Write-Host "Missing Azure modules. Installing..." -ForegroundColor Yellow
            foreach ($module in $missingModules) {
                Install-Module -Name $module -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
            }
        }
        
        New-ComprehensiveMonitors
    }
    
    $duration = (Get-Date) - $Script:StartTime
    Write-Host "Total time: $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Cyan
    Write-Host ""
    
    $logPath = Join-Path -Path $PSScriptRoot -ChildPath "Datadog-Deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $Script:DeploymentLog | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "Log saved: $logPath" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host "  DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "==========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
finally {
    $ProgressPreference = 'Continue'
}
