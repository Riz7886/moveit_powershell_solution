# CORRECT FIX - Front Door → Load Balancer → MOVEit Transfer VM

Clear-Host
Write-Host "CORRECT ARCHITECTURE FIX" -ForegroundColor Cyan
Write-Host ""

# Load config
$config = Get-Content "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json" | ConvertFrom-Json

# Get Load Balancer public IP
Write-Host "Getting Load Balancer IP..." -ForegroundColor Yellow
$lbIP = az network public-ip show --resource-group $config.DeploymentResourceGroup --name $config.PublicIPName --query ipAddress --output tsv

Write-Host "Load Balancer IP: $lbIP" -ForegroundColor Green
Write-Host ""

# Update Front Door to point to Load Balancer
Write-Host "Updating Front Door to point to Load Balancer..." -ForegroundColor Yellow

az afd origin update --resource-group $config.DeploymentResourceGroup --profile-name moveit-frontdoor-profile --origin-group-name moveit-origin-group --origin-name moveit-origin --host-name $lbIP --origin-host-header moveit.pyxhealth.com --enabled-state Enabled --http-port 80 --https-port 443

Write-Host "✅ Front Door now points to Load Balancer!" -ForegroundColor Green
Write-Host ""

# Wait
Write-Host "Waiting 30 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Test
Write-Host "Testing..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 | Out-Null
    Write-Host "✅ SUCCESS! https://moveit.pyxhealth.com works!" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Still propagating. Wait 5 minutes." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Architecture:" -ForegroundColor Cyan
Write-Host "  User → Front Door → Load Balancer ($lbIP) → MOVEit VM (192.168.0.5)" -ForegroundColor White
Write-Host ""
Write-Host "HTTPS: https://moveit.pyxhealth.com" -ForegroundColor Green
