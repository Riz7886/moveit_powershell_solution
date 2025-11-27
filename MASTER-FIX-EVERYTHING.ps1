# MASTER FIX - CHECKS AND FIXES EVERYTHING
# This script checks EVERY component and fixes what's broken

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "MASTER DIAGNOSTIC AND FIX - EVERYTHING" -ForegroundColor Cyan
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
# LEVEL 1: AZURE LOGIN
# ============================================
Write-Host "`n[LEVEL 1] Azure Login Check" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Host "  [ISSUE] Not logged in" -ForegroundColor Red
        $issuesFound++
        Connect-AzAccount
        $fixesApplied++
        Write-Host "  [FIXED] Logged in" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Logged in as: $($context.Account)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Login error: $_" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

# ============================================
# LEVEL 2: VM STATUS AND CONNECTIVITY
# ============================================
Write-Host "`n[LEVEL 2] MOVEit VM Status" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status
    $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
    
    Write-Host "  VM Name: $VMName" -ForegroundColor Cyan
    Write-Host "  Power State: $powerState" -ForegroundColor $(if($powerState -eq "VM running"){"Green"}else{"Red"})
    
    if ($powerState -ne "VM running") {
        Write-Host "  [ISSUE] VM is not running!" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [FIXING] Starting VM..." -ForegroundColor Yellow
        Start-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -NoWait | Out-Null
        $fixesApplied++
        Write-Host "  [FIXED] VM start initiated" -ForegroundColor Green
    }
    
    # Get VM IP
    $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroup | Where-Object { $_.VirtualMachine.Id -like "*$VMName*" }
    $vmIP = $nic.IpConfigurations[0].PrivateIpAddress
    Write-Host "  VM Private IP: $vmIP" -ForegroundColor Cyan
    Write-Host "  VM Public IP: $CorrectIP" -ForegroundColor Cyan
    
} catch {
    Write-Host "  [FAIL] Cannot get VM status: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 3: NSG - PORT 443 CHECK
# ============================================
Write-Host "`n[LEVEL 3] Network Security Groups - Port 443" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup
    
    foreach ($nsg in $nsgs) {
        Write-Host "`n  Checking NSG: $($nsg.Name)" -ForegroundColor Cyan
        
        # Get all inbound rules
        $inboundRules = $nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" } | Sort-Object Priority
        
        # Check for DENY rules on 443
        $denyRules = $inboundRules | Where-Object { 
            ($_.DestinationPortRange -eq "443" -or $_.DestinationPortRange -eq "*") -and 
            $_.Access -eq "Deny"
        }
        
        if ($denyRules) {
            Write-Host "    [ISSUE] Found DENY rules blocking port 443!" -ForegroundColor Red
            $issuesFound++
            
            foreach ($rule in $denyRules) {
                Write-Host "      Removing rule: $($rule.Name) (Priority: $($rule.Priority))" -ForegroundColor Yellow
                Remove-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name $rule.Name | Out-Null
            }
            
            Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null
            $fixesApplied++
            Write-Host "    [FIXED] DENY rules removed" -ForegroundColor Green
            
            # Refresh NSG
            $nsg = Get-AzNetworkSecurityGroup -Name $nsg.Name -ResourceGroupName $ResourceGroup
        }
        
        # Check for ALLOW rule on 443
        $allowRule = $nsg.SecurityRules | Where-Object {
            $_.DestinationPortRange -eq "443" -and
            $_.Access -eq "Allow" -and
            $_.Direction -eq "Inbound"
        }
        
        if (-not $allowRule) {
            Write-Host "    [ISSUE] No ALLOW rule for port 443" -ForegroundColor Red
            $issuesFound++
            
            # Find lowest available priority
            $priorities = ($nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" }).Priority
            $priority = 100
            while ($priorities -contains $priority -and $priority -lt 4096) {
                $priority += 10
            }
            
            Write-Host "    [FIXING] Adding ALLOW rule with priority $priority..." -ForegroundColor Yellow
            
            $nsg | Add-AzNetworkSecurityRuleConfig `
                -Name "Allow-HTTPS-443" `
                -Description "Allow HTTPS traffic for MOVEit" `
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
            Write-Host "    [OK] Port 443 is allowed (Rule: $($allowRule.Name), Priority: $($allowRule.Priority))" -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [FAIL] NSG check failed: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 4: FRONT DOOR ENDPOINT
# ============================================
Write-Host "`n[LEVEL 4] Front Door Endpoint" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $endpoint = Get-AzFrontDoorCdnEndpoint -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName
    
    Write-Host "  Endpoint: $($endpoint.Name)" -ForegroundColor Cyan
    Write-Host "  Hostname: $($endpoint.HostName)" -ForegroundColor Cyan
    Write-Host "  Status: $($endpoint.EnabledState)" -ForegroundColor $(if($endpoint.EnabledState -eq "Enabled"){"Green"}else{"Red"})
    
    if ($endpoint.EnabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Endpoint is not enabled!" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [FIXING] Enabling endpoint..." -ForegroundColor Yellow
        
        Update-AzFrontDoorCdnEndpoint `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -EndpointName $EndpointName `
            -EnabledState Enabled | Out-Null
        
        $fixesApplied++
        Write-Host "  [FIXED] Endpoint enabled" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Cannot check endpoint: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 5: KEY VAULT CERTIFICATE
# ============================================
Write-Host "`n[LEVEL 5] Key Vault Certificate" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup
    Write-Host "  Key Vault: $($keyVault.VaultName)" -ForegroundColor Cyan
    
    $cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertName
    if ($cert) {
        Write-Host "  Certificate: $CertName" -ForegroundColor Green
        Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Cyan
        Write-Host "  [OK] Certificate exists in Key Vault" -ForegroundColor Green
        
        $certId = "$($keyVault.ResourceId)/secrets/$CertName"
        Write-Host "  Certificate ID: $certId" -ForegroundColor Cyan
    } else {
        Write-Host "  [FAIL] Certificate $CertName not found in Key Vault!" -ForegroundColor Red
        $issuesFound++
    }
} catch {
    Write-Host "  [FAIL] Cannot access Key Vault: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 6: CUSTOM DOMAIN
# ============================================
Write-Host "`n[LEVEL 6] Custom Domain Configuration" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -CustomDomainName $CustomDomainName -ErrorAction SilentlyContinue
    
    if ($domain) {
        Write-Host "  Domain: $($domain.HostName)" -ForegroundColor Cyan
        Write-Host "  Provisioning: $($domain.ProvisioningState)" -ForegroundColor Cyan
        Write-Host "  Validation: $($domain.DomainValidationState)" -ForegroundColor Cyan
        Write-Host "  Certificate Type: $($domain.TlsSetting.CertificateType)" -ForegroundColor Cyan
        
        # Check if using wrong certificate type
        if ($domain.TlsSetting.CertificateType -eq "ManagedCertificate") {
            Write-Host "  [ISSUE] Using AFD Managed Certificate instead of Key Vault!" -ForegroundColor Red
            $issuesFound++
            
            Write-Host "  [FIXING] Deleting and recreating with Key Vault certificate..." -ForegroundColor Yellow
            
            # Delete old domain
            Remove-AzFrontDoorCdnCustomDomain `
                -ResourceGroupName $ResourceGroup `
                -ProfileName $ProfileName `
                -CustomDomainName $CustomDomainName | Out-Null
            
            Start-Sleep -Seconds 5
            
            # Create new domain with Key Vault cert
            $newDomain = New-AzFrontDoorCdnCustomDomain `
                -ResourceGroupName $ResourceGroup `
                -ProfileName $ProfileName `
                -CustomDomainName $CustomDomainName `
                -HostName "moveit.pyxhealth.com" `
                -CertificateType CustomerCertificate `
                -MinimumTlsVersion TLS12 `
                -SecretId $certId
            
            $fixesApplied++
            Write-Host "  [FIXED] Domain recreated with Key Vault certificate" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Using Key Vault certificate" -ForegroundColor Green
        }
    } else {
        Write-Host "  [ISSUE] Custom domain does not exist!" -ForegroundColor Red
        $issuesFound++
        
        Write-Host "  [FIXING] Creating custom domain with Key Vault certificate..." -ForegroundColor Yellow
        
        $newDomain = New-AzFrontDoorCdnCustomDomain `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -CustomDomainName $CustomDomainName `
            -HostName "moveit.pyxhealth.com" `
            -CertificateType CustomerCertificate `
            -MinimumTlsVersion TLS12 `
            -SecretId $certId
        
        $fixesApplied++
        Write-Host "  [FIXED] Custom domain created" -ForegroundColor Green
    }
    
    # Refresh domain
    $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -CustomDomainName $CustomDomainName
    
} catch {
    Write-Host "  [FAIL] Custom domain check failed: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 7: ORIGIN GROUP AND ORIGINS
# ============================================
Write-Host "`n[LEVEL 7] Origin Group and Origins" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $originGroup = Get-AzFrontDoorCdnOriginGroup -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $OriginGroupName
    Write-Host "  Origin Group: $($originGroup.Name)" -ForegroundColor Cyan
    Write-Host "  Status: $($originGroup.ProvisioningState)" -ForegroundColor Green
    
    # Get all origins
    $origins = Get-AzFrontDoorCdnOrigin -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $OriginGroupName
    
    Write-Host "`n  Checking origins:" -ForegroundColor Cyan
    $correctOriginExists = $false
    $wrongOrigins = @()
    
    foreach ($origin in $origins) {
        Write-Host "    Origin: $($origin.Name)" -ForegroundColor Cyan
        Write-Host "      Host: $($origin.HostName)" -ForegroundColor Cyan
        Write-Host "      Status: $($origin.EnabledState)" -ForegroundColor $(if($origin.EnabledState -eq "Enabled"){"Green"}else{"Red"})
        
        if ($origin.HostName -eq $CorrectIP) {
            $correctOriginExists = $true
            Write-Host "      [OK] Correct IP!" -ForegroundColor Green
        } else {
            Write-Host "      [ISSUE] Wrong IP!" -ForegroundColor Red
            $wrongOrigins += $origin
        }
    }
    
    # Remove wrong origins
    if ($wrongOrigins.Count -gt 0) {
        $issuesFound++
        Write-Host "`n  [FIXING] Removing wrong origins..." -ForegroundColor Yellow
        
        foreach ($wrongOrigin in $wrongOrigins) {
            Write-Host "    Removing: $($wrongOrigin.HostName)" -ForegroundColor Yellow
            Remove-AzFrontDoorCdnOrigin `
                -ResourceGroupName $ResourceGroup `
                -ProfileName $ProfileName `
                -OriginGroupName $OriginGroupName `
                -OriginName $wrongOrigin.Name | Out-Null
        }
        
        $fixesApplied++
        Write-Host "  [FIXED] Wrong origins removed" -ForegroundColor Green
    }
    
    # Create correct origin if missing
    if (-not $correctOriginExists) {
        $issuesFound++
        Write-Host "`n  [ISSUE] Correct origin with IP $CorrectIP does not exist!" -ForegroundColor Red
        Write-Host "  [FIXING] Creating correct origin..." -ForegroundColor Yellow
        
        New-AzFrontDoorCdnOrigin `
            -ResourceGroupName $ResourceGroup `
            -ProfileName $ProfileName `
            -OriginGroupName $OriginGroupName `
            -OriginName "moveit-origin-correct" `
            -HostName $CorrectIP `
            -HttpPort 80 `
            -HttpsPort 443 `
            -Priority 1 `
            -Weight 1000 `
            -EnabledState Enabled | Out-Null
        
        $fixesApplied++
        Write-Host "  [FIXED] Correct origin created with IP $CorrectIP" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  [FAIL] Origin check failed: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 8: ROUTE CONFIGURATION
# ============================================
Write-Host "`n[LEVEL 8] Route Configuration" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $route = Get-AzFrontDoorCdnRoute -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName -RouteName $RouteName
    
    Write-Host "  Route: $($route.Name)" -ForegroundColor Cyan
    Write-Host "  Status: $($route.EnabledState)" -ForegroundColor $(if($route.EnabledState -eq "Enabled"){"Green"}else{"Red"})
    Write-Host "  HTTPS Redirect: $($route.HttpsRedirect)" -ForegroundColor Cyan
    Write-Host "  Supported Protocols: $($route.SupportedProtocol -join ', ')" -ForegroundColor Cyan
    
    # Check if route is enabled
    if ($route.EnabledState -ne "Enabled") {
        Write-Host "  [ISSUE] Route is not enabled!" -ForegroundColor Red
        $issuesFound++
    }
    
    # Check if custom domain is associated
    if ($route.CustomDomain -and $route.CustomDomain.Count -gt 0) {
        Write-Host "  Custom Domains: $($route.CustomDomain.Count)" -ForegroundColor Green
        foreach ($domainRef in $route.CustomDomain) {
            Write-Host "    - $($domainRef.Id)" -ForegroundColor Green
        }
    } else {
        Write-Host "  [ISSUE] NO custom domain associated with route!" -ForegroundColor Red
        $issuesFound++
    }
    
    # Fix route if needed
    if ($route.EnabledState -ne "Enabled" -or -not $route.CustomDomain -or $route.CustomDomain.Count -eq 0) {
        Write-Host "`n  [FIXING] Updating route to associate custom domain..." -ForegroundColor Yellow
        
        # Get fresh domain reference
        $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -CustomDomainName $CustomDomainName
        
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
        Write-Host "  [FIXED] Route updated and domain associated" -ForegroundColor Green
    }
    
} catch {
    Write-Host "  [FAIL] Route check failed: $_" -ForegroundColor Red
    $issuesFound++
}

# ============================================
# LEVEL 9: DNS RESOLUTION
# ============================================
Write-Host "`n[LEVEL 9] DNS Resolution" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

try {
    $dns = Resolve-DnsName -Name "moveit.pyxhealth.com" -Type CNAME -ErrorAction SilentlyContinue
    if ($dns) {
        Write-Host "  [OK] DNS resolves to: $($dns.NameHost)" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] DNS not resolving - may need DNS update" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARNING] DNS check failed" -ForegroundColor Yellow
}

# ============================================
# LEVEL 10: CONNECTIVITY TEST
# ============================================
Write-Host "`n[LEVEL 10] Direct VM Connectivity Test" -ForegroundColor Yellow
Write-Host "=" -NoNewline; 1..50 | ForEach-Object { Write-Host "=" -NoNewline }; Write-Host ""

Write-Host "  Testing connection to $CorrectIP:443..." -ForegroundColor Cyan
$testResult = Test-NetConnection -ComputerName $CorrectIP -Port 443 -WarningAction SilentlyContinue

if ($testResult.TcpTestSucceeded) {
    Write-Host "  [OK] VM is reachable on port 443!" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Cannot reach VM on port 443!" -ForegroundColor Red
    Write-Host "  This could be:" -ForegroundColor Yellow
    Write-Host "    - NSG changes still propagating (wait 2-3 minutes)" -ForegroundColor Yellow
    Write-Host "    - VM firewall blocking traffic" -ForegroundColor Yellow
    Write-Host "    - MOVEit service not running on VM" -ForegroundColor Yellow
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nISSUES FOUND: $issuesFound" -ForegroundColor $(if($issuesFound -eq 0){"Green"}else{"Yellow"})
Write-Host "FIXES APPLIED: $fixesApplied" -ForegroundColor $(if($fixesApplied -gt 0){"Green"}else{"Cyan"})

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NEXT STEPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($fixesApplied -gt 0) {
    Write-Host "1. Wait 10-15 minutes for all changes to propagate" -ForegroundColor Yellow
    Write-Host "2. Azure Front Door needs time to update certificate and routes" -ForegroundColor Yellow
    Write-Host "3. Test: https://moveit.pyxhealth.com" -ForegroundColor Yellow
    Write-Host "4. Look for LOCK ICON in browser" -ForegroundColor Yellow
} else {
    Write-Host "All checks passed! Test the site now:" -ForegroundColor Green
    Write-Host "https://moveit.pyxhealth.com" -ForegroundColor Green
}

Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
Read-Host
