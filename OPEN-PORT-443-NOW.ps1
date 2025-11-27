# EMERGENCY - OPEN PORT 443 ON ALL NSGs
# This is blocking Front Door from reaching MOVEit!

Write-Host "`n========================================" -ForegroundColor Red
Write-Host "EMERGENCY: OPENING PORT 443" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

$ResourceGroup = "rg-moveit"

Write-Host "[STEP 1] Finding all NSGs in $ResourceGroup..." -ForegroundColor Yellow
$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup

if ($nsgs.Count -eq 0) {
    Write-Host "  [FAIL] No NSGs found!" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit
}

Write-Host "  Found $($nsgs.Count) NSG(s)" -ForegroundColor Cyan

foreach ($nsg in $nsgs) {
    Write-Host "`n[NSG] Processing: $($nsg.Name)" -ForegroundColor Cyan
    
    # Check for existing port 443 ALLOW rule
    $allow443 = $nsg.SecurityRules | Where-Object {
        $_.DestinationPortRange -contains "443" -and
        $_.Access -eq "Allow" -and
        $_.Direction -eq "Inbound"
    }
    
    # Check for existing port 443 DENY rule
    $deny443 = $nsg.SecurityRules | Where-Object {
        $_.DestinationPortRange -contains "443" -and
        $_.Access -eq "Deny" -and
        $_.Direction -eq "Inbound"
    }
    
    if ($deny443) {
        Write-Host "  [FOUND] DENY rule blocking port 443: $($deny443.Name)" -ForegroundColor Red
        Write-Host "  [ACTION] Removing DENY rule..." -ForegroundColor Yellow
        
        $nsg | Remove-AzNetworkSecurityRuleConfig -Name $deny443.Name | Set-AzNetworkSecurityGroup | Out-Null
        Write-Host "  [OK] DENY rule removed!" -ForegroundColor Green
        
        # Refresh NSG
        $nsg = Get-AzNetworkSecurityGroup -Name $nsg.Name -ResourceGroupName $ResourceGroup
    }
    
    if (-not $allow443) {
        Write-Host "  [ACTION] Adding ALLOW rule for port 443..." -ForegroundColor Yellow
        
        # Find available priority
        $usedPriorities = $nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" } | Select-Object -ExpandProperty Priority
        $priority = 100
        while ($usedPriorities -contains $priority) {
            $priority += 10
        }
        
        $nsg | Add-AzNetworkSecurityRuleConfig `
            -Name "Allow-HTTPS-443-URGENT" `
            -Description "Allow HTTPS for MOVEit Front Door" `
            -Access Allow `
            -Protocol Tcp `
            -Direction Inbound `
            -Priority $priority `
            -SourceAddressPrefix Internet `
            -SourcePortRange * `
            -DestinationAddressPrefix * `
            -DestinationPortRange 443 | Set-AzNetworkSecurityGroup | Out-Null
        
        Write-Host "  [OK] ALLOW rule added with priority $priority!" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Port 443 already allowed" -ForegroundColor Green
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "PORT 443 IS NOW OPEN!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Test connectivity
Write-Host "[TEST] Testing VM connectivity on port 443..." -ForegroundColor Yellow
$testResult = Test-NetConnection -ComputerName "20.86.24.164" -Port 443 -WarningAction SilentlyContinue

if ($testResult.TcpTestSucceeded) {
    Write-Host "  [SUCCESS] VM 20.86.24.164:443 IS REACHABLE!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Still not reachable - may take 2-3 minutes for NSG update" -ForegroundColor Yellow
}

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 2-3 minutes for NSG changes to apply" -ForegroundColor Cyan
Write-Host "2. Test: https://moveit.pyxhealth.com" -ForegroundColor Cyan
Write-Host "3. Should work now!" -ForegroundColor Cyan

Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
Read-Host
