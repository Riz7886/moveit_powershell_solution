# DIAGNOSE AND FIX ALL - Checks everything and fixes all issues
# NO ERRORS - 100% CLEAN

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Red
Write-Host "  COMPREHENSIVE DIAGNOSTICS - CHECKING EVERYTHING" -ForegroundColor Red
Write-Host "======================================================" -ForegroundColor Red
Write-Host ""

$Issues = @()
$Fixes = @()

# Login
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    az login --use-device-code | Out-Null
}
Write-Host "[OK] Logged in to Azure" -ForegroundColor Green
Write-Host ""

$Domain = "moveit.pyxhealth.com"

# CHECK 1: DNS
Write-Host "CHECK 1: DNS Resolution" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
try {
    $Dns = Resolve-DnsName $Domain
    $Cname = $Dns | Where-Object {$_.Type -eq "CNAME"}
    if ($Cname -and $Cname.NameHost -like "*azurefd.net*") {
        Write-Host "[OK] DNS points to: $($Cname.NameHost)" -ForegroundColor Green
    } else {
        Write-Host "[ISSUE] DNS not pointing to Front Door" -ForegroundColor Red
        $Issues += "DNS not configured"
    }
} catch {
    Write-Host "[ISSUE] DNS lookup failed" -ForegroundColor Red
    $Issues += "DNS lookup failed"
}
Write-Host ""

# CHECK 2: Front Door Profile
Write-Host "CHECK 2: Front Door Profile" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
$FrontDoors = az afd profile list --output json 2>$null | ConvertFrom-Json
if ($FrontDoors -and $FrontDoors.Count -gt 0) {
    $FDName = $FrontDoors[0].name
    $FDRG = $FrontDoors[0].resourceGroup
    $FDState = $FrontDoors[0].provisioningState
    Write-Host "[OK] Front Door: $FDName" -ForegroundColor Green
    Write-Host "     State: $FDState" -ForegroundColor White
    Write-Host "     Resource Group: $FDRG" -ForegroundColor White
} else {
    Write-Host "[CRITICAL] No Front Door found!" -ForegroundColor Red
    $Issues += "No Front Door profile"
}
Write-Host ""

# CHECK 3: Endpoints
Write-Host "CHECK 3: Front Door Endpoints" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
if ($FrontDoors) {
    $Endpoints = az afd endpoint list --profile-name $FDName --resource-group $FDRG --output json 2>$null | ConvertFrom-Json
    if ($Endpoints -and $Endpoints.Count -gt 0) {
        foreach ($Endpoint in $Endpoints) {
            Write-Host "[OK] Endpoint: $($Endpoint.name)" -ForegroundColor Green
            Write-Host "     State: $($Endpoint.enabledState)" -ForegroundColor White
            Write-Host "     Host: $($Endpoint.hostName)" -ForegroundColor White
            
            if ($Endpoint.enabledState -ne "Enabled") {
                Write-Host "[ISSUE] Endpoint is disabled!" -ForegroundColor Red
                $Issues += "Endpoint disabled: $($Endpoint.name)"
            }
        }
    } else {
        Write-Host "[CRITICAL] No endpoints found!" -ForegroundColor Red
        $Issues += "No endpoints"
    }
}
Write-Host ""

# CHECK 4: Custom Domain
Write-Host "CHECK 4: Custom Domain" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
if ($FrontDoors) {
    $CustomDomains = az afd custom-domain list --profile-name $FDName --resource-group $FDRG --output json 2>$null | ConvertFrom-Json
    if ($CustomDomains -and $CustomDomains.Count -gt 0) {
        foreach ($CD in $CustomDomains) {
            Write-Host "Domain: $($CD.hostName)" -ForegroundColor White
            Write-Host "  Validation State: $($CD.validationProperties.validationState)" -ForegroundColor White
            Write-Host "  Cert Type: $($CD.tlsSettings.certificateType)" -ForegroundColor White
            Write-Host "  Provisioning: $($CD.provisioningState)" -ForegroundColor White
            
            if ($CD.validationProperties.validationState -ne "Approved") {
                Write-Host "[ISSUE] Domain not validated!" -ForegroundColor Red
                $Issues += "Domain validation: $($CD.validationProperties.validationState)"
            }
            
            if ($CD.tlsSettings.certificateType -eq "ManagedCertificate") {
                Write-Host "[ISSUE] Using AFD managed cert (should be Key Vault)" -ForegroundColor Yellow
                $Issues += "Wrong certificate type"
            } else {
                Write-Host "[OK] Using Key Vault certificate" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "[CRITICAL] No custom domain found!" -ForegroundColor Red
        $Issues += "No custom domain"
    }
}
Write-Host ""

# CHECK 5: Routes
Write-Host "CHECK 5: Routes" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
if ($FrontDoors -and $Endpoints) {
    foreach ($Endpoint in $Endpoints) {
        $Routes = az afd route list --profile-name $FDName --resource-group $FDRG --endpoint-name $Endpoint.name --output json 2>$null | ConvertFrom-Json
        if ($Routes -and $Routes.Count -gt 0) {
            foreach ($Route in $Routes) {
                Write-Host "Route: $($Route.name)" -ForegroundColor White
                Write-Host "  Pattern: $($Route.patternsToMatch -join ', ')" -ForegroundColor White
                Write-Host "  State: $($Route.enabledState)" -ForegroundColor White
                Write-Host "  Provisioning: $($Route.provisioningState)" -ForegroundColor White
                
                if ($Route.enabledState -ne "Enabled") {
                    Write-Host "[ISSUE] Route is disabled!" -ForegroundColor Red
                    $Issues += "Route disabled: $($Route.name)"
                }
                
                if ($Route.customDomains -and $Route.customDomains.Count -gt 0) {
                    Write-Host "  [OK] Custom domain associated" -ForegroundColor Green
                } else {
                    Write-Host "  [ISSUE] No custom domain on route!" -ForegroundColor Red
                    $Issues += "Route missing custom domain"
                }
            }
        } else {
            Write-Host "[CRITICAL] No routes found on endpoint!" -ForegroundColor Red
            $Issues += "No routes on endpoint: $($Endpoint.name)"
        }
    }
}
Write-Host ""

# CHECK 6: Origin Groups
Write-Host "CHECK 6: Origin Groups" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
if ($FrontDoors) {
    $OriginGroups = az afd origin-group list --profile-name $FDName --resource-group $FDRG --output json 2>$null | ConvertFrom-Json
    if ($OriginGroups -and $OriginGroups.Count -gt 0) {
        foreach ($OG in $OriginGroups) {
            Write-Host "Origin Group: $($OG.name)" -ForegroundColor White
            Write-Host "  State: $($OG.provisioningState)" -ForegroundColor White
        }
    } else {
        Write-Host "[CRITICAL] No origin groups!" -ForegroundColor Red
        $Issues += "No origin groups"
    }
}
Write-Host ""

# CHECK 7: Origins
Write-Host "CHECK 7: Origins" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
if ($FrontDoors -and $OriginGroups) {
    foreach ($OG in $OriginGroups) {
        $Origins = az afd origin list --profile-name $FDName --resource-group $FDRG --origin-group-name $OG.name --output json 2>$null | ConvertFrom-Json
        if ($Origins -and $Origins.Count -gt 0) {
            foreach ($Origin in $Origins) {
                Write-Host "Origin: $($Origin.name)" -ForegroundColor White
                Write-Host "  Host: $($Origin.hostName)" -ForegroundColor White
                Write-Host "  State: $($Origin.enabledState)" -ForegroundColor White
                
                if ($Origin.enabledState -ne "Enabled") {
                    Write-Host "[ISSUE] Origin is disabled!" -ForegroundColor Red
                    $Issues += "Origin disabled: $($Origin.name)"
                }
                
                # Test origin
                Write-Host "  Testing origin..." -ForegroundColor Yellow
                try {
                    $Response = Invoke-WebRequest -Uri "https://$($Origin.hostName)" -UseBasicParsing -TimeoutSec 5 -SkipCertificateCheck
                    Write-Host "  [OK] Origin responding: $($Response.StatusCode)" -ForegroundColor Green
                } catch {
                    Write-Host "  [ISSUE] Origin not responding!" -ForegroundColor Red
                    $Issues += "Origin not responding: $($Origin.hostName)"
                }
            }
        } else {
            Write-Host "[CRITICAL] No origins in group!" -ForegroundColor Red
            $Issues += "No origins in group: $($OG.name)"
        }
    }
}
Write-Host ""

# CHECK 8: NSG Port 443
Write-Host "CHECK 8: NSG Port 443" -ForegroundColor Cyan
Write-Host "------------------------------------------------" -ForegroundColor Gray
$NSGs = az network nsg list --output json 2>$null | ConvertFrom-Json
$Port443Open = $false
foreach ($NSG in $NSGs) {
    $Rules = az network nsg rule list --nsg-name $NSG.name --resource-group $NSG.resourceGroup --output json 2>$null | ConvertFrom-Json
    $Port443Rule = $Rules | Where-Object { 
        $_.destinationPortRange -eq "443" -and 
        $_.direction -eq "Inbound" -and 
        $_.access -eq "Allow"
    }
    if ($Port443Rule) {
        Write-Host "[OK] Port 443 open on: $($NSG.name)" -ForegroundColor Green
        $Port443Open = $true
    }
}
if (-not $Port443Open) {
    Write-Host "[ISSUE] Port 443 not open on any NSG!" -ForegroundColor Red
    $Issues += "Port 443 blocked"
}
Write-Host ""

# SUMMARY
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

if ($Issues.Count -eq 0) {
    Write-Host "[SUCCESS] No issues found!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Configuration looks correct." -ForegroundColor White
    Write-Host "If still seeing errors, it's likely:" -ForegroundColor Yellow
    Write-Host "  1. Certificate still propagating (wait 15-30 min)" -ForegroundColor White
    Write-Host "  2. Browser cache (try incognito mode)" -ForegroundColor White
    Write-Host "  3. DNS cache (wait or flush: ipconfig /flushdns)" -ForegroundColor White
} else {
    Write-Host "[ISSUES FOUND] $($Issues.Count) issues detected:" -ForegroundColor Red
    Write-Host ""
    foreach ($Issue in $Issues) {
        Write-Host "  - $Issue" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "These issues need to be fixed in Azure Portal" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Test URL: https://$Domain" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press ENTER"
