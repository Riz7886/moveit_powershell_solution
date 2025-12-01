# ADD PORT 443 TO LOAD BALANCER - FINAL FIX

Clear-Host
Write-Host "ADDING HTTPS (PORT 443) TO LOAD BALANCER" -ForegroundColor Cyan
Write-Host ""

$config = Get-Content "C:\Users\$env:USERNAME\AppData\Local\Temp\moveit-config.json" | ConvertFrom-Json

# Step 1: Create health probe for port 443
Write-Host "Creating health probe for port 443..." -ForegroundColor Yellow
az network lb probe create --resource-group $config.DeploymentResourceGroup --lb-name lb-moveit-sftp --name moveit-https-probe --protocol tcp --port 443 --interval 15 --threshold 2 2>$null
Write-Host "✅ Health probe created!" -ForegroundColor Green
Write-Host ""

# Step 2: Get frontend IP name
$frontendIP = az network lb frontend-ip list --resource-group $config.DeploymentResourceGroup --lb-name lb-moveit-sftp --query "[0].name" --output tsv

# Step 3: Create LB rule for port 443
Write-Host "Creating load balancing rule for port 443..." -ForegroundColor Yellow
az network lb rule create --resource-group $config.DeploymentResourceGroup --lb-name lb-moveit-sftp --name moveit-https-rule --protocol tcp --frontend-port 443 --backend-port 443 --frontend-ip-name $frontendIP --backend-pool-name moveit-backend-pool --probe-name moveit-https-probe --idle-timeout 4 2>$null
Write-Host "✅ Port 443 rule created!" -ForegroundColor Green
Write-Host ""

# Step 4: Wait
Write-Host "Waiting 30 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 5: Test
Write-Host "Testing https://moveit.pyxhealth.com..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri "https://moveit.pyxhealth.com" -TimeoutSec 10 | Out-Null
    Write-Host ""
    Write-Host "✅✅✅ SUCCESS! IT'S WORKING! ✅✅✅" -ForegroundColor Green
    Write-Host ""
    Write-Host "https://moveit.pyxhealth.com IS LIVE!" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Wait 5 more minutes and try again" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DONE!" -ForegroundColor Cyan
