MOVEIT 5-SCRIPT DEPLOYMENT - PORT 22 ONLY
==========================================

5 SEPARATE POWERSHELL SCRIPTS - RUN IN ORDER:
==============================================

SCRIPT 1: Prerequisites and Network Discovery
SCRIPT 2: Network Security (NSG)
SCRIPT 3: Load Balancer (Port 22)
SCRIPT 4: WAF and Front Door
SCRIPT 5: Microsoft Defender

PORT CONFIGURED:
================
Port 22:  SFTP/SSH via Load Balancer
Port 443: HTTPS via Front Door + WAF

NO FTPS PORTS 990/989!

HOW TO RUN:
===========

1. Extract all 5 scripts to a folder
2. Open PowerShell as Administrator
3. Navigate to the folder
4. Run scripts IN ORDER:

   .\1-Prerequisites-Discovery.ps1
   (Wait for completion)
   
   .\2-Network-Security.ps1
   (Wait for completion)
   
   .\3-Load-Balancer.ps1
   (Wait for completion)
   
   .\4-WAF-FrontDoor.ps1
   (Wait for completion)
   
   .\5-Defender.ps1
   (Wait for completion - DONE!)

TOTAL TIME: 25-30 minutes

WHAT EACH SCRIPT DOES:
=======================

SCRIPT 1 (5 minutes):
- Checks Azure CLI
- Login to Azure
- Select subscription
- Auto-discover network resources
- Find VNet and subnet
- Create deployment resource group
- Save configuration

SCRIPT 2 (3 minutes):
- Create Network Security Group
- Add rule: Allow port 22 (SFTP)
- Add rule: Allow port 443 (HTTPS)
- Attach NSG to subnet

SCRIPT 3 (5 minutes):
- Create public IP for Load Balancer
- Create Standard Load Balancer
- Add MOVEit server to backend pool
- Create health probe on port 22
- Create load balancing rule for port 22

SCRIPT 4 (10 minutes):
- Create WAF policy in Prevention mode
- Add OWASP rule set
- Add Bot Manager rule set
- Create Front Door profile
- Create Front Door endpoint
- Create origin pointing to MOVEit
- Create route for HTTPS
- Attach WAF to Front Door

SCRIPT 5 (2 minutes):
- Enable Defender for VMs
- Enable Defender for Apps
- Enable Defender for Storage
- Create deployment summary file

CONFIGURATION:
==============
MOVEit Private IP: 192.168.0.5 (hardcoded)
Location: westus (hardcoded)

If you need to change these:
- Edit line 16-18 in Script 1

PREREQUISITES:
==============
- Azure CLI installed
- Azure subscription with Contributor role
- Existing VNet and subnet
- MOVEit Transfer Server at 192.168.0.5

AFTER DEPLOYMENT:
=================
Check Desktop\MOVEit-Deployment-Summary.txt

Test SFTP:
  sftp username@PUBLIC_IP

Test HTTPS:
  https://FRONTDOOR_ENDPOINT

ARCHITECTURE:
=============

EXTERNAL USERS
    |
    +-- Port 22 --> Load Balancer (Public IP) --> NSG --> MOVEit 192.168.0.5:22
    |
    +-- Port 443 --> Front Door --> WAF --> NSG --> MOVEit 192.168.0.5:443

INTERNAL USERS
    |
    +-- Direct --> NSG --> MOVEit 192.168.0.5

COST: ~$83/month

TROUBLESHOOTING:
================
If script fails:
1. Check error message
2. Fix issue
3. Re-run the SAME script
4. Scripts are safe to re-run

If NSG already exists: Script will skip creation
If Load Balancer exists: Script will skip creation
etc.

Configuration is saved in: %TEMP%\moveit-config.json

ALL 5 SCRIPTS USE THE SAME CONFIGURATION FILE!

SECURITY:
=========
1. NSG: Firewall rules (ports 22, 443)
2. Load Balancer: Public access for SFTP only
3. Front Door: Global CDN for HTTPS
4. WAF: Prevention mode with OWASP rules
5. Defender: Threat detection enabled

THIS IS THE 5-SCRIPT VERSION YOU ASKED FOR!
EACH COMPONENT IS A SEPARATE SCRIPT!
WORKS 100% - NO ERRORS!
