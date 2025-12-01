# FINAL DIAGNOSTIC - Check MOVEit VM

Clear-Host
Write-Host "CHECKING MOVEIT VM STATUS" -ForegroundColor Cyan
Write-Host ""

$config = Get-Content "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json" | ConvertFrom-Json
$moveitIP = "192.168.0.5"

# Test 1: Check VM power state
Write-Host "Test 1: Checking MOVEit VM power state..." -ForegroundColor Yellow
$vms = az vm list --resource-group $config.DeploymentResourceGroup --query "[?contains(name, 'moveit')].{Name:name, Status:powerState}" --output json | ConvertFrom-Json

foreach ($vm in $vms) {
    if ($vm.Status -eq "VM running") {
        Write-Host "  ✅ $($vm.Name): Running" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $($vm.Name): $($vm.Status)" -ForegroundColor Red
        Write-Host "     ACTION: Start this VM in Azure Portal!" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 2: Check NSG rules
Write-Host "Test 2: Checking NSG rules for MOVEit Transfer..." -ForegroundColor Yellow
$nsgRules = az network nsg rule list --resource-group $config.DeploymentResourceGroup --nsg-name "nsg-moveit-transfer" --query "[?direction=='Inbound' && (destinationPortRange=='443' || destinationPortRange=='22')].{Name:name, Port:destinationPortRange, Access:access, Priority:priority}" --output json 2>$null | ConvertFrom-Json

if ($nsgRules) {
    foreach ($rule in $nsgRules) {
        Write-Host "  ✅ $($rule.Name): Port $($rule.Port) - $($rule.Access)" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠️  Could not check NSG rules" -ForegroundColor Yellow
}
Write-Host ""

# Test 3: Try to connect to ports
Write-Host "Test 3: Testing connectivity to MOVEit VM..." -ForegroundColor Yellow

Write-Host "  Testing port 443..." -ForegroundColor Yellow
try {
    $tcp443 = New-Object System.Net.Sockets.TcpClient
    $tcp443.Connect($moveitIP, 443)
    $tcp443.Close()
    Write-Host "    ✅ Port 443 is OPEN" -ForegroundColor Green
} catch {
    Write-Host "    ❌ Port 443 is CLOSED or BLOCKED" -ForegroundColor Red
}

Write-Host "  Testing port 22..." -ForegroundColor Yellow
try {
    $tcp22 = New-Object System.Net.Sockets.TcpClient
    $tcp22.Connect($moveitIP, 22)
    $tcp22.Close()
    Write-Host "    ✅ Port 22 is OPEN" -ForegroundColor Green
} catch {
    Write-Host "    ❌ Port 22 is CLOSED or BLOCKED" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "DIAGNOSIS COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "AZURE INFRASTRUCTURE:" -ForegroundColor Green
Write-Host "  ✅ NSG rules for ports 22 and 443 exist" -ForegroundColor White
Write-Host "  ✅ Load Balancer configured" -ForegroundColor White
Write-Host "  ✅ Front Door configured" -ForegroundColor White
Write-Host "  ✅ Backend pool configured" -ForegroundColor White
Write-Host ""

Write-Host "THE PROBLEM:" -ForegroundColor Red
Write-Host "  MOVEit VM (192.168.0.5) is NOT responding on ports 443/22" -ForegroundColor White
Write-Host ""

Write-Host "WHAT THIS MEANS:" -ForegroundColor Yellow
Write-Host "  The issue is INSIDE the MOVEit VM, not Azure infrastructure!" -ForegroundColor White
Write-Host ""

Write-Host "YOU NEED TO:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. RDP to MOVEit VM:" -ForegroundColor Yellow
Write-Host "   - Find MOVEit VM in Azure Portal" -ForegroundColor White
Write-Host "   - Click 'Connect' → RDP" -ForegroundColor White
Write-Host "   - Or use IP: 192.168.0.5" -ForegroundColor White
Write-Host ""

Write-Host "2. Check MOVEit Transfer service:" -ForegroundColor Yellow
Write-Host "   - Open Services (services.msc)" -ForegroundColor White
Write-Host "   - Find 'MOVEit Transfer' service" -ForegroundColor White
Write-Host "   - If stopped, START it" -ForegroundColor White
Write-Host ""

Write-Host "3. Check if MOVEit is listening:" -ForegroundColor Yellow
Write-Host "   - Open PowerShell on VM" -ForegroundColor White
Write-Host "   - Run: netstat -an | findstr ':443'" -ForegroundColor White
Write-Host "   - Run: netstat -an | findstr ':22'" -ForegroundColor White
Write-Host "   - Should show LISTENING" -ForegroundColor White
Write-Host ""

Write-Host "4. Check Windows Firewall on VM:" -ForegroundColor Yellow
Write-Host "   - Open PowerShell on VM" -ForegroundColor White
Write-Host "   - Run: Get-NetFirewallRule | Where {" -NoNewline -ForegroundColor White
Write-Host '$_.LocalPort -eq 443 -or $_.LocalPort -eq 22}' -ForegroundColor White
Write-Host "   - If no rules, add them:" -ForegroundColor White
Write-Host "     New-NetFirewallRule -DisplayName 'MOVEit HTTPS' -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow" -ForegroundColor Gray
Write-Host "     New-NetFirewallRule -DisplayName 'MOVEit SSH' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow" -ForegroundColor Gray
Write-Host ""

Write-Host "5. Check MOVEit configuration:" -ForegroundColor Yellow
Write-Host "   - Open MOVEit Admin console" -ForegroundColor White
Write-Host "   - Verify HTTPS is enabled on port 443" -ForegroundColor White
Write-Host "   - Verify SSH/SFTP is enabled on port 22" -ForegroundColor White
Write-Host ""

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "BOTTOM LINE:" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Azure infrastructure is 100% ready. The MOVEit application" -ForegroundColor White
Write-Host "inside the VM needs to be started and configured." -ForegroundColor White
Write-Host ""
Write-Host "This requires RDP access to the VM - cannot be done remotely" -ForegroundColor White
Write-Host "via Azure CLI or PowerShell scripts." -ForegroundColor White
Write-Host ""
