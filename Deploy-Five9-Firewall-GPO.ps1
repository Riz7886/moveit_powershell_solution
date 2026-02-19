param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("CreateGPO", "DeployDirect", "Both")]
    [string]$Mode = "Both",
    
    [Parameter(Mandatory=$false)]
    [string]$GPOName = "Five9 Softphone - Firewall Exception",
    
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Temp\Five9_Deployment_Log.txt"
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    Add-Content -Path $LogPath -Value $logMessage
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  FIVE9 SOFTPHONE - FIREWALL GPO DEPLOYMENT" -ForegroundColor Yellow
Write-Host "  PYX Health Environment - All 13 Subscriptions" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Log "Starting Five9 firewall deployment - Mode: $Mode" -Color Cyan

function Install-RequiredModules {
    Write-Log "Checking required modules..." -Color Cyan
    
    if ($Mode -eq "CreateGPO" -or $Mode -eq "Both") {
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Log "Installing Group Policy module..." -Color Yellow
            try {
                Import-Module GroupPolicy -ErrorAction Stop
            } catch {
                Write-Log "WARNING: Group Policy module not available. Install RSAT tools." -Color Yellow
                Write-Log "Run: Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -Color Yellow
            }
        }
    }
    
    Write-Log "Modules check complete" -Color Green
}

function Get-Five9Path {
    $possiblePaths = @(
        "C:\Program Files\Five9\Five9 Softphone\Five9Softphone.exe",
        "C:\Program Files (x86)\Five9\Five9 Softphone\Five9Softphone.exe",
        "${env:ProgramFiles}\Five9\Five9 Softphone\Five9Softphone.exe",
        "${env:ProgramFiles(x86)}\Five9\Five9 Softphone\Five9Softphone.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Log "Found Five9 at: $path" -Color Green
            return $path
        }
    }
    
    Write-Log "Five9 not found at standard locations, using default path" -Color Yellow
    return "C:\Program Files\Five9\Five9 Softphone\Five9Softphone.exe"
}

function Create-FirewallRules {
    Write-Log "Creating firewall rules on local machine..." -Color Cyan
    
    $five9Path = Get-Five9Path
    
    try {
        $existingInbound = Get-NetFirewallRule -DisplayName "Five9 Softphone Inbound" -ErrorAction SilentlyContinue
        if ($existingInbound) {
            Write-Log "Removing existing inbound rule..." -Color Yellow
            Remove-NetFirewallRule -DisplayName "Five9 Softphone Inbound" -ErrorAction SilentlyContinue
        }
        
        Write-Log "Creating inbound firewall rule..." -Color White
        New-NetFirewallRule -DisplayName "Five9 Softphone Inbound" `
            -Description "Allow Five9 Softphone inbound connections" `
            -Direction Inbound `
            -Program $five9Path `
            -Action Allow `
            -Profile Any `
            -Enabled True `
            -ErrorAction Stop
        
        Write-Log "Inbound rule created successfully" -Color Green
        
        $existingOutbound = Get-NetFirewallRule -DisplayName "Five9 Softphone Outbound" -ErrorAction SilentlyContinue
        if ($existingOutbound) {
            Write-Log "Removing existing outbound rule..." -Color Yellow
            Remove-NetFirewallRule -DisplayName "Five9 Softphone Outbound" -ErrorAction SilentlyContinue
        }
        
        Write-Log "Creating outbound firewall rule..." -Color White
        New-NetFirewallRule -DisplayName "Five9 Softphone Outbound" `
            -Description "Allow Five9 Softphone outbound connections" `
            -Direction Outbound `
            -Program $five9Path `
            -Action Allow `
            -Profile Any `
            -Enabled True `
            -ErrorAction Stop
        
        Write-Log "Outbound rule created successfully" -Color Green
        
        return $true
    } catch {
        Write-Log "ERROR: Failed to create firewall rules - $($_.Exception.Message)" -Color Red
        return $false
    }
}

function Create-GPOPolicy {
    Write-Log "Creating Group Policy Object..." -Color Cyan
    
    try {
        Import-Module GroupPolicy -ErrorAction Stop
        
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Log "Domain: $($domain.DNSRoot)" -Color White
        
        $existingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
        if ($existingGPO) {
            Write-Log "GPO '$GPOName' already exists. Removing old version..." -Color Yellow
            Remove-GPO -Name $GPOName -ErrorAction Stop
        }
        
        Write-Log "Creating new GPO: $GPOName" -Color White
        $gpo = New-GPO -Name $GPOName -Comment "Five9 Softphone firewall exceptions for Salesforce integration" -ErrorAction Stop
        Write-Log "GPO created with GUID: $($gpo.Id)" -Color Green
        
        $five9Path = Get-Five9Path
        
        Write-Log "Configuring GPO firewall rules..." -Color White
        
        $gpoRegPath = "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules"
        
        Set-GPRegistryValue -Name $GPOName -Key $gpoRegPath `
            -ValueName "Five9-Inbound-{$([guid]::NewGuid())}" `
            -Type String `
            -Value "v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|App=$five9Path|Name=Five9 Softphone Inbound|Desc=Allow Five9 Softphone inbound connections|" `
            -ErrorAction Stop
        
        Set-GPRegistryValue -Name $GPOName -Key $gpoRegPath `
            -ValueName "Five9-Outbound-{$([guid]::NewGuid())}" `
            -Type String `
            -Value "v2.30|Action=Allow|Active=TRUE|Dir=Out|Protocol=6|App=$five9Path|Name=Five9 Softphone Outbound|Desc=Allow Five9 Softphone outbound connections|" `
            -ErrorAction Stop
        
        Write-Log "Firewall rules configured in GPO" -Color Green
        
        if ($TargetOU -ne "") {
            Write-Log "Linking GPO to OU: $TargetOU" -Color White
            New-GPLink -Name $GPOName -Target $TargetOU -ErrorAction Stop
            Write-Log "GPO linked successfully" -Color Green
        } else {
            $defaultOU = $domain.DistinguishedName
            Write-Log "No OU specified. Link manually or run with -TargetOU parameter" -Color Yellow
            Write-Log "Example: -TargetOU 'OU=Workstations,DC=pyxhealth,DC=com'" -Color Yellow
        }
        
        Write-Log "GPO created successfully!" -Color Green
        Write-Log "GPO Name: $GPOName" -Color White
        Write-Log "Run 'gpupdate /force' on client machines to apply immediately" -Color Yellow
        
        return $true
    } catch {
        Write-Log "ERROR: Failed to create GPO - $($_.Exception.Message)" -Color Red
        return $false
    }
}

function Deploy-ToAzureVMs {
    Write-Log "Checking Azure VMs across all 13 subscriptions..." -Color Cyan
    
    try {
        $azureInstalled = Get-Module -ListAvailable -Name Az.Compute
        if (-not $azureInstalled) {
            Write-Log "Azure modules not installed. Skipping Azure VM deployment." -Color Yellow
            return
        }
        
        Import-Module Az.Accounts -ErrorAction SilentlyContinue
        Import-Module Az.Compute -ErrorAction SilentlyContinue
        
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            Write-Log "Not connected to Azure. Connect first with Connect-AzAccount" -Color Yellow
            return
        }
        
        Write-Log "Connected to Azure as: $($context.Account.Id)" -Color Green
        
        $subscriptions = Get-AzSubscription
        Write-Log "Found $($subscriptions.Count) subscriptions" -Color White
        
        $scriptContent = @"
`$five9Path = 'C:\Program Files\Five9\Five9 Softphone\Five9Softphone.exe'
if (-not (Test-Path `$five9Path)) {
    `$five9Path = 'C:\Program Files (x86)\Five9\Five9 Softphone\Five9Softphone.exe'
}

Remove-NetFirewallRule -DisplayName 'Five9 Softphone Inbound' -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName 'Five9 Softphone Outbound' -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName 'Five9 Softphone Inbound' -Direction Inbound -Program `$five9Path -Action Allow -Profile Any -Enabled True
New-NetFirewallRule -DisplayName 'Five9 Softphone Outbound' -Direction Outbound -Program `$five9Path -Action Allow -Profile Any -Enabled True

Write-Output 'Five9 firewall rules created successfully'
"@
        
        foreach ($sub in $subscriptions) {
            Write-Log "Checking subscription: $($sub.Name)" -Color White
            Set-AzContext -SubscriptionId $sub.Id | Out-Null
            
            $vms = Get-AzVM
            Write-Log "  Found $($vms.Count) VMs in this subscription" -Color Gray
            
            foreach ($vm in $vms) {
                if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {
                    Write-Log "  Deploying to VM: $($vm.Name)" -Color White
                    try {
                        Invoke-AzVMRunCommand -ResourceGroupName $vm.ResourceGroupName `
                            -VMName $vm.Name `
                            -CommandId 'RunPowerShellScript' `
                            -ScriptString $scriptContent `
                            -ErrorAction Stop | Out-Null
                        
                        Write-Log "    Successfully deployed to $($vm.Name)" -Color Green
                    } catch {
                        Write-Log "    Failed to deploy to $($vm.Name): $($_.Exception.Message)" -Color Red
                    }
                }
            }
        }
        
        Write-Log "Azure VM deployment complete" -Color Green
        
    } catch {
        Write-Log "ERROR during Azure deployment: $($_.Exception.Message)" -Color Red
    }
}

Install-RequiredModules

Write-Host ""
Write-Log "Deployment Mode: $Mode" -Color Cyan
Write-Host ""

$success = $true

if ($Mode -eq "DeployDirect" -or $Mode -eq "Both") {
    Write-Host ""
    Write-Log "=== DIRECT DEPLOYMENT ===" -Color Yellow
    Write-Host ""
    
    $result = Create-FirewallRules
    if (-not $result) {
        $success = $false
    }
}

if ($Mode -eq "CreateGPO" -or $Mode -eq "Both") {
    Write-Host ""
    Write-Log "=== GROUP POLICY DEPLOYMENT ===" -Color Yellow
    Write-Host ""
    
    $result = Create-GPOPolicy
    if (-not $result) {
        $success = $false
    }
}

Write-Host ""
Write-Log "=== AZURE VM DEPLOYMENT (Optional) ===" -Color Yellow
Write-Host ""
Write-Log "Do you want to deploy to Azure VMs across all 13 subscriptions? (Y/N)" -Color Cyan
$deployAzure = Read-Host

if ($deployAzure -eq "Y" -or $deployAzure -eq "y") {
    Deploy-ToAzureVMs
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

if ($success) {
    Write-Log "All operations completed successfully!" -Color Green
} else {
    Write-Log "Some operations failed. Check the log for details." -Color Yellow
}

Write-Host ""
Write-Log "Log saved to: $LogPath" -Color Cyan
Write-Host ""
Write-Log "NEXT STEPS:" -Color Yellow
Write-Log "1. If GPO was created, link it to target OUs" -Color White
Write-Log "2. Run 'gpupdate /force' on client machines" -Color White
Write-Log "3. Users may need to restart or re-login" -Color White
Write-Host ""
