#Requires -Version 5.1

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Audit','Remediate')]
    [string]$Mode = 'Audit',
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = ".\Reports"
)

$ErrorActionPreference = 'Stop'
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptPath "Modules"

$Global:AllIssues = @()
$Global:RemediationLog = @()
$Global:SelectedSubscriptions = @()
$Global:CostReport = @()
$Global:NSGReport = @()

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Install-ADModule {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  CHECKING ACTIVEDIRECTORY MODULE" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    
    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    
    if (-not $adModule) {
        Write-Host "ACTIVEDIRECTORY MODULE NOT FOUND" -ForegroundColor Red
        Write-Host ""
        Write-Host "The ActiveDirectory PowerShell module is required for AD scanning." -ForegroundColor Yellow
        Write-Host "Without it, the script cannot scan Active Directory." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Do you want to install it now?" -ForegroundColor Cyan
        Write-Host ""
        
        $install = Read-Host "Install ActiveDirectory module? (Y/N)"
        
        if ($install -eq 'Y' -or $install -eq 'y') {
            Write-Host ""
            Write-Host "Installing RSAT ActiveDirectory Tools..." -ForegroundColor Yellow
            Write-Host "Please wait, this may take 2-5 minutes..." -ForegroundColor Gray
            Write-Host ""
            
            try {
                $result = Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
                
                if ($result.RestartNeeded) {
                    Write-Host "Installation complete but RESTART REQUIRED" -ForegroundColor Yellow
                    Write-Host "Please restart your computer and run the script again" -ForegroundColor Yellow
                    return $false
                }
                
                Write-Host "ActiveDirectory module installed successfully!" -ForegroundColor Green
                Write-Host ""
                return $true
            }
            catch {
                Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                Write-Host "Try installing manually with this command:" -ForegroundColor Yellow
                Write-Host "Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor White
                Write-Host ""
                return $false
            }
        }
        else {
            Write-Host ""
            Write-Host "Installation skipped - AD scanning will be disabled" -ForegroundColor Yellow
            Write-Host ""
            return $false
        }
    }
    else {
        Write-Host "ACTIVEDIRECTORY MODULE FOUND" -ForegroundColor Green
        Write-Host ""
        return $true
    }
}

function Install-Modules {
    $modules = @('Az.Accounts', 'Az.Resources', 'Az.Compute', 'Az.Network', 'Az.Storage')
    foreach ($m in $modules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            Install-Module -Name $m -Repository PSGallery -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        }
    }
}

function Select-Subscriptions {
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Connect-AzAccount
        }
        
        $allSubs = Get-AzSubscription
        
        if ($allSubs.Count -eq 0) {
            return @()
        }
        
        Write-Host ""
        Write-Host "Available Subscriptions:" -ForegroundColor Cyan
        Write-Host ""
        
        for ($i = 0; $i -lt $allSubs.Count; $i++) {
            Write-Host "[$($i + 1)] $($allSubs[$i].Name)" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "[A] All Subscriptions" -ForegroundColor Green
        Write-Host ""
        
        $choice = Read-Host "Select subscriptions (1-$($allSubs.Count), A for all, or comma-separated)"
        
        if ($choice -eq 'A' -or $choice -eq 'a') {
            return $allSubs
        }
        
        $selected = @()
        $choices = $choice.Split(',').Trim()
        
        foreach ($c in $choices) {
            $index = [int]$c - 1
            if ($index -ge 0 -and $index -lt $allSubs.Count) {
                $selected += $allSubs[$index]
            }
        }
        
        return $selected
    }
    catch {
        return @()
    }
}

function Load-Modules {
    $moduleFiles = Get-ChildItem -Path $ModulePath -Filter "*.psm1" -ErrorAction SilentlyContinue
    foreach ($module in $moduleFiles) {
        Import-Module $module.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Header "ENTERPRISE CLOUD AUDIT SUITE V6"

if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$adModuleAvailable = Install-ADModule

Install-Modules
Load-Modules

$Global:SelectedSubscriptions = Select-Subscriptions

if ($Global:SelectedSubscriptions.Count -gt 0) {
    Write-Host ""
    Write-Host "Selected Subscriptions: $($Global:SelectedSubscriptions.Count)" -ForegroundColor Green
    Write-Host ""
}

if ($adModuleAvailable) {
    Write-Header "ACTIVE DIRECTORY AUDIT"
    
    try {
        $adIssues = Invoke-ADScan
        $Global:AllIssues += $adIssues
        
        Write-Host "AD Issues Found: $($adIssues.Count)" -ForegroundColor Yellow
        
        $critical = ($adIssues | Where-Object { $_.Severity -eq 'Critical' }).Count
        $high = ($adIssues | Where-Object { $_.Severity -eq 'High' }).Count
        Write-Host "  Critical: $critical" -ForegroundColor Red
        Write-Host "  High: $high" -ForegroundColor Magenta
        Write-Host ""
    }
    catch {
        Write-Host "AD scan failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  SKIPPING ACTIVE DIRECTORY AUDIT" -ForegroundColor White
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "AD module not available - AD scanning disabled" -ForegroundColor Yellow
    Write-Host ""
}

if ($Global:SelectedSubscriptions.Count -gt 0) {
    Write-Header "AZURE ENVIRONMENT AUDIT"
    
    try {
        $azureIssues = Invoke-AzureScan -Subscriptions $Global:SelectedSubscriptions
        $Global:AllIssues += $azureIssues
        
        Write-Host "Azure Issues Found: $($azureIssues.Count)" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Azure scan failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Header "AUDIT SUMMARY"

Write-Host "Total Issues: $($Global:AllIssues.Count)" -ForegroundColor Yellow
Write-Host ""

$fixable = ($Global:AllIssues | Where-Object { $_.AutoFixable -eq $true }).Count
Write-Host "Auto-Fixable: $fixable" -ForegroundColor Green
Write-Host ""

if ($Mode -eq 'Remediate' -and $fixable -gt 0) {
    Write-Header "REMEDIATION MODE"
    
    $confirm = Read-Host "Proceed with remediation? (Y/N)"
    
    if ($confirm -eq 'Y') {
        $fixableIssues = $Global:AllIssues | Where-Object { $_.AutoFixable -eq $true }
        
        foreach ($issue in $fixableIssues) {
            $result = $null
            
            switch ($issue.Type) {
                'AD' {
                    $result = Invoke-ADRemediation -Issue $issue
                }
                'Azure' {
                    $result = Invoke-AzureRemediation -Issue $issue
                }
            }
            
            if ($result) {
                $logEntry = [PSCustomObject]@{
                    Timestamp = Get-Date
                    Environment = $issue.Type
                    Resource = $issue.Resource
                    Issue = $issue.Issue
                    Action = $result.Action
                    Success = $result.Success
                    Details = $result.Details
                }
                
                $Global:RemediationLog += $logEntry
                
                $color = if ($result.Success) { 'Green' } else { 'Red' }
                Write-Host "[$($result.Action)] $($issue.Resource)" -ForegroundColor $color
            }
        }
        
        Write-Host ""
        Write-Header "REMEDIATION SUMMARY"
        
        $fixed = ($Global:RemediationLog | Where-Object { $_.Success -eq $true }).Count
        Write-Host "Issues Fixed: $fixed" -ForegroundColor Green
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$auditReport = Join-Path $ReportPath "AuditReport_$timestamp.csv"
$Global:AllIssues | Export-Csv -Path $auditReport -NoTypeInformation

Write-Host ""
Write-Host "Report: $auditReport" -ForegroundColor Green

if ($Global:RemediationLog.Count -gt 0) {
    $remLog = Join-Path $ReportPath "RemediationLog_$timestamp.csv"
    $Global:RemediationLog | Export-Csv -Path $remLog -NoTypeInformation
    Write-Host "Remediation Log: $remLog" -ForegroundColor Green
}

try {
    Export-CostReport -CostData $Global:CostReport -OutputPath $ReportPath
}
catch {}

try {
    Export-NSGReport -NSGData $Global:NSGReport -OutputPath $ReportPath
}
catch {}

try {
    Start-UI -Issues $Global:AllIssues -OutputPath $ReportPath
}
catch {}

try {
    Export-PBIDataset -Issues $Global:AllIssues -OutputPath $ReportPath
}
catch {}

Write-Host ""
Write-Header "AUDIT COMPLETE"
