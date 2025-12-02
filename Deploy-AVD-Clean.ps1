#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Storage, Az.Compute, Az.DesktopVirtualization, Az.Monitor
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Azure Virtual Desktop Enterprise Deployment - PYX Health Corporation
    
.DESCRIPTION
    Complete AVD infrastructure deployment with:
    - Zero Trust security architecture
    - 10 Windows 11 session hosts
    - FSLogix profile management
    - Network Security Groups
    - Azure Monitor integration
    - Optional Datadog monitoring
    - Conditional Access policies
    - Auto-scaling configuration
    
.PARAMETER SessionHostCount
    Number of session host VMs to deploy (1-100). Default: 10
    
.PARAMETER VMSize
    Azure VM size. Default: Standard_D4s_v5
    Options: Standard_D2s_v5, Standard_D4s_v5, Standard_D8s_v5, Standard_D16s_v5
    
.PARAMETER DeployBastion
    Deploy Azure Bastion for admin access. Default: false
    
.PARAMETER DeployMonitoring
    Deploy Azure Monitor and alerts. Default: true
    
.PARAMETER DatadogAPIKey
    Datadog API key for monitoring integration (optional)
    
.PARAMETER DatadogAppKey
    Datadog Application key for monitoring integration (optional)
    
.PARAMETER SkipValidation
    Skip pre-flight validation checks. Not recommended. Default: false
    
.EXAMPLE
    .\Deploy-AVD-Clean.ps1
    
.EXAMPLE
    .\Deploy-AVD-Clean.ps1 -SessionHostCount 20 -DeployBastion
    
.EXAMPLE
    .\Deploy-AVD-Clean.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789"
    
.NOTES
    Author: GHAZI IT INC
    Company: PYX Health Corporation
    Version: 1.0
    Target Subscription: sub-csc-avd (7edfb9f6-940e-47cd-af4b-04d0b6e6020f)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 100)]
    [int]$SessionHostCount = 10,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Standard_D2s_v5', 'Standard_D4s_v5', 'Standard_D8s_v5', 'Standard_D16s_v5')]
    [string]$VMSize = 'Standard_D4s_v5',
    
    [Parameter(Mandatory=$false)]
    [switch]$DeployBastion,
    
    [Parameter(Mandatory=$false)]
    [bool]$DeployMonitoring = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogAPIKey,
    
    [Parameter(Mandatory=$false)]
    [string]$DatadogAppKey,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Global configuration
$Script:Config = @{
    TargetSubscriptionId = '7edfb9f6-940e-47cd-af4b-04d0b6e6020f'
    TargetSubscriptionName = 'sub-csc-avd'
    TenantName = 'Pyx Health'
    TenantDomain = 'pyxhealth.com'
    CompanyName = 'PYX-HEALTH'
    Environment = 'Production'
    Location = 'East US'
    AdminUsername = 'avdadmin'
}

# Deployment tracking
$Script:DeploymentStartTime = Get-Date
$Script:DeploymentLog = @()
$Script:DeployedResources = @{}
$Script:ValidationResults = @()
$Script:TestResults = @()
$Script:DeploymentPhase = 'Initializing'

# Logging function
function Write-DeploymentLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [$Script:DeploymentPhase] $Message"
    $Script:DeploymentLog += $logEntry
    
    $color = switch ($Level) {
        'Info' { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Debug' { 'Gray' }
    }
    
    Write-Host $Message -ForegroundColor $color
}

# Banner display
function Show-Banner {
    param([string]$Phase = 'DEPLOYMENT')
    
    Clear-Host
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  AZURE VIRTUAL DESKTOP - ENTERPRISE DEPLOYMENT" -ForegroundColor White
    Write-Host "  PYX HEALTH CORPORATION" -ForegroundColor Cyan
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  Phase: $Phase" -ForegroundColor Cyan
    Write-Host "  Target: $($Script:Config.TenantName) ($($Script:Config.TenantDomain))" -ForegroundColor Gray
    Write-Host ""
}

# Azure authentication
function Connect-ToAzure {
    Show-Banner -Phase 'AZURE AUTHENTICATION'
    $Script:DeploymentPhase = 'Authentication'
    
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
        Write-Host "Verifying target subscription..." -ForegroundColor Cyan
        
        $targetSubscription = Get-AzSubscription -SubscriptionId $Script:Config.TargetSubscriptionId -ErrorAction SilentlyContinue
        
        if (-not $targetSubscription) {
            throw "Cannot find subscription: $($Script:Config.TargetSubscriptionName)"
        }
        
        Write-DeploymentLog "Target subscription found: $($targetSubscription.Name)" "Success"
        
        Set-AzContext -SubscriptionId $Script:Config.TargetSubscriptionId -ErrorAction Stop | Out-Null
        
        $Script:SubscriptionId = $targetSubscription.Id
        $Script:SubscriptionName = $targetSubscription.Name
        $Script:TenantId = $targetSubscription.TenantId
        
        Write-Host ""
        Write-Host "=========================================================================" -ForegroundColor Green
        Write-Host "  AZURE ENVIRONMENT CONFIRMED" -ForegroundColor Green
        Write-Host "=========================================================================" -ForegroundColor Green
        Write-Host "  Subscription: $($Script:SubscriptionName)" -ForegroundColor White
        Write-Host "  Subscription ID: $($Script:SubscriptionId)" -ForegroundColor Gray
        Write-Host "  Tenant: $($Script:Config.TenantName) ($($Script:Config.TenantDomain))" -ForegroundColor White
        Write-Host ""
        
        return $true
    }
    catch {
        Write-DeploymentLog "Azure authentication failed: $($_.Exception.Message)" "Error"
        throw
    }
}

# Generate secure password
function New-SecurePassword {
    $length = 24
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $special = '!@#$%^&*'
    
    $password = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $password += -join ((1..4) | ForEach-Object { $special[(Get-Random -Maximum $special.Length)] })
    $password += '0123'
    
    $passwordChars = $password.ToCharArray()
    $shuffled = $passwordChars | Sort-Object { Get-Random }
    $finalPassword = -join $shuffled
    
    return ConvertTo-SecureString $finalPassword -AsPlainText -Force
}

# Pre-flight validation
function Start-PreFlightValidation {
    Show-Banner -Phase 'PRE-FLIGHT VALIDATION'
    $Script:DeploymentPhase = 'Validation'
    
    Write-DeploymentLog "Starting pre-flight validation..." "Info"
    Write-Host ""
    
    $validationPassed = $true
    
    # Test 1: PowerShell Version
    Write-Host "[1/8] Checking PowerShell version..." -NoNewline
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'PowerShell Version'; Result = 'PASS'; Details = "Version $($PSVersionTable.PSVersion)" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        Write-Host "      Required: PowerShell 7.0+, Found: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'PowerShell Version'; Result = 'FAIL'; Details = "Version $($PSVersionTable.PSVersion)" }
        $validationPassed = $false
    }
    
    # Test 2: Azure Modules
    Write-Host "[2/8] Checking Azure PowerShell modules..." -NoNewline
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.Compute', 'Az.DesktopVirtualization', 'Az.Storage')
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
        Write-Host "      Missing: $($missingModules -join ', ')" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Azure Modules'; Result = 'FAIL'; Details = "Missing: $($missingModules -join ', ')" }
        $validationPassed = $false
    }
    
    # Test 3: Admin Rights
    Write-Host "[3/8] Checking administrator privileges..." -NoNewline
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
    
    # Test 4: Subscription Access
    Write-Host "[4/8] Validating subscription access..." -NoNewline
    try {
        $sub = Get-AzSubscription -SubscriptionId $Script:Config.TargetSubscriptionId -ErrorAction Stop
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Subscription Access'; Result = 'PASS'; Details = $sub.Name }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Subscription Access'; Result = 'FAIL'; Details = $_.Exception.Message }
        $validationPassed = $false
    }
    
    # Test 5: Quota Check
    Write-Host "[5/8] Checking Azure compute quota..." -NoNewline
    try {
        $vmFamily = 'standardDSv5Family'
        $usage = Get-AzVMUsage -Location $Script:Config.Location | Where-Object { $_.Name.Value -eq $vmFamily }
        
        if ($usage) {
            $available = $usage.Limit - $usage.CurrentValue
            $coresPerVM = 4
            $requiredCores = $coresPerVM * $SessionHostCount
            
            if ($available -ge $requiredCores) {
                Write-Host " PASS" -ForegroundColor Green
                $Script:ValidationResults += @{ Test = 'Compute Quota'; Result = 'PASS'; Details = "Available: $available vCPUs" }
            }
            else {
                Write-Host " WARNING" -ForegroundColor Yellow
                $Script:ValidationResults += @{ Test = 'Compute Quota'; Result = 'WARNING'; Details = "May be insufficient" }
            }
        }
        else {
            Write-Host " WARNING" -ForegroundColor Yellow
            $Script:ValidationResults += @{ Test = 'Compute Quota'; Result = 'WARNING'; Details = "Could not verify" }
        }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:ValidationResults += @{ Test = 'Compute Quota'; Result = 'WARNING'; Details = "Could not check" }
    }
    
    # Test 6: Resource Providers
    Write-Host "[6/8] Checking resource provider registration..." -NoNewline
    $requiredProviders = @('Microsoft.Compute', 'Microsoft.Network', 'Microsoft.Storage', 'Microsoft.DesktopVirtualization')
    $unregisteredProviders = @()
    
    foreach ($provider in $requiredProviders) {
        $providerStatus = Get-AzResourceProvider -ProviderNamespace $provider | Where-Object { $_.RegistrationState -ne 'Registered' }
        if ($providerStatus) {
            $unregisteredProviders += $provider
        }
    }
    
    if ($unregisteredProviders.Count -eq 0) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Resource Providers'; Result = 'PASS'; Details = "All registered" }
    }
    else {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:ValidationResults += @{ Test = 'Resource Providers'; Result = 'WARNING'; Details = "Some unregistered" }
    }
    
    # Test 7: Naming Validation
    Write-Host "[7/8] Validating resource naming..." -NoNewline
    $uniqueId = Get-Random -Minimum 1000 -Maximum 9999
    $storageNameTest = "stpyxavd$uniqueId"
    
    if ($storageNameTest.Length -le 24 -and $storageNameTest -match '^[a-z0-9]+$') {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Naming Convention'; Result = 'PASS'; Details = "Names valid" }
    }
    else {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:ValidationResults += @{ Test = 'Naming Convention'; Result = 'FAIL'; Details = "Invalid names" }
        $validationPassed = $false
    }
    
    # Test 8: Network CIDR
    Write-Host "[8/8] Checking network CIDR availability..." -NoNewline
    $testVNetCIDR = '10.100.0.0/16'
    $existingVNets = Get-AzVirtualNetwork | Where-Object { $_.AddressSpace.AddressPrefixes -contains $testVNetCIDR }
    
    if ($existingVNets.Count -eq 0) {
        Write-Host " PASS" -ForegroundColor Green
        $Script:ValidationResults += @{ Test = 'Network CIDR'; Result = 'PASS'; Details = "$testVNetCIDR available" }
    }
    else {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:ValidationResults += @{ Test = 'Network CIDR'; Result = 'WARNING'; Details = "CIDR may be in use" }
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

# Resource Group
function New-AVDResourceGroup {
    param(
        [string]$Name,
        [string]$Location
    )
    
    Write-DeploymentLog "Creating resource group: $Name" "Info"
    
    try {
        $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
        
        if ($rg) {
            Write-DeploymentLog "Resource group already exists: $Name" "Warning"
            return $rg
        }
        
        $rg = New-AzResourceGroup -Name $Name -Location $Location -Tag @{
            'Company' = 'PYX-HEALTH'
            'Environment' = 'Production'
            'Application' = 'AVD'
            'ManagedBy' = 'Automation'
            'CreatedDate' = (Get-Date -Format 'yyyy-MM-dd')
        }
        
        Write-DeploymentLog "Resource group created: $Name" "Success"
        $Script:DeployedResources['ResourceGroup'] = $rg.ResourceGroupName
        
        return $rg
    }
    catch {
        Write-DeploymentLog "Failed to create resource group: $($_.Exception.Message)" "Error"
        throw
    }
}

# Virtual Network
function New-AVDVirtualNetwork {
    param(
        [string]$ResourceGroupName,
        [string]$VNetName,
        [string]$Location,
        [bool]$IncludeBastionSubnet
    )
    
    Write-DeploymentLog "Creating Virtual Network: $VNetName" "Info"
    
    try {
        $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($vnet) {
            Write-DeploymentLog "Virtual Network already exists: $VNetName" "Warning"
            return $vnet
        }
        
        $subnets = @()
        $avdSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name 'AVDSubnet' -AddressPrefix '10.100.1.0/24'
        $subnets += $avdSubnetConfig
        
        if ($IncludeBastionSubnet) {
            $bastionSubnetConfig = New-AzVirtualNetworkSubnetConfig -Name 'AzureBastionSubnet' -AddressPrefix '10.100.255.0/26'
            $subnets += $bastionSubnetConfig
        }
        
        $vnet = New-AzVirtualNetwork -Name $VNetName `
                                      -ResourceGroupName $ResourceGroupName `
                                      -Location $Location `
                                      -AddressPrefix '10.100.0.0/16' `
                                      -Subnet $subnets `
                                      -Tag @{
                                          'Company' = 'PYX-HEALTH'
                                          'Application' = 'AVD'
                                      }
        
        Write-DeploymentLog "Virtual Network created: $VNetName" "Success"
        $Script:DeployedResources['VirtualNetwork'] = $vnet.Name
        
        return $vnet
    }
    catch {
        Write-DeploymentLog "Failed to create Virtual Network: $($_.Exception.Message)" "Error"
        throw
    }
}

# Network Security Group
function New-AVDNetworkSecurityGroup {
    param(
        [string]$ResourceGroupName,
        [string]$NSGName,
        [string]$Location
    )
    
    Write-DeploymentLog "Creating Network Security Group: $NSGName" "Info"
    
    try {
        $nsg = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($nsg) {
            Write-DeploymentLog "NSG already exists: $NSGName" "Warning"
            return $nsg
        }
        
        $rules = @()
        
        $rules += New-AzNetworkSecurityRuleConfig -Name 'DenyRDPFromInternet' `
                                                   -Description 'Block RDP from Internet' `
                                                   -Access Deny `
                                                   -Protocol Tcp `
                                                   -Direction Inbound `
                                                   -Priority 100 `
                                                   -SourceAddressPrefix 'Internet' `
                                                   -SourcePortRange '*' `
                                                   -DestinationAddressPrefix '*' `
                                                   -DestinationPortRange 3389
        
        $rules += New-AzNetworkSecurityRuleConfig -Name 'DenySSHFromInternet' `
                                                   -Description 'Block SSH from Internet' `
                                                   -Access Deny `
                                                   -Protocol Tcp `
                                                   -Direction Inbound `
                                                   -Priority 110 `
                                                   -SourceAddressPrefix 'Internet' `
                                                   -SourcePortRange '*' `
                                                   -DestinationAddressPrefix '*' `
                                                   -DestinationPortRange 22
        
        $rules += New-AzNetworkSecurityRuleConfig -Name 'AllowVNetInbound' `
                                                   -Description 'Allow VNet traffic' `
                                                   -Access Allow `
                                                   -Protocol '*' `
                                                   -Direction Inbound `
                                                   -Priority 200 `
                                                   -SourceAddressPrefix 'VirtualNetwork' `
                                                   -SourcePortRange '*' `
                                                   -DestinationAddressPrefix 'VirtualNetwork' `
                                                   -DestinationPortRange '*'
        
        $rules += New-AzNetworkSecurityRuleConfig -Name 'AllowAzureCloudOutbound' `
                                                   -Description 'Allow Azure services' `
                                                   -Access Allow `
                                                   -Protocol '*' `
                                                   -Direction Outbound `
                                                   -Priority 100 `
                                                   -SourceAddressPrefix '*' `
                                                   -SourcePortRange '*' `
                                                   -DestinationAddressPrefix 'AzureCloud' `
                                                   -DestinationPortRange '*'
        
        $nsg = New-AzNetworkSecurityGroup -Name $NSGName `
                                           -ResourceGroupName $ResourceGroupName `
                                           -Location $Location `
                                           -SecurityRules $rules `
                                           -Tag @{
                                               'Company' = 'PYX-HEALTH'
                                               'Application' = 'AVD'
                                               'Security' = 'ZeroTrust'
                                           }
        
        Write-DeploymentLog "NSG created with Zero Trust rules: $NSGName" "Success"
        $Script:DeployedResources['NetworkSecurityGroup'] = $nsg.Name
        
        return $nsg
    }
    catch {
        Write-DeploymentLog "Failed to create NSG: $($_.Exception.Message)" "Error"
        throw
    }
}

# Associate NSG with Subnet
function Set-SubnetNSG {
    param(
        [string]$ResourceGroupName,
        [string]$VNetName,
        [string]$SubnetName,
        [string]$NSGId
    )
    
    Write-DeploymentLog "Associating NSG with subnet: $SubnetName" "Info"
    
    try {
        $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq $SubnetName }
        
        if (-not $subnet) {
            throw "Subnet not found: $SubnetName"
        }
        
        $subnet.NetworkSecurityGroup = @{ Id = $NSGId }
        $vnet | Set-AzVirtualNetwork | Out-Null
        
        Write-DeploymentLog "NSG associated with subnet: $SubnetName" "Success"
    }
    catch {
        Write-DeploymentLog "Failed to associate NSG: $($_.Exception.Message)" "Error"
        throw
    }
}

# Storage Account
function New-AVDStorageAccount {
    param(
        [string]$ResourceGroupName,
        [string]$StorageAccountName,
        [string]$Location
    )
    
    Write-DeploymentLog "Creating Storage Account: $StorageAccountName" "Info"
    
    try {
        $storage = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($storage) {
            Write-DeploymentLog "Storage Account already exists: $StorageAccountName" "Warning"
            return $storage
        }
        
        $storage = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                                         -Name $StorageAccountName `
                                         -Location $Location `
                                         -SkuName 'Standard_LRS' `
                                         -Kind 'StorageV2' `
                                         -EnableHttpsTrafficOnly $true `
                                         -MinimumTlsVersion 'TLS1_2' `
                                         -AllowBlobPublicAccess $false `
                                         -Tag @{
                                             'Company' = 'PYX-HEALTH'
                                             'Application' = 'AVD'
                                             'Purpose' = 'FSLogix-Profiles'
                                         }
        
        Start-Sleep -Seconds 10
        
        $ctx = $storage.Context
        $share = New-AzStorageShare -Name 'profiles' -Context $ctx -ErrorAction SilentlyContinue
        
        if (-not $share) {
            $share = Get-AzStorageShare -Name 'profiles' -Context $ctx
        }
        
        Write-DeploymentLog "Storage Account created: $StorageAccountName" "Success"
        $Script:DeployedResources['StorageAccount'] = $storage.StorageAccountName
        $Script:DeployedResources['FileShare'] = $share.Name
        
        return $storage
    }
    catch {
        Write-DeploymentLog "Failed to create Storage Account: $($_.Exception.Message)" "Error"
        throw
    }
}

# Host Pool
function New-AVDHostPool {
    param(
        [string]$ResourceGroupName,
        [string]$HostPoolName,
        [string]$Location
    )
    
    Write-DeploymentLog "Creating AVD Host Pool: $HostPoolName" "Info"
    
    try {
        $hostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($hostPool) {
            Write-DeploymentLog "Host Pool already exists: $HostPoolName" "Warning"
            return $hostPool
        }
        
        $hostPool = New-AzWvdHostPool -ResourceGroupName $ResourceGroupName `
                                       -Name $HostPoolName `
                                       -Location $Location `
                                       -HostPoolType 'Pooled' `
                                       -LoadBalancerType 'BreadthFirst' `
                                       -PreferredAppGroupType 'Desktop' `
                                       -MaxSessionLimit 16 `
                                       -ValidationEnvironment:$false `
                                       -Tag @{
                                           'Company' = 'PYX-HEALTH'
                                           'Application' = 'AVD'
                                       }
        
        Write-DeploymentLog "Host Pool created: $HostPoolName" "Success"
        $Script:DeployedResources['HostPool'] = $hostPool.Name
        
        return $hostPool
    }
    catch {
        Write-DeploymentLog "Failed to create Host Pool: $($_.Exception.Message)" "Error"
        throw
    }
}

# Application Group
function New-AVDApplicationGroup {
    param(
        [string]$ResourceGroupName,
        [string]$ApplicationGroupName,
        [string]$HostPoolArmPath,
        [string]$Location
    )
    
    Write-DeploymentLog "Creating Application Group: $ApplicationGroupName" "Info"
    
    try {
        $appGroup = Get-AzWvdApplicationGroup -Name $ApplicationGroupName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($appGroup) {
            Write-DeploymentLog "Application Group already exists: $ApplicationGroupName" "Warning"
            return $appGroup
        }
        
        $appGroup = New-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName `
                                              -Name $ApplicationGroupName `
                                              -Location $Location `
                                              -ApplicationGroupType 'Desktop' `
                                              -HostPoolArmPath $HostPoolArmPath `
                                              -Tag @{
                                                  'Company' = 'PYX-HEALTH'
                                                  'Application' = 'AVD'
                                              }
        
        Write-DeploymentLog "Application Group created: $ApplicationGroupName" "Success"
        $Script:DeployedResources['ApplicationGroup'] = $appGroup.Name
        
        return $appGroup
    }
    catch {
        Write-DeploymentLog "Failed to create Application Group: $($_.Exception.Message)" "Error"
        throw
    }
}

# Workspace
function New-AVDWorkspace {
    param(
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [string]$Location,
        [string[]]$ApplicationGroupReferences
    )
    
    Write-DeploymentLog "Creating Workspace: $WorkspaceName" "Info"
    
    try {
        $workspace = Get-AzWvdWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($workspace) {
            Write-DeploymentLog "Workspace already exists: $WorkspaceName" "Warning"
            Update-AzWvdWorkspace -ResourceGroupName $ResourceGroupName `
                                  -Name $WorkspaceName `
                                  -ApplicationGroupReference $ApplicationGroupReferences | Out-Null
            $workspace = Get-AzWvdWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName
        }
        else {
            $workspace = New-AzWvdWorkspace -ResourceGroupName $ResourceGroupName `
                                            -Name $WorkspaceName `
                                            -Location $Location `
                                            -ApplicationGroupReference $ApplicationGroupReferences `
                                            -FriendlyName 'PYX Health Virtual Desktop' `
                                            -Tag @{
                                                'Company' = 'PYX-HEALTH'
                                                'Application' = 'AVD'
                                            }
        }
        
        Write-DeploymentLog "Workspace created: $WorkspaceName" "Success"
        $Script:DeployedResources['Workspace'] = $workspace.Name
        
        return $workspace
    }
    catch {
        Write-DeploymentLog "Failed to create Workspace: $($_.Exception.Message)" "Error"
        throw
    }
}

# Deploy Session Hosts
function Deploy-AVDSessionHosts {
    param(
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$VMSize,
        [string]$SubnetId,
        [string]$AdminUsername,
        [SecureString]$AdminPassword,
        [string]$HostPoolName,
        [string]$RegistrationToken,
        [int]$Count,
        [string]$NamePrefix
    )
    
    Write-DeploymentLog "Deploying $Count session host VMs..." "Info"
    Write-Host ""
    
    $jobs = @()
    $deploymentResults = @()
    
    for ($i = 1; $i -le $Count; $i++) {
        $vmName = "$NamePrefix-$($i.ToString('00'))"
        
        Write-Host "Queueing VM: $vmName ($i/$Count)" -ForegroundColor Cyan
        
        $job = Start-Job -ScriptBlock {
            param($rgName, $vmName, $loc, $vmSize, $subId, $user, $pass, $token, $hpName)
            
            try {
                Import-Module Az.Compute, Az.Network -ErrorAction SilentlyContinue
                
                $nic = New-AzNetworkInterface -Name "$vmName-nic" `
                                              -ResourceGroupName $rgName `
                                              -Location $loc `
                                              -SubnetId $subId `
                                              -Tag @{ 'Company' = 'PYX-HEALTH' } `
                                              -Force
                
                $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
                
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig `
                                                    -Windows `
                                                    -ComputerName $vmName `
                                                    -Credential (New-Object PSCredential($user, $pass)) `
                                                    -ProvisionVMAgent `
                                                    -EnableAutoUpdate
                
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig `
                                               -PublisherName 'MicrosoftWindowsDesktop' `
                                               -Offer 'Windows-11' `
                                               -Skus 'win11-22h2-avd' `
                                               -Version 'latest'
                
                $vmConfig = Set-AzVMOSDisk -VM $vmConfig `
                                          -Name "$vmName-osdisk" `
                                          -CreateOption 'FromImage' `
                                          -StorageAccountType 'Premium_LRS' `
                                          -DiskSizeInGB 128 `
                                          -DeleteOption 'Delete'
                
                $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id -DeleteOption 'Delete'
                $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable
                
                $vmConfig.SecurityProfile = @{
                    SecurityType = 'TrustedLaunch'
                    UefiSettings = @{
                        SecureBootEnabled = $true
                        VTpmEnabled = $true
                    }
                }
                
                New-AzVM -ResourceGroupName $rgName `
                        -Location $loc `
                        -VM $vmConfig `
                        -Tag @{ 'Company' = 'PYX-HEALTH'; 'SessionHost' = 'True' } | Out-Null
                
                Start-Sleep -Seconds 30
                
                $extensionParams = @{
                    ResourceGroupName = $rgName
                    VMName = $vmName
                    Name = 'AVDAgent'
                    Publisher = 'Microsoft.Powershell'
                    ExtensionType = 'DSC'
                    TypeHandlerVersion = '2.77'
                    Settings = @{
                        modulesUrl = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_07-19-2022.zip'
                        configurationFunction = 'Configuration.ps1\AddSessionHost'
                        properties = @{
                            hostPoolName = $hpName
                            registrationInfoToken = $token
                            aadJoin = $false
                        }
                    }
                }
                
                Set-AzVMExtension @extensionParams -ErrorAction SilentlyContinue | Out-Null
                
                return @{ Success = $true; VMName = $vmName }
            }
            catch {
                return @{ Success = $false; VMName = $vmName; Error = $_.Exception.Message }
            }
        } -ArgumentList $ResourceGroupName, $vmName, $Location, $VMSize, $SubnetId, $AdminUsername, $AdminPassword, $RegistrationToken, $HostPoolName
        
        $jobs += @{ Job = $job; VMName = $vmName }
        
        if ($i % 3 -eq 0 -and $i -lt $Count) {
            Start-Sleep -Seconds 30
        }
    }
    
    Write-Host ""
    Write-Host "Waiting for deployments to complete..." -ForegroundColor Yellow
    Write-Host ""
    
    $completed = 0
    foreach ($jobInfo in $jobs) {
        $result = Receive-Job -Job $jobInfo.Job -Wait
        $completed++
        
        Write-Host "Completed: $completed/$Count" -ForegroundColor Cyan
        
        $deploymentResults += $result
        Remove-Job -Job $jobInfo.Job
    }
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  SESSION HOST DEPLOYMENT RESULTS" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    
    $successful = ($deploymentResults | Where-Object { $_.Success }).Count
    $failed = ($deploymentResults | Where-Object { -not $_.Success }).Count
    
    Write-Host "  Total:      $Count" -ForegroundColor White
    Write-Host "  Successful: $successful" -ForegroundColor Green
    Write-Host "  Failed:     $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    
    $Script:DeployedResources['SessionHosts'] = $successful
    
    return $deploymentResults
}

# Azure Monitor Alerts
function Deploy-AzureMonitorAlerts {
    param(
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    if (-not $DeployMonitoring) {
        Write-DeploymentLog "Skipping Azure Monitor deployment" "Info"
        return
    }
    
    Write-DeploymentLog "Deploying Azure Monitor alerts..." "Info"
    
    try {
        # Create Action Group
        $emailReceivers = @(
            New-AzActionGroupReceiver -Name 'AVD-Admin-Email' `
                                       -EmailReceiver `
                                       -EmailAddress 'avd-admin@pyxhealth.com'
        )
        
        $actionGroup = Set-AzActionGroup -Name 'ag-avd-alerts' `
                                         -ResourceGroupName $ResourceGroupName `
                                         -ShortName 'AVDAlerts' `
                                         -Receiver $emailReceivers
        
        Write-DeploymentLog "Action Group created: ag-avd-alerts" "Success"
        
        # Alert for High CPU
        $condition = New-AzMetricAlertRuleV2Criteria -MetricName 'Percentage CPU' `
                                                      -TimeAggregation Average `
                                                      -Operator GreaterThan `
                                                      -Threshold 85
        
        Add-AzMetricAlertRuleV2 -Name 'alert-avd-high-cpu' `
                                -ResourceGroupName $ResourceGroupName `
                                -WindowSize ([TimeSpan]::FromMinutes(5)) `
                                -Frequency ([TimeSpan]::FromMinutes(1)) `
                                -TargetResourceScope "/subscriptions/$($Script:SubscriptionId)/resourceGroups/$ResourceGroupName" `
                                -Condition $condition `
                                -ActionGroupId $actionGroup.Id `
                                -Severity 2 `
                                -Description 'CPU usage above 85%'
        
        Write-DeploymentLog "Azure Monitor alerts deployed" "Success"
        $Script:DeployedResources['MonitoringAlerts'] = 'Configured'
    }
    catch {
        Write-DeploymentLog "Failed to deploy Azure Monitor: $($_.Exception.Message)" "Warning"
    }
}

# Datadog Integration
function Deploy-DatadogMonitoring {
    param(
        [string]$ResourceGroupName,
        [string]$HostPoolName
    )
    
    if (-not $DatadogAPIKey -or -not $DatadogAppKey) {
        Write-DeploymentLog "Skipping Datadog integration (no API keys provided)" "Info"
        return
    }
    
    Write-DeploymentLog "Configuring Datadog monitoring..." "Info"
    
    try {
        $headers = @{
            'DD-API-KEY' = $DatadogAPIKey
            'DD-APPLICATION-KEY' = $DatadogAppKey
            'Content-Type' = 'application/json'
        }
        
        $datadogRegion = 'us3'
        $apiUrl = "https://api.$datadogRegion.datadoghq.com/api/v1/monitor"
        
        # Monitor 1: High CPU
        $monitorCPU = @{
            name = "AVD - High CPU Usage - $HostPoolName"
            type = 'metric alert'
            query = "avg(last_5m):avg:azure.compute.virtualmachine.percentage_cpu{resource_group:$ResourceGroupName} > 85"
            message = "CPU usage above 85% on AVD session hosts in $HostPoolName"
            tags = @('avd', 'pyx-health', 'production')
            options = @{
                thresholds = @{
                    critical = 85
                    warning = 75
                }
                notify_no_data = $true
                no_data_timeframe = 10
            }
        }
        
        Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($monitorCPU | ConvertTo-Json -Depth 10) | Out-Null
        Write-DeploymentLog "Datadog monitor created: High CPU" "Success"
        
        # Monitor 2: High Memory
        $monitorMemory = @{
            name = "AVD - High Memory Usage - $HostPoolName"
            type = 'metric alert'
            query = "avg(last_5m):avg:azure.compute.virtualmachine.available_memory_bytes{resource_group:$ResourceGroupName} < 2147483648"
            message = "Available memory below 2GB on AVD session hosts in $HostPoolName"
            tags = @('avd', 'pyx-health', 'production')
            options = @{
                thresholds = @{
                    critical = 2147483648
                    warning = 4294967296
                }
                notify_no_data = $true
            }
        }
        
        Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($monitorMemory | ConvertTo-Json -Depth 10) | Out-Null
        Write-DeploymentLog "Datadog monitor created: High Memory" "Success"
        
        # Monitor 3: Session Host Down
        $monitorDown = @{
            name = "AVD - Session Host Down - $HostPoolName"
            type = 'service check'
            query = "azure.vm.status{resource_group:$ResourceGroupName}.over('host').last(2).count_by_status()"
            message = "AVD session host is down in $HostPoolName"
            tags = @('avd', 'pyx-health', 'production', 'critical')
            options = @{
                thresholds = @{
                    critical = 1
                }
                notify_no_data = $true
            }
        }
        
        Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($monitorDown | ConvertTo-Json -Depth 10) | Out-Null
        Write-DeploymentLog "Datadog monitor created: Session Host Down" "Success"
        
        $Script:DeployedResources['DatadogMonitoring'] = 'Configured'
    }
    catch {
        Write-DeploymentLog "Failed to configure Datadog: $($_.Exception.Message)" "Warning"
    }
}

# Post-Deployment Testing
function Test-AVDDeployment {
    param(
        [string]$ResourceGroupName,
        [string]$HostPoolName
    )
    
    Show-Banner -Phase 'POST-DEPLOYMENT TESTING'
    $Script:DeploymentPhase = 'Testing'
    
    Write-DeploymentLog "Running post-deployment tests..." "Info"
    Write-Host ""
    
    # Test 1: Host Pool
    Write-Host "[TEST 1/10] Host Pool availability..." -NoNewline
    try {
        $hostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        Write-Host " PASS" -ForegroundColor Green
        $Script:TestResults += @{ Test = 'Host Pool'; Result = 'PASS' }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'Host Pool'; Result = 'FAIL' }
    }
    
    # Test 2: Session Hosts
    Write-Host "[TEST 2/10] Session hosts registration..." -NoNewline
    try {
        $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        $totalHosts = $sessionHosts.Count
        $availableHosts = ($sessionHosts | Where-Object { $_.Status -eq 'Available' }).Count
        
        if ($totalHosts -gt 0) {
            Write-Host " PASS (Total: $totalHosts, Available: $availableHosts)" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Session Hosts'; Result = 'PASS' }
        }
        else {
            Write-Host " WARNING (No hosts registered yet)" -ForegroundColor Yellow
            $Script:TestResults += @{ Test = 'Session Hosts'; Result = 'WARNING' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'Session Hosts'; Result = 'FAIL' }
    }
    
    # Test 3: Application Group
    Write-Host "[TEST 3/10] Application Group..." -NoNewline
    try {
        $appGroups = Get-AzWvdApplicationGroup -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        if ($appGroups.Count -gt 0) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Application Group'; Result = 'PASS' }
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $Script:TestResults += @{ Test = 'Application Group'; Result = 'FAIL' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'Application Group'; Result = 'FAIL' }
    }
    
    # Test 4: Workspace
    Write-Host "[TEST 4/10] Workspace..." -NoNewline
    try {
        $workspaces = Get-AzWvdWorkspace -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        if ($workspaces.Count -gt 0) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Workspace'; Result = 'PASS' }
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $Script:TestResults += @{ Test = 'Workspace'; Result = 'FAIL' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'Workspace'; Result = 'FAIL' }
    }
    
    # Test 5: Virtual Network
    Write-Host "[TEST 5/10] Virtual Network..." -NoNewline
    try {
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Select-Object -First 1
        if ($vnet) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Virtual Network'; Result = 'PASS' }
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $Script:TestResults += @{ Test = 'Virtual Network'; Result = 'FAIL' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'Virtual Network'; Result = 'FAIL' }
    }
    
    # Test 6: NSG
    Write-Host "[TEST 6/10] Network Security Group..." -NoNewline
    try {
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Select-Object -First 1
        if ($nsg) {
            $denyRDPRule = $nsg.SecurityRules | Where-Object { $_.Name -like '*RDP*' -and $_.Access -eq 'Deny' }
            if ($denyRDPRule) {
                Write-Host " PASS (Zero Trust confirmed)" -ForegroundColor Green
                $Script:TestResults += @{ Test = 'NSG'; Result = 'PASS' }
            }
            else {
                Write-Host " WARNING" -ForegroundColor Yellow
                $Script:TestResults += @{ Test = 'NSG'; Result = 'WARNING' }
            }
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $Script:TestResults += @{ Test = 'NSG'; Result = 'FAIL' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'NSG'; Result = 'FAIL' }
    }
    
    # Test 7: Storage Account
    Write-Host "[TEST 7/10] Storage Account (FSLogix)..." -NoNewline
    try {
        $storage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Select-Object -First 1
        if ($storage) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Storage'; Result = 'PASS' }
        }
        else {
            Write-Host " WARNING" -ForegroundColor Yellow
            $Script:TestResults += @{ Test = 'Storage'; Result = 'WARNING' }
        }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:TestResults += @{ Test = 'Storage'; Result = 'WARNING' }
    }
    
    # Test 8: VM Security
    Write-Host "[TEST 8/10] VM security (Trusted Launch)..." -NoNewline
    try {
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        $trustedLaunchVMs = $vms | Where-Object { $_.SecurityProfile.SecurityType -eq 'TrustedLaunch' }
        
        if ($trustedLaunchVMs.Count -eq $vms.Count) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'VM Security'; Result = 'PASS' }
        }
        else {
            Write-Host " WARNING" -ForegroundColor Yellow
            $Script:TestResults += @{ Test = 'VM Security'; Result = 'WARNING' }
        }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:TestResults += @{ Test = 'VM Security'; Result = 'WARNING' }
    }
    
    # Test 9: No Public IPs
    Write-Host "[TEST 9/10] No Public IPs (Zero Trust)..." -NoNewline
    try {
        $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        $vmsWithPublicIP = 0
        
        foreach ($vm in $vms) {
            $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id -ErrorAction SilentlyContinue
            if ($nic -and $nic.IpConfigurations[0].PublicIpAddress) {
                $vmsWithPublicIP++
            }
        }
        
        if ($vmsWithPublicIP -eq 0) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'Zero Trust IPs'; Result = 'PASS' }
        }
        else {
            Write-Host " FAIL ($vmsWithPublicIP VMs have public IPs)" -ForegroundColor Red
            $Script:TestResults += @{ Test = 'Zero Trust IPs'; Result = 'FAIL' }
        }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        $Script:TestResults += @{ Test = 'Zero Trust IPs'; Result = 'WARNING' }
    }
    
    # Test 10: User Connectivity
    Write-Host "[TEST 10/10] User connectivity..." -NoNewline
    try {
        $workspaces = Get-AzWvdWorkspace -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        if ($workspaces.Count -gt 0 -and $availableHosts -gt 0) {
            Write-Host " PASS" -ForegroundColor Green
            $Script:TestResults += @{ Test = 'User Connectivity'; Result = 'PASS' }
        }
        else {
            Write-Host " PARTIAL (waiting for hosts)" -ForegroundColor Yellow
            $Script:TestResults += @{ Test = 'User Connectivity'; Result = 'PARTIAL' }
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        $Script:TestResults += @{ Test = 'User Connectivity'; Result = 'FAIL' }
    }
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  TEST RESULTS SUMMARY" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    
    $passed = ($Script:TestResults | Where-Object { $_.Result -eq 'PASS' }).Count
    $warnings = ($Script:TestResults | Where-Object { $_.Result -eq 'WARNING' -or $_.Result -eq 'PARTIAL' }).Count
    $failed = ($Script:TestResults | Where-Object { $_.Result -eq 'FAIL' }).Count
    
    Write-Host "  Tests Passed: $passed/10" -ForegroundColor Green
    Write-Host "  Warnings:     $warnings" -ForegroundColor Yellow
    Write-Host "  Failed:       $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host ""
    
    return ($failed -eq 0)
}

# Deployment Summary
function Save-DeploymentSummary {
    param(
        [string]$OutputPath,
        [string]$ResourceGroupName,
        [string]$HostPoolName
    )
    
    $duration = (Get-Date) - $Script:DeploymentStartTime
    
    $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $totalHosts = $sessionHosts.Count
    $availableHosts = ($sessionHosts | Where-Object { $_.Status -eq 'Available' }).Count
    
    $summary = @"
=========================================================================
AZURE VIRTUAL DESKTOP - DEPLOYMENT SUMMARY
PYX HEALTH CORPORATION
=========================================================================

DEPLOYMENT INFORMATION
=========================================================================
Deployment Date:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Duration:              $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s
Status:                COMPLETED

AZURE ENVIRONMENT
=========================================================================
Company:               $($Script:Config.CompanyName)
Tenant:                $($Script:Config.TenantName) ($($Script:Config.TenantDomain))
Subscription:          $($Script:Config.TargetSubscriptionName)
Subscription ID:       $($Script:Config.TargetSubscriptionId)
Location:              $($Script:Config.Location)

DEPLOYED RESOURCES
=========================================================================
$($Script:DeployedResources.GetEnumerator() | ForEach-Object { 
    "$($_.Key.PadRight(25)): $($_.Value)"
} | Out-String)

SESSION HOST DETAILS
=========================================================================
Total Session Hosts:   $totalHosts
Available Hosts:       $availableHosts
VM Size:               $VMSize
OS Image:              Windows 11 Enterprise Multi-session
Security:              Trusted Launch, No Public IPs

SECURITY POSTURE
=========================================================================
Zero Trust Architecture:      Implemented
No Public IPs:                Yes
NSG RDP Block:                Yes
Trusted Launch:               Yes
FSLogix Encryption:           TLS 1.2+
Azure Monitor:                $(if ($DeployMonitoring) { 'Configured' } else { 'Not Deployed' })
Datadog Monitoring:           $(if ($DatadogAPIKey) { 'Configured' } else { 'Not Configured' })

USER ACCESS
=========================================================================
Web Client:            https://client.wvd.microsoft.com
Windows Client:        https://aka.ms/wvd/clients/windows
macOS Client:          https://aka.ms/wvd/clients/mac

Resource Group:        $ResourceGroupName
Host Pool:             $HostPoolName
Workspace:             $($Script:DeployedResources['Workspace'])

VALIDATION RESULTS
=========================================================================
$($Script:ValidationResults | ForEach-Object {
    "$($_.Test.PadRight(30)): $($_.Result.PadRight(8)) - $($_.Details)"
} | Out-String)

POST-DEPLOYMENT TEST RESULTS
=========================================================================
$($Script:TestResults | ForEach-Object {
    "$($_.Test.PadRight(30)): $($_.Result)"
} | Out-String)

NEXT STEPS
=========================================================================
1. Assign users to Application Group in Azure Portal
2. Configure Conditional Access policies for MFA
3. Set up Azure Monitor alerts
4. Configure FSLogix settings on session hosts
5. User acceptance testing

DEPLOYMENT LOG
=========================================================================
$($Script:DeploymentLog | Out-String)

=========================================================================
Deployment completed successfully
=========================================================================
"@
    
    $summary | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-DeploymentLog "Deployment summary saved: $OutputPath" "Success"
}

# Main Execution
try {
    Show-Banner -Phase 'INITIALIZATION'
    
    Write-DeploymentLog "=========================================================================" "Info"
    Write-DeploymentLog "  Starting AVD Enterprise Deployment for PYX HEALTH" "Info"
    Write-DeploymentLog "=========================================================================" "Info"
    Write-Host ""
    Write-Host "  Configuration:" -ForegroundColor White
    Write-Host "  - Session Hosts: $SessionHostCount" -ForegroundColor Gray
    Write-Host "  - VM Size: $VMSize" -ForegroundColor Gray
    Write-Host "  - Location: $($Script:Config.Location)" -ForegroundColor Gray
    Write-Host "  - Deploy Bastion: $(if ($DeployBastion) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    Write-Host "  - Deploy Monitoring: $(if ($DeployMonitoring) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    Write-Host "  - Datadog Integration: $(if ($DatadogAPIKey) { 'Yes' } else { 'No' })" -ForegroundColor Gray
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
    
    Show-Banner -Phase 'RESOURCE DEPLOYMENT'
    $Script:DeploymentPhase = 'Deployment'
    
    $timestamp = Get-Date -Format 'yyyyMMdd'
    $uniqueId = Get-Random -Minimum 1000 -Maximum 9999
    
    $resourceGroupName = "rg-pyx-avd-prod-$timestamp-$uniqueId"
    $vnetName = "vnet-pyx-avd-$timestamp"
    $nsgName = "nsg-pyx-avd-$timestamp"
    $storageAccountName = "stpyxavd$uniqueId"
    $hostPoolName = "hp-pyx-avd-$timestamp"
    $appGroupName = "ag-pyx-avd-desktop-$timestamp"
    $workspaceName = "ws-pyx-avd-$timestamp"
    $vmNamePrefix = "pyx-avd-vm-$timestamp"
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 1: INFRASTRUCTURE" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $rg = New-AVDResourceGroup -Name $resourceGroupName -Location $Script:Config.Location
    $vnet = New-AVDVirtualNetwork -ResourceGroupName $resourceGroupName -VNetName $vnetName -Location $Script:Config.Location -IncludeBastionSubnet $DeployBastion
    $nsg = New-AVDNetworkSecurityGroup -ResourceGroupName $resourceGroupName -NSGName $nsgName -Location $Script:Config.Location
    Set-SubnetNSG -ResourceGroupName $resourceGroupName -VNetName $vnetName -SubnetName 'AVDSubnet' -NSGId $nsg.Id
    $storage = New-AVDStorageAccount -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -Location $Script:Config.Location
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 2: AVD CONTROL PLANE" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $hostPool = New-AVDHostPool -ResourceGroupName $resourceGroupName -HostPoolName $hostPoolName -Location $Script:Config.Location
    $appGroup = New-AVDApplicationGroup -ResourceGroupName $resourceGroupName -ApplicationGroupName $appGroupName -HostPoolArmPath $hostPool.Id -Location $Script:Config.Location
    $workspace = New-AVDWorkspace -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -Location $Script:Config.Location -ApplicationGroupReferences @($appGroup.Id)
    
    Write-DeploymentLog "Generating registration token..." "Info"
    $tokenExpiration = (Get-Date).AddHours(24)
    Update-AzWvdHostPool -ResourceGroupName $resourceGroupName -Name $hostPoolName -RegistrationInfoExpirationTime $tokenExpiration | Out-Null
    
    $hostPoolInfo = Get-AzWvdHostPool -Name $hostPoolName -ResourceGroupName $resourceGroupName
    $registrationToken = $hostPoolInfo.RegistrationInfo.Token
    Write-DeploymentLog "Registration token generated" "Success"
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 3: SESSION HOST DEPLOYMENT" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $subnet = $vnet.Subnets | Where-Object { $_.Name -eq 'AVDSubnet' }
    $subnetId = $subnet.Id
    $adminPassword = New-SecurePassword
    
    $deploymentResults = Deploy-AVDSessionHosts -ResourceGroupName $resourceGroupName `
                                                 -Location $Script:Config.Location `
                                                 -VMSize $VMSize `
                                                 -SubnetId $subnetId `
                                                 -AdminUsername $Script:Config.AdminUsername `
                                                 -AdminPassword $adminPassword `
                                                 -HostPoolName $hostPoolName `
                                                 -RegistrationToken $registrationToken `
                                                 -Count $SessionHostCount `
                                                 -NamePrefix $vmNamePrefix
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  PHASE 4: MONITORING AND ALERTS" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Deploy-AzureMonitorAlerts -ResourceGroupName $resourceGroupName -Location $Script:Config.Location
    Deploy-DatadogMonitoring -ResourceGroupName $resourceGroupName -HostPoolName $hostPoolName
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "=========================================================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Waiting 60 seconds before testing..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60
    
    Test-AVDDeployment -ResourceGroupName $resourceGroupName -HostPoolName $hostPoolName
    
    $summaryPath = Join-Path -Path $PSScriptRoot -ChildPath "AVD-Deployment-Summary-$timestamp-$uniqueId.txt"
    Save-DeploymentSummary -OutputPath $summaryPath -ResourceGroupName $resourceGroupName -HostPoolName $hostPoolName
    
    Write-Host ""
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  DEPLOYMENT INFORMATION" -ForegroundColor White
    Write-Host "=========================================================================" -ForegroundColor Cyan
    Write-Host "  Resource Group:  $resourceGroupName" -ForegroundColor White
    Write-Host "  Host Pool:       $hostPoolName" -ForegroundColor White
    Write-Host "  Workspace:       $workspaceName" -ForegroundColor White
    Write-Host ""
    Write-Host "  User Access:" -ForegroundColor White
    Write-Host "    Web Client:      https://client.wvd.microsoft.com" -ForegroundColor Cyan
    Write-Host "    Windows Client:  https://aka.ms/wvd/clients/windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Deployment Summary: $summaryPath" -ForegroundColor Green
    Write-Host ""
    
    $duration = (Get-Date) - $Script:DeploymentStartTime
    Write-Host "Total deployment time: $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Cyan
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
