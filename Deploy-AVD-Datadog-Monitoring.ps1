#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Datadog Monitoring Integration for Azure Virtual Desktop
    
.DESCRIPTION
    Deploy Datadog monitors for AVD infrastructure.
    Run this AFTER Datadog agent is installed and configured.
    
    Creates monitors for:
    - CPU usage alerts
    - Memory usage alerts
    - Disk space alerts
    - Session host availability
    - User session counts
    - Network performance
    
.PARAMETER DatadogAPIKey
    Datadog API key (required)
    
.PARAMETER DatadogAppKey
    Datadog Application key (required)
    
.PARAMETER ResourceGroupName
    Azure resource group containing AVD resources
    
.PARAMETER HostPoolName
    AVD Host Pool name
    
.PARAMETER DatadogRegion
    Datadog region. Default: us3
    Options: us1, us3, us5, eu, ap1
    
.PARAMETER AlertEmail
    Email address for alert notifications
    
.PARAMETER SlackChannel
    Slack channel for alerts (optional)
    
.EXAMPLE
    .\Deploy-AVD-Datadog-Monitoring.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789" -ResourceGroupName "rg-pyx-avd-prod-20251202-1234" -HostPoolName "hp-pyx-avd-20251202"
    
.EXAMPLE
    .\Deploy-AVD-Datadog-Monitoring.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789" -ResourceGroupName "rg-pyx-avd-prod-20251202-1234" -HostPoolName "hp-pyx-avd-20251202" -AlertEmail "avd-admin@pyxhealth.com" -SlackChannel "@slack-avd-alerts"
    
.NOTES
    Author: GHAZI IT INC
    Company: PYX Health Corporation
    Version: 1.0
    
    Requirements:
    - Datadog account with API access
    - Datadog agent installed on Azure VMs
    - Azure PowerShell modules installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DatadogAPIKey,
    
    [Parameter(Mandatory=$true)]
    [string]$DatadogAppKey,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$HostPoolName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('us1', 'us3', 'us5', 'eu', 'ap1')]
    [string]$DatadogRegion = 'us3',
    
    [Parameter(Mandatory=$false)]
    [string]$AlertEmail = 'avd-admin@pyxhealth.com',
    
    [Parameter(Mandatory=$false)]
    [string]$SlackChannel
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "  DATADOG MONITORING INTEGRATION FOR AVD" -ForegroundColor White
Write-Host "  PYX HEALTH CORPORATION" -ForegroundColor Cyan
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host ""

$headers = @{
    'DD-API-KEY' = $DatadogAPIKey
    'DD-APPLICATION-KEY' = $DatadogAppKey
    'Content-Type' = 'application/json'
}

$apiUrl = "https://api.$DatadogRegion.datadoghq.com/api/v1/monitor"

$monitorsCreated = 0
$monitorsFailed = 0

function New-DatadogMonitor {
    param(
        [string]$Name,
        [string]$Type,
        [string]$Query,
        [string]$Message,
        [hashtable]$Options
    )
    
    try {
        $body = @{
            name = $Name
            type = $Type
            query = $Query
            message = $Message
            tags = @('avd', 'pyx-health', 'production', 'automated')
            options = $Options
        }
        
        Write-Host "Creating monitor: $Name..." -NoNewline
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 10)
        
        Write-Host " SUCCESS" -ForegroundColor Green
        $Script:monitorsCreated++
        
        return $response
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $Script:monitorsFailed++
        return $null
    }
}

Write-Host "Creating Datadog monitors for AVD environment..." -ForegroundColor Cyan
Write-Host ""

$notifyString = $AlertEmail
if ($SlackChannel) {
    $notifyString = "$AlertEmail $SlackChannel"
}

Write-Host "[1/10] High CPU Usage..." -NoNewline
New-DatadogMonitor -Name "AVD - High CPU Usage - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "avg(last_5m):avg:azure.compute.virtualmachine.percentage_cpu{resource_group:$ResourceGroupName} > 85" `
                   -Message "CPU usage above 85% on AVD session hosts. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 85
                           warning = 75
                       }
                       notify_no_data = $true
                       no_data_timeframe = 10
                   } | Out-Null

Write-Host "[2/10] High Memory Usage..." -NoNewline
New-DatadogMonitor -Name "AVD - High Memory Usage - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "avg(last_5m):avg:system.mem.pct_usable{resource_group:$ResourceGroupName} < 15" `
                   -Message "Available memory below 15% on AVD session hosts. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 15
                           warning = 20
                       }
                       notify_no_data = $true
                   } | Out-Null

Write-Host "[3/10] High Disk Usage..." -NoNewline
New-DatadogMonitor -Name "AVD - High Disk Usage - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "avg(last_5m):avg:system.disk.in_use{resource_group:$ResourceGroupName} > 85" `
                   -Message "Disk usage above 85% on AVD session hosts. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 85
                           warning = 75
                       }
                       notify_no_data = $true
                   } | Out-Null

Write-Host "[4/10] Session Host Down..." -NoNewline
New-DatadogMonitor -Name "AVD - Session Host Down - $HostPoolName" `
                   -Type 'service check' `
                   -Query "azure.vm.status{resource_group:$ResourceGroupName}.over('host').last(2).count_by_status()" `
                   -Message "AVD session host is down. CRITICAL ALERT. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 1
                       }
                       notify_no_data = $true
                   } | Out-Null

Write-Host "[5/10] Network Latency..." -NoNewline
New-DatadogMonitor -Name "AVD - High Network Latency - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "avg(last_5m):avg:azure.network.latency{resource_group:$ResourceGroupName} > 100" `
                   -Message "Network latency above 100ms on AVD infrastructure. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 100
                           warning = 75
                       }
                       notify_no_data = $false
                   } | Out-Null

Write-Host "[6/10] Storage Account Availability..." -NoNewline
New-DatadogMonitor -Name "AVD - Storage Account Unavailable - $HostPoolName" `
                   -Type 'service check' `
                   -Query "azure.storage.availability{resource_group:$ResourceGroupName}.over('storage_account').last(3).count_by_status()" `
                   -Message "Azure Storage (FSLogix) unavailable. User profiles cannot load. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 1
                       }
                       notify_no_data = $true
                   } | Out-Null

Write-Host "[7/10] High User Session Count..." -NoNewline
New-DatadogMonitor -Name "AVD - High User Session Count - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "avg(last_10m):avg:azure.desktopvirtualization.hostpool.active_sessions{host_pool:$HostPoolName} > 80" `
                   -Message "Active user sessions above 80. Consider scaling. $notifyString" `
                   -Options @{
                       thresholds = @{
                           warning = 80
                       }
                       notify_no_data = $false
                   } | Out-Null

Write-Host "[8/10] Failed User Connections..." -NoNewline
New-DatadogMonitor -Name "AVD - Failed User Connections - $HostPoolName" `
                   -Type 'metric alert' `
                   -Query "sum(last_5m):sum:azure.desktopvirtualization.hostpool.failed_connections{host_pool:$HostPoolName} > 5" `
                   -Message "More than 5 failed user connections detected. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 5
                           warning = 3
                       }
                       notify_no_data = $false
                   } | Out-Null

Write-Host "[9/10] Agent Heartbeat Loss..." -NoNewline
New-DatadogMonitor -Name "AVD - Agent Heartbeat Loss - $HostPoolName" `
                   -Type 'service check' `
                   -Query "datadog.agent.up{resource_group:$ResourceGroupName}.over('host').last(3).count_by_status()" `
                   -Message "Datadog agent stopped reporting from session host. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 1
                       }
                       notify_no_data = $true
                       no_data_timeframe = 10
                   } | Out-Null

Write-Host "[10/10] Resource Group Changes..." -NoNewline
New-DatadogMonitor -Name "AVD - Resource Group Changes - $HostPoolName" `
                   -Type 'event alert' `
                   -Query "events('sources:azure resource_group:$ResourceGroupName').rollup('count').last('10m') > 5" `
                   -Message "Unusual number of changes detected in AVD resource group. $notifyString" `
                   -Options @{
                       thresholds = @{
                           critical = 5
                       }
                       notify_no_data = $false
                   } | Out-Null

Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT SUMMARY" -ForegroundColor White
Write-Host "=========================================================================" -ForegroundColor Cyan
Write-Host "  Monitors Created:  $monitorsCreated" -ForegroundColor Green
Write-Host "  Monitors Failed:   $monitorsFailed" -ForegroundColor $(if ($monitorsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Resource Group:    $ResourceGroupName" -ForegroundColor White
Write-Host "  Host Pool:         $HostPoolName" -ForegroundColor White
Write-Host "  Alert Email:       $AlertEmail" -ForegroundColor White
if ($SlackChannel) {
    Write-Host "  Slack Channel:     $SlackChannel" -ForegroundColor White
}
Write-Host ""
Write-Host "  Datadog Dashboard: https://app.$DatadogRegion.datadoghq.com/monitors/manage" -ForegroundColor Cyan
Write-Host ""

if ($monitorsCreated -gt 0) {
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host "  DATADOG MONITORING CONFIGURED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "=========================================================================" -ForegroundColor Green
}
else {
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host "  DATADOG MONITORING CONFIGURATION FAILED" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Red
}

Write-Host ""
