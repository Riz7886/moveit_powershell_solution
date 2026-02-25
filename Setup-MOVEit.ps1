# SQL DTU Optimizer - MOVEit Server Setup
# Complete automated installation
# Author: Syed Rizvi

Write-Host "SQL DTU Optimizer - MOVEit Server Setup" -ForegroundColor Cyan
Write-Host "Syed Rizvi" -ForegroundColor White
Write-Host ""

$ScriptPath = "C:\Scripts\Weekly-Optimizer.ps1"
$ScriptFolder = "C:\Scripts"
$TaskName = "SQL DTU Weekly Optimizer"

Write-Host "Step 1: Creating directories..." -ForegroundColor Yellow
if (!(Test-Path $ScriptFolder)) {
    New-Item -Path $ScriptFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created $ScriptFolder" -ForegroundColor Green
}

if (!(Test-Path "C:\Temp\SQL_DTU_Optimizer")) {
    New-Item -Path "C:\Temp\SQL_DTU_Optimizer" -ItemType Directory -Force | Out-Null
    Write-Host "Created log directory" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 2: Installing Azure modules..." -ForegroundColor Yellow
$modules = @('Az.Accounts','Az.Sql','Az.Monitor')
foreach ($module in $modules) {
    if (!(Get-Module -ListAvailable -Name $module)) { 
        Write-Host "Installing $module..." -ForegroundColor Gray
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
        Write-Host "$module installed" -ForegroundColor Green
    } else {
        Write-Host "$module already installed" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Step 3: Copying optimizer script..." -ForegroundColor Yellow
$currentScript = Join-Path $PSScriptRoot "Weekly-Optimizer.ps1"
if (Test-Path $currentScript) {
    Copy-Item -Path $currentScript -Destination $ScriptPath -Force
    Write-Host "Script copied to $ScriptPath" -ForegroundColor Green
} else {
    Write-Host "ERROR: Weekly-Optimizer.ps1 not found" -ForegroundColor Red
    Write-Host "Please ensure Weekly-Optimizer.ps1 is in the same folder" -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "Step 4: Creating scheduled task..." -ForegroundColor Yellow

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed existing task" -ForegroundColor Gray
}

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" -AutoFix"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 7AM

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Weekly SQL DTU optimization. Analyzes all databases, maintains 50-60% utilization, emails Tony Schlak." | Out-Null

Write-Host "Task created successfully" -ForegroundColor Green

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "SETUP COMPLETE" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Task Name: $TaskName" -ForegroundColor White
Write-Host "  Schedule: Every Monday at 7:00 AM" -ForegroundColor White
Write-Host "  Script Location: $ScriptPath" -ForegroundColor White
Write-Host "  Reports: C:\Temp\SQL_DTU_Optimizer\Reports\" -ForegroundColor White
Write-Host "  Email To: tony.schlak@pyxhealth.com" -ForegroundColor White
Write-Host ""
Write-Host "What happens every Monday:" -ForegroundColor Cyan
Write-Host "  1. Analyzes all 170 databases" -ForegroundColor White
Write-Host "  2. Identifies databases needing adjustment" -ForegroundColor White
Write-Host "  3. Auto-fixes to optimal tier (50-60% utilization)" -ForegroundColor White
Write-Host "  4. Creates HTML report" -ForegroundColor White
Write-Host "  5. Emails report to Tony" -ForegroundColor White
Write-Host "  6. Saves report locally" -ForegroundColor White
Write-Host ""
Write-Host "Next scheduled run: Next Monday at 7:00 AM" -ForegroundColor Green
Write-Host ""
Write-Host "Manual Commands:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Test run (no changes):" -ForegroundColor Yellow
Write-Host "    cd C:\Scripts" -ForegroundColor Gray
Write-Host "    .\Weekly-Optimizer.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  Run with fixes:" -ForegroundColor Yellow
Write-Host "    cd C:\Scripts" -ForegroundColor Gray
Write-Host "    .\Weekly-Optimizer.ps1 -AutoFix" -ForegroundColor Gray
Write-Host ""
Write-Host "  Check task status:" -ForegroundColor Yellow
Write-Host "    Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "  Disable automation:" -ForegroundColor Yellow
Write-Host "    Disable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "  Re-enable automation:" -ForegroundColor Yellow
Write-Host "    Enable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host ""
Write-Host "Setup by: Syed Rizvi" -ForegroundColor White
Write-Host "Installation complete" -ForegroundColor Green
Write-Host ""
