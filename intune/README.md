# INTUNE SECURITY POLICIES DEPLOYMENT

This PowerShell script automates the deployment of security policies to your Intune-managed devices using the Microsoft Graph API. It creates and assigns the following security policies to prevent common network and USB-based vulnerabilities:

1. **Disable Link-Local Multicast Name Resolution (LLMNR)** - Mitigates poisoning attacks.
2. **Block USB Storage** - Prevents data exfiltration via removable storage devices.
3. **Disable NETBIOS and WPAD** - Avoids network poisoning attacks.

## Features

- Installs and loads required Microsoft Graph modules.
- Connects to Microsoft Graph and retrieves tenant information for validation.
- Lists available device groups for policy assignment.
- Creates three security policies and assigns them to the selected device group.
- Provides a deployment summary with next steps.

## Prerequisites

1. **Microsoft Graph PowerShell Modules:** The script installs the required modules if they aren't available locally:
   - `Microsoft.Graph.Authentication`
   - `Microsoft.Graph.DeviceManagement`
   - `Microsoft.Graph.Groups`
2. **Permissions:** The script requires the following Microsoft Graph API permissions:
   - `DeviceManagementConfiguration.ReadWrite.All`
   - `DeviceManagementManagedDevices.ReadWrite.All`
   - `Group.Read.All`
   - `Organization.Read.All`
3. **Administrator Role:** You must have sufficient permissions in your tenant to manage Intune configuration profiles.
4. **Intune Subscription:** Ensure your Microsoft 365 tenant has Intune enabled.

## How to Use

### Step 1: Run the Script

Run the PowerShell script in an elevated PowerShell session. The script will guide you through each step.

```powershell
.\IntuneSecurityDeployment.ps1
```

### Step 2: Follow the Steps

The script proceeds through the following steps:
1. **Install Required Modules:** Automatically checks and installs modules needed for the deployment.
2. **Connect to Microsoft Graph:** Authenticates and retrieves tenant details.
3. **Select Device Group:** Allows you to choose the target device group for policy assignment.
4. **Create and Assign Policies:** Deploys the three predefined security policies.

### Step 3: Verify Deployment

1. Open the [Intune Admin Center](https://intune.microsoft.com).
2. Navigate to **Devices > Configuration Profiles** to verify that policies are assigned and deploying.
3. Monitor policy status under **Reports > Device configuration**.

## Policies Created

### 1. Disable LLMNR
- **Policy Name:** `Security - Disable LLMNR`
- **Purpose:** Disables Link-Local Multicast Name Resolution to prevent poisoning attacks.

### 2. Block USB Storage
- **Policy Name:** `Security - Block USB Storage`
- **Purpose:** Blocks USB removable storage to prevent data exfiltration.

### 3. Disable NETBIOS and WPAD
- **Policy Name:** `Security - Disable NETBIOS and WPAD`
- **Purpose:** Disables NETBIOS and Web Proxy Auto-Discovery (WPAD) to defend against network poisoning attacks.

## Next Steps

1. Open [Intune Admin Center](https://intune.microsoft.com).
2. Verify the policies under **Devices > Configuration profiles**.
3. Check assignment and deployment statuses.
4. Monitor device compliance under **Reports > Device configuration**.

## Notes

- Ensure that you have the necessary permissions for managing Intune and Microsoft Graph.
- This script does not support running in restricted environments without access to PowerShell Gallery or Microsoft Graph.
- Disconnects from Microsoft Graph automatically after the script execution is complete.
