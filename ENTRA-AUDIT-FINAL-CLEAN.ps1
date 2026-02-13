param([string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ENTRA ID AUDIT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$az = Get-Command az -ErrorAction SilentlyContinue
if (!$az) {
    Write-Host "Installing Azure CLI..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
}

Write-Host "Login to Azure..." -ForegroundColor Yellow
az login --allow-no-subscriptions

Write-Host "Getting data..." -ForegroundColor Cyan
$tenant = az account show | ConvertFrom-Json
$users = az ad user list | ConvertFrom-Json
$groups = az ad group list | ConvertFrom-Json

$d = @{
    TName = $tenant.name
    TID = $tenant.tenantId
    UTotal = $users.Count
    UEnabled = ($users | Where-Object {$_.accountEnabled}).Count
    UDisabled = ($users | Where-Object {!$_.accountEnabled}).Count
    GTotal = $groups.Count
}

if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$f = Join-Path $OutputPath "EntraAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

@"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Entra Audit</title>
<style>
body{font-family:Arial;background:#667eea;padding:20px}
.box{max-width:1000px;margin:0 auto;background:white;padding:40px;border-radius:15px}
h1{color:#0078d4}
.info{background:#667eea;color:white;padding:20px;border-radius:10px;margin:20px 0}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;margin:20px 0}
.stat{background:#f093fb;color:white;padding:20px;border-radius:10px;text-align:center}
.num{font-size:3em;font-weight:bold}
</style></head><body>
<div class="box">
<h1>Entra ID Audit</h1>
<div class="info">
<p><b>Tenant:</b> $($d.TName)</p>
<p><b>ID:</b> $($d.TID)</p>
<p><b>Date:</b> $(Get-Date)</p>
</div>
<h2>Users</h2>
<div class="stats">
<div class="stat"><div>Total</div><div class="num">$($d.UTotal)</div></div>
<div class="stat"><div>Enabled</div><div class="num">$($d.UEnabled)</div></div>
<div class="stat"><div>Disabled</div><div class="num">$($d.UDisabled)</div></div>
</div>
<h2>Groups</h2>
<div class="stats">
<div class="stat"><div>Total</div><div class="num">$($d.GTotal)</div></div>
</div>
</div></body></html>
"@ | Out-File -FilePath $f -Encoding UTF8

Write-Host "DONE! $f" -ForegroundColor Green
Start-Process $f
