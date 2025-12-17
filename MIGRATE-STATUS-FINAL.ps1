# MIGRATE STATUS PAGE TO AZURE - FINAL VERSION
# Enables Basic Auth, uploads status.html, updates web.config

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  MIGRATE STATUS PAGE TO AZURE APP SERVICE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Azure Login
Write-Host "Step 1: Checking Azure login..." -ForegroundColor Yellow

try {
    $accountJson = az account show
    $account = $accountJson | ConvertFrom-Json
} catch {
    $account = $null
}

if (-not $account) {
    Write-Host "Not logged in. Opening browser..." -ForegroundColor Yellow
    az login
    $accountJson = az account show
    $account = $accountJson | ConvertFrom-Json
}
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green

# Step 2: List subscriptions
Write-Host ""
Write-Host "Step 2: Getting subscriptions..." -ForegroundColor Yellow
Write-Host ""

$subscriptions = az account list --query "[].{Name:name, Id:id, State:state}" -o json | ConvertFrom-Json
$activeSubscriptions = $subscriptions | Where-Object { $_.State -eq "Enabled" }

Write-Host "Available Subscriptions:" -ForegroundColor Cyan
Write-Host ""

$i = 1
foreach ($sub in $activeSubscriptions) {
    Write-Host "  $i. $($sub.Name)" -ForegroundColor White
    $i++
}

Write-Host ""
$selection = Read-Host "Select subscription number"

$selectedSub = $activeSubscriptions[$selection - 1]
Write-Host "Selected: $($selectedSub.Name)" -ForegroundColor Green

# Step 3: Switch subscription
Write-Host ""
Write-Host "Step 3: Switching to subscription..." -ForegroundColor Yellow
az account set --subscription $selectedSub.Id
Write-Host "Done!" -ForegroundColor Green

# Step 4: Find App Service
Write-Host ""
Write-Host "Step 4: Finding PYXHEALTHFOWARDING..." -ForegroundColor Yellow

$appService = az webapp list --query "[?contains(name,'PYXHEALTHFOWARDING')].{name:name, rg:resourceGroup}" -o json | ConvertFrom-Json

if (-not $appService -or $appService.Count -eq 0) {
    $allApps = az webapp list --query "[].{name:name, rg:resourceGroup}" -o json | ConvertFrom-Json
    Write-Host "Select App Service:" -ForegroundColor Cyan
    $j = 1
    foreach ($app in $allApps) {
        Write-Host "  $j. $($app.name)" -ForegroundColor White
        $j++
    }
    $appSelection = Read-Host "Select number"
    $appService = $allApps[$appSelection - 1]
} else {
    $appService = $appService[0]
}

$AppServiceName = $appService.name
$ResourceGroupName = $appService.rg

Write-Host "Found: $AppServiceName (RG: $ResourceGroupName)" -ForegroundColor Green

# Step 5: Get URL
Write-Host ""
Write-Host "Step 5: Getting App Service URL..." -ForegroundColor Yellow
$webappUrl = az webapp show --name $AppServiceName --resource-group $ResourceGroupName --query "defaultHostName" -o tsv
Write-Host "URL: $webappUrl" -ForegroundColor Cyan

# Step 6: Enable Basic Auth for SCM
Write-Host ""
Write-Host "Step 6: Enabling Basic Auth for Kudu..." -ForegroundColor Yellow

az resource update --resource-group $ResourceGroupName --name scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/$AppServiceName --set properties.allow=true

az resource update --resource-group $ResourceGroupName --name ftp --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies --parent sites/$AppServiceName --set properties.allow=true

Write-Host "Basic Auth enabled!" -ForegroundColor Green

# Step 7: Get publishing credentials
Write-Host ""
Write-Host "Step 7: Getting credentials..." -ForegroundColor Yellow

$publishProfile = az webapp deployment list-publishing-profiles --name $AppServiceName --resource-group $ResourceGroupName --query "[?publishMethod=='FTP']" -o json | ConvertFrom-Json
$ftpUser = $publishProfile[0].userName
$ftpPass = $publishProfile[0].userPWD
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $ftpUser, $ftpPass)))

Write-Host "Got credentials!" -ForegroundColor Green

# Step 8: Build SCM URL
$urlParts = $webappUrl -split "\.", 2
$scmHost = "$($urlParts[0]).scm.$($urlParts[1])"
Write-Host "SCM URL: $scmHost" -ForegroundColor Cyan

# Step 9: Download current web.config
Write-Host ""
Write-Host "Step 8: Downloading current web.config..." -ForegroundColor Yellow

$kuduWebConfigUrl = "https://$scmHost/api/vfs/site/wwwroot/web.config"
$headersGet = @{Authorization = "Basic $base64Auth"}

$backupFolder = $PSScriptRoot
if (-not $backupFolder) { $backupFolder = Get-Location }
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupFolder "web.config.BACKUP-$timestamp.xml"

try {
    $currentWebConfig = Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersGet -Method Get
    Write-Host "Downloaded!" -ForegroundColor Green
    $currentWebConfig | Out-File -FilePath $backupPath -Encoding UTF8
    Write-Host "Backup saved: $backupPath" -ForegroundColor Cyan
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

# Step 10: Check for existing status rule
Write-Host ""
Write-Host "Step 9: Checking existing rules..." -ForegroundColor Yellow

[xml]$xmlDoc = $currentWebConfig
$rules = $xmlDoc.configuration.'system.webServer'.rewrite.rules.rule

Write-Host "Found $($rules.Count) existing rules" -ForegroundColor Cyan

$statusRuleExists = $false
foreach ($rule in $rules) {
    if ($rule.name -eq "status-page" -or $rule.name -eq "status") {
        $statusRuleExists = $true
        Write-Host "Status rule already exists!" -ForegroundColor Green
        break
    }
}

# Step 11: Add status rule if needed
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Step 10: Adding status rule..." -ForegroundColor Yellow
    
    $newRule = $xmlDoc.CreateElement("rule")
    $newRule.SetAttribute("name", "status-page")
    $newRule.SetAttribute("stopProcessing", "true")
    
    $match = $xmlDoc.CreateElement("match")
    $match.SetAttribute("url", ".*")
    $newRule.AppendChild($match) | Out-Null
    
    $conditions = $xmlDoc.CreateElement("conditions")
    $add = $xmlDoc.CreateElement("add")
    $add.SetAttribute("input", "{HTTP_HOST}")
    $add.SetAttribute("pattern", "^status\.pyxhealth\.com$")
    $conditions.AppendChild($add) | Out-Null
    $newRule.AppendChild($conditions) | Out-Null
    
    $action = $xmlDoc.CreateElement("action")
    $action.SetAttribute("type", "Rewrite")
    $action.SetAttribute("url", "status.html")
    $newRule.AppendChild($action) | Out-Null
    
    $rulesNode = $xmlDoc.configuration.'system.webServer'.rewrite.rules
    $firstRule = $rulesNode.FirstChild
    $rulesNode.InsertBefore($newRule, $firstRule) | Out-Null
    
    $stringWriter = New-Object System.IO.StringWriter
    $xmlWriter = New-Object System.Xml.XmlTextWriter($stringWriter)
    $xmlWriter.Formatting = [System.Xml.Formatting]::Indented
    $xmlDoc.WriteTo($xmlWriter)
    $newWebConfig = $stringWriter.ToString()
    
    Write-Host "Rule added!" -ForegroundColor Green
} else {
    $newWebConfig = $currentWebConfig
}

# Step 12: Create status.html
Write-Host ""
Write-Host "Step 11: Creating status.html..." -ForegroundColor Yellow

$htmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pyx Health System Status</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-color: #ffffff;
        }
        .container {
            text-align: center;
            padding: 40px;
        }
        h1 {
            color: #000000;
            font-size: 28px;
            font-weight: bold;
            margin-bottom: 20px;
        }
        p {
            color: #000000;
            font-size: 16px;
            margin-bottom: 15px;
        }
        .operational {
            color: #006400;
            font-weight: bold;
        }
        a {
            color: #0066cc;
            text-decoration: none;
            font-weight: bold;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Pyx Health System Status</h1>
        <p class="operational">All Systems Are Operational, with no current reported incidents.</p>
        <p>Click <a href="https://pyxhealth.samanage.com">HERE</a> to return to the Pyx Health Service Portal</p>
    </div>
</body>
</html>
'@

Write-Host "status.html ready!" -ForegroundColor Green

# Step 13: Confirm
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "READY TO DEPLOY" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "App Service: $AppServiceName" -ForegroundColor Cyan
Write-Host "Will upload: status.html" -ForegroundColor White
if (-not $statusRuleExists) {
    Write-Host "Will update: web.config (add status rule)" -ForegroundColor White
}
Write-Host "Backup at: $backupPath" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Type YES to deploy"

if ($confirm -ne "YES") {
    Write-Host "CANCELLED" -ForegroundColor Yellow
    exit 0
}

# Step 14: Upload status.html
Write-Host ""
Write-Host "Uploading status.html..." -ForegroundColor Yellow

$kuduStatusUrl = "https://$scmHost/api/vfs/site/wwwroot/status.html"
$headersPut = @{
    Authorization = "Basic $base64Auth"
    "If-Match" = "*"
}

try {
    Invoke-RestMethod -Uri $kuduStatusUrl -Headers $headersPut -Method Put -Body $htmlContent -ContentType "text/html; charset=utf-8"
    Write-Host "status.html uploaded!" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}

# Step 15: Upload web.config
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Uploading web.config..." -ForegroundColor Yellow
    
    try {
        Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersPut -Method Put -Body $newWebConfig -ContentType "application/xml; charset=utf-8"
        Write-Host "web.config updated!" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
        Write-Host "Restore backup from: $backupPath" -ForegroundColor Yellow
        exit 1
    }
}

# Step 16: Add custom domain
Write-Host ""
Write-Host "Adding custom domain..." -ForegroundColor Yellow

try {
    az webapp config hostname add --webapp-name $AppServiceName --resource-group $ResourceGroupName --hostname "status.pyxhealth.com"
    Write-Host "Domain added!" -ForegroundColor Green
} catch {
    Write-Host "Domain pending - DNS needed first" -ForegroundColor Yellow
}

# Done
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "COMPLETED:" -ForegroundColor Green
Write-Host "  [OK] status.html uploaded" -ForegroundColor Green
Write-Host "  [OK] web.config updated" -ForegroundColor Green
Write-Host "  [OK] All existing rules unchanged" -ForegroundColor Green
Write-Host ""
Write-Host "DNS CNAME FOR CLIENT:" -ForegroundColor Yellow
Write-Host "  Host:  status" -ForegroundColor White
Write-Host "  Type:  CNAME" -ForegroundColor White
Write-Host "  Value: $webappUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "AFTER DNS:" -ForegroundColor Yellow
Write-Host "  1. Add custom domain in Azure Portal" -ForegroundColor White
Write-Host "  2. Enable SSL certificate" -ForegroundColor White
Write-Host "  3. Test https://status.pyxhealth.com" -ForegroundColor White
Write-Host "  4. SHUTDOWN ON-PREMISES IIS SERVER" -ForegroundColor White
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
