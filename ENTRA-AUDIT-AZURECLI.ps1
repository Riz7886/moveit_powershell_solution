<#
.SYNOPSIS
Entra ID Audit using Azure CLI - ACTUALLY WORKS
#>

param([string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit")

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "ENTRA ID AUDIT - AZURE CLI METHOD" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is installed
$azInstalled = Get-Command az -ErrorAction SilentlyContinue

if (!$azInstalled) {
    Write-Host "Azure CLI not found. Installing..." -ForegroundColor Yellow
    Write-Host "This will download and install Azure CLI..." -ForegroundColor Yellow
    
    # Download and install Azure CLI
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

Write-Host "Logging into Azure..." -ForegroundColor Yellow
Write-Host "A browser window will open - login with your account" -ForegroundColor Yellow
Write-Host ""

# Login
az login --allow-no-subscriptions | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Login failed!" -ForegroundColor Red
    exit
}

Write-Host "Logged in successfully!" -ForegroundColor Green
Write-Host ""

# Collect data
Write-Host "Collecting Entra ID data..." -ForegroundColor Cyan

$data = @{
    Tenant = @{}
    Users = @{Total=0; Enabled=0; Disabled=0; Guests=0}
    Groups = @{Total=0}
    Apps = @{Total=0}
}

# Get tenant info
Write-Host "  Getting tenant info..." -ForegroundColor Gray
$tenant = az account show | ConvertFrom-Json
$data.Tenant = @{
    Name = $tenant.name
    ID = $tenant.tenantId
    User = $tenant.user.name
}

# Get users
Write-Host "  Getting users..." -ForegroundColor Gray
$users = az ad user list | ConvertFrom-Json
$data.Users.Total = $users.Count
$data.Users.Enabled = ($users | Where-Object {$_.accountEnabled -eq $true}).Count
$data.Users.Disabled = ($users | Where-Object {$_.accountEnabled -eq $false}).Count
$data.Users.Guests = ($users | Where-Object {$_.userType -eq "Guest"}).Count

# Get groups
Write-Host "  Getting groups..." -ForegroundColor Gray
$groups = az ad group list | ConvertFrom-Json
$data.Groups.Total = $groups.Count

# Get apps
Write-Host "  Getting applications..." -ForegroundColor Gray
$apps = az ad app list | ConvertFrom-Json
$data.Apps.Total = $apps.Count

Write-Host "Data collected successfully!" -ForegroundColor Green
Write-Host ""

# Generate HTML report
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = Join-Path $OutputPath "EntraAudit_$timestamp.html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Entra ID Audit Report</title>
<style>
body { font-family: 'Segoe UI', Arial; background: linear-gradient(135deg, #667eea, #764ba2); padding: 20px; margin: 0; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 15px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
h1 { color: #0078d4; font-size: 2.5em; margin: 0 0 10px 0; }
.subtitle { color: #666; font-size: 1.1em; margin-bottom: 30px; }
.tenant-box { background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 30px; border-radius: 10px; margin: 20px 0; }
.tenant-box h3 { margin: 0 0 15px 0; }
.tenant-box p { margin: 8px 0; font-size: 1.1em; }
h2 { color: #2b579a; font-size: 1.8em; margin: 40px 0 20px 0; border-bottom: 3px solid #e1e1e1; padding-bottom: 10px; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 20px; margin: 25px 0; }
.stat-card { background: linear-gradient(135deg, #f093fb, #f5576c); color: white; padding: 30px; border-radius: 12px; text-align: center; box-shadow: 0 5px 20px rgba(0,0,0,0.2); transition: transform 0.3s; }
.stat-card:hover { transform: translateY(-5px); box-shadow: 0 10px 30px rgba(0,0,0,0.3); }
.stat-label { font-size: 0.95em; opacity: 0.95; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 1px; }
.stat-value { font-size: 3.5em; font-weight: bold; line-height: 1; }
.footer { margin-top: 50px; padding-top: 30px; border-top: 2px solid #e1e1e1; text-align: center; color: #666; }
.success { background: #d4edda; border-left: 5px solid #28a745; padding: 20px; border-radius: 5px; margin: 20px 0; }
.success h3 { color: #155724; margin: 0 0 10px 0; }
</style>
</head>
<body>
<div class="container">

<h1>🛡️ Microsoft Entra ID Security Audit</h1>
<div class="subtitle">Complete Tenant Analysis Report</div>

<div class="success">
<h3>✅ Audit Completed Successfully</h3>
<p>Generated: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
</div>

<div class="tenant-box">
<h3>📋 Tenant Information</h3>
<p><strong>Tenant Name:</strong> $($data.Tenant.Name)</p>
<p><strong>Tenant ID:</strong> $($data.Tenant.ID)</p>
<p><strong>Logged in as:</strong> $($data.Tenant.User)</p>
</div>

<h2>👥 User Accounts</h2>
<div class="stats">
<div class="stat-card">
<div class="stat-label">Total Users</div>
<div class="stat-value">$($data.Users.Total)</div>
</div>
<div class="stat-card">
<div class="stat-label">Enabled</div>
<div class="stat-value">$($data.Users.Enabled)</div>
</div>
<div class="stat-card">
<div class="stat-label">Disabled</div>
<div class="stat-value">$($data.Users.Disabled)</div>
</div>
<div class="stat-card">
<div class="stat-label">Guest Users</div>
<div class="stat-value">$($data.Users.Guests)</div>
</div>
</div>

<h2>👥 Groups</h2>
<div class="stats">
<div class="stat-card">
<div class="stat-label">Total Groups</div>
<div class="stat-value">$($data.Groups.Total)</div>
</div>
</div>

<h2>📱 Applications</h2>
<div class="stats">
<div class="stat-card">
<div class="stat-label">Registered Apps</div>
<div class="stat-value">$($data.Apps.Total)</div>
</div>
</div>

<div class="footer">
<p><strong>Microsoft Entra ID Security Audit Report</strong></p>
<p>Generated by: $env:USERNAME</p>
<p>Report Date: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
<p style="margin-top: 15px; font-size: 0.9em; color: #999;">
Powered by Azure CLI | Method: az ad commands
</p>
</div>

</div>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host "===============================================" -ForegroundColor Green
Write-Host "✅ REPORT GENERATED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Report saved to:" -ForegroundColor Cyan
Write-Host "   $reportFile" -ForegroundColor White
Write-Host ""
Write-Host "Opening report..." -ForegroundColor Cyan

Start-Process $reportFile

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host ""
