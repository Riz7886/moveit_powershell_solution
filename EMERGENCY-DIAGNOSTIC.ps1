# EMERGENCY DIAGNOSTIC - CHECK REAL STATE
# Find out what's ACTUALLY broken vs what portal shows

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "EMERGENCY DIAGNOSTIC - REAL STATE CHECK" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$ResourceGroup = "rg-moveit"
$ProfileName = "moveit-frontdoor-profile"
$EndpointName = "moveit-endpoint-e9foashyq2cddef0"
$CustomDomainName = "moveit-pyxhealth-com"
$RouteName = "moveit-route"
$OriginGroupName = "moveit-origin-group"

# Login check
Write-Host "[CHECK 1] Azure Login..." -ForegroundColor Yellow
$context = Get-AzContext
if ($null -eq $context) {
    Write-Host "  [FAIL] Not logged in!" -ForegroundColor Red
    Connect-AzAccount
} else {
    Write-Host "  [OK] Logged in as: $($context.Account)" -ForegroundColor Green
}

# Check Endpoint Status
Write-Host "`n[CHECK 2] Endpoint Status..." -ForegroundColor Yellow
try {
    $endpoint = Get-AzFrontDoorCdnEndpoint -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName
    Write-Host "  Status: $($endpoint.EnabledState)" -ForegroundColor $(if($endpoint.EnabledState -eq "Enabled"){"Green"}else{"Red"})
    Write-Host "  Hostname: $($endpoint.HostName)" -ForegroundColor Cyan
} catch {
    Write-Host "  [FAIL] Cannot get endpoint: $_" -ForegroundColor Red
}

# Check Custom Domain - DETAILED
Write-Host "`n[CHECK 3] Custom Domain - DETAILED..." -ForegroundColor Yellow
try {
    $domain = Get-AzFrontDoorCdnCustomDomain -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -CustomDomainName $CustomDomainName
    Write-Host "  Domain: $($domain.HostName)" -ForegroundColor Cyan
    Write-Host "  Provisioning State: $($domain.ProvisioningState)" -ForegroundColor $(if($domain.ProvisioningState -eq "Succeeded"){"Green"}else{"Red"})
    Write-Host "  Validation State: $($domain.DomainValidationState)" -ForegroundColor $(if($domain.DomainValidationState -eq "Approved"){"Green"}else{"Yellow"})
    Write-Host "  Certificate Type: $($domain.TlsSetting.CertificateType)" -ForegroundColor Cyan
    Write-Host "  Certificate Source: $($domain.TlsSetting.Secret.Id)" -ForegroundColor Cyan
} catch {
    Write-Host "  [FAIL] Cannot get domain: $_" -ForegroundColor Red
}

# Check Route - DETAILED
Write-Host "`n[CHECK 4] Route Configuration - DETAILED..." -ForegroundColor Yellow
try {
    $route = Get-AzFrontDoorCdnRoute -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -EndpointName $EndpointName -RouteName $RouteName
    Write-Host "  Route Name: $($route.Name)" -ForegroundColor Cyan
    Write-Host "  Route State: $($route.EnabledState)" -ForegroundColor $(if($route.EnabledState -eq "Enabled"){"Green"}else{"Red"})
    Write-Host "  Provisioning State: $($route.ProvisioningState)" -ForegroundColor $(if($route.ProvisioningState -eq "Succeeded"){"Green"}else{"Red"})
    
    # THIS IS THE CRITICAL PART - CHECK CUSTOM DOMAINS ON ROUTE
    if ($route.CustomDomain -and $route.CustomDomain.Count -gt 0) {
        Write-Host "  Custom Domains on Route: $($route.CustomDomain.Count)" -ForegroundColor Green
        foreach ($domain in $route.CustomDomain) {
            Write-Host "    - $($domain.Id)" -ForegroundColor Green
        }
    } else {
        Write-Host "  Custom Domains on Route: NONE (THIS IS THE PROBLEM!)" -ForegroundColor Red
    }
    
    Write-Host "  Origin Group: $($route.OriginGroup.Id)" -ForegroundColor Cyan
    Write-Host "  Supported Protocols: $($route.SupportedProtocol -join ', ')" -ForegroundColor Cyan
    Write-Host "  HTTPS Redirect: $($route.HttpsRedirect)" -ForegroundColor Cyan
} catch {
    Write-Host "  [FAIL] Cannot get route: $_" -ForegroundColor Red
}

# Check Origin Group
Write-Host "`n[CHECK 5] Origin Group..." -ForegroundColor Yellow
try {
    $originGroup = Get-AzFrontDoorCdnOriginGroup -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $OriginGroupName
    Write-Host "  State: $($originGroup.ProvisioningState)" -ForegroundColor $(if($originGroup.ProvisioningState -eq "Succeeded"){"Green"}else{"Red"})
} catch {
    Write-Host "  [FAIL] Cannot get origin group: $_" -ForegroundColor Red
}

# Check Origins
Write-Host "`n[CHECK 6] Origins in Group..." -ForegroundColor Yellow
try {
    $origins = Get-AzFrontDoorCdnOrigin -ResourceGroupName $ResourceGroup -ProfileName $ProfileName -OriginGroupName $OriginGroupName
    foreach ($origin in $origins) {
        Write-Host "  Origin: $($origin.Name)" -ForegroundColor Cyan
        Write-Host "    Host: $($origin.HostName)" -ForegroundColor Cyan
        Write-Host "    State: $($origin.EnabledState)" -ForegroundColor $(if($origin.EnabledState -eq "Enabled"){"Green"}else{"Red"})
        Write-Host "    Provisioning: $($origin.ProvisioningState)" -ForegroundColor $(if($origin.ProvisioningState -eq "Succeeded"){"Green"}else{"Red"})
    }
} catch {
    Write-Host "  [FAIL] Cannot get origins: $_" -ForegroundColor Red
}

# DNS Check
Write-Host "`n[CHECK 7] DNS Resolution..." -ForegroundColor Yellow
try {
    $dns = Resolve-DnsName -Name "moveit.pyxhealth.com" -Type CNAME -ErrorAction SilentlyContinue
    if ($dns) {
        Write-Host "  DNS Points To: $($dns.NameHost)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] DNS not resolving!" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FAIL] DNS check failed: $_" -ForegroundColor Red
}

# Direct connectivity test
Write-Host "`n[CHECK 8] Direct VM Connectivity Test..." -ForegroundColor Yellow
try {
    $result = Test-NetConnection -ComputerName "20.86.24.164" -Port 443 -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "  [OK] VM 20.86.24.164:443 is reachable" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Cannot reach VM on port 443!" -ForegroundColor Red
    }
} catch {
    Write-Host "  [FAIL] Connectivity test failed: $_" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Press ENTER to exit..." -ForegroundColor Yellow
Read-Host
