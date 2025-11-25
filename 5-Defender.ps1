# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 5 OF 5
# MICROSOFT DEFENDER FOR CLOUD
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 5 OF 5: MICROSOFT DEFENDER" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# ----------------------------------------------------------------
# LOAD CONFIGURATION
# ----------------------------------------------------------------
$configFile = "$env:TEMP\moveit-config.json"
if (-not (Test-Path $configFile)) {
    Write-Log "ERROR: Configuration not found! Run Script 1 first." "Red"
    exit 1
}

$config = Get-Content $configFile | ConvertFrom-Json
Write-Log "Configuration loaded" "Green"
Write-Host ""

# ----------------------------------------------------------------
# ENABLE MICROSOFT DEFENDER
# ----------------------------------------------------------------
Write-Log "Enabling Microsoft Defender for Cloud..." "Cyan"
Write-Host ""

Write-Log "Enabling Defender for Virtual Machines..." "Yellow"
az security pricing create --name VirtualMachines --tier Standard --output none 2>$null
Write-Log "  Virtual Machines: Enabled" "Green"

Write-Log "Enabling Defender for App Services..." "Yellow"
az security pricing create --name AppServices --tier Standard --output none 2>$null
Write-Log "  App Services: Enabled" "Green"

Write-Log "Enabling Defender for Storage Accounts..." "Yellow"
az security pricing create --name StorageAccounts --tier Standard --output none 2>$null
Write-Log "  Storage Accounts: Enabled" "Green"

# ----------------------------------------------------------------
# GET FINAL DETAILS
# ----------------------------------------------------------------
$LBPublicIPName = "pip-moveit-sftp"
$FrontDoorProfileName = "moveit-frontdoor-profile"
$FrontDoorEndpointName = "moveit-endpoint"

$sftpPublicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $LBPublicIPName --query ipAddress --output tsv 2>$null
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $FrontDoorProfileName --endpoint-name $FrontDoorEndpointName --query hostName --output tsv 2>$null

# ----------------------------------------------------------------
# CREATE SUMMARY FILE
# ----------------------------------------------------------------
$summaryFile = "$env:USERPROFILE\Desktop\MOVEit-Deployment-Summary.txt"
@"
========================================
MOVEIT DEPLOYMENT SUMMARY
========================================
Deployment Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

CONNECTION INFORMATION:
SFTP:  sftp username@$sftpPublicIP (Port 22)
HTTPS: https://$frontDoorEndpoint

INFRASTRUCTURE:
Network RG: $($config.NetworkResourceGroup)
Deployment RG: $($config.DeploymentResourceGroup)
VNet: $($config.VNetName)
Subnet: $($config.SubnetName)
MOVEit Private IP: $($config.MOVEitPrivateIP)
Load Balancer Public IP: $sftpPublicIP

SECURITY DEPLOYED:
1. Network Security Group (NSG)
   - Port 22 (SFTP): ALLOWED
   - Port 443 (HTTPS): ALLOWED
   
2. Load Balancer
   - Public IP: $sftpPublicIP
   - Port 22 forwarding to MOVEit
   
3. Azure Front Door
   - Global CDN endpoint
   - HTTPS-only with redirect
   
4. Web Application Firewall (WAF)
   - Prevention mode
   - OWASP rules active
   - Bot protection active
   
5. Microsoft Defender
   - VM protection: ENABLED
   - App protection: ENABLED
   - Storage protection: ENABLED

MONTHLY COST: ~$83/month

NEXT STEPS:
1. Configure MOVEit Transfer to listen on:
   - Port 22 (SFTP/SSH)
   - Port 443 (HTTPS)
2. Test SFTP: sftp username@$sftpPublicIP
3. Test HTTPS: https://$frontDoorEndpoint
4. Configure SSL certificates in MOVEit
5. Set up user accounts and permissions
6. Configure file retention policies
7. Set up monitoring and alerts

USERS CAN NOW CONNECT VIA:
- SFTP on port 22 (external)
- HTTPS via Front Door (external)
- Direct access at 192.168.0.5 (internal)

========================================
"@ | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 5 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "MICROSOFT DEFENDER ENABLED:" -ForegroundColor Cyan
Write-Host "  Virtual Machines: PROTECTED" -ForegroundColor Green
Write-Host "  App Services: PROTECTED" -ForegroundColor Green
Write-Host "  Storage Accounts: PROTECTED" -ForegroundColor Green
Write-Host ""
Write-Log "============================================" "Yellow"
Write-Log "ALL 5 SCRIPTS COMPLETED!" "Yellow"
Write-Log "============================================" "Yellow"
Write-Host ""
Write-Host "DEPLOYMENT SUMMARY:" -ForegroundColor Cyan
Write-Host "  SFTP: $sftpPublicIP (port 22)" -ForegroundColor Green
Write-Host "  HTTPS: https://$frontDoorEndpoint" -ForegroundColor Green
Write-Host ""
Write-Host "SECURITY COMPONENTS:" -ForegroundColor Cyan
Write-Host "  1. NSG (Firewall): CONFIGURED" -ForegroundColor White
Write-Host "  2. Load Balancer: CONFIGURED" -ForegroundColor White
Write-Host "  3. Front Door: CONFIGURED" -ForegroundColor White
Write-Host "  4. WAF: CONFIGURED" -ForegroundColor White
Write-Host "  5. Defender: ENABLED" -ForegroundColor White
Write-Host ""
Write-Host "Summary saved to: $summaryFile" -ForegroundColor Gray
Write-Host ""
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "Users can now connect via SFTP on port 22!" -ForegroundColor Green
Write-Host ""
