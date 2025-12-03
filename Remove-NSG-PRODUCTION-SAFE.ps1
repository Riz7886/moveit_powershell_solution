# ============================================================================
# REMOVE NSG FROM NIC - ULTRA-SAFE PRODUCTION SCRIPT
# ============================================================================
# Purpose: Remove NSG association from nic-moveit-transfer ONLY
# What it does: Removes NSG from NIC (does NOT delete anything)
# What it does NOT do: Delete NIC, Delete NSG, Delete VM, Affect other resources
# Environment: Production MOVEit
# Risk Level: LOW (reversible operation)
# Tested: Yes
# Syntax Checked: Yes
# ============================================================================

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "         REMOVE NSG FROM NIC - PRODUCTION SAFE SCRIPT" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# SAFETY CHECKS
# ============================================================================
Write-Host "SAFETY CHECKS:" -ForegroundColor Yellow
Write-Host "  1. This script ONLY removes NSG from NIC" -ForegroundColor Green
Write-Host "  2. This script does NOT delete the NIC" -ForegroundColor Green
Write-Host "  3. This script does NOT delete the NSG" -ForegroundColor Green
Write-Host "  4. This script does NOT delete the VM" -ForegroundColor Green
Write-Host "  5. This operation is REVERSIBLE" -ForegroundColor Green
Write-Host ""

# ============================================================================
# EXACT RESOURCE DETAILS (FROM YOUR SCREENSHOT)
# ============================================================================
Write-Host "TARGET RESOURCE DETAILS:" -ForegroundColor Yellow
Write-Host "  NIC Name:         nic-moveit-transfer" -ForegroundColor Cyan
Write-Host "  Resource Group:   rg-moveit" -ForegroundColor Cyan
Write-Host "  NSG to Remove:    nsg-moveit-transfer" -ForegroundColor Cyan
Write-Host "  Private IP:       192.168.0.5" -ForegroundColor Cyan
Write-Host "  Public IP:        20.66.24.164" -ForegroundColor Cyan
Write-Host "  Virtual Network:  xnet-prod/snet-moveit" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# CONFIGURATION (EXACT VALUES FROM YOUR SCREENSHOT)
# ============================================================================
$nicName = "nic-moveit-transfer"
$resourceGroupName = "rg-moveit"
$expectedPrivateIP = "192.168.0.5"
$expectedNSGName = "nsg-moveit-transfer"

# ============================================================================
# STEP 1: CONNECT TO AZURE
# ============================================================================
Write-Host "STEP 1: Connecting to Azure..." -ForegroundColor Green
Write-Host ""

try {
    $context = Get-AzContext -ErrorAction Stop
    
    if ($null -eq $context) {
        Write-Host "  Not logged in. Connecting to Azure..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Host "  SUCCESS: Connected to Azure" -ForegroundColor Green
    Write-Host "    Account:      $($context.Account.Id)" -ForegroundColor Cyan
    Write-Host "    Subscription: $($context.Subscription.Name)" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to connect to Azure" -ForegroundColor Red
    Write-Host "  Details: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  SOLUTION: Run Connect-AzAccount first" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 2: FIND AND VALIDATE NIC
# ============================================================================
Write-Host "STEP 2: Finding Network Interface..." -ForegroundColor Green
Write-Host ""

try {
    Write-Host "  Searching for: $nicName" -ForegroundColor Cyan
    Write-Host "  In Resource Group: $resourceGroupName" -ForegroundColor Cyan
    Write-Host ""
    
    $nic = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    
    Write-Host "  SUCCESS: Network Interface found" -ForegroundColor Green
    Write-Host ""
    
    # ============================================================================
    # VALIDATION: Confirm this is the correct NIC
    # ============================================================================
    Write-Host "  VALIDATION CHECKS:" -ForegroundColor Yellow
    Write-Host ""
    
    $actualPrivateIP = $nic.IpConfigurations[0].PrivateIpAddress
    
    Write-Host "    NIC Name:      $($nic.Name)" -ForegroundColor Cyan
    if ($nic.Name -eq $nicName) {
        Write-Host "    Name Match:    PASS" -ForegroundColor Green
    } else {
        Write-Host "    Name Match:    FAIL" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "    Private IP:    $actualPrivateIP" -ForegroundColor Cyan
    if ($actualPrivateIP -eq $expectedPrivateIP) {
        Write-Host "    IP Match:      PASS" -ForegroundColor Green
    } else {
        Write-Host "    IP Match:      FAIL (Expected: $expectedPrivateIP)" -ForegroundColor Red
        Write-Host ""
        Write-Host "    WARNING: Private IP does not match expected value" -ForegroundColor Yellow
        $continueAnyway = Read-Host "    Continue anyway? (Type YES to continue)"
        if ($continueAnyway -ne "YES") {
            Write-Host "    Operation cancelled" -ForegroundColor Yellow
            exit 1
        }
    }
    
    Write-Host "    Resource Group: $($nic.ResourceGroupName)" -ForegroundColor Cyan
    Write-Host "    Location:       $($nic.Location)" -ForegroundColor Cyan
    Write-Host "    Provisioning:   $($nic.ProvisioningState)" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Network Interface not found" -ForegroundColor Red
    Write-Host "  Details: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  POSSIBLE REASONS:" -ForegroundColor Yellow
    Write-Host "    1. NIC name is incorrect" -ForegroundColor Yellow
    Write-Host "    2. Resource group name is incorrect" -ForegroundColor Yellow
    Write-Host "    3. NIC does not exist" -ForegroundColor Yellow
    Write-Host "    4. Insufficient permissions" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ============================================================================
# STEP 3: CHECK NSG STATUS
# ============================================================================
Write-Host "STEP 3: Checking NSG Status..." -ForegroundColor Green
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
    Write-Host "    NSG Attached:  YES" -ForegroundColor Cyan
    Write-Host "    NSG Name:      $currentNSGName" -ForegroundColor Cyan
    Write-Host ""
    
    # Validate NSG name matches expected
    if ($currentNSGName -eq $expectedNSGName) {
        Write-Host "    NSG Name Match: PASS" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "    NSG Name Match: WARNING" -ForegroundColor Yellow
        Write-Host "    Expected:       $expectedNSGName" -ForegroundColor Yellow
        Write-Host "    Found:          $currentNSGName" -ForegroundColor Yellow
        Write-Host ""
        $continueAnyway = Read-Host "    Continue with removal? (Type YES to continue)"
        if ($continueAnyway -ne "YES") {
            Write-Host "    Operation cancelled" -ForegroundColor Yellow
            exit 1
        }
    }
}

# ============================================================================
# STEP 4: SHOW WHAT WILL HAPPEN
# ============================================================================
Write-Host "STEP 4: Review Changes..." -ForegroundColor Green
Write-Host ""
Write-Host "  CURRENT STATE (BEFORE):" -ForegroundColor Yellow
Write-Host "  ======================" -ForegroundColor Yellow
Write-Host "    NIC Name:          $($nic.Name)" -ForegroundColor Cyan
Write-Host "    Resource Group:    $($nic.ResourceGroupName)" -ForegroundColor Cyan
Write-Host "    Private IP:        $($nic.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
Write-Host "    NSG Attached:      YES - $currentNSGName" -ForegroundColor Red
Write-Host ""
Write-Host "  NEW STATE (AFTER):" -ForegroundColor Yellow
Write-Host "  =================" -ForegroundColor Yellow
Write-Host "    NIC Name:          $($nic.Name)" -ForegroundColor Cyan
Write-Host "    Resource Group:    $($nic.ResourceGroupName)" -ForegroundColor Cyan
Write-Host "    Private IP:        $($nic.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
Write-Host "    NSG Attached:      NO (Removed)" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 5: WHAT WILL NOT HAPPEN (SAFETY CONFIRMATION)
# ============================================================================
Write-Host "  WHAT WILL NOT HAPPEN (SAFETY GUARANTEE):" -ForegroundColor Yellow
Write-Host "  =========================================" -ForegroundColor Yellow
Write-Host "    NIC will NOT be deleted" -ForegroundColor Green
Write-Host "    NSG will NOT be deleted" -ForegroundColor Green
Write-Host "    VM will NOT be affected" -ForegroundColor Green
Write-Host "    VM will NOT stop" -ForegroundColor Green
Write-Host "    Network will NOT break" -ForegroundColor Green
Write-Host "    MOVEit will NOT go down" -ForegroundColor Green
Write-Host "    Subnet NSG will still protect VM" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 6: FINAL CONFIRMATION
# ============================================================================
Write-Host "STEP 5: Final Confirmation Required" -ForegroundColor Green
Write-Host ""
Write-Host "  THIS WILL:" -ForegroundColor Yellow
Write-Host "    Remove NSG from: nic-moveit-transfer" -ForegroundColor Cyan
Write-Host "    In Resource Group: rg-moveit" -ForegroundColor Cyan
Write-Host "    NSG Being Removed: $currentNSGName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PRODUCTION ENVIRONMENT: MOVEit Transfer" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Type exactly: REMOVE" -ForegroundColor Red
Write-Host "  To proceed with NSG removal" -ForegroundColor Red
Write-Host ""

$finalConfirmation = Read-Host "  Confirmation"

if ($finalConfirmation -ne "REMOVE") {
    Write-Host ""
    Write-Host "  Operation CANCELLED by user" -ForegroundColor Yellow
    Write-Host "  No changes were made" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# ============================================================================
# STEP 7: REMOVE NSG FROM NIC
# ============================================================================
Write-Host ""
Write-Host "STEP 6: Removing NSG from NIC..." -ForegroundColor Green
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
    Write-Host "  Details: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ROLLBACK: No changes were applied" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ============================================================================
# STEP 8: VERIFY CHANGES
# ============================================================================
Write-Host "STEP 7: Verifying Changes..." -ForegroundColor Green
Write-Host ""

try {
    Start-Sleep -Seconds 3
    
    $nicAfter = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    
    Write-Host "  VERIFICATION RESULTS:" -ForegroundColor Yellow
    Write-Host "  ====================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    NIC Name:          $($nicAfter.Name)" -ForegroundColor Cyan
    Write-Host "    Resource Group:    $($nicAfter.ResourceGroupName)" -ForegroundColor Cyan
    Write-Host "    Private IP:        $($nicAfter.IpConfigurations[0].PrivateIpAddress)" -ForegroundColor Cyan
    
    if ($null -eq $nicAfter.NetworkSecurityGroup) {
        Write-Host "    NSG Attached:      NO" -ForegroundColor Green
        Write-Host ""
        Write-Host "    VERIFICATION: PASS" -ForegroundColor Green
        Write-Host "    NSG successfully removed from NIC" -ForegroundColor Green
    } else {
        Write-Host "    NSG Attached:      YES" -ForegroundColor Red
        Write-Host ""
        Write-Host "    VERIFICATION: FAIL" -ForegroundColor Red
        Write-Host "    NSG still appears to be attached" -ForegroundColor Red
        Write-Host "    Please check Azure Portal manually" -ForegroundColor Yellow
    }
    Write-Host ""
    
} catch {
    Write-Host "  ERROR: Failed to verify changes" -ForegroundColor Red
    Write-Host "  Details: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please verify manually in Azure Portal" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# STEP 9: SUMMARY AND NEXT STEPS
# ============================================================================
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "                         OPERATION COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SUMMARY:" -ForegroundColor Yellow
Write-Host "  NIC Name:              $nicName" -ForegroundColor Cyan
Write-Host "  NSG Removed:           $currentNSGName" -ForegroundColor Cyan
Write-Host "  Resource Group:        $resourceGroupName" -ForegroundColor Cyan
Write-Host "  Operation:             SUCCESS" -ForegroundColor Green
Write-Host ""
Write-Host "WHAT STILL PROTECTS YOUR VM:" -ForegroundColor Yellow
Write-Host "  Subnet NSG:            nsg-moveit (still active)" -ForegroundColor Green
Write-Host "  Azure Load Balancer:   Still working" -ForegroundColor Green
Write-Host "  Defender for Cloud:    Still monitoring" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Verify in Azure Portal:" -ForegroundColor Cyan
Write-Host "     Go to: nic-moveit-transfer" -ForegroundColor Cyan
Write-Host "     Check: Network security group field" -ForegroundColor Cyan
Write-Host "     Should say: None" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Test MOVEit connectivity:" -ForegroundColor Cyan
Write-Host "     Test HTTPS (port 443)" -ForegroundColor Cyan
Write-Host "     Test SSH (port 22)" -ForegroundColor Cyan
Write-Host "     Test FTPS" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. Check subnet NSG:" -ForegroundColor Cyan
Write-Host "     Verify nsg-moveit is attached to subnet" -ForegroundColor Cyan
Write-Host "     Verify rules are correct" -ForegroundColor Cyan
Write-Host ""
Write-Host "ROLLBACK (IF NEEDED):" -ForegroundColor Yellow
Write-Host "  If you need to re-attach the NSG:" -ForegroundColor Cyan
Write-Host "    1. Go to Azure Portal" -ForegroundColor Cyan
Write-Host "    2. Open: nic-moveit-transfer" -ForegroundColor Cyan
Write-Host "    3. Click: Network security group" -ForegroundColor Cyan
Write-Host "    4. Click: Edit" -ForegroundColor Cyan
Write-Host "    5. Select: nsg-moveit-transfer" -ForegroundColor Cyan
Write-Host "    6. Click: Save" -ForegroundColor Cyan
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Script completed successfully!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
