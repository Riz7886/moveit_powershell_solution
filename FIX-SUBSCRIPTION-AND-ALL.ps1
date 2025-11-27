# FIX SUBSCRIPTION AND EVERYTHING ELSE
# This will find the right subscription and fix all issues

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUBSCRIPTION FIX + COMPLETE REPAIR" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# STEP 1: Find the correct subscription
Write-Host "[STEP 1] Finding subscription with rg-moveit..." -ForegroundColor Yellow

$subscriptions = Get-AzSubscription
$targetSubscription = $null

foreach ($sub in $subscriptions) {
    Write-Host "  Checking subscription: $($sub.Name)..." -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $sub.Id | Out-Null
    
    $rg = Get-AzResourceGroup -Name "rg-moveit" -ErrorAction SilentlyContinue
    if ($rg) {
        Write-Host "  [FOUND] rg-moveit in subscription: $($sub.Name)" -ForegroundColor Green
        $targetSubscription = $sub
        break
    }
}

if ($null -eq $targetSubscription) {
    Write-Host "  [FAIL] Could not find rg-moveit in any subscription!" -ForegroundColor Red
    Write-Host "`nAvailable subscriptions:" -ForegroundColor Yellow
    foreach ($sub in $subscriptions) {
        Write-Host "  - $($sub.Name)" -ForegroundColor Cyan
    }
    Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
    Read-Host
    exit
}

Write-Host "  [OK] Using subscription: $($targetSubscription.Name)" -ForegroundColor Green

# STEP 2: Set variables
$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"
$EndpointName = "moveit-endpoint-e9foashyq2cddef0"
$CustomDomainName = "moveit-pyxhealth-com"
$RouteName = "moveit-route"
$OriginGroupName = "moveit-origin-group"
$CorrectIP = "20.86.24.164"
$KeyVaultName = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

# STEP 3: Open Port 443 on ALL NSGs
Write-Host "`n[STEP 2] Opening Port 443 on ALL NSGs..." -ForegroundColor Yellow

$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup

foreach ($nsg in $nsgs) {
    Write-Host "  Checking NSG: $($nsg.Name)..." -ForegroundColor Cyan
    
    # Check if port 443 rule exists and is allowed
    $rule443 = $nsg.SecurityRules | Where-Object {
        $_.DestinationPortRange -eq "443" -and
        $_.Access -eq "Allow" -and
        $_.Direction -eq "Inbound"
    }
    
    if (-not $rule443) {
        Write-Host "    Adding rule to allow port 443..." -ForegroundColor Yellow
        $nsg | Add-AzNetworkSecurityRuleConfig `
            -Name "Allow-HTTPS-443" `
            -Description "Allow HTTPS traffic" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority 1000 `
            -SourceAddressPrefix Internet `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 443 | Set-AzNetworkSecurityGroup | Out-Null
        Write-Host "    [OK] Port 443 opened!" -ForegroundColor Green
    } else {
        Write-Host "    [OK] Port 443 already open" -ForegroundColor Green
    }
}

# STEP 4: Get Key Vault certificate ID
Write-Host "`n[STEP 3] Getting Key Vault certificate..." -ForegroundColor Yellow
$keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup
$certId = "$($keyVault.ResourceId)/secrets/$CertName"
Write-Host "  [OK] Certificate ID: $certId" -ForegroundColor Green

# STEP 5: Delete and recreate custom domain with Key Vault cert
Write-Host "`n[STEP 4] Fixing custom domain with Key Vault certificate..." -ForegroundColor Yellow

Write-Host "  Deleting old domain..." -ForegroundColor Yellow
Remove-AzFrontDoorCdnCustomDomain `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -CustomDomainName $CustomDomainName `
    -ErrorAction SilentlyContinue | Out-Null

Write-Host "  Creating new domain with Key Vault cert..." -ForegroundColor Yellow
$customDomain = New-AzFrontDoorCdnCustomDomain `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -CustomDomainName $CustomDomainName `
    -HostName "moveit.pyxhealth.com" `
    -CertificateType CustomerCertificate `
    -MinimumTlsVersion TLS12 `
    -SecretId $certId

Write-Host "  [OK] Domain created with Key Vault certificate!" -ForegroundColor Green

# STEP 6: Fix origins - delete wrong ones, create correct one
Write-Host "`n[STEP 5] Fixing origin IP addresses..." -ForegroundColor Yellow

$origins = Get-AzFrontDoorCdnOrigin `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -OriginGroupName $OriginGroupName

foreach ($origin in $origins) {
    if ($origin.HostName -ne $CorrectIP) {
        Write-Host "  Deleting wrong origin: $($origin.HostName)..." -ForegroundColor Yellow
        Remove-AzFrontDoorCdnOrigin `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -OriginGroupName $OriginGroupName `
            -OriginName $origin.Name `
            -ErrorAction SilentlyContinue | Out-Null
    }
}

# Check if correct origin exists
$correctOrigin = Get-AzFrontDoorCdnOrigin `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -OriginGroupName $OriginGroupName `
    -ErrorAction SilentlyContinue | Where-Object { $_.HostName -eq $CorrectIP }

if (-not $correctOrigin) {
    Write-Host "  Creating correct origin with IP: $CorrectIP..." -ForegroundColor Yellow
    New-AzFrontDoorCdnOrigin `
        -ResourceGroupName $ResourceGroup `
        -ProfileName $ProfileName `
        -OriginGroupName $OriginGroupName `
        -OriginName "moveit-origin" `
        -HostName $CorrectIP `
        -HttpPort 80 `
        -HttpsPort 443 `
        -Priority 1 `
        -Weight 1000 `
        -EnabledState Enabled | Out-Null
    Write-Host "  [OK] Correct origin created!" -ForegroundColor Green
} else {
    Write-Host "  [OK] Correct origin already exists!" -ForegroundColor Green
}

# STEP 7: Enable endpoint
Write-Host "`n[STEP 6] Enabling endpoint..." -ForegroundColor Yellow
Update-AzFrontDoorCdnEndpoint `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -EndpointName $EndpointName `
    -EnabledState Enabled | Out-Null
Write-Host "  [OK] Endpoint enabled!" -ForegroundColor Green

# STEP 8: Update route to associate custom domain
Write-Host "`n[STEP 7] Associating custom domain with route..." -ForegroundColor Yellow

$route = Get-AzFrontDoorCdnRoute `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -EndpointName $EndpointName `
    -RouteName $RouteName

Update-AzFrontDoorCdnRoute `
    -ResourceGroupName $ResourceGroup `
    -ProfileName $ProfileName `
    -EndpointName $EndpointName `
    -RouteName $RouteName `
    -CustomDomainId $customDomain.Id `
    -OriginGroupId $route.OriginGroup.Id `
    -EnabledState Enabled `
    -HttpsRedirect Enabled `
    -SupportedProtocol Https `
    -LinkToDefaultDomain Enabled `
    -ForwardingProtocol HttpsOnly | Out-Null

Write-Host "  [OK] Domain associated with route!" -ForegroundColor Green

# STEP 9: Test VM connectivity
Write-Host "`n[STEP 8] Testing VM connectivity..." -ForegroundColor Yellow
$testResult = Test-NetConnection -ComputerName $CorrectIP -Port 443 -WarningAction SilentlyContinue
if ($testResult.TcpTestSucceeded) {
    Write-Host "  [OK] VM is reachable on port 443!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] VM not reachable yet - may need to wait for NSG update" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ALL FIXES APPLIED!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 10-15 minutes for changes to propagate" -ForegroundColor Cyan
Write-Host "2. Test: https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host "3. Look for LOCK ICON in browser" -ForegroundColor Cyan
Write-Host "4. Test upload/download" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
Read-Host
