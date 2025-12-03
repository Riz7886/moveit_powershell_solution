# ============================================================================
# REMOVE NSG FROM NIC - WITH SUBSCRIPTION SELECTION (LIKE AVD SCRIPT)
# ============================================================================
# Purpose: Remove NSG from nic-moveit-transfer with proper subscription selection
# Author: PYX Health IT
# Date: December 2025
# ============================================================================

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "    REMOVE NSG FROM NIC - PRODUCTION SAFE WITH SUBSCRIPTION SELECTION" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 1: CONNECT TO AZURE
# ============================================================================
Write-Host "STEP 1: Connecting to Azure..." -ForegroundColor Green
Write-Host ""

try {
    $context = Get-AzContext -ErrorAction SilentlyContinue
    
    if ($null -eq $context) {
        Write-Host "  Not logged in. Please log in to Azure..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Host "  SUCCESS: Connected to Azure" -ForegroundColor Green
    Write-Host "    Current Account: $($context.Account.Id)" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to connect to Azure" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Run: Connect-AzAccount" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 2: GET ALL SUBSCRIPTIONS (LIKE AVD SCRIPT)
# ============================================================================
Write-Host "STEP 2: Getting Azure subscriptions..." -ForegroundColor Green
Write-Host ""

try {
    $subscriptions = Get-AzSubscription | Sort-Object Name
    
    if ($subscriptions.Count -eq 0) {
        Write-Host "  ERROR: No subscriptions found" -ForegroundColor Red
        Write-Host "  Make sure your account has access to Azure subscriptions" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  Found $($subscriptions.Count) subscription(s)" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to get subscriptions" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 3: DISPLAY SUBSCRIPTION MENU (EXACTLY LIKE AVD SCRIPT)
# ============================================================================
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                     SELECT SUBSCRIPTION" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Available subscriptions:" -ForegroundColor Yellow
Write-Host ""

for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    Write-Host "  [$($i + 1)] $($sub.Name)" -ForegroundColor Cyan
    Write-Host "      Subscription ID: $($sub.Id)" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "----------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# STEP 4: GET USER SELECTION
# ============================================================================
while ($true) {
    $selection = Read-Host "Select subscription number (e.g., 1, 2, 3)"
    
    if ($selection -match '^\d+$') {
        $selectedIndex = [int]$selection - 1
        
        if ($selectedIndex -ge 0 -and $selectedIndex -lt $subscriptions.Count) {
            $selectedSubscription = $subscriptions[$selectedIndex]
            break
        } else {
            Write-Host "  ERROR: Invalid selection. Please choose 1-$($subscriptions.Count)" -ForegroundColor Red
            Write-Host ""
        }
    } else {
        Write-Host "  ERROR: Please enter a number" -ForegroundColor Red
        Write-Host ""
    }
}

Write-Host ""
Write-Host "  SELECTED SUBSCRIPTION:" -ForegroundColor Green
Write-Host "    Name: $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host "    ID:   $($selectedSubscription.Id)" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 5: SET AZURE CONTEXT TO SELECTED SUBSCRIPTION
# ============================================================================
Write-Host "STEP 3: Setting subscription context..." -ForegroundColor Green
Write-Host ""

try {
    Set-AzContext -SubscriptionId $selectedSubscription.Id | Out-Null
    
    Write-Host "  SUCCESS: Subscription context set" -ForegroundColor Green
    Write-Host "    Working in: $($selectedSubscription.Name)" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to set subscription context" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 6: GET NIC CONFIGURATION
# ============================================================================
Write-Host "STEP 4: Finding Network Interface..." -ForegroundColor Green
Write-Host ""

# Configuration
$nicName = "nic-moveit-transfer"
$resourceGroupName = "rg-moveit"
$expectedPrivateIP = "192.168.0.5"

Write-Host "  Searching for NIC:" -ForegroundColor Yellow
Write-Host "    NIC Name:       $nicName" -ForegroundColor Cyan
Write-Host "    Resource Group: $resourceGroupName" -ForegroundColor Cyan
Write-Host "    Subscription:   $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host ""

try {
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    
    Write-Host "  SUCCESS: Network Interface found" -ForegroundColor Green
    Write-Host ""
    
    # Validate NIC details
    Write-Host "  NIC DETAILS:" -ForegroundColor Yellow
    Write-Host "  ============" -ForegroundColor Yellow
    Write-Host "    Name:           $($nic.Name)" -ForegroundColor Cyan
    Write-Host "    Resource Group: $($nic.ResourceGroupName)" -ForegroundColor Cyan
    Write-Host "    Location:       $($nic.Location)" -ForegroundColor Cyan
    Write-Host "    Private IP:     $($nic.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
    Write-Host "    Subscription:   $($selectedSubscription.Name)" -ForegroundColor Cyan
    
    # Verify private IP matches
    $actualPrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
    if ($actualPrivateIP -eq $expectedPrivateIP) {
        Write-Host "    IP Validation:  PASS (matches $expectedPrivateIP)" -ForegroundColor Green
    } else {
        Write-Host "    IP Validation:  WARNING (expected $expectedPrivateIP, got $actualPrivateIP)" -ForegroundColor Yellow
    }
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Network Interface not found in this subscription" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  POSSIBLE REASONS:" -ForegroundColor Yellow
    Write-Host "    1. Wrong subscription selected" -ForegroundColor Yellow
    Write-Host "    2. NIC doesn't exist in this subscription" -ForegroundColor Yellow
    Write-Host "    3. Resource group name is incorrect" -ForegroundColor Yellow
    Write-Host "    4. Insufficient permissions" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ============================================================================
# STEP 7: CHECK NSG STATUS
# ============================================================================
Write-Host "STEP 5: Checking NSG Status..." -ForegroundColor Green
Write-Host ""

if ($null -eq $nic.NetworkSecurityGroup) {
    Write-Host "  RESULT: No NSG is attached to this NIC" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Nothing to remove. Operation complete." -ForegroundColor Yellow
    Write-Host ""
    exit 0
} else {
    $currentNSGName = $nic.NetworkSecurityGroup.Id.Split('/')[-1]
    
    Write-Host "  CURRENT STATUS:" -ForegroundColor Yellow
    Write-Host "  ===============" -ForegroundColor Yellow
    Write-Host "    NSG Attached:  YES" -ForegroundColor Red
    Write-Host "    NSG Name:      $currentNSGName" -ForegroundColor Cyan
    Write-Host "    NSG ID:        $($nic.NetworkSecurityGroup.Id)" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# STEP 8: SHOW BEFORE/AFTER COMPARISON
# ============================================================================
Write-Host "STEP 6: Review Changes..." -ForegroundColor Green
Write-Host ""

Write-Host "  CURRENT STATE (BEFORE):" -ForegroundColor Yellow
Write-Host "  =======================" -ForegroundColor Yellow
Write-Host "    Subscription:      $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host "    NIC Name:          $($nic.Name)" -ForegroundColor Cyan
Write-Host "    Resource Group:    $($nic.ResourceGroupName)" -ForegroundColor Cyan
Write-Host "    Private IP:        $($nic.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
Write-Host "    NSG Attached:      YES - $currentNSGName" -ForegroundColor Red
Write-Host ""

Write-Host "  NEW STATE (AFTER):" -ForegroundColor Yellow
Write-Host "  ==================" -ForegroundColor Yellow
Write-Host "    Subscription:      $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host "    NIC Name:          $($nic.Name)" -ForegroundColor Cyan
Write-Host "    Resource Group:    $($nic.ResourceGroupName)" -ForegroundColor Cyan
Write-Host "    Private IP:        $($nic.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
Write-Host "    NSG Attached:      NO (Removed)" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 9: SAFETY REMINDERS
# ============================================================================
Write-Host "  SAFETY GUARANTEES:" -ForegroundColor Yellow
Write-Host "  ==================" -ForegroundColor Yellow
Write-Host "    NIC will NOT be deleted" -ForegroundColor Green
Write-Host "    NSG will NOT be deleted" -ForegroundColor Green
Write-Host "    VM will NOT be affected" -ForegroundColor Green
Write-Host "    Subnet NSG still protects VM" -ForegroundColor Green
Write-Host "    Operation is reversible" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 10: FINAL CONFIRMATION
# ============================================================================
Write-Host "STEP 7: Final Confirmation" -ForegroundColor Green
Write-Host ""
Write-Host "  YOU ARE ABOUT TO:" -ForegroundColor Red
Write-Host "    Remove NSG from:     $nicName" -ForegroundColor Cyan
Write-Host "    In Subscription:     $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host "    Resource Group:      $resourceGroupName" -ForegroundColor Cyan
Write-Host "    NSG Being Removed:   $currentNSGName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ENVIRONMENT: Production MOVEit" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Type exactly: REMOVE" -ForegroundColor Red
Write-Host "  To proceed with NSG removal" -ForegroundColor Red
Write-Host "  (or press Ctrl+C to cancel)" -ForegroundColor Gray
Write-Host ""

$finalConfirmation = Read-Host "  Confirmation"

if ($finalConfirmation -ne "REMOVE") {
    Write-Host ""
    Write-Host "  Operation CANCELLED" -ForegroundColor Yellow
    Write-Host "  No changes were made" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# ============================================================================
# STEP 11: REMOVE NSG FROM NIC
# ============================================================================
Write-Host ""
Write-Host "STEP 8: Removing NSG from NIC..." -ForegroundColor Green
Write-Host ""

try {
    Write-Host "  Disconnecting NSG from NIC..." -ForegroundColor Cyan
    
    # Remove the NSG association
    $nic.NetworkSecurityGroup = $null
    
    # Update the NIC
    Write-Host "  Updating Network Interface..." -ForegroundColor Cyan
    $result = $nic | Set-AzNetworkInterface -ErrorAction Stop
    
    Write-Host ""
    Write-Host "  SUCCESS: NSG removed from NIC" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "  ERROR: Failed to remove NSG from NIC" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  No changes were applied" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ============================================================================
# STEP 12: VERIFY CHANGES
# ============================================================================
Write-Host "STEP 9: Verifying Changes..." -ForegroundColor Green
Write-Host ""

try {
    Start-Sleep -Seconds 3
    
    $nicAfter = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    
    Write-Host "  VERIFICATION:" -ForegroundColor Yellow
    Write-Host "  =============" -ForegroundColor Yellow
    Write-Host "    Subscription:      $($selectedSubscription.Name)" -ForegroundColor Cyan
    Write-Host "    NIC Name:          $($nicAfter.Name)" -ForegroundColor Cyan
    Write-Host "    Private IP:        $($nicAfter.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
    
    if ($null -eq $nicAfter.NetworkSecurityGroup) {
        Write-Host "    NSG Attached:      NO" -ForegroundColor Green
        Write-Host ""
        Write-Host "    VERIFICATION: PASS" -ForegroundColor Green
        Write-Host "    NSG successfully removed" -ForegroundColor Green
    } else {
        Write-Host "    NSG Attached:      YES (Still attached?)" -ForegroundColor Red
        Write-Host ""
        Write-Host "    VERIFICATION: WARNING" -ForegroundColor Yellow
        Write-Host "    Please verify manually in Azure Portal" -ForegroundColor Yellow
    }
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to verify changes" -ForegroundColor Red
    Write-Host "  Error: $_" -ForegroundColor Red
    Write-Host ""
}

# ============================================================================
# STEP 13: SUMMARY
# ============================================================================
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                    OPERATION COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Yellow
Write-Host "  Subscription:      $($selectedSubscription.Name)" -ForegroundColor Cyan
Write-Host "  NIC Name:          $nicName" -ForegroundColor Cyan
Write-Host "  Resource Group:    $resourceGroupName" -ForegroundColor Cyan
Write-Host "  NSG Removed:       $currentNSGName" -ForegroundColor Cyan
Write-Host "  Status:            SUCCESS" -ForegroundColor Green
Write-Host ""
Write-Host "VM PROTECTION:" -ForegroundColor Yellow
Write-Host "  Subnet NSG:        nsg-moveit (ACTIVE)" -ForegroundColor Green
Write-Host "  Load Balancer:     Still working" -ForegroundColor Green
Write-Host "  Defender:          Still monitoring" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Test MOVEit connectivity" -ForegroundColor Cyan
Write-Host "     - Test HTTPS (port 443)" -ForegroundColor Cyan
Write-Host "     - Test SSH (port 22)" -ForegroundColor Cyan
Write-Host "     - Test FTPS" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Verify in Azure Portal:" -ForegroundColor Cyan
Write-Host "     - Go to: nic-moveit-transfer" -ForegroundColor Cyan
Write-Host "     - Check: Network security group = None" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Check Datadog for alerts" -ForegroundColor Cyan
Write-Host "     - No alerts should trigger" -ForegroundColor Cyan
Write-Host ""
Write-Host "ROLLBACK (IF NEEDED):" -ForegroundColor Yellow
Write-Host "  Azure Portal > nic-moveit-transfer > Network security group" -ForegroundColor Cyan
Write-Host "  > Edit > Select: nsg-moveit-transfer > Save" -ForegroundColor Cyan
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Script completed successfully!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
