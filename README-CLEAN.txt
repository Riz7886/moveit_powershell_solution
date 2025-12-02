AZURE VIRTUAL DESKTOP DEPLOYMENT
PYX HEALTH CORPORATION

PROFESSIONAL DEPLOYMENT PACKAGE - CLEAN VERSION

================================================================================
FILES INCLUDED
================================================================================

1. Deploy-AVD-Clean.ps1
   Main deployment script (1,800+ lines)
   Deploys complete AVD infrastructure
   NO special characters, NO emojis, NO syntax errors

2. Deploy-AVD-Datadog-Monitoring.ps1
   Separate Datadog integration script
   Run AFTER Datadog agent is installed
   Creates 10 Datadog monitors

3. AVD-DEPLOYMENT-GUIDE-CLEAN.txt
   Complete deployment guide
   Step-by-step instructions
   Troubleshooting section

4. This README file
   Quick reference
   File descriptions
   Quick start guide

================================================================================
QUICK START
================================================================================

BASIC DEPLOYMENT (10 VMs, Azure Monitor only):
```
.\Deploy-AVD-Clean.ps1
```

DEPLOY WITH DATADOG (during deployment):
```
.\Deploy-AVD-Clean.ps1 -DatadogAPIKey "your-key" -DatadogAppKey "your-app-key"
```

DEPLOY WITH BASTION:
```
.\Deploy-AVD-Clean.ps1 -DeployBastion
```

DEPLOY MORE VMs:
```
.\Deploy-AVD-Clean.ps1 -SessionHostCount 20
```

================================================================================
DATADOG INTEGRATION OPTIONS
================================================================================

OPTION 1: During AVD Deployment
Include Datadog keys when running main script:
```
.\Deploy-AVD-Clean.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789"
```

OPTION 2: After AVD Deployment
Run separate Datadog script after deployment completes:
```
.\Deploy-AVD-Datadog-Monitoring.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789" -ResourceGroupName "rg-pyx-avd-prod-20251202-1234" -HostPoolName "hp-pyx-avd-20251202"
```

With email and Slack:
```
.\Deploy-AVD-Datadog-Monitoring.ps1 -DatadogAPIKey "abc123" -DatadogAppKey "xyz789" -ResourceGroupName "rg-pyx-avd-prod-20251202-1234" -HostPoolName "hp-pyx-avd-20251202" -AlertEmail "admin@pyxhealth.com" -SlackChannel "@slack-avd-alerts"
```

================================================================================
WHAT GETS DEPLOYED
================================================================================

INFRASTRUCTURE:
- Resource Group (with PYX Health tags)
- Virtual Network (10.100.0.0/16)
- AVD Subnet (10.100.1.0/24)
- Network Security Group (Zero Trust rules)
- Storage Account (FSLogix profiles)
- Optional: Azure Bastion subnet and resource

AVD COMPONENTS:
- Host Pool (Pooled, BreadthFirst load balancing)
- Desktop Application Group
- Workspace (user access point)
- 10 Windows 11 Session Hosts (scalable to 100)

SECURITY:
- Zero Trust architecture
- No public IPs on session hosts
- NSG denies RDP from Internet
- NSG denies SSH from Internet
- Trusted Launch VMs (Secure Boot + vTPM)
- FSLogix encrypted profiles (TLS 1.2+)

MONITORING (If Enabled):
- Azure Monitor action groups
- Alert rules (CPU, Memory, Disk, Availability)
- Datadog monitors (10 total, if keys provided)

================================================================================
TARGET ENVIRONMENT
================================================================================

Subscription Name:  sub-csc-avd
Subscription ID:    7edfb9f6-940e-47cd-af4b-04d0b6e6020f
Tenant Domain:      pyxhealth.com
Location:           East US

The script automatically connects to this subscription and deploys all resources there.

================================================================================
DEPLOYMENT TIME
================================================================================

Total Time: 30-40 minutes

Breakdown:
- Authentication: 2 minutes
- Pre-flight validation: 1 minute
- Infrastructure deployment: 10 minutes
- AVD control plane: 5 minutes
- Session host deployment: 20-25 minutes (parallel)
- Monitoring configuration: 2 minutes
- Post-deployment testing: 2 minutes

================================================================================
TESTS PERFORMED
================================================================================

PRE-FLIGHT VALIDATION (8 Tests):
1. PowerShell version check
2. Azure modules verification
3. Administrator privileges
4. Subscription access
5. Compute quota
6. Resource providers
7. Naming conventions
8. Network CIDR availability

POST-DEPLOYMENT TESTING (10 Tests):
1. Host Pool availability
2. Session hosts registration
3. Application Group configuration
4. Workspace configuration
5. Virtual Network validation
6. Network Security Group (Zero Trust)
7. Storage Account (FSLogix)
8. VM security (Trusted Launch)
9. No Public IPs verification
10. User connectivity test

ALL TESTS SHOW PASS/FAIL STATUS

================================================================================
DATADOG MONITORS CREATED (10 Total)
================================================================================

When Datadog integration is enabled, the following monitors are created:

1. High CPU Usage
   - Threshold: 85% (critical), 75% (warning)
   - Check interval: 5 minutes

2. High Memory Usage
   - Threshold: 15% free (critical), 20% free (warning)
   - Check interval: 5 minutes

3. High Disk Usage
   - Threshold: 85% (critical), 75% (warning)
   - Check interval: 5 minutes

4. Session Host Down
   - Critical alert if any host is down
   - Check interval: 2 minutes

5. Network Latency
   - Threshold: 100ms (critical), 75ms (warning)
   - Check interval: 5 minutes

6. Storage Account Availability
   - Critical alert if FSLogix storage unavailable
   - Check interval: 3 minutes

7. High User Session Count
   - Warning at 80 active sessions
   - Check interval: 10 minutes

8. Failed User Connections
   - Critical at 5 failures, Warning at 3
   - Check interval: 5 minutes

9. Agent Heartbeat Loss
   - Critical if Datadog agent stops reporting
   - Check interval: 3 minutes
   - No data timeout: 10 minutes

10. Resource Group Changes
    - Critical if more than 5 changes in 10 minutes
    - Monitors for unusual activity

================================================================================
COST ESTIMATE (MONTHLY)
================================================================================

SESSION HOSTS (10x Standard_D4s_v5):
$14 per VM x 10 = $140

STORAGE (FSLogix):
Azure Files Standard LRS = $10

NETWORKING:
Virtual Network = Free
NSG = Free
Outbound data = $5

AZURE MONITOR:
First 10GB logs = Free
First 1,000 alerts = Free
Cost = $0-5

WITHOUT BASTION:
Total = $155 per month

WITH BASTION (Optional):
Bastion Basic SKU = $140
Total = $295 per month

DATADOG (Optional):
Infrastructure Monitoring = $15 per host
10 VMs = $150 per month additional

================================================================================
COST SAVINGS
================================================================================

NO AZURE FRONT DOOR NEEDED:
- Azure Front Door cost: $35-50 per month
- AVD uses Microsoft's global infrastructure
- Saves: $420-600 per year

COMPARED TO TRADITIONAL VPN:
- Cisco AnyConnect: $500/month (50 users)
- Azure VPN Gateway: $140/month
- AVD (10 VMs for 50 users): $155/month
- Savings: $345-$4,140 per year

OPTIMIZATION OPTIONS:
- Reserved Instances: Save 40% on VMs
- Azure Hybrid Benefit: Save 49% on licensing
- Auto-scaling: Save 50-70% on off-hours
- Right-sizing: Optimize VM sizes based on usage

================================================================================
USER ACCESS
================================================================================

WEB CLIENT (Recommended):
URL: https://client.wvd.microsoft.com
Works on any device with browser
No installation required

WINDOWS CLIENT:
Download: https://aka.ms/wvd/clients/windows
Best performance
Multiple monitor support

MACOS CLIENT:
Download: https://aka.ms/wvd/clients/mac
Native macOS experience

MOBILE CLIENTS:
iOS: App Store > "Azure Virtual Desktop"
Android: Play Store > "Azure Virtual Desktop"

================================================================================
ARCHITECTURE NOTES
================================================================================

WHY NO AZURE FRONT DOOR?

AVD TRAFFIC FLOW:
Users > Microsoft AVD Broker (Global) > Entra ID + MFA > Your VNet > Session Hosts

Microsoft provides:
- Global edge locations
- DDoS protection
- Connection brokering
- SSL termination
- Load balancing

You only manage:
- Session host VMs
- Virtual Network
- Storage

MOVEIT SERVER (Different - Needs Front Door):
Users > Azure Front Door (WAF) > Your Load Balancer > Your VMs

MoveIt needs Front Door because:
- Web application (HTTP/HTTPS)
- Custom domain required
- WAF protection needed
- Direct access to your infrastructure

AVD does NOT need Front Door because:
- Remote Desktop Protocol (not web)
- Microsoft's domain (client.wvd.microsoft.com)
- Microsoft handles all edge services
- No direct access to your VMs

RESULT: Save $420-600 per year by not deploying unnecessary Front Door

================================================================================
SECURITY FEATURES
================================================================================

ZERO TRUST ARCHITECTURE:
- No public IPs on session hosts
- RDP from Internet is DENIED
- All connections through Microsoft's secure infrastructure

NETWORK SECURITY:
- NSG denies RDP from Internet (port 3389)
- NSG denies SSH from Internet (port 22)
- NSG allows internal VNet traffic only
- Optional Azure Bastion for admin access (HTTPS 443)

VM SECURITY:
- Trusted Launch enabled
- Secure Boot + vTPM
- Windows 11 Enterprise Multi-session
- Automatic security updates

DATA SECURITY:
- FSLogix profiles encrypted (TLS 1.2+)
- HTTPS-only storage access
- No public blob access
- Storage account private endpoints (optional)

IDENTITY SECURITY:
- Entra ID (Azure AD) authentication
- Multi-factor authentication support
- Conditional Access policies ready
- Role-based access control (RBAC)

================================================================================
POST-DEPLOYMENT TASKS
================================================================================

IMMEDIATE (Day 1):
1. Assign users to Application Group
2. Test user connectivity
3. Verify monitoring alerts

WEEK 1:
1. Configure Conditional Access policies
2. Enable MFA for all users
3. Configure FSLogix settings
4. Set up auto-scaling (optional)

MONTH 1:
1. Performance monitoring and optimization
2. Cost review and optimization
3. User training
4. Security audit

================================================================================
TROUBLESHOOTING
================================================================================

SCRIPT WON'T RUN:
```
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

NOT ADMINISTRATOR:
Right-click PowerShell > "Run as Administrator"

CAN'T FIND SUBSCRIPTION:
Verify access to sub-csc-avd subscription
Contact Azure admin if needed

SESSION HOSTS NOT AVAILABLE:
Wait 15-30 minutes (normal)
VMs still joining host pool

USERS CAN'T CONNECT:
1. Verify user assigned to Application Group
2. Check Conditional Access policies
3. Verify MFA setup
4. Test with web client first

PROFILES DON'T ROAM:
1. Check Storage Account access
2. Verify FSLogix configuration
3. Check file share permissions

DATADOG MONITORS NOT WORKING:
1. Verify Datadog agent installed on VMs
2. Check agent status
3. Verify API keys correct
4. Check agent logs

================================================================================
SUPPORT
================================================================================

SCRIPT ISSUES:
Review deployment summary document
Check deployment log
Review error messages

USER ACCESS ISSUES:
Verify user assignment in Azure Portal
Check user MFA setup
Review Azure AD sign-in logs

AZURE ISSUES:
Azure Service Health: https://status.azure.com
Azure Support Portal: https://portal.azure.com

DATADOG ISSUES:
Datadog Support: https://app.datadoghq.com/help
Datadog Documentation: https://docs.datadoghq.com

PYX HEALTH IT:
Email: avd-admin@pyxhealth.com

================================================================================
FILE VERSIONS
================================================================================

Deploy-AVD-Clean.ps1: Version 1.0
Deploy-AVD-Datadog-Monitoring.ps1: Version 1.0
AVD-DEPLOYMENT-GUIDE-CLEAN.txt: Version 1.0
README.txt: Version 1.0

Last Updated: December 2025
Author: GHAZI IT INC
Company: PYX HEALTH CORPORATION

================================================================================
SCRIPT FEATURES
================================================================================

NO SPECIAL CHARACTERS:
- No emojis
- No boxes
- No fancy symbols
- Plain text output only

NO SYNTAX ERRORS:
- Tested and verified
- PowerShell best practices
- Error handling on every operation
- Comprehensive logging

PRODUCTION READY:
- Enterprise-grade quality
- Comprehensive validation
- Detailed testing
- Professional output

MODULAR DESIGN:
- Main deployment script
- Separate Datadog integration
- Optional components
- Flexible configuration

================================================================================
COMMAND REFERENCE
================================================================================

BASIC DEPLOYMENT:
.\Deploy-AVD-Clean.ps1

WITH DATADOG:
.\Deploy-AVD-Clean.ps1 -DatadogAPIKey "key" -DatadogAppKey "appkey"

WITH BASTION:
.\Deploy-AVD-Clean.ps1 -DeployBastion

MORE VMS:
.\Deploy-AVD-Clean.ps1 -SessionHostCount 20

SKIP VALIDATION:
.\Deploy-AVD-Clean.ps1 -SkipValidation

WITHOUT AZURE MONITOR:
.\Deploy-AVD-Clean.ps1 -DeployMonitoring $false

DATADOG AFTER DEPLOYMENT:
.\Deploy-AVD-Datadog-Monitoring.ps1 -DatadogAPIKey "key" -DatadogAppKey "appkey" -ResourceGroupName "rg-name" -HostPoolName "hp-name"

CHECK DEPLOYMENT STATUS:
Get-AzResource | Where-Object { $_.ResourceGroupName -like '*pyx-avd*' }

================================================================================
END OF README
================================================================================
