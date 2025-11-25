# MOVEIT TERRAFORM DEPLOYMENT

## ONE COMMAND - NO EDITING REQUIRED

Script asks you for everything during runtime.

### Run as Administrator

Right-click PowerShell → Run as Administrator

```powershell
cd C:\Path\To\MOVEit-Terraform
.\DEPLOY.ps1
```

### What It Does

1. Auto-installs Terraform if missing
2. Auto-installs Azure CLI if missing
3. Logs into Azure
4. Lists subscriptions - you select
5. Lists resource groups - you select or auto-finds "network"
6. Lists VNets - you select or auto-selects
7. Lists Subnets - you select or auto-selects
8. **ASKS for MOVEit IP** - you type it (e.g., 192.168.0.5)
9. **ASKS for Azure region** - you type it (e.g., eastus)
10. Generates terraform.tfvars
11. Runs terraform init, plan, apply
12. Deploys everything
13. Shows endpoints

**NO EDITING FILES. SCRIPT ASKS FOR EVERYTHING.**

### What Gets Deployed

- Network Security Group (SFTP port 22 + HTTPS rules)
- Load Balancer Standard + Public IP (SFTP port 22)
- Azure Front Door Standard (HTTPS port 443)
- WAF Policy (Prevention mode, OWASP + Bot protection)
- Microsoft Defender Standard

Cost: ~83 USD/month

### Your MOVEit Server Is Safe

Creates NEW resources in NEW resource group (rg-moveit-security).
Your MOVEit VM, VNet, Subnet stay untouched.

### After Deployment

View endpoints:
```powershell
terraform output deployment_summary
```

Remove everything:
```powershell
terraform destroy
```

### Files

- DEPLOY.ps1 - Main script (RUN THIS)
- provider.tf - Terraform provider
- variables.tf - Terraform variables
- main.tf - Terraform resources
- outputs.tf - Terraform outputs
- README.md - This file

### Troubleshooting

Script fails?
- Make sure running as Administrator
- Check internet connection
- Verify Azure login works: `az account show`

Still issues?
Run Terraform manually:
```powershell
# After DEPLOY.ps1 creates terraform.tfvars:
terraform init
terraform plan
terraform apply
```

### That's It

Extract → Edit IP → Run as Admin → Done

Time: 15 minutes
Deadline: Wednesday
You have time.
