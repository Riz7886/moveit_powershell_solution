# Fix-DatadogHostname.ps1
# This script fixes Datadog agent hostname configuration
# Run as Administrator

param(
    [Parameter(Mandatory=$true)]
    [string]$NewHostname
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   DATADOG HOSTNAME FIX SCRIPT" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

$configFile = "C:\ProgramData\Datadog\datadog.yaml"

# Check if Datadog is installed
if (-not (Test-Path $configFile)) {
    Write-Host "ERROR: Datadog config file not found at $configFile" -ForegroundColor Red
    Write-Host "Is the Datadog Agent installed?" -ForegroundColor Yellow
    exit 1
}

Write-Host "Current hostname will be changed to: $NewHostname" -ForegroundColor Green
Write-Host ""

# Backup the config file
$backupFile = "$configFile.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Creating backup: $backupFile" -ForegroundColor Yellow
Copy-Item $configFile $backupFile

# Read the config
Write-Host "Reading current configuration..." -ForegroundColor Yellow
$config = Get-Content $configFile

# Update or add hostname
$hostnameFound = $false
$newConfig = @()

foreach ($line in $config) {
    if ($line -match "^hostname:" -or $line -match "^#hostname:") {
        $newConfig += "hostname: $NewHostname"
        $hostnameFound = $true
        Write-Host "Found existing hostname line - updating it" -ForegroundColor Yellow
    } else {
        $newConfig += $line
    }
}

if (-not $hostnameFound) {
    Write-Host "No hostname line found - adding it at the top" -ForegroundColor Yellow
    $newConfig = @("hostname: $NewHostname", "") + $newConfig
}

# Write the updated config
Write-Host "Writing new configuration..." -ForegroundColor Yellow
$newConfig | Set-Content $configFile -Force

Write-Host ""
Write-Host "Configuration updated successfully!" -ForegroundColor Green
Write-Host ""

# Restart the agent
Write-Host "Restarting Datadog Agent service..." -ForegroundColor Yellow
try {
    Restart-Service datadogagent -ErrorAction Stop
    Write-Host "Service restarted successfully!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to restart service: $_" -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 5

# Verify the change
Write-Host ""
Write-Host "Verifying the change..." -ForegroundColor Yellow
Write-Host ""

$agentExe = "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe"
if (Test-Path $agentExe) {
    Write-Host "Running agent status check..." -ForegroundColor Cyan
    Write-Host ""
    & $agentExe status | Select-String -Pattern "Hostnames|hostname" -Context 0,2
} else {
    Write-Host "Warning: Could not find agent.exe to verify status" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   HOSTNAME FIX COMPLETE!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "New hostname: $NewHostname" -ForegroundColor Green
Write-Host "Backup saved: $backupFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 2-3 minutes for data to start flowing" -ForegroundColor White
Write-Host "2. Check Datadog Infrastructure: https://us3.datadoghq.com/infrastructure" -ForegroundColor White
Write-Host "3. Look for hostname: $NewHostname" -ForegroundColor White
Write-Host ""