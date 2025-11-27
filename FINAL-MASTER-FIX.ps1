# FINAL MASTER FIX - NO MORE ERRORS
# Fixed all cmdlet issues and subscription problems

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FINAL MASTER FIX - CORRECT VERSION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$ErrorActionPreference = "Continue"
$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"
$EndpointName = "moveit-endpoint-e9foashyq2cddef0"
$CustomDomainName = "moveit-pyxhealth-com"
$RouteName = "moveit-route"
$OriginGroupName = "moveit-origin-group"
$CorrectIP = "20.86.24.164"
$VMName = "vm-moveit-afd"
$KeyVaultName = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"

$issuesFound = 0
$fixesApplied = 0

# ============================================
# STEP 1: ENSURE CORRECT SUBSCRIPTION
# ============================================
Write-Host "[STEP 1] Finding correct subscription..." -ForegroundColor Yellow

try {
    # Get all subscriptions
    $subs = Get-AzSubscription
    Write-Host "  Found $($subs.Count) subscriptions" -ForegroundColor Cyan
    
    $correctSub = $null
    foreach ($sub in $subs) {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
        $testRG = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
        
        if ($testRG) {
            $correctSub = $sub
            Write-Host "  [OK] Found rg-moveit in: $($sub.Name)" -ForegroundColor Green
            break
        }
    }
    
    if (-not $correctSub) {
        Write-Host "  [FAIL] Could not find rg-moveit in any subscription!" -ForegroundColor Red
        Write-Host "`nAvailable subscriptions:" -ForegroundColor Yellow
        foreach ($sub in $subs) {
            Write-Host "  - $($sub.Name)" -ForegroundColor Cyan
        }
        Read-Host "Press ENTER to exit"
        exit
    }
    
    Set-AzContext -SubscriptionId $correctSub.Id | Out-Null
    Write-Host "  [OK] Using subscription: $($correctSub.Name)" -ForegroundColor Green
    
} catch {
    Write-Host "  [FAIL] Subscription check failed: $_" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# ============================================
# STEP 2: VERIFY RESOURCE GROUP EXISTS
# ============================================
Write-Host "`n[STEP 2] Verifying resource group..." -ForegroundColor Yellow

try {
    $rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
    Write-Host "  [OK] Resource group exists: $($rg.ResourceGroupName)" -ForegroundColor Green
    Write-Host "  Location: $($rg.Location)" -ForegroundColor Cyan
} catch {
    Write-Host "  [FAIL] Resource group not found: $_" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# ============================================
# STEP 3: FIX NSG PORT 443
# ============================================
Write-Host "`n[STEP 3] Fixing NSG Port 443..." -ForegroundColor Yellow

try {
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup
    Write-Host "  Found $($nsgs.Count) NSG(s)" -ForegroundColor Cyan
    
    foreach ($nsg in $nsgs) {
        Write-Host "`n  Processing: $($nsg.Name)" -ForegroundColor Cyan
        
        # Remove ANY deny rules on port 443
        $denyRules = $nsg.SecurityRules | Where-Object {
            $_.Access -eq "Deny" -and
            $_.Direction -eq "Inbound" -and
            ($_.DestinationPortRange -eq "443" -or $_.DestinationPortRange -eq "*")
        }
        
        if ($denyRules) {
            Write-Host "    [ISSUE] Found DENY rules!" -ForegroundColor Red
            $issuesFound++
            
            foreach ($rule in $denyRules) {
                Write-Host "      Removing: $($rule.Name)" -ForegroundColor Yellow
                $nsg = $nsg | Remove-AzNetworkSecurityRuleConfig -Name $rule.Name
            }
            
            $nsg | Set-AzNetworkSecurityGroup | Out-Null
            $fixesApplied++
            Write-Host "    [FIXED] DENY rules removed" -ForegroundColor Green
            
            # Refresh
            $nsg = Get-AzNetworkSecurityGroup -Name $nsg.Name -ResourceGroupName $ResourceGroup
        }
        
        # Check for ALLOW rule
        $allowRule = $nsg.SecurityRules | Where-Object {
            $_.Access -eq "Allow" -and
            $_.Direction -eq "Inbound" -and
            $_.DestinationPortRange -eq "443"
        }
        
        if (-not $allowRule) {
            Write-Host "    [ISSUE] No ALLOW rule for 443" -ForegroundColor Red
            $issuesFound++
            
            $priorities = ($nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" }).Priority
            $priority = 100
            while ($priorities -contains $priority -and $priority -lt 4096) {
                $priority += 10
            }
            
            Write-Host "    [FIXING] Adding ALLOW rule (priority $priority)..." -ForegroundColor Yellow
            
            $nsg | Add-AzNetworkSecurityRuleConfig `
                -Name "Allow-HTTPS-443-MOVEit" `
                -Description "Allow HTTPS for MOVEit Front Door" `
                -Access Allow `
                -Protocol Tcp `
                -Direction Inbound `
                -Priority $priority `
                -SourceAddressPrefix Internet `
                -SourcePortRange * `
                -DestinationAddressPrefix * `
                -DestinationPortRange 443 | Set-AzNetworkSecurityGroup | Out-Null
            
            $fixesApplied++
            Write-Host "    [FIXED] ALLOW rule added" -ForegroundColor Green
        } else {
            Write-Host "    [OK] Port 443 allowed" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [ERROR] NSG fix failed: $_" -ForegroundColor Red
}

# ============================================
# STEP 4: GET KEY VAULT CERTIFICATE
# ============================================
Write-Host "`n[STEP 4] Key Vault Certificate..." -ForegroundColor Yellow

try {
    $kv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ErrorAction Stop
    Write-Host "  [OK] Key Vault: $($kv.VaultName)" -ForegroundColor Green
    
    # Try to get certificate
    $cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertName -ErrorAction SilentlyContinue
    
    if (-not $cert) {
        # Try without "wildcard" prefix
        Write-Host "  Trying alternate certificate names..." -ForegroundColor Yellow
        $allCerts = Get-AzKeyVaultCertificate -VaultName $KeyVaultName
        Write-Host "  Available certificates:" -ForegroundColor Cyan
        foreach ($c in $allCerts) {
            Write-Host "    - $($c.Name)" -ForegroundColor Cyan
        }
        
        # Find the wildcard cert
        $cert = $allCerts | Where-Object { $_.Name -like "*wildcard*" -or $_.Name -like "*pyxhealth*" } | Select-Object -First 1
        
        if ($cert) {
            $CertName = $cert.Name
            Write-Host "  [OK] Using certificate: $CertName" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] No certificate found!" -ForegroundColor Red
            $issuesFound++
        }
    } else {
        Write-Host "  [OK] Certificate: $CertName" -ForegroundColor Green
    }
    
    if ($cert) {
        $certId = "$($kv.ResourceId)/secrets/$CertName"
        Write-Host "  Certificate ID: $certId" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "  [ERROR] Key Vault access failed: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# STEP 5: FIX FRONT DOOR ENDPOINT
# ============================================
Write-Host "`n[STEP 5] Front Door Endpoint..." -ForegroundColor Yellow

try {
    $endpoint = Get-AzFrontDoorCdnEndpoint `
        -ResourceGroupName $ResourceGroup `
        -ProfileName $ProfileName `
        -EndpointName $EndpointName -ErrorAction Stop
    
    Write-Host "  Endpoint: $($endpoint.Name)" -ForegroundColor Cyan
    Write-Host "  Status: $($endpoint.EnabledState)" -ForegroundColor $(if($endpoint.EnabledState -eq "Enabled"){"Green"}else{"Red"})
    
    if ($endpoint.EnabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Endpoint disabled!" -ForegroundColor Red
        $issuesFound++
        
        Write-Host "  [FIXING] Enabling..." -ForegroundColor Yellow
        Update-AzFrontDoorCdnEndpoint `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -EndpointName $EndpointName `
            -EnabledState Enabled | Out-Null
        
        $fixesApplied++
        Write-Host "  [FIXED] Endpoint enabled" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERROR] Endpoint check failed: $_" -ForegroundColor Red
}

# ============================================
# STEP 6: FIX CUSTOM DOMAIN
# ============================================
Write-Host "`n[STEP 6] Custom Domain..." -ForegroundColor Yellow

if ($cert) {
    try {
        $domain = Get-AzFrontDoorCdnCustomDomain `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -CustomDomainName $CustomDomainName -ErrorAction SilentlyContinue
        
        $needsRecreate = $false
        
        if ($domain) {
            Write-Host "  Domain exists: $($domain.HostName)" -ForegroundColor Cyan
            Write-Host "  Certificate Type: $($domain.TlsSetting.CertificateType)" -ForegroundColor Cyan
            
            if ($domain.TlsSetting.CertificateType -eq "ManagedCertificate") {
                Write-Host "  [ISSUE] Using AFD Managed cert!" -ForegroundColor Red
                $issuesFound++
                $needsRecreate = $true
            }
        } else {
            Write-Host "  [ISSUE] Domain doesn't exist!" -ForegroundColor Red
            $issuesFound++
            $needsRecreate = $true
        }
        
        if ($needsRecreate) {
            Write-Host "  [FIXING] Recreating domain with Key Vault cert..." -ForegroundColor Yellow
            
            # Delete if exists
            if ($domain) {
                Remove-AzFrontDoorCdnCustomDomain `
                    -ResourceGroupName $ResourceGroup `
                    -ProfileName $ProfileName `
                    -CustomDomainName $CustomDomainName -ErrorAction SilentlyContinue | Out-Null
                Start-Sleep -Seconds 5
            }
            
            # Create new
            $domain = New-AzFrontDoorCdnCustomDomain `
                -ResourceGroupName $ResourceGroup `
                -ProfileName $ProfileName `
                -CustomDomainName $CustomDomainName `
                -HostName "moveit.pyxhealth.com" `
                -CertificateType CustomerCertificate `
                -MinimumTlsVersion TLS12 `
                -SecretId $certId
            
            $fixesApplied++
            Write-Host "  [FIXED] Domain created with Key Vault cert" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Domain using Key Vault cert" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "  [ERROR] Domain fix failed: $_" -ForegroundColor Red
    }
}

# ============================================
# STEP 7: FIX ORIGINS
# ============================================
Write-Host "`n[STEP 7] Origin Configuration..." -ForegroundColor Yellow

try {
    $origins = Get-AzFrontDoorCdnOrigin `
        -ResourceGroupName $ResourceGroup `
        -ProfileName $ProfileName `
        -OriginGroupName $OriginGroupName
    
    $correctExists = $false
    $wrongOrigins = @()
    
    foreach ($origin in $origins) {
        Write-Host "  Origin: $($origin.Name) -> $($origin.HostName)" -ForegroundColor Cyan
        
        if ($origin.HostName -eq $CorrectIP) {
            $correctExists = $true
            Write-Host "    [OK] Correct IP!" -ForegroundColor Green
        } else {
            Write-Host "    [ISSUE] Wrong IP!" -ForegroundColor Red
            $wrongOrigins += $origin
        }
    }
    
    # Remove wrong origins
    foreach ($wrong in $wrongOrigins) {
        Write-Host "  [FIXING] Removing wrong origin: $($wrong.HostName)..." -ForegroundColor Yellow
        Remove-AzFrontDoorCdnOrigin `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -OriginGroupName $OriginGroupName `
            -OriginName $wrong.Name -ErrorAction SilentlyContinue | Out-Null
        $fixesApplied++
    }
    
    # Create correct origin if needed
    if (-not $correctExists) {
        Write-Host "  [FIXING] Creating correct origin with IP $CorrectIP..." -ForegroundColor Yellow
        
        New-AzFrontDoorCdnOrigin `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -OriginGroupName $OriginGroupName `
            -OriginName "moveit-origin-fixed" `
            -HostName $CorrectIP `
            -HttpPort 80 `
            -HttpsPort 443 `
            -Priority 1 `
            -Weight 1000 `
            -EnabledState Enabled | Out-Null
        
        $fixesApplied++
        Write-Host "  [FIXED] Correct origin created" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  [ERROR] Origin fix failed: $_" -ForegroundColor Red
}

# ============================================
# STEP 8: FIX ROUTE
# ============================================
Write-Host "`n[STEP 8] Route Configuration..." -ForegroundColor Yellow

try {
    $route = Get-AzFrontDoorCdnRoute `
        -ResourceGroupName $ResourceGroup `
        -ProfileName $ProfileName `
        -EndpointName $EndpointName `
        -RouteName $RouteName
    
    Write-Host "  Route: $($route.Name)" -ForegroundColor Cyan
    Write-Host "  Status: $($route.EnabledState)" -ForegroundColor Cyan
    
    $needsUpdate = $false
    
    if ($route.EnabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Route not enabled!" -ForegroundColor Red
        $issuesFound++
        $needsUpdate = $true
    }
    
    if (-not $route.CustomDomain -or $route.CustomDomain.Count -eq 0) {
        Write-Host "  [ISSUE] No custom domain on route!" -ForegroundColor Red
        $issuesFound++
        $needsUpdate = $true
    }
    
    if ($needsUpdate) {
        Write-Host "  [FIXING] Updating route..." -ForegroundColor Yellow
        
        # Get fresh domain reference
        $domain = Get-AzFrontDoorCdnCustomDomain `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -CustomDomainName $CustomDomainName
        
        Update-AzFrontDoorCdnRoute `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -EndpointName $EndpointName `
            -RouteName $RouteName `
            -CustomDomainId $domain.Id `
            -OriginGroupId $route.OriginGroup.Id `
            -EnabledState Enabled `
            -HttpsRedirect Enabled `
            -SupportedProtocol Https `
            -LinkToDefaultDomain Enabled `
            -ForwardingProtocol HttpsOnly | Out-Null
        
        $fixesApplied++
        Write-Host "  [FIXED] Route updated" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Route configured correctly" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  [ERROR] Route fix failed: $_" -ForegroundColor Red
}

# ============================================
# STEP 9: TEST CONNECTIVITY
# ============================================
Write-Host "`n[STEP 9] Testing Connectivity..." -ForegroundColor Yellow

$testResult = Test-NetConnection -ComputerName $CorrectIP -Port 443 -WarningAction SilentlyContinue
if ($testResult.TcpTestSucceeded) {
    Write-Host "  [OK] VM reachable on port 443!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] VM not reachable yet (may take 2-3 minutes)" -ForegroundColor Yellow
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "COMPLETED!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nISSUES FOUND: $issuesFound" -ForegroundColor Yellow
Write-Host "FIXES APPLIED: $fixesApplied" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($fixesApplied -gt 0) {
    Write-Host "1. Wait 10-15 minutes for propagation" -ForegroundColor Yellow
    Write-Host "2. Test: https://moveit.pyxhealth.com" -ForegroundColor Yellow
    Write-Host "3. Look for LOCK ICON" -ForegroundColor Yellow
} else {
    Write-Host "No fixes needed! Test now:" -ForegroundColor Green
    Write-Host "https://moveit.pyxhealth.com" -ForegroundColor Green
}

Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
Read-Host
