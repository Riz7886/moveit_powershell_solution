#Requires -RunAsAdministrator
# ================================================================
# MOVEIT ONE-CLICK DEPLOYMENT - 100% AUTOMATED
# NO EDITING REQUIRED - SCRIPT ASKS YOU FOR EVERYTHING
# ================================================================

$ErrorActionPreference = "Continue"

function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

Write-Color "================================================================" "Cyan"
Write-Color "MOVEIT ONE-CLICK TERRAFORM DEPLOYMENT" "Cyan"
Write-Color "Auto-installs everything, detects everything, deploys everything" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

# ================================================================
# STEP 1: AUTO-INSTALL TERRAFORM
# ================================================================
Write-Color "Checking Terraform..." "Yellow"

$terraformInstalled = $false
try {
    $null = & terraform version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $terraformInstalled = $true
        Write-Color "Terraform: Already installed" "Green"
    }
} catch {
    $terraformInstalled = $false
}

if (-not $terraformInstalled) {
    Write-Color "Terraform not found - Installing now..." "Yellow"
    
    $terraformVersion = "1.6.6"
    $terraformUrl = "https://releases.hashicorp.com/terraform/$terraformVersion/terraform_${terraformVersion}_windows_amd64.zip"
    $terraformZip = "$env:TEMP\terraform.zip"
    $terraformDir = "C:\terraform"
    
    try {
        Write-Color "Downloading Terraform..." "Yellow"
        Invoke-WebRequest -Uri $terraformUrl -OutFile $terraformZip -UseBasicParsing
        
        Write-Color "Extracting Terraform..." "Yellow"
        if (Test-Path $terraformDir) { Remove-Item $terraformDir -Recurse -Force }
        New-Item -ItemType Directory -Path $terraformDir -Force | Out-Null
        Expand-Archive -Path $terraformZip -DestinationPath $terraformDir -Force
        Remove-Item $terraformZip -Force
        
        Write-Color "Adding Terraform to PATH..." "Yellow"
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($currentPath -notlike "*$terraformDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$terraformDir", "Machine")
        }
        $env:Path += ";$terraformDir"
        
        Write-Color "Terraform: Installed successfully" "Green"
    } catch {
        Write-Color "ERROR: Failed to install Terraform: $_" "Red"
        exit 1
    }
}

# ================================================================
# STEP 2: AUTO-INSTALL AZURE CLI
# ================================================================
Write-Color "Checking Azure CLI..." "Yellow"

$azInstalled = $false
try {
    $null = & az version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $azInstalled = $true
        Write-Color "Azure CLI: Already installed" "Green"
    }
} catch {
    $azInstalled = $false
}

if (-not $azInstalled) {
    Write-Color "Azure CLI not found - Installing now..." "Yellow"
    
    $azCliInstaller = "$env:TEMP\AzureCLI.msi"
    $azCliUrl = "https://aka.ms/installazurecliwindowsx64"
    
    try {
        Write-Color "Downloading Azure CLI..." "Yellow"
        Invoke-WebRequest -Uri $azCliUrl -OutFile $azCliInstaller -UseBasicParsing
        
        Write-Color "Installing Azure CLI (this takes 2-3 minutes)..." "Yellow"
        Start-Process msiexec.exe -ArgumentList "/i `"$azCliInstaller`" /quiet /norestart" -Wait
        Remove-Item $azCliInstaller -Force
        
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Color "Azure CLI: Installed successfully" "Green"
    } catch {
        Write-Color "ERROR: Failed to install Azure CLI: $_" "Red"
        exit 1
    }
}

Write-Host ""

# ================================================================
# STEP 3: AZURE LOGIN
# ================================================================
Write-Color "Checking Azure login..." "Yellow"

$loggedIn = $false
try {
    $accountCheck = az account show 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $loggedIn = $true
        Write-Color "Already logged in to Azure" "Green"
    }
} catch {
    $loggedIn = $false
}

if (-not $loggedIn) {
    Write-Color "Not logged in - Starting Azure login..." "Yellow"
    az login --use-device-code
}

Write-Host ""

# ================================================================
# STEP 4: SELECT SUBSCRIPTION
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "AVAILABLE SUBSCRIPTIONS" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

$subscriptions = az account list --output json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    Write-Color "ERROR: No subscriptions found" "Red"
    exit 1
}

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    $status = if ($sub.state -eq "Enabled") { "Green" } else { "Yellow" }
    Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($sub.name) " -NoNewline
    Write-Host "($($sub.state))" -ForegroundColor $status
}

Write-Host ""
$subChoice = Read-Host "Select subscription number"
$selectedSub = $subscriptions[[int]$subChoice - 1]

az account set --subscription $selectedSub.id
$currentSub = az account show --output json | ConvertFrom-Json
Write-Color "Active: $($currentSub.name)" "Green"

Write-Host ""

# ================================================================
# STEP 5: FIND RESOURCE GROUP
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "FINDING YOUR NETWORK" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

$allRGs = az group list --output json | ConvertFrom-Json

# Try to find network RG
$networkRG = $null
foreach ($rg in $allRGs) {
    if ($rg.name -like "*network*") {
        $networkRG = $rg.name
        Write-Color "Found Network RG: $networkRG" "Green"
        break
    }
}

if (-not $networkRG) {
    Write-Color "Select resource group:" "Yellow"
    for ($i = 0; $i -lt $allRGs.Count; $i++) {
        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Cyan
        Write-Host "$($allRGs[$i].name)"
    }
    Write-Host ""
    $rgChoice = Read-Host "Select number"
    $networkRG = $allRGs[[int]$rgChoice - 1].name
}

Write-Host ""

# ================================================================
# STEP 6: FIND VNET
# ================================================================
$allVNets = az network vnet list --resource-group $networkRG --output json | ConvertFrom-Json

if ($allVNets.Count -eq 0) {
    Write-Color "ERROR: No VNets in $networkRG" "Red"
    exit 1
}

$selectedVNet = $null
if ($allVNets.Count -eq 1) {
    $selectedVNet = $allVNets[0].name
    Write-Color "VNet: $selectedVNet (auto-selected)" "Green"
} else {
    Write-Color "Select VNet:" "Yellow"
    for ($i = 0; $i -lt $allVNets.Count; $i++) {
        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Cyan
        Write-Host "$($allVNets[$i].name)"
    }
    Write-Host ""
    $vnetChoice = Read-Host "Select number"
    $selectedVNet = $allVNets[[int]$vnetChoice - 1].name
}

Write-Host ""

# ================================================================
# STEP 7: FIND SUBNET
# ================================================================
$vnetDetails = az network vnet show --resource-group $networkRG --name $selectedVNet --output json | ConvertFrom-Json
$allSubnets = $vnetDetails.subnets

$selectedSubnet = $null
if ($allSubnets.Count -eq 1) {
    $selectedSubnet = $allSubnets[0].name
    Write-Color "Subnet: $selectedSubnet (auto-selected)" "Green"
} else {
    Write-Color "Select Subnet:" "Yellow"
    for ($i = 0; $i -lt $allSubnets.Count; $i++) {
        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Cyan
        Write-Host "$($allSubnets[$i].name) " -NoNewline
        Write-Host "($($allSubnets[$i].addressPrefix))" -ForegroundColor Gray
    }
    Write-Host ""
    $subnetChoice = Read-Host "Select number"
    $selectedSubnet = $allSubnets[[int]$subnetChoice - 1].name
}

Write-Host ""

# ================================================================
# STEP 8: ASK FOR MOVEIT IP AND LOCATION
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "MOVEIT SERVER CONFIGURATION" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

$MOVEitPrivateIP = Read-Host "Enter MOVEit server private IP (e.g., 192.168.0.5 or 10.0.1.4)"
Write-Host ""

$Location = Read-Host "Enter Azure region (e.g., eastus, westus, centralus)"
Write-Host ""

Write-Color "MOVEit IP: $MOVEitPrivateIP" "Green"
Write-Color "Location: $Location" "Green"

Write-Host ""

# ================================================================
# STEP 9: SUMMARY
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "CONFIGURATION" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""
Write-Host "Subscription:  $($currentSub.name)"
Write-Host "Location:      $Location"
Write-Host "Network RG:    $networkRG"
Write-Host "VNet:          $selectedVNet"
Write-Host "Subnet:        $selectedSubnet"
Write-Host "MOVEit IP:     $MOVEitPrivateIP"
Write-Host ""
Write-Host "Will create: NSG, Load Balancer, Front Door, WAF"
Write-Host "Cost: ~83 USD/month"
Write-Host ""

$deployConfirm = Read-Host "Deploy? (yes/no)"
if ($deployConfirm -ne "yes") {
    Write-Color "Cancelled" "Yellow"
    exit 0
}

Write-Host ""

# ================================================================
# STEP 10: CREATE TERRAFORM.TFVARS
# ================================================================
Write-Color "Generating Terraform config..." "Cyan"

$tfvars = @"
subscription_id      = "$($currentSub.id)"
location            = "$Location"
existing_vnet_name  = "$selectedVNet"
existing_vnet_rg    = "$networkRG"
existing_subnet_name = "$selectedSubnet"
moveit_private_ip   = "$MOVEitPrivateIP"
resource_group_name = "rg-moveit-security"
project_name        = "moveit"
environment         = "prod"
enable_waf          = true
waf_mode            = "Prevention"
"@

$tfvars | Out-File -FilePath "terraform.tfvars" -Encoding UTF8
Write-Color "Created terraform.tfvars" "Green"

Write-Host ""

# ================================================================
# STEP 11: TERRAFORM INIT
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "TERRAFORM INIT" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

terraform init
if ($LASTEXITCODE -ne 0) {
    Write-Color "ERROR: terraform init failed" "Red"
    exit 1
}

Write-Host ""

# ================================================================
# STEP 12: TERRAFORM PLAN
# ================================================================
Write-Color "================================================================" "Cyan"
Write-Color "TERRAFORM PLAN" "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

terraform plan -out=tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Color "ERROR: terraform plan failed" "Red"
    exit 1
}

Write-Host ""

# ================================================================
# STEP 13: TERRAFORM APPLY
# ================================================================
Write-Color "================================================================" "Yellow"
Write-Color "READY TO DEPLOY" "Yellow"
Write-Color "================================================================" "Yellow"
Write-Host ""

$finalConfirm = Read-Host "Deploy now? (yes/no)"
if ($finalConfirm -ne "yes") {
    Write-Color "Cancelled" "Yellow"
    exit 0
}

Write-Host ""
Write-Color "================================================================" "Cyan"
Write-Color "DEPLOYING (10 minutes)..." "Cyan"
Write-Color "================================================================" "Cyan"
Write-Host ""

terraform apply tfplan

if ($LASTEXITCODE -ne 0) {
    Write-Color "ERROR: terraform apply failed" "Red"
    exit 1
}

Write-Host ""

# ================================================================
# COMPLETE
# ================================================================
Write-Color "================================================================" "Green"
Write-Color "DEPLOYMENT COMPLETE" "Green"
Write-Color "================================================================" "Green"
Write-Host ""

terraform output deployment_summary

Write-Host ""
Write-Color "Saved: terraform.tfvars, terraform.tfstate" "Cyan"
Write-Color "To destroy: terraform destroy" "Yellow"
Write-Host ""
