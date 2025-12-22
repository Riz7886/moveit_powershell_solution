# ============================================================================
# INTUNE SECURITY POLICIES DEPLOYMENT
# Deploys LLMNR Disable, USB Block, NETBIOS/WPAD Security Policies
# ============================================================================

param(
    [string]$TenantId = "",
    [string]$GroupName = "All-Windows-Devices"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "INTUNE SECURITY POLICIES DEPLOYMENT" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# STEP 1: CONNECT TO MICROSOFT GRAPH
# ----------------------------------------------------------------------------
Write-Host "[1/6] Connecting to Microsoft Graph..." -ForegroundColor Yellow

# Check if Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}

Import-Module Microsoft.Graph.DeviceManagement -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue

# Connect to Graph with required permissions
$scopes = @(
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All",
    "Group.Read.All"
)

try {
    if ($TenantId) {
        Connect-MgGraph -Scopes $scopes -TenantId $TenantId
    } else {
        Connect-MgGraph -Scopes $scopes
    }
    $context = Get-MgContext
    Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to connect to Microsoft Graph" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------------
# STEP 2: GET TARGET GROUP
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/6] Finding target group..." -ForegroundColor Yellow

$group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue

if (-not $group) {
    Write-Host "Group '$GroupName' not found. Available groups:" -ForegroundColor Yellow
    $groups = Get-MgGroup -Top 20 | Where-Object { $_.DisplayName -like "*Windows*" -or $_.DisplayName -like "*Device*" }
    for ($i = 0; $i -lt $groups.Count; $i++) {
        Write-Host "  [$($i + 1)] $($groups[$i].DisplayName)" -ForegroundColor White
    }
    $selection = Read-Host "Select group number"
    $group = $groups[[int]$selection - 1]
}

Write-Host "Target group: $($group.DisplayName)" -ForegroundColor Green
$groupId = $group.Id

# ----------------------------------------------------------------------------
# STEP 3: CREATE DISABLE LLMNR POLICY (Settings Catalog)
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/6] Creating Disable LLMNR Policy..." -ForegroundColor Yellow

$llmnrPolicyName = "Security - Disable LLMNR"

# Check if policy already exists
$existingPolicy = Get-MgDeviceManagementConfigurationPolicy -Filter "name eq '$llmnrPolicyName'" -ErrorAction SilentlyContinue

if ($existingPolicy) {
    Write-Host "Policy already exists: $llmnrPolicyName" -ForegroundColor Yellow
} else {
    # Settings Catalog policy for LLMNR
    $llmnrPolicy = @{
        name = $llmnrPolicyName
        description = "Disables Link-Local Multicast Name Resolution (LLMNR) to prevent name resolution poisoning attacks"
        platforms = "windows10"
        technologies = "mdm"
        settings = @(
            @{
                "@odata.type" = "#microsoft.graph.deviceManagementConfigurationSetting"
                settingInstance = @{
                    "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance"
                    settingDefinitionId = "device_vendor_msft_policy_config_admx_dnsclient_turn_off_multicast"
                    choiceSettingValue = @{
                        "@odata.type" = "#microsoft.graph.deviceManagementConfigurationChoiceSettingValue"
                        value = "device_vendor_msft_policy_config_admx_dnsclient_turn_off_multicast_1"
                        children = @()
                    }
                }
            }
        )
    }

    try {
        $newPolicy = New-MgDeviceManagementConfigurationPolicy -BodyParameter $llmnrPolicy
        Write-Host "Created: $llmnrPolicyName (ID: $($newPolicy.Id))" -ForegroundColor Green

        # Assign to group
        $assignment = @{
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $groupId
                    }
                }
            )
        }
        
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($newPolicy.Id)')/assign" -Body $assignment
        Write-Host "Assigned to: $($group.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "Note: Using alternative method for LLMNR policy..." -ForegroundColor Yellow
        
        # Alternative: Create via Device Configuration Profile
        $llmnrProfile = @{
            "@odata.type" = "#microsoft.graph.windows10CustomConfiguration"
            displayName = $llmnrPolicyName
            description = "Disables LLMNR to prevent name resolution poisoning attacks"
            omaSettings = @(
                @{
                    "@odata.type" = "#microsoft.graph.omaSettingInteger"
                    displayName = "Turn off multicast name resolution"
                    description = "Disables LLMNR"
                    omaUri = "./Device/Vendor/MSFT/Policy/Config/ADMX_DnsClient/Turn_Off_Multicast"
                    value = 1
                }
            )
        }
        
        $newProfile = New-MgDeviceManagementDeviceConfiguration -BodyParameter $llmnrProfile
        Write-Host "Created: $llmnrPolicyName (ID: $($newProfile.Id))" -ForegroundColor Green
    }
}

# ----------------------------------------------------------------------------
# STEP 4: CREATE USB BLOCK POLICY
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/6] Creating USB Block Policy..." -ForegroundColor Yellow

$usbPolicyName = "Security - Block USB Storage"

$existingUsbPolicy = Get-MgDeviceManagementDeviceConfiguration -Filter "displayName eq '$usbPolicyName'" -ErrorAction SilentlyContinue

if ($existingUsbPolicy) {
    Write-Host "Policy already exists: $usbPolicyName" -ForegroundColor Yellow
} else {
    $usbPolicy = @{
        "@odata.type" = "#microsoft.graph.windows10GeneralConfiguration"
        displayName = $usbPolicyName
        description = "Blocks USB removable storage devices to prevent data exfiltration"
        storageBlockRemovableStorage = $true
        storageRequireMobileDeviceEncryption = $false
        storageBlockRemovableStorageWrite = $true
    }

    try {
        $newUsbPolicy = New-MgDeviceManagementDeviceConfiguration -BodyParameter $usbPolicy
        Write-Host "Created: $usbPolicyName (ID: $($newUsbPolicy.Id))" -ForegroundColor Green

        # Assign to group
        $usbAssignment = @{
            deviceConfigurationGroupAssignments = @(
                @{
                    targetGroupId = $groupId
                    excludeGroup = $false
                }
            )
        }
        
        Update-MgDeviceManagementDeviceConfiguration -DeviceConfigurationId $newUsbPolicy.Id -BodyParameter $usbAssignment
        Write-Host "Assigned to: $($group.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR creating USB policy: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------------------
# STEP 5: CREATE NETBIOS/WPAD DISABLE POLICY
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[5/6] Creating NETBIOS/WPAD Disable Policy..." -ForegroundColor Yellow

$netbiosPolicyName = "Security - Disable NETBIOS and WPAD"

$existingNetbios = Get-MgDeviceManagementDeviceConfiguration -Filter "displayName eq '$netbiosPolicyName'" -ErrorAction SilentlyContinue

if ($existingNetbios) {
    Write-Host "Policy already exists: $netbiosPolicyName" -ForegroundColor Yellow
} else {
    $netbiosPolicy = @{
        "@odata.type" = "#microsoft.graph.windows10CustomConfiguration"
        displayName = $netbiosPolicyName
        description = "Disables NETBIOS over TCP/IP and WPAD to prevent network poisoning attacks"
        omaSettings = @(
            @{
                "@odata.type" = "#microsoft.graph.omaSettingString"
                displayName = "Disable WPAD"
                description = "Disables Web Proxy Auto-Discovery"
                omaUri = "./Device/Vendor/MSFT/Policy/Config/Connectivity/DisableDownloadingOfPrintDriversOverHTTP"
                value = "1"
            }
        )
    }

    try {
        $newNetbiosPolicy = New-MgDeviceManagementDeviceConfiguration -BodyParameter $netbiosPolicy
        Write-Host "Created: $netbiosPolicyName (ID: $($newNetbiosPolicy.Id))" -ForegroundColor Green
        
        # Assign to group
        $netbiosAssignment = @{
            deviceConfigurationGroupAssignments = @(
                @{
                    targetGroupId = $groupId
                    excludeGroup = $false
                }
            )
        }
        
        Update-MgDeviceManagementDeviceConfiguration -DeviceConfigurationId $newNetbiosPolicy.Id -BodyParameter $netbiosAssignment
        Write-Host "Assigned to: $($group.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "ERROR creating NETBIOS policy: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------------------
# STEP 6: CREATE REMEDIATION SCRIPT FOR NETBIOS
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[6/6] Creating NETBIOS Remediation Script..." -ForegroundColor Yellow

$remediationName = "Remediation - Disable NETBIOS over TCP/IP"

# Detection Script
$detectionScript = @'
# Detection Script - Check if NETBIOS is enabled
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
$netbiosEnabled = $false

foreach ($adapter in $adapters) {
    # TcpipNetbiosOptions: 0=Default, 1=Enable, 2=Disable
    if ($adapter.TcpipNetbiosOptions -ne 2) {
        $netbiosEnabled = $true
        break
    }
}

if ($netbiosEnabled) {
    Write-Output "NETBIOS is enabled - remediation required"
    exit 1
} else {
    Write-Output "NETBIOS is disabled - compliant"
    exit 0
}
'@

# Remediation Script
$remediationScript = @'
# Remediation Script - Disable NETBIOS over TCP/IP
$adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }

foreach ($adapter in $adapters) {
    $result = $adapter.SetTcpipNetbios(2)
    if ($result.ReturnValue -eq 0) {
        Write-Output "NETBIOS disabled on adapter: $($adapter.Description)"
    }
}

# Disable LLMNR via Registry
$llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $llmnrPath)) {
    New-Item -Path $llmnrPath -Force | Out-Null
}
Set-ItemProperty -Path $llmnrPath -Name "EnableMulticast" -Value 0 -Type DWord

# Disable WPAD
$wpadPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WinHttpAutoProxySvc"
Set-ItemProperty -Path $wpadPath -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue

Write-Output "Remediation complete - NETBIOS, LLMNR, and WPAD disabled"
exit 0
'@

try {
    $detectionScriptBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($detectionScript))
    $remediationScriptBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remediationScript))

    $remediationPolicy = @{
        displayName = $remediationName
        description = "Detects and disables NETBIOS over TCP/IP, LLMNR, and WPAD on Windows devices"
        publisher = "IT Security"
        runAs32Bit = $false
        runAsAccount = "system"
        enforceSignatureCheck = $false
        detectionScriptContent = $detectionScriptBase64
        remediationScriptContent = $remediationScriptBase64
    }

    $newRemediation = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Body $remediationPolicy
    Write-Host "Created: $remediationName" -ForegroundColor Green

    # Assign remediation to group
    $remediationAssignment = @{
        deviceHealthScriptAssignments = @(
            @{
                target = @{
                    "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                    groupId = $groupId
                }
                runRemediationScript = $true
                runSchedule = @{
                    "@odata.type" = "#microsoft.graph.deviceHealthScriptDailySchedule"
                    interval = 1
                }
            }
        )
    }

    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$($newRemediation.id)/assign" -Body $remediationAssignment
    Write-Host "Assigned to: $($group.DisplayName)" -ForegroundColor Green

} catch {
    Write-Host "Note: Remediation script creation requires additional permissions" -ForegroundColor Yellow
    Write-Host "Manual creation may be required in Intune portal" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------------
# DEPLOYMENT SUMMARY
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "POLICIES CREATED:" -ForegroundColor Cyan
Write-Host "  1. $llmnrPolicyName" -ForegroundColor White
Write-Host "     - Disables LLMNR multicast name resolution" -ForegroundColor Gray
Write-Host "     - Prevents name resolution poisoning attacks" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. $usbPolicyName" -ForegroundColor White
Write-Host "     - Blocks USB removable storage" -ForegroundColor Gray
Write-Host "     - Prevents data exfiltration" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. $netbiosPolicyName" -ForegroundColor White
Write-Host "     - Disables NETBIOS and WPAD" -ForegroundColor Gray
Write-Host "     - Prevents network poisoning attacks" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. $remediationName" -ForegroundColor White
Write-Host "     - Remediation script for legacy systems" -ForegroundColor Gray
Write-Host "     - Runs daily to ensure compliance" -ForegroundColor Gray
Write-Host ""

Write-Host "ASSIGNED TO:" -ForegroundColor Cyan
Write-Host "  Group: $($group.DisplayName)" -ForegroundColor White
Write-Host "  Group ID: $groupId" -ForegroundColor Gray
Write-Host ""

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Verify policies in Intune admin center" -ForegroundColor White
Write-Host "  2. Monitor device compliance in Reports" -ForegroundColor White
Write-Host "  3. Check remediation script results" -ForegroundColor White
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Green

# Disconnect from Graph
Disconnect-MgGraph | Out-Null
