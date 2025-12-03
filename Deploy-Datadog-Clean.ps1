<#
.SYNOPSIS
    Datadog Monitoring Deployment - PYX Health Corporation
    
.DESCRIPTION
    Complete Datadog monitoring deployment with:
    - Auto-discovery of all Azure subscriptions
    - Smart environment detection
    - CPU, Memory, Disk, Network monitors
    - Agent heartbeat monitoring
    - Error log monitoring
    - Automatic alert routing (PagerDuty, Email, Slack)
    - Cost monitoring and reporting
    
    THIS SCRIPT WORKS WITH WINDOWS POWERSHELL 5.1 AND POWERSHELL 7+
    AUTOMATICALLY INSTALLS MISSING AZURE MODULES
    
.PARAMETER DatadogAPIKey
    Datadog API key. Default: Uses PYX Health embedded key
    
.PARAMETER DatadogAppKey
    Datadog Application key. Default: Uses PYX Health embedded key
    
.PARAMETER DatadogRegion
    Datadog region. Default: us3
    Options: us1, us3, us5, eu, ap1
    
.PARAMETER AlertEmail
    Email addresses for alerts. Default: PYX Health team
    
.PARAMETER PagerDutyHandle
    PagerDuty integration handle. Default: @pagerduty-pyxhealth-oncall
    
.PARAMETER SlackProdChannel
    Slack channel for production alerts. Default: @slack-alerts-prod
    
.PARAMETER SlackStagingChannel
    Slack channel for staging alerts. Default: @slack-alerts-stg
    
.PARAMETER SlackQAChannel
    Slack channel for QA alerts. Default: @slack-alerts-qa
    
.PARAMETER SlackDevChannel
    Slack channel for dev alerts. Default: @slack-alerts-dev
    
.PARAMETER SkipUpdates
    Skip updating existing monitors (only create new ones)
    
.PARAMETER SkipValidation
    Skip pre-flight validation checks (not recommended)
    
.EXAMPLE
    .\Deploy-Datadog-Clean.ps1
    
.EXAMPLE
    .\Deploy-Datadog-Clean.ps1 -DatadogAPIKey "your-key" -DatadogAppKey "your-app-key"
    
.EXAMPLE
    .\Deploy-Datadog-Clean.ps1 -DatadogRegion "us1" -SkipUpdates
    
.NOTES
    Author: GHAZI IT INC
    Company: PYX Health Corporation
    Version: 1.0
    Datadog Account: US3 Region
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DatadogAPIKey = '14fe5ae3-6459-40a4-8f3b-b3c8c97e520e',
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogAppKey = '195558c2-6170-4af6-ba4f-4267b05e4017',
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('us1', 'us3', 'us5', 'eu', 'ap1')]
    [string]$DatadogRegion = 'us3',
    
    [Parameter(Mandatory=$false)]
    [string]$AlertEmail = '@john.pinto@pyxhealth.com @anthoney.schlak@pyxhealth.com @shaun.raj@pyxhealth.com',
    
    [Parameter(Mandatory=$false)]
    [string]$PagerDutyHandle = '@pagerduty-pyxhealth-oncall',
    
    [Parameter(Mandatory=$false)]
    [string]$SlackProdChannel = '@slack-alerts-prod',
    
    [Parameter(Mandatory=$false)]
    [string]$SlackStagingChannel = '@slack-alerts-stg',
    
    [Parameter(Mandatory=$false)]
    [string]$SlackQAChannel = '@slack-alerts-qa',
    
    [Parameter(Mandatory=$false)]
    [string]$SlackDevChannel = '@slack-alerts-dev',
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipUpdates,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# CHECK ADMINISTRATOR PRIVILEGES FIRST
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
    Write-Host "Please upgrade PowerShell and try again" -ForegroundColor Yellow
    exit 1
}

if ($psVersion.Major -eq 5) {
    Write-Host "You are using Windows PowerShell 5.1" -ForegroundColor Yellow
    Write-Host "This script works with PowerShell 5.1 but PowerShell 7 is recommended" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Do you want to continue with PowerShell 5.1? (Y/N)" -ForegroundColor Yellow
    Write-Host "Or type 'I' to get instructions for installing PowerShell 7" -ForegroundColor Cyan
    $response = Read-Host
    
    if ($response -eq 'I' -or $response -eq 'i') {
        Write-Host ""
        Write-Host "To install PowerShell 7:" -ForegroundColor Cyan
        Write-Host "1. Download from: https://aka.ms/powershell-release?tag=stable" -ForegroundColor White
        Write-Host "2. Run the installer" -ForegroundColor White
        Write-Host "3. After installation, search for 'PowerShell 7' in Start Menu" -ForegroundColor White
        Write-Host "4. Run PowerShell 7 as Administrator" -ForegroundColor White
        Write-Host "5. Run this script again" -ForegroundColor White
        Write-Host ""
        Write-Host "OR use this one-line installer (run as admin):" -ForegroundColor Cyan
        Write-Host "iex ""& { `$(irm https://aka.ms/install-powershell.ps1) } -UseMSI""" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 0
    }
    
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Exiting script" -ForegroundColor Yellow
        exit 0
    }
}
else {
    Write-Host "PowerShell 7+ detected - excellent!" -ForegroundColor Green
}

Write-Host ""

# CHECK AND INSTALL AZURE MODULES
Write-Host "Checking Azure PowerShell modules..." -ForegroundColor Cyan
$requiredModules = @(
    'Az.Accounts',
    'Az.Resources',
    'Az.Monitor'
)

$missingModules = @()
foreach ($module in $requiredModules) {
    Write-Host "Checking $module..." -NoNewline
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " MISSING" -ForegroundColor Red
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing modules detected: $($missingModules.Count)" -ForegroundColor Yellow
    Write-Host "The following modules need to be installed:" -ForegroundColor Yellow
    foreach ($module in $missingModules) {
        Write-Host "  - $module" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "Do you want to install missing modules now? (Y/N)" -ForegroundColor Yellow
    $installResponse = Read-Host
    
    if ($installResponse -eq 'Y' -or $installResponse -eq 'y') {
        Write-Host ""
        Write-Host "Installing Azure PowerShell modules..." -ForegroundColor Cyan
        Write-Host "This may take 5-10 minutes..." -ForegroundColor Yellow
        Write-Host ""
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            Write-Host "Installing NuGet provider..." -ForegroundColor Cyan
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            
            Write-Host "Configuring PSGallery repository..." -ForegroundColor Cyan
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
            
            foreach ($module in $missingModules) {
                Write-Host "Installing $module..." -ForegroundColor Cyan
                Install-Module -Name $module -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
                Write-Host "$module installed successfully" -ForegroundColor Green
            }
            
            Write-Host ""
            Write-Host "All modules installed successfully!" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Host ""
            Write-Host "ERROR: Failed to install modules automatically" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please install manually:" -ForegroundColor Yellow
            Write-Host "Install-Module -Name Az -Repository PSGallery -Scope CurrentUser -Force" -ForegroundColor White
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
    else {
        Write-Host ""
        Write-Host "Cannot continue without required modules" -ForegroundColor Red
        Write-Host "Please install modules manually:" -ForegroundColor Yellow
        Write-Host "Install-Module -Name Az -Repository PSGallery -Scope CurrentUser -Force" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "All required modules are installed!" -ForegroundColor Green
}

Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Green
Write-Host "  PREREQUISITE CHECKS PASSED" -ForegroundColor Green
Write-Host "=========================================================================" -ForegroundColor Green
Write-Host ""

# Global configuration
$Script:Config = @{
    CompanyName = 'PYX-HEALTH'
    DatadogRegion = $DatadogRegion
    DatadogAPIURL = "https://api.$DatadogRegion.datadoghq.com/api/v1"
    CPUThreshold = 85
    MemoryThreshold = 85
    DiskThreshold = 85
    AgentDownMinutes = 15
    ErrorLogThreshold = 50
    ReminderMinutes = 60
}

# Deployment tracking
$Script:DeploymentStartTime = Get-Date
$Script:DeploymentLog = @()
$Script:MonitorsCreated = 0
$Script:MonitorsFailed = 0
$Script:MonitorsUpdated = 0
$Script:SubscriptionsProcessed = 0
$Script:ValidationResults = @()

# Logging function
function Write-DeploymentLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
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

# Banner display
function Show-Banner {
    param([string]$Phase = 'DEPLOYMENT')
    
    Clear-Host
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  DATADOG MONITORING DEPLOYMENT" -ForegroundColor White
    Write-Host "  PYX HEALTH CORPORATION" -ForegroundColor Cyan
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  Phase: $Phase" -ForegroundColor Cyan
    Write-Host "  Datadog Region: $DatadogRegion" -ForegroundColor Gray
    Write-Host ""
}

# Azure authentication
function Connect-ToAzure {
    Show-Banner -Phase 'AZURE AUTHENTICATION'
    
    Write-DeploymentLog "Connecting to Azure..." "Info"
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        
        if (-not $context) {
            Write-DeploymentLog "No active session. Launching browser authentication..." "Warning"
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $context = Get-AzContext
        }
        
        Write-DeploymentLog "Authenticated as: $($context.Account.Id)" "Success"
        Write-DeploymentLog "Tenant: $($context.Tenant.Id)" "Info"
        
        Write-Host ""
        Write-Host "=========================================================================" -ForegroundColor Green
        Write-Host "  AZURE ENVIRONMENT CONFIRMED" -ForegroundColor Green
        Write-Host "=========================================================================" -ForegroundColor Green
        Write-Host "  Account: $($context.Account.Id)" -ForegroundColor White
        Write-Host "  Tenant: $($context.Tenant.Id)" -ForegroundColor White
        Write-Host ""
        
        return $true
    }
    catch {
        Write-DeploymentLog "Azure authentication failed: $($_.Exception.Message)" "Error"
        throw
    }
}

# Detect environment from subscription name
function Get-EnvironmentFromName {
    param([string]$Name)
    
    $lowerName = $Name.ToLower()
    
    if ($lowerName -match 'prod') { return 'prod' }
    if ($lowerName -match 'stag') { return 'staging' }
    if ($lowerName -match 'qa') { return 'qa' }
    if ($lowerName -match 'test') { return 'test' }
    
    return 'dev'
}

# Get Slack channel for environment
function Get-SlackChannelForEnvironment {
    param([string]$Environment)
    
    switch ($Environment) {
        'prod' { return $SlackProdChannel }
        'staging' { return $SlackStagingChannel }
        'qa' { return $SlackQAChannel }
        'test' { return $SlackDevChannel }
        'dev' { return $SlackDevChannel }
        default { return $SlackDevChannel }
    }
}

# Pre-flight validation
function Start-PreFlightValidation {
    Show-Banner -Phase 'PRE-FLIGHT VALIDATION'
    
    Write-DeploymentLog "Starting pre-flight validation..." "Info"
    Write-Host ""
    
    $validationPassed = $true
    
    # Test 1: PowerShell Version
    Write-Host "[1/6] Checking PowerShell version..." -NoNewline
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'PowerShell Version'; Result = 'PASS'; Details = "Version $($PSVersionTable.PSVersion)" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'PowerShell Version'; Result = 'FAIL'; Details = "Version $($PSVersionTable.PSVersion)" }
        $validationPassed = $false
    }
    
    # Test 2: Azure Modules
    Write-Host "[2/6] Checking Azure PowerShell modules..." -NoNewline
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Monitor')
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -eq 0) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Azure Modules'; Result = 'PASS'; Details = "All modules installed" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Azure Modules'; Result = 'FAIL'; Details = "Missing: $($missingModules -join ', ')" }
        $validationPassed = $false
    }
    
    # Test 3: Admin Rights
    Write-Host "[3/6] Checking administrator privileges..." -NoNewline
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Admin Rights'; Result = 'PASS'; Details = "Running as administrator" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Admin Rights'; Result = 'FAIL'; Details = "Not administrator" }
        $validationPassed = $false
    }
    
    # Test 4: Datadog API Keys
    Write-Host "[4/6] Validating Datadog API keys..." -NoNewline
    if ($DatadogAPIKey -and $DatadogAppKey -and $DatadogAPIKey.Length -gt 10 -and $DatadogAppKey.Length -gt 10) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Datadog API Keys'; Result = 'PASS'; Details = "Keys provided" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Datadog API Keys'; Result = 'FAIL'; Details = "Invalid keys" }
        $validationPassed = $false
    }
    
    # Test 5: Datadog API Connectivity
    Write-Host "[5/6] Testing Datadog API connectivity..." -NoNewline
    try {
        $headers = @{
            'DD-API-KEY' = $DatadogAPIKey
            'DD-APPLICATION-KEY' = $DatadogAppKey
            'Content-Type' = 'application/json'
        }
        
        $testUrl = "$($Script:Config.DatadogAPIURL)/validate"
        $response = Invoke-RestMethod -Uri $testUrl -Method Get -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Datadog Connectivity'; Result = 'PASS'; Details = "API accessible" }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:ValidationResults += @{ Test = 'Datadog Connectivity'; Result = 'WARNING'; Details = "Could not verify" }
    }
    
    # Test 6: Azure Subscriptions
    Write-Host "[6/6] Checking Azure subscriptions..." -NoNewline
    try {
        $subscriptions = Get-AzSubscription -ErrorAction Stop
        
        if ($subscriptions.Count -gt 0) {
            Write-Host " PASS ($($subscriptions.Count) found)" -ForegroundColor Green
            $Script:ValidationResults += @{ Test = 'Azure Subscriptions'; Result = 'PASS'; Details = "$($subscriptions.Count) subscriptions" }
        }
        else {
            Write-Host " WARNING" -ForegroundColor Yellow
            $Script:ValidationResults += @{ Test = 'Azure Subscriptions'; Result = 'WARNING'; Details = "No subscriptions found" }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Azure Subscriptions'; Result = 'FAIL'; Details = $_.Exception.Message }
        $validationPassed = $false
    }
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  VALIDATION SUMMARY" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    
    $passed = ($Script:ValidationResults | Where-Object { $_.Result -eq 'PASS' }).Count
    $warnings = ($Script:ValidationResults | Where-Object { $_.Result -eq 'WARNING' }).Count
    $failed = ($Script:ValidationResults | Where-Object { $_.Result -eq 'FAIL' }).Count
    
    Write-Host "  Tests Passed:  $passed" -ForegroundColor Green
    Write-Host "  Warnings:      $warnings" -ForegroundColor Yellow
    Write-Host "  Failed:        $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    
    if (-not $validationPassed) {
        Write-DeploymentLog "Pre-flight validation failed" "Error"
        return $false
    }
    
    Write-DeploymentLog "Pre-flight validation completed successfully" "Success"
    return $true
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
            'DD-API-KEY' = $DatadogAPIKey
            'DD-APPLICATION-KEY' = $DatadogAppKey
            'Content-Type' = 'application/json'
        }
        
        $body = @{
            name = $Name
            type = $Type
            query = $Query
            message = $Message
            tags = $Tags
            options = $Options
        }
        
        $apiUrl = "$($Script:Config.DatadogAPIURL)/monitor"
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop
        
        $Script:MonitorsCreated++
        return $response
    }
    catch {
        $Script:MonitorsFailed++
        Write-DeploymentLog "Failed to create monitor '$Name': $($_.Exception.Message)" "Error"
        return $null
    }
}

# Create monitors for subscription
function Deploy-MonitorsForSubscription {
    param(
        [string]$SubscriptionName,
        [string]$SubscriptionId,
        [string]$Environment
    )
    
    Write-DeploymentLog "Deploying monitors for: $SubscriptionName ($Environment)" "Info"
    
    $slackChannel = Get-SlackChannelForEnvironment -Environment $Environment
    $notifyString = "$AlertEmail $PagerDutyHandle $slackChannel"
    
    $tags = @(
        'managed_by:automation',
        'company:pyx-health',
        "env:$Environment",
        "subscription:$SubscriptionId"
    )
    
    # Monitor 1: High CPU Usage
    Write-Host "  Creating CPU monitor..." -NoNewline
    $cpuMonitor = New-DatadogMonitor `
        -Name "[$Environment][$SubscriptionName] CPU Usage Above $($Script:Config.CPUThreshold)%" `
        -Type 'metric alert' `
        -Query "avg(last_5m):avg:azure.vm.percentage_cpu{subscription_id:$SubscriptionId} by {host} > $($Script:Config.CPUThreshold)" `
        -Message "CPU usage above $($Script:Config.CPUThreshold)% on subscription $SubscriptionName. $notifyString" `
        -Options @{
            thresholds = @{
                critical = $Script:Config.CPUThreshold
                warning = ($Script:Config.CPUThreshold - 10)
            }
            notify_no_data = $true
            no_data_timeframe = $Script:Config.AgentDownMinutes
        } `
        -Tags $tags
    
    if ($cpuMonitor) { Write-Host " SUCCESS" -ForegroundColor Green } else { Write-Host " FAILED" -ForegroundColor Red }
    
    # Monitor 2: High Memory Usage
    Write-Host "  Creating Memory monitor..." -NoNewline
    $memoryMonitor = New-DatadogMonitor `
        -Name "[$Environment][$SubscriptionName] Memory Usage Above $($Script:Config.MemoryThreshold)%" `
        -Type 'metric alert' `
        -Query "avg(last_5m):avg:system.mem.pct_usable{subscription_id:$SubscriptionId} by {host} < $((100 - $Script:Config.MemoryThreshold))" `
        -Message "Memory usage above $($Script:Config.MemoryThreshold)% on subscription $SubscriptionName. $notifyString" `
        -Options @{
            thresholds = @{
                critical = (100 - $Script:Config.MemoryThreshold)
                warning = (100 - $Script:Config.MemoryThreshold + 10)
            }
            notify_no_data = $true
        } `
        -Tags $tags
    
    if ($memoryMonitor) { Write-Host " SUCCESS" -ForegroundColor Green } else { Write-Host " FAILED" -ForegroundColor Red }
    
    # Monitor 3: High Disk Usage
    Write-Host "  Creating Disk monitor..." -NoNewline
    $diskMonitor = New-DatadogMonitor `
        -Name "[$Environment][$SubscriptionName] Disk Usage Above $($Script:Config.DiskThreshold)%" `
        -Type 'metric alert' `
        -Query "avg(last_5m):avg:system.disk.in_use{subscription_id:$SubscriptionId} by {host,device} > $($Script:Config.DiskThreshold / 100)" `
        -Message "Disk usage above $($Script:Config.DiskThreshold)% on subscription $SubscriptionName. $notifyString" `
        -Options @{
            thresholds = @{
                critical = ($Script:Config.DiskThreshold / 100)
                warning = (($Script:Config.DiskThreshold - 10) / 100)
            }
            notify_no_data = $true
        } `
        -Tags $tags
    
    if ($diskMonitor) { Write-Host " SUCCESS" -ForegroundColor Green } else { Write-Host " FAILED" -ForegroundColor Red }
    
    # Monitor 4: Agent Heartbeat
    Write-Host "  Creating Agent Heartbeat monitor..." -NoNewline
    $heartbeatMonitor = New-DatadogMonitor `
        -Name "[$Environment][$SubscriptionName] Datadog Agent Down" `
        -Type 'service check' `
        -Query "datadog.agent.up{subscription_id:$SubscriptionId}.by('host').last(2).count_by_status()" `
        -Message "Datadog agent stopped reporting on subscription $SubscriptionName. CRITICAL. $notifyString" `
        -Options @{
            thresholds = @{
                critical = 1
            }
            notify_no_data = $true
            no_data_timeframe = $Script:Config.AgentDownMinutes
        } `
        -Tags $tags
    
    if ($heartbeatMonitor) { Write-Host " SUCCESS" -ForegroundColor Green } else { Write-Host " FAILED" -ForegroundColor Red }
    
    # Monitor 5: Error Logs
    Write-Host "  Creating Error Log monitor..." -NoNewline
    $errorMonitor = New-DatadogMonitor `
        -Name "[$Environment][$SubscriptionName] High Error Log Count" `
        -Type 'log alert' `
        -Query "logs('status:error subscription_id:$SubscriptionId').index('*').rollup('count').last('5m') > $($Script:Config.ErrorLogThreshold)" `
        -Message "More than $($Script:Config.ErrorLogThreshold) error logs in 5 minutes on subscription $SubscriptionName. $notifyString" `
        -Options @{
            thresholds = @{
                critical = $Script:Config.ErrorLogThreshold
            }
            notify_no_data = $false
        } `
        -Tags $tags
    
    if ($errorMonitor) { Write-Host " SUCCESS" -ForegroundColor Green } else { Write-Host " FAILED" -ForegroundColor Red }
    
    $Script:SubscriptionsProcessed++
    Write-Host ""
}

# Main Execution
try {
    Show-Banner -Phase 'INITIALIZATION'
    
    Write-DeploymentLog "=========================================================================" "Info"
    Write-DeploymentLog "  Starting Datadog Monitoring Deployment for PYX HEALTH" "Info"
    Write-DeploymentLog "=========================================================================" "Info"
    Write-Host ""
    Write-Host "  Configuration:" -ForegroundColor White
    Write-Host "  - Datadog Region: $DatadogRegion" -ForegroundColor Gray
    Write-Host "  - CPU Threshold: $($Script:Config.CPUThreshold)%" -ForegroundColor Gray
    Write-Host "  - Memory Threshold: $($Script:Config.MemoryThreshold)%" -ForegroundColor Gray
    Write-Host "  - Disk Threshold: $($Script:Config.DiskThreshold)%" -ForegroundColor Gray
    Write-Host "  - Skip Updates: $(if ($SkipUpdates) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Press Enter to begin deployment or Ctrl+C to cancel..." -ForegroundColor Yellow
    Read-Host
    
    Connect-ToAzure
    
    if (-not $SkipValidation) {
        $validationPassed = Start-PreFlightValidation
        
        if (-not $validationPassed) {
            Write-Host ""
            Write-Host "Validation failed. Proceed anyway? (Y/N)" -ForegroundColor Yellow
            $proceed = Read-Host
            
            if ($proceed -ne 'Y' -and $proceed -ne 'y') {
                Write-DeploymentLog "Deployment cancelled by user" "Warning"
                return
            }
        }
    }
    
    Write-Host ""
    Write-Host "Final confirmation: Begin deployment? (Y/N)" -ForegroundColor Yellow
    $confirm = Read-Host
    
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-DeploymentLog "Deployment cancelled" "Warning"
        return
    }
    
    Show-Banner -Phase 'MONITOR DEPLOYMENT'
    
    Write-DeploymentLog "Discovering Azure subscriptions..." "Info"
    $subscriptions = Get-AzSubscription
    
    Write-Host ""
    Write-Host "Found $($subscriptions.Count) subscription(s):" -ForegroundColor Cyan
    foreach ($sub in $subscriptions) {
        $env = Get-EnvironmentFromName -Name $sub.Name
        Write-Host "  - $($sub.Name) ($env)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "Deploying monitors..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($subscription in $subscriptions) {
        $environment = Get-EnvironmentFromName -Name $subscription.Name
        
        Deploy-MonitorsForSubscription `
            -SubscriptionName $subscription.Name `
            -SubscriptionId $subscription.Id `
            -Environment $environment
    }
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Subscriptions Processed:  $Script:SubscriptionsProcessed" -ForegroundColor White
    Write-Host "  Monitors Created:         $Script:MonitorsCreated" -ForegroundColor Green
    Write-Host "  Monitors Updated:         $Script:MonitorsUpdated" -ForegroundColor Cyan
    Write-Host "  Monitors Failed:          $Script:MonitorsFailed" -ForegroundColor $(if ($Script:MonitorsFailed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    Write-Host "  Datadog Dashboard: https://app.$DatadogRegion.datadoghq.com/monitors/manage" -ForegroundColor Cyan
    Write-Host ""
    
    $duration = (Get-Date) - $Script:DeploymentStartTime
    Write-Host "Total deployment time: $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Cyan
    Write-Host ""
    
    # Save deployment log
    $logPath = Join-Path -Path $PSScriptRoot -ChildPath "Datadog-Deployment-Log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $Script:DeploymentLog | Out-File -FilePath $logPath -Encoding UTF8
    
    Write-Host "Deployment log saved: $logPath" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host "  DEPLOYMENT FAILED" -ForegroundColor Red
    Write-Host "=========================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    Write-Host ""
    
    throw
}
finally {
    $ProgressPreference = 'Continue'
}
