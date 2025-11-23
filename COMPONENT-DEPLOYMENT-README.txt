# MOVEIT COMPONENT-BASED DEPLOYMENT
## 5 Separate Stories for Agile/Sprint Deployment

---

## OVERVIEW

This deployment has been broken into 5 independent stories/components that can be deployed separately across sprints or testing phases.

**Total Deployment Time:** ~25 minutes (if run sequentially)

**Cost:** $83/month ($18 LB + $35 Front Door + $30 WAF)

---

## COMPONENT STORIES

### Story 1: Prerequisites & Network Discovery
**File:** Story-1-Prerequisites-Network-Discovery.ps1
**Duration:** 5 minutes
**What it does:**
- Checks Azure CLI installation
- Logs into Azure
- Shows all available subscriptions
- Lets you select subscription
- Auto-detects network resource group (with "network" in name)
- Auto-detects VNet (prefers "prod" in name)
- Auto-detects subnet (prefers "moveit" in name)
- Creates deployment resource group (rg-moveit)
- Saves state to Desktop

**Output:** MOVEit-Deployment-State.json

---

### Story 2: Network Security (NSG)
**File:** Story-2-Network-Security.ps1
**Duration:** 3 minutes
**Requires:** Story 1 complete
**What it does:**
- Loads state from Story 1
- Creates Network Security Group (nsg-moveit)
- Adds security rule for FTPS port 990
- Adds security rule for FTPS port 989
- Adds security rule for HTTPS port 443
- Attaches NSG to MOVEit subnet
- Updates state file

**Security Rules Created:**
- Allow-FTPS-990 (priority 100)
- Allow-FTPS-989 (priority 110)
- Allow-HTTPS-443 (priority 120)

---

### Story 3: Load Balancer (FTPS)
**File:** Story-3-Load-Balancer.ps1
**Duration:** 5 minutes
**Requires:** Stories 1-2 complete
**What it does:**
- Loads state from previous stories
- Creates public IP address (pip-moveit-ftps)
- Creates Standard Load Balancer (lb-moveit-ftps)
- Configures backend pool with MOVEit server IP
- Creates TCP health probe on port 990
- Creates load balancing rule for port 990 (command)
- Creates load balancing rule for port 989 (data)
- Updates state file with public IP

**Result:** FTPS endpoint available at public IP:990

---

### Story 4: WAF Policy
**File:** Story-4-WAF-Policy.ps1
**Duration:** 4 minutes
**Requires:** Stories 1-3 complete
**What it does:**
- Loads state from previous stories
- Creates WAF Policy (moveitWAFPolicy)
- Sets mode to Prevention
- Configures policy settings (max body size, file upload limits)
- Adds DefaultRuleSet 1.0 (OWASP protection)
- Adds Microsoft_BotManagerRuleSet 1.0 (bot protection)
- Creates custom rule: AllowLargeUploads (priority 100)
- Creates custom rule: AllowMOVEitMethods (priority 110)
- Updates state file

**Protection:**
- OWASP Top 10 vulnerabilities
- Bot attacks
- DDoS attacks
- Large file uploads allowed

---

### Story 5: Front Door & Final Configuration
**File:** Story-5-Front-Door-Final.ps1
**Duration:** 6 minutes
**Requires:** Stories 1-4 complete
**What it does:**
- Loads state from previous stories
- Creates Front Door profile (moveit-frontdoor-profile)
- Creates Front Door endpoint (moveit-endpoint)
- Creates origin group with health probes
- Creates origin pointing to MOVEit private IP
- Creates route for HTTPS traffic
- Attaches WAF security policy to Front Door
- Enables Microsoft Defender for Cloud
  - VMs: Standard tier
  - App Services: Standard tier
  - Storage: Standard tier
- Creates final deployment summary
- Saves complete state

**Result:** Complete MOVEit deployment with HTTPS endpoint

---

## DEPLOYMENT SEQUENCE

### Run All Stories in Order:

```powershell
# Story 1
.\Story-1-Prerequisites-Network-Discovery.ps1

# Story 2
.\Story-2-Network-Security.ps1

# Story 3
.\Story-3-Load-Balancer.ps1

# Story 4
.\Story-4-WAF-Policy.ps1

# Story 5
.\Story-5-Front-Door-Final.ps1
```

---

## STATE MANAGEMENT

All stories use a shared state file: `MOVEit-Deployment-State.json`

**Location:** `%USERPROFILE%\Desktop\MOVEit-Deployment-State.json`

**Purpose:**
- Stores configuration between stories
- Allows independent execution
- Enables rollback/restart
- Tracks deployment progress

**State Contents:**
```json
{
  "SubscriptionId": "...",
  "SubscriptionName": "...",
  "NetworkResourceGroup": "rg-networking",
  "VNetName": "vnet-prod",
  "SubnetName": "snet-moveit",
  "DeploymentResourceGroup": "rg-moveit",
  "Location": "westus",
  "MOVEitPrivateIP": "192.168.0.5",
  "NSGName": "nsg-moveit",
  "LoadBalancerName": "lb-moveit-ftps",
  "LoadBalancerPublicIP": "x.x.x.x",
  "WAFPolicyName": "moveitWAFPolicy",
  "FrontDoorEndpoint": "moveit-endpoint-xxx.z01.azurefd.net",
  "DeploymentCompleted": true
}
```

---

## AGILE/SPRINT PLANNING

### Sprint 1: Foundation
- Story 1: Prerequisites & Network Discovery
- Story 2: Network Security
**Deliverable:** Secured network ready for components

### Sprint 2: File Transfer
- Story 3: Load Balancer
**Deliverable:** Working FTPS endpoint

### Sprint 3: Security & Web Access
- Story 4: WAF Policy
- Story 5: Front Door & Final Configuration
**Deliverable:** Complete deployment with HTTPS and security

---

## TESTING BETWEEN STORIES

### After Story 1:
```powershell
# Verify state file exists
Get-Content "$env:USERPROFILE\Desktop\MOVEit-Deployment-State.json" | ConvertFrom-Json
```

### After Story 2:
```powershell
# Verify NSG created
az network nsg show --resource-group rg-networking --name nsg-moveit
```

### After Story 3:
```powershell
# Test FTPS connection
# Get public IP from state file
$state = Get-Content "$env:USERPROFILE\Desktop\MOVEit-Deployment-State.json" | ConvertFrom-Json
Test-NetConnection -ComputerName $state.LoadBalancerPublicIP -Port 990
```

### After Story 4:
```powershell
# Verify WAF policy
az network front-door waf-policy show --resource-group rg-moveit --name moveitWAFPolicy
```

### After Story 5:
```powershell
# Test HTTPS endpoint
$state = Get-Content "$env:USERPROFILE\Desktop\MOVEit-Deployment-State.json" | ConvertFrom-Json
Start-Process "https://$($state.FrontDoorEndpoint)"
```

---

## ROLLBACK PROCEDURES

### Rollback Story 5 (Keep Stories 1-4):
```powershell
az afd profile delete --resource-group rg-moveit --profile-name moveit-frontdoor-profile
az security pricing create --name VirtualMachines --tier Free
az security pricing create --name AppServices --tier Free
az security pricing create --name StorageAccounts --tier Free
```

### Rollback Story 4 (Keep Stories 1-3):
```powershell
az network front-door waf-policy delete --resource-group rg-moveit --name moveitWAFPolicy
```

### Rollback Story 3 (Keep Stories 1-2):
```powershell
az network lb delete --resource-group rg-moveit --name lb-moveit-ftps
az network public-ip delete --resource-group rg-moveit --name pip-moveit-ftps
```

### Rollback Story 2 (Keep Story 1):
```powershell
az network nsg delete --resource-group rg-networking --name nsg-moveit
```

### Rollback Everything:
```powershell
az group delete --name rg-moveit --yes --no-wait
# Manually remove NSG from rg-networking if needed
az network nsg delete --resource-group rg-networking --name nsg-moveit
```

---

## ADVANTAGES OF COMPONENT DEPLOYMENT

1. **Incremental Testing:** Test each component independently
2. **Agile/Sprint Friendly:** Distribute across multiple sprints
3. **Easy Rollback:** Roll back individual components
4. **Team Collaboration:** Different team members can work on different stories
5. **Risk Mitigation:** Identify issues early before full deployment
6. **Documentation:** Clear separation of concerns
7. **State Tracking:** JSON state file shows progress
8. **Reusability:** Can re-run individual stories to update components

---

## FINAL DELIVERABLES

After completing all 5 stories:

**Desktop Files:**
- MOVEit-Deployment-State.json (deployment state)
- MOVEit-Deployment-Summary.txt (final summary)

**Azure Resources:**
- Network Security Group in rg-networking
- Load Balancer in rg-moveit
- WAF Policy in rg-moveit
- Front Door in rg-moveit
- Microsoft Defender enabled

**Endpoints:**
- FTPS: [PublicIP]:990, 989
- HTTPS: https://[endpoint].azurefd.net

**Cost:** $83/month

---

## TROUBLESHOOTING

### Story fails with "State file not found"
**Solution:** Run previous stories first in sequence

### Story fails with permission error
**Solution:** Ensure you're logged into correct subscription:
```powershell
az account show
az account set --subscription [subscription-id]
```

### Want to start over
**Solution:**
```powershell
# Delete state file
Remove-Item "$env:USERPROFILE\Desktop\MOVEit-Deployment-State.json"
# Run Story 1 again
```

### Resources already exist
**Solution:** Scripts detect existing resources and skip creation

---

## REQUIREMENTS

- Windows PowerShell 5.1+ or PowerShell Core 7+
- Azure CLI installed
- Azure subscription with permissions to create resources
- Existing network infrastructure (VNet, subnet with MOVEit server)

---

## SUPPORT

**Questions?** Check the state file for current configuration:
```powershell
Get-Content "$env:USERPROFILE\Desktop\MOVEit-Deployment-State.json" | ConvertFrom-Json | Format-List
```

**Need to see what's deployed?**
```powershell
# List all resources in deployment RG
az resource list --resource-group rg-moveit --output table
```

---

**Component-Based Deployment = Flexible, Safe, Agile!**
