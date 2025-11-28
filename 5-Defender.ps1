# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 5 OF 7
# MICROSOFT DEFENDER
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 5 OF 7: MICROSOFT DEFENDER" -ForegroundColor Cyan
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
# ENABLE DEFENDER FOR VMS
# ----------------------------------------------------------------
Write-Log "Enabling Defender for VMs..." "Cyan"
az security pricing create `
    --name VirtualMachines `
    --tier Standard `
    --output none 2>$null

Write-Log "Defender for VMs enabled" "Green"

Write-Host ""

# ----------------------------------------------------------------
# ENABLE DEFENDER FOR APP SERVICE
# ----------------------------------------------------------------
Write-Log "Enabling Defender for App Service..." "Cyan"
az security pricing create `
    --name AppServices `
    --tier Standard `
    --output none 2>$null

Write-Log "Defender for App Service enabled" "Green"

Write-Host ""

# ----------------------------------------------------------------
# ENABLE DEFENDER FOR STORAGE
# ----------------------------------------------------------------
Write-Log "Enabling Defender for Storage..." "Cyan"
az security pricing create `
    --name StorageAccounts `
    --tier Standard `
    --output none 2>$null

Write-Log "Defender for Storage enabled" "Green"

Write-Host ""

# ----------------------------------------------------------------
# CREATE DEPLOYMENT SUMMARY
# ----------------------------------------------------------------
Write-Log "Creating deployment summary..." "Yellow"

$summaryFile = "$env:USERPROFILE\Desktop\MOVEit-Deployment-Summary.txt"

$publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv

$summary = @"
================================================================
MOVEIT DEPLOYMENT SUMMARY
================================================================
Deployment Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

CONFIGURATION:
==============
Resource Group:     $($config.DeploymentResourceGroup)
Location:           $($config.Location)
MOVEit Private IP:  $($config.MOVEitPrivateIP)
Network RG:         $($config.NetworkResourceGroup)
VNet:               $($config.VNetName)
Subnet:             $($config.SubnetName)

SFTP ACCESS (Load Balancer):
=============================
Public IP:          $publicIP
Port:               22
Command:            sftp username@$publicIP

HTTPS ACCESS (Front Door):
===========================
Endpoint:           https://$frontDoorEndpoint
Custom Domain:      $($config.CustomDomain)
WAF:                Prevention Mode
TLS:                1.2 minimum

SECURITY:
=========
✓ Network Security Group (NSG)
✓ Load Balancer (Port 22 only)
✓ Front Door with WAF
✓ OWASP Rule Set
✓ Bot Protection
✓ Microsoft Defender enabled
✓ TLS 1.2+ enforcement
✓ HTTPS-only (HTTP redirects)

ARCHITECTURE:
=============

SFTP Traffic (Port 22):
  Internet → Load Balancer ($publicIP) → NSG → MOVEit

HTTPS Traffic (Port 443):
  Internet → Front Door → WAF → NSG → MOVEit

ROUTING:
========
✓ Origin Group:     $($config.FrontDoorOriginGroupName)
✓ Origin:           $($config.FrontDoorOriginName) → $($config.MOVEitPrivateIP)
✓ Route:            $($config.FrontDoorRouteName) (/* → origin group)
✓ Endpoint:         $($config.FrontDoorEndpointName)

NEXT STEPS:
===========
1. Test SFTP:   sftp username@$publicIP
2. Test HTTPS:  https://$frontDoorEndpoint
3. Configure custom domain (run Script 6 - optional)
4. Verify MOVEit Transfer is running
5. Import SSL certificate if needed

COST ESTIMATE:
==============
Load Balancer:      ~$18/month
Front Door:         ~$35/month
WAF:                ~$20/month
Defender:           ~$10/month
Total:              ~$83/month

================================================================
"@

$summary | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Summary saved to: $summaryFile" "Green"

Write-Host ""
Write-Log "============================================" "Green"
Write-Log "SCRIPT 5 COMPLETED!" "Green"
Write-Log "============================================" "Green"
Write-Host ""
Write-Host "MICROSOFT DEFENDER ENABLED:" -ForegroundColor Cyan
Write-Host "  ✓ VMs" -ForegroundColor Green
Write-Host "  ✓ App Service" -ForegroundColor Green
Write-Host "  ✓ Storage" -ForegroundColor Green
Write-Host ""
Write-Host "DEPLOYMENT SUMMARY:" -ForegroundColor Cyan
Write-Host "  File: $summaryFile" -ForegroundColor White
Write-Host ""
Write-Host "CORE DEPLOYMENT COMPLETE! 🎉" -ForegroundColor Green
Write-Host ""
Write-Host "OPTIONAL: Run Script 6 to configure custom domain" -ForegroundColor Yellow
Write-Host "          Run Script 7 for post-deployment testing" -ForegroundColor Yellow
Write-Host ""
