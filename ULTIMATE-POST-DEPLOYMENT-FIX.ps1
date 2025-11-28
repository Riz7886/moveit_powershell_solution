# ULTIMATE-POST-DEPLOYMENT-FIX.ps1
# Run this AFTER deploying 5-story scripts
# Checks and fixes EVERYTHING: Certs, Routes, DNS, Origins, NSG, Endpoints

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ULTIMATE POST-DEPLOYMENT FIX" -ForegroundColor Cyan
Write-Host "Checks and fixes EVERYTHING" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$ErrorActionPreference = "Continue"

# CONFIGURATION
$RG = "rg-moveit"
$FDProfile = "moveit-frontdoor-profile"
$FDEndpoint = "moveit-endpoint-e9foashyq2cddef0"
$CustomDomainName = "moveit-pyxhealth-com"
$RouteName = "moveit-route"
$OriginGroupName = "moveit-origin-group"
$KeyVaultName = "kv-moveit-prod"
$CertName = "wildcardpyxhealth"
$VMName = "vm-moveit-afd"
$Domain = "moveit.pyxhealth.com"
$CorrectIP = "20.86.24.141"  # THE IP THAT WORKED!

$issuesFound = 0
$fixesApplied = 0

# ============================================
# CHECK 1: AZURE LOGIN
# ============================================
Write-Host "[CHECK 1] Azure Login..." -ForegroundColor Yellow
$context = Get-AzContext
if ($null -eq $context) {
    Write-Host "  [FIXING] Logging in..." -ForegroundColor Red
    Connect-AzAccount
    $fixesApplied++
}
Write-Host "  [OK] Logged in as: $($context.Account)" -ForegroundColor Green

# Find correct subscription
Write-Host "`n[CHECK 2] Finding subscription with rg-moveit..." -ForegroundColor Yellow
$subs = Get-AzSubscription
$correctSub = $null

foreach ($sub in $subs) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    $rg = Get-AzResourceGroup -Name $RG -ErrorAction SilentlyContinue
    if ($rg) {
        $correctSub = $sub
        Write-Host "  [OK] Using: $($sub.Name)" -ForegroundColor Green
        break
    }
}

if (-not $correctSub) {
    Write-Host "  [FAIL] Cannot find rg-moveit!" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# ============================================
# CHECK 2: VM STATUS
# ============================================
Write-Host "`n[CHECK 3] VM Status..." -ForegroundColor Yellow
try {
    $vm = Get-AzVM -ResourceGroupName $RG -Name $VMName -Status
    $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
    
    if ($powerState -ne "VM running") {
        Write-Host "  [ISSUE] VM not running: $powerState" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [FIXING] Starting VM..." -ForegroundColor Yellow
        Start-AzVM -ResourceGroupName $RG -Name $VMName -NoWait | Out-Null
        $fixesApplied++
    } else {
        Write-Host "  [OK] VM is running" -ForegroundColor Green
    }
} catch {
    Write-Host "  [WARNING] Cannot check VM status" -ForegroundColor Yellow
}

# ============================================
# CHECK 3: NSG PORT 443
# ============================================
Write-Host "`n[CHECK 4] NSG Port 443..." -ForegroundColor Yellow
$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $RG

foreach ($nsg in $nsgs) {
    Write-Host "  Checking: $($nsg.Name)" -ForegroundColor Cyan
    
    # Remove deny rules
    $denyRules = $nsg.SecurityRules | Where-Object {
        $_.Access -eq "Deny" -and
        $_.Direction -eq "Inbound" -and
        ($_.DestinationPortRange -eq "443" -or $_.DestinationPortRange -eq "*")
    }
    
    if ($denyRules) {
        $issuesFound++
        foreach ($rule in $denyRules) {
            Write-Host "    [FIXING] Removing deny rule: $($rule.Name)" -ForegroundColor Yellow
            $nsg = $nsg | Remove-AzNetworkSecurityRuleConfig -Name $rule.Name
        }
        $nsg | Set-AzNetworkSecurityGroup | Out-Null
        $fixesApplied++
    }
    
    # Check allow rule
    $allowRule = $nsg.SecurityRules | Where-Object {
        $_.Access -eq "Allow" -and
        $_.Direction -eq "Inbound" -and
        $_.DestinationPortRange -eq "443"
    }
    
    if (-not $allowRule) {
        $issuesFound++
        Write-Host "    [FIXING] Adding allow rule for 443..." -ForegroundColor Yellow
        
        $priorities = ($nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" }).Priority
        $priority = 100
        while ($priorities -contains $priority) { $priority += 10 }
        
        $nsg | Add-AzNetworkSecurityRuleConfig `
            -Name "Allow-HTTPS-443" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority $priority `
            -SourceAddressPrefix Internet `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 443 | Set-AzNetworkSecurityGroup | Out-Null
        
        $fixesApplied++
    } else {
        Write-Host "    [OK] Port 443 open" -ForegroundColor Green
    }
}

# ============================================
# CHECK 4: KEY VAULT CERTIFICATE
# ============================================
Write-Host "`n[CHECK 5] Key Vault Certificate..." -ForegroundColor Yellow

$kv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $RG -ErrorAction SilentlyContinue
if (-not $kv) {
    Write-Host "  [FAIL] Key Vault not found!" -ForegroundColor Red
    $issuesFound++
} else {
    Write-Host "  [OK] Key Vault found: $($kv.VaultName)" -ForegroundColor Green
    
    # Check certificate
    $cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertName -ErrorAction SilentlyContinue
    
    if (-not $cert) {
        # Try to find any wildcard cert
        Write-Host "  [WARNING] Certificate $CertName not found, searching..." -ForegroundColor Yellow
        $allCerts = Get-AzKeyVaultCertificate -VaultName $KeyVaultName
        $cert = $allCerts | Where-Object { $_.Name -like "*wildcard*" -or $_.Name -like "*pyxhealth*" } | Select-Object -First 1
        
        if ($cert) {
            $CertName = $cert.Name
            Write-Host "  [OK] Using certificate: $CertName" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] NO certificate found in Key Vault!" -ForegroundColor Red
            $issuesFound++
        }
    } else {
        Write-Host "  [OK] Certificate exists: $CertName" -ForegroundColor Green
    }
    
    if ($cert) {
        $certId = "$($kv.ResourceId)/secrets/$CertName"
        Write-Host "  Certificate ID: $certId" -ForegroundColor Cyan
    }
}

# ============================================
# CHECK 5: FRONT DOOR ENDPOINT
# ============================================
Write-Host "`n[CHECK 6] Front Door Endpoint..." -ForegroundColor Yellow

$endpoint = Get-AzFrontDoorCdnEndpoint -ResourceGroupName $RG -ProfileName $FDProfile -EndpointName $FDEndpoint -ErrorAction SilentlyContinue

if (-not $endpoint) {
    Write-Host "  [FAIL] Endpoint not found! Did you deploy 5-story?" -ForegroundColor Red
    $issuesFound++
} else {
    Write-Host "  Endpoint: $($endpoint.HostName)" -ForegroundColor Cyan
    Write-Host "  Status: $($endpoint.EnabledState)" -ForegroundColor Cyan
    
    if ($endpoint.EnabledState -ne "Enabled") {
        $issuesFound++
        Write-Host "  [FIXING] Enabling endpoint..." -ForegroundColor Yellow
        Update-AzFrontDoorCdnEndpoint -ResourceGroupName $RG -ProfileName $FDProfile -EndpointName $FDEndpoint -EnabledState Enabled | Out-Null
        $fixesApplied++
    } else {
        Write-Host "  [OK] Endpoint enabled" -ForegroundColor Green
    }
}

# ============================================
# CHECK 6: CUSTOM DOMAIN & CERTIFICATE
# ============================================
Write-Host "`n[CHECK 7] Custom Domain & Certificate..." -ForegroundColor Yellow

$domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $RG -ProfileName $FDProfile -CustomDomainName $CustomDomainName -ErrorAction SilentlyContinue

if (-not $domain) {
    Write-Host "  [FAIL] Custom domain not found!" -ForegroundColor Red
    $issuesFound++
    
    if ($cert) {
        Write-Host "  [FIXING] Creating custom domain with Key Vault cert..." -ForegroundColor Yellow
        New-AzFrontDoorCdnCustomDomain `
            -ResourceGroupName $RG `
            -ProfileName $FDProfile `
            -CustomDomainName $CustomDomainName `
            -HostName $Domain `
            -CertificateType CustomerCertificate `
            -MinimumTlsVersion TLS12 `
            -SecretId $certId | Out-Null
        $fixesApplied++
        
        # Refresh
        Start-Sleep -Seconds 5
        $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $RG -ProfileName $FDProfile -CustomDomainName $CustomDomainName
    }
} else {
    Write-Host "  Domain: $($domain.HostName)" -ForegroundColor Cyan
    Write-Host "  Provisioning: $($domain.ProvisioningState)" -ForegroundColor Cyan
    Write-Host "  Validation: $($domain.DomainValidationState)" -ForegroundColor Cyan
    Write-Host "  Cert Type: $($domain.TlsSetting.CertificateType)" -ForegroundColor Cyan
    
    # Check if using wrong cert type
    if ($domain.TlsSetting.CertificateType -ne "CustomerCertificate") {
        $issuesFound++
        Write-Host "  [ISSUE] Using AFD managed cert instead of Key Vault!" -ForegroundColor Red
        Write-Host "  [FIXING] Switching to Key Vault certificate..." -ForegroundColor Yellow
        
        # Delete and recreate
        Remove-AzFrontDoorCdnCustomDomain -ResourceGroupName $RG -ProfileName $FDProfile -CustomDomainName $CustomDomainName | Out-Null
        Start-Sleep -Seconds 5
        
        New-AzFrontDoorCdnCustomDomain `
            -ResourceGroupName $RG `
            -ProfileName $FDProfile `
            -CustomDomainName $CustomDomainName `
            -HostName $Domain `
            -CertificateType CustomerCertificate `
            -MinimumTlsVersion TLS12 `
            -SecretId $certId | Out-Null
        
        $fixesApplied++
        
        # Refresh
        Start-Sleep -Seconds 5
        $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $RG -ProfileName $FDProfile -CustomDomainName $CustomDomainName
        Write-Host "  [OK] Switched to Key Vault certificate!" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Using Key Vault certificate" -ForegroundColor Green
    }
}

# ============================================
# CHECK 7: ORIGINS
# ============================================
Write-Host "`n[CHECK 8] Origin Configuration..." -ForegroundColor Yellow

$origins = Get-AzFrontDoorCdnOrigin -ResourceGroupName $RG -ProfileName $FDProfile -OriginGroupName $OriginGroupName -ErrorAction SilentlyContinue

if (-not $origins) {
    Write-Host "  [FAIL] No origins found!" -ForegroundColor Red
    $issuesFound++
} else {
    $correctExists = $false
    $wrongOrigins = @()
    
    foreach ($origin in $origins) {
        Write-Host "  Origin: $($origin.Name) -> $($origin.HostName)" -ForegroundColor Cyan
        
        if ($origin.HostName -eq $CorrectIP) {
            $correctExists = $true
            Write-Host "    [OK] Correct IP!" -ForegroundColor Green
            
            if ($origin.EnabledState -ne "Enabled") {
                $issuesFound++
                Write-Host "    [FIXING] Enabling origin..." -ForegroundColor Yellow
                Update-AzFrontDoorCdnOrigin -ResourceGroupName $RG -ProfileName $FDProfile -OriginGroupName $OriginGroupName -OriginName $origin.Name -EnabledState Enabled | Out-Null
                $fixesApplied++
            }
        } else {
            Write-Host "    [ISSUE] Wrong IP!" -ForegroundColor Red
            $wrongOrigins += $origin
        }
    }
    
    # Remove wrong origins
    foreach ($wrong in $wrongOrigins) {
        $issuesFound++
        Write-Host "  [FIXING] Removing wrong origin: $($wrong.HostName)" -ForegroundColor Yellow
        Remove-AzFrontDoorCdnOrigin -ResourceGroupName $RG -ProfileName $FDProfile -OriginGroupName $OriginGroupName -OriginName $wrong.Name | Out-Null
        $fixesApplied++
    }
    
    # Create correct origin if missing
    if (-not $correctExists) {
        $issuesFound++
        Write-Host "  [FIXING] Creating correct origin with IP $CorrectIP..." -ForegroundColor Yellow
        
        New-AzFrontDoorCdnOrigin `
            -ResourceGroupName $RG `
            -ProfileName $FDProfile `
            -OriginGroupName $OriginGroupName `
            -OriginName "moveit-backend-correct" `
            -HostName $CorrectIP `
            -HttpPort 80 `
            -HttpsPort 443 `
            -Priority 1 `
            -Weight 1000 `
            -EnabledState Enabled | Out-Null
        
        $fixesApplied++
        Write-Host "  [OK] Correct origin created!" -ForegroundColor Green
    }
}

# ============================================
# CHECK 8: ROUTE CONFIGURATION
# ============================================
Write-Host "`n[CHECK 9] Route Configuration..." -ForegroundColor Yellow

$route = Get-AzFrontDoorCdnRoute -ResourceGroupName $RG -ProfileName $FDProfile -EndpointName $FDEndpoint -RouteName $RouteName -ErrorAction SilentlyContinue

if (-not $route) {
    Write-Host "  [FAIL] Route not found!" -ForegroundColor Red
    $issuesFound++
} else {
    Write-Host "  Route: $($route.Name)" -ForegroundColor Cyan
    Write-Host "  Status: $($route.EnabledState)" -ForegroundColor Cyan
    Write-Host "  HTTPS Redirect: $($route.HttpsRedirect)" -ForegroundColor Cyan
    
    $needsUpdate = $false
    
    if ($route.EnabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Route not enabled!" -ForegroundColor Red
        $issuesFound++
        $needsUpdate = $true
    }
    
    if (-not $route.CustomDomain -or $route.CustomDomain.Count -eq 0) {
        Write-Host "  [ISSUE] NO custom domain on route!" -ForegroundColor Red
        $issuesFound++
        $needsUpdate = $true
    } else {
        Write-Host "  [OK] Custom domain associated" -ForegroundColor Green
    }
    
    if ($needsUpdate -and $domain) {
        Write-Host "  [FIXING] Updating route..." -ForegroundColor Yellow
        
        Update-AzFrontDoorCdnRoute `
            -ResourceGroupName $RG `
            -ProfileName $FDProfile `
            -EndpointName $FDEndpoint `
            -RouteName $RouteName `
            -CustomDomainId $domain.Id `
            -OriginGroupId $route.OriginGroup.Id `
            -EnabledState Enabled `
            -HttpsRedirect Enabled `
            -SupportedProtocol Https `
            -LinkToDefaultDomain Enabled `
            -ForwardingProtocol HttpsOnly | Out-Null
        
        $fixesApplied++
        Write-Host "  [OK] Route updated!" -ForegroundColor Green
    }
}

# ============================================
# CHECK 9: DNS RESOLUTION
# ============================================
Write-Host "`n[CHECK 10] DNS Resolution..." -ForegroundColor Yellow

try {
    $dns = Resolve-DnsName -Name $Domain -Type CNAME -ErrorAction SilentlyContinue
    if ($dns) {
        Write-Host "  [OK] DNS points to: $($dns.NameHost)" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] DNS not resolving to Front Door" -ForegroundColor Yellow
        Write-Host "  Check GoDaddy CNAME record" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARNING] DNS check failed" -ForegroundColor Yellow
}

# ============================================
# CHECK 10: VM CONNECTIVITY
# ============================================
Write-Host "`n[CHECK 11] VM Connectivity Test..." -ForegroundColor Yellow

$testResult = Test-NetConnection -ComputerName $CorrectIP -Port 443 -WarningAction SilentlyContinue

if ($testResult.TcpTestSucceeded) {
    Write-Host "  [OK] VM reachable on port 443!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] VM not reachable (may take 2-3 minutes)" -ForegroundColor Yellow
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "ULTIMATE CHECK COMPLETE!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nISSUES FOUND: $issuesFound" -ForegroundColor $(if($issuesFound -eq 0){"Green"}else{"Yellow"})
Write-Host "FIXES APPLIED: $fixesApplied" -ForegroundColor $(if($fixesApplied -gt 0){"Green"}else{"Cyan"})

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($fixesApplied -gt 0) {
    Write-Host "1. Wait 10-15 minutes for changes to propagate" -ForegroundColor Yellow
    Write-Host "2. Test: https://moveit.pyxhealth.com" -ForegroundColor Yellow
    Write-Host "3. Look for LOCK ICON (secure certificate)" -ForegroundColor Yellow
    Write-Host "4. Test upload/download" -ForegroundColor Yellow
    Write-Host "5. If still issues, run this script again" -ForegroundColor Yellow
} else {
    Write-Host "Everything looks good!" -ForegroundColor Green
    Write-Host "Test now: https://moveit.pyxhealth.com" -ForegroundColor Green
}

Write-Host "`nPress ENTER to exit..." -ForegroundColor Gray
Read-Host
