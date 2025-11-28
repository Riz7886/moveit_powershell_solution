# ================================================================
# MOVEIT DEPLOYMENT - SCRIPT 7 OF 7
# COMPLETE TESTING AND VERIFICATION
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SCRIPT 7 OF 7: TESTING & VERIFICATION" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Test-Component {
    param([string]$Name, [scriptblock]$Test)
    Write-Host ""
    Write-Host "Testing: $Name" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    try {
        $result = & $Test
        if ($result) {
            Write-Host "[PASS] $Name" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[FAIL] $Name" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[ERROR] $Name - $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
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
# TEST 1: RESOURCE GROUP
# ----------------------------------------------------------------
$test1 = Test-Component "Resource Group Exists" {
    $rg = az group show --name $config.DeploymentResourceGroup 2>$null
    return ($null -ne $rg)
}

# ----------------------------------------------------------------
# TEST 2: NSG
# ----------------------------------------------------------------
$test2 = Test-Component "Network Security Group" {
    $nsg = az network nsg show --resource-group $config.DeploymentResourceGroup --name $config.NSGName 2>$null
    if ($nsg) {
        $nsgObj = $nsg | ConvertFrom-Json
        Write-Host "  Rules: $($nsgObj.securityRules.Count)" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 3: LOAD BALANCER
# ----------------------------------------------------------------
$test3 = Test-Component "Load Balancer" {
    $lb = az network lb show --resource-group $config.DeploymentResourceGroup --name $config.LoadBalancerName 2>$null
    if ($lb) {
        $lbObj = $lb | ConvertFrom-Json
        $publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv
        Write-Host "  Public IP: $publicIP" -ForegroundColor White
        Write-Host "  Backend Pool: $($lbObj.backendAddressPools.Count) configured" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 4: FRONT DOOR PROFILE
# ----------------------------------------------------------------
$test4 = Test-Component "Front Door Profile" {
    $fd = az afd profile show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName 2>$null
    if ($fd) {
        $fdObj = $fd | ConvertFrom-Json
        Write-Host "  SKU: $($fdObj.sku.name)" -ForegroundColor White
        Write-Host "  State: $($fdObj.provisioningState)" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 5: FRONT DOOR ENDPOINT
# ----------------------------------------------------------------
$test5 = Test-Component "Front Door Endpoint" {
    $endpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName 2>$null
    if ($endpoint) {
        $epObj = $endpoint | ConvertFrom-Json
        Write-Host "  Hostname: $($epObj.hostName)" -ForegroundColor White
        Write-Host "  State: $($epObj.enabledState)" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 6: ORIGIN GROUP
# ----------------------------------------------------------------
$test6 = Test-Component "Origin Group" {
    $og = az afd origin-group show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName 2>$null
    if ($og) {
        $ogObj = $og | ConvertFrom-Json
        Write-Host "  Health Probe: $($ogObj.healthProbeSettings.probeProtocol) on $($ogObj.healthProbeSettings.probePath)" -ForegroundColor White
        Write-Host "  Interval: $($ogObj.healthProbeSettings.probeIntervalInSeconds)s" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 7: ORIGIN
# ----------------------------------------------------------------
$test7 = Test-Component "Origin (MOVEit Backend)" {
    $origin = az afd origin show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --origin-group-name $config.FrontDoorOriginGroupName --origin-name $config.FrontDoorOriginName 2>$null
    if ($origin) {
        $originObj = $origin | ConvertFrom-Json
        Write-Host "  Host: $($originObj.hostName)" -ForegroundColor White
        Write-Host "  HTTPS Port: $($originObj.httpsPort)" -ForegroundColor White
        Write-Host "  State: $($originObj.enabledState)" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 8: ROUTE
# ----------------------------------------------------------------
$test8 = Test-Component "Front Door Route" {
    $route = az afd route show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --route-name $config.FrontDoorRouteName 2>$null
    if ($route) {
        $routeObj = $route | ConvertFrom-Json
        Write-Host "  Patterns: $($routeObj.patternsToMatch -join ', ')" -ForegroundColor White
        Write-Host "  HTTPS Redirect: $($routeObj.httpsRedirect)" -ForegroundColor White
        Write-Host "  Forwarding Protocol: $($routeObj.forwardingProtocol)" -ForegroundColor White
        
        if ($routeObj.originGroup) {
            Write-Host "  ✓ Linked to Origin Group" -ForegroundColor Green
        } else {
            Write-Host "  ✗ NOT linked to Origin Group" -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 9: WAF POLICY
# ----------------------------------------------------------------
$test9 = Test-Component "WAF Policy" {
    $waf = az network front-door waf-policy show --resource-group $config.DeploymentResourceGroup --name $config.WAFPolicyName 2>$null
    if ($waf) {
        $wafObj = $waf | ConvertFrom-Json
        Write-Host "  Mode: $($wafObj.policySettings.mode)" -ForegroundColor White
        Write-Host "  SKU: $($wafObj.sku.name)" -ForegroundColor White
        Write-Host "  Managed Rules: $($wafObj.managedRules.managedRuleSets.Count)" -ForegroundColor White
        return $true
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 10: DNS RESOLUTION (if custom domain configured)
# ----------------------------------------------------------------
$test10 = Test-Component "DNS Resolution" {
    try {
        Write-Host "  Testing: $($config.CustomDomain)" -ForegroundColor White
        $dns = Resolve-DnsName -Name $config.CustomDomain -Type CNAME -ErrorAction SilentlyContinue
        if ($dns) {
            Write-Host "  ✓ CNAME: $($dns.NameHost)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  ⚠ Not configured yet (run Script 6)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  ⚠ Not configured yet (run Script 6)" -ForegroundColor Yellow
        return $false
    }
}

# ----------------------------------------------------------------
# TEST 11: HTTPS CONNECTIVITY
# ----------------------------------------------------------------
$test11 = Test-Component "HTTPS Connectivity" {
    $frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv
    
    if ($frontDoorEndpoint) {
        Write-Host "  Testing: https://$frontDoorEndpoint" -ForegroundColor White
        
        try {
            $response = Invoke-WebRequest -Uri "https://$frontDoorEndpoint" -Method Head -TimeoutSec 10 -ErrorAction SilentlyContinue -SkipCertificateCheck
            Write-Host "  Status: $($response.StatusCode)" -ForegroundColor White
            return $true
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode) {
                Write-Host "  Status: $statusCode" -ForegroundColor White
                if ($statusCode -eq 404 -or $statusCode -eq 403) {
                    Write-Host "  ⚠ Server responded (routing may need DNS change)" -ForegroundColor Yellow
                    return $true
                }
            } else {
                Write-Host "  ✗ Connection failed" -ForegroundColor Red
                return $false
            }
        }
    }
    return $false
}

# ----------------------------------------------------------------
# TEST 12: SFTP PORT
# ----------------------------------------------------------------
$test12 = Test-Component "SFTP Port Accessibility" {
    $publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv
    
    if ($publicIP) {
        Write-Host "  Testing: $publicIP`:22" -ForegroundColor White
        
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcpClient.BeginConnect($publicIP, 22, $null, $null)
            $wait = $asyncResult.AsyncWaitHandle.WaitOne(3000, $false)
            
            if ($wait) {
                try {
                    $tcpClient.EndConnect($asyncResult)
                    Write-Host "  ✓ Port 22 is open" -ForegroundColor Green
                    $tcpClient.Close()
                    return $true
                } catch {
                    Write-Host "  ✗ Port 22 is closed" -ForegroundColor Red
                    return $false
                }
            } else {
                Write-Host "  ✗ Connection timeout" -ForegroundColor Red
                $tcpClient.Close()
                return $false
            }
        } catch {
            Write-Host "  ✗ Connection failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    return $false
}

# ----------------------------------------------------------------
# RESULTS SUMMARY
# ----------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$allTests = @($test1, $test2, $test3, $test4, $test5, $test6, $test7, $test8, $test9, $test10, $test11, $test12)
$passed = ($allTests | Where-Object { $_ -eq $true }).Count
$failed = ($allTests | Where-Object { $_ -eq $false }).Count
$total = $allTests.Count

Write-Host "Total Tests:  $total" -ForegroundColor White
Write-Host "Passed:       $passed" -ForegroundColor Green
Write-Host "Failed:       $failed" -ForegroundColor $(if ($failed -eq 0) {"Green"} else {"Red"})
Write-Host ""

$percentage = [math]::Round(($passed / $total) * 100, 2)

if ($percentage -ge 90) {
    Write-Host "✓ DEPLOYMENT SUCCESSFUL! ($percentage%)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your MOVEit deployment is fully operational!" -ForegroundColor Green
} elseif ($percentage -ge 70) {
    Write-Host "⚠ DEPLOYMENT MOSTLY COMPLETE ($percentage%)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Core components are working. Some optional features may need configuration." -ForegroundColor Yellow
} else {
    Write-Host "✗ DEPLOYMENT INCOMPLETE ($percentage%)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Critical components are missing. Review failed tests above." -ForegroundColor Red
}

Write-Host ""

# ----------------------------------------------------------------
# QUICK ACCESS INFORMATION
# ----------------------------------------------------------------
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "QUICK ACCESS INFORMATION" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$publicIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv
$frontDoorEndpoint = az afd endpoint show --resource-group $config.DeploymentResourceGroup --profile-name $config.FrontDoorProfileName --endpoint-name $config.FrontDoorEndpointName --query hostName --output tsv

Write-Host "SFTP ACCESS:" -ForegroundColor Cyan
Write-Host "  Command: sftp username@$publicIP" -ForegroundColor Green
Write-Host ""

Write-Host "HTTPS ACCESS:" -ForegroundColor Cyan
Write-Host "  Default:       https://$frontDoorEndpoint" -ForegroundColor White
Write-Host "  Custom Domain: https://$($config.CustomDomain)" -ForegroundColor Green
Write-Host ""

Write-Host "AZURE PORTAL:" -ForegroundColor Cyan
Write-Host "  Resource Group: $($config.DeploymentResourceGroup)" -ForegroundColor White
Write-Host "  Location:       $($config.Location)" -ForegroundColor White
Write-Host ""

Write-Host "============================================" -ForegroundColor Green
Write-Host "TESTING COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Save results to file
$resultsFile = "$env:USERPROFILE\Desktop\MOVEit-Test-Results.txt"
$results = @"
================================================================
MOVEIT DEPLOYMENT TEST RESULTS
================================================================
Test Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

SUMMARY:
========
Total Tests:    $total
Passed:         $passed
Failed:         $failed
Success Rate:   $percentage%

COMPONENT STATUS:
=================
[$(if($test1){'✓'}else{'✗'})] Resource Group
[$(if($test2){'✓'}else{'✗'})] Network Security Group
[$(if($test3){'✓'}else{'✗'})] Load Balancer
[$(if($test4){'✓'}else{'✗'})] Front Door Profile
[$(if($test5){'✓'}else{'✗'})] Front Door Endpoint
[$(if($test6){'✓'}else{'✗'})] Origin Group
[$(if($test7){'✓'}else{'✗'})] Origin (MOVEit Backend)
[$(if($test8){'✓'}else{'✗'})] Front Door Route
[$(if($test9){'✓'}else{'✗'})] WAF Policy
[$(if($test10){'✓'}else{'✗'})] DNS Resolution
[$(if($test11){'✓'}else{'✗'})] HTTPS Connectivity
[$(if($test12){'✓'}else{'✗'})] SFTP Port Accessibility

QUICK ACCESS:
=============
SFTP:   sftp username@$publicIP
HTTPS:  https://$frontDoorEndpoint
Custom: https://$($config.CustomDomain)

================================================================
"@

$results | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host "Results saved to: $resultsFile" -ForegroundColor Gray
Write-Host ""
