# MIGRATE STATUS PAGE TO AZURE - SMART VERSION
# Lists subscriptions, auto-detects App Service, fully automated

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  MIGRATE STATUS PAGE TO AZURE APP SERVICE" -ForegroundColor Cyan
Write-Host "  Smart Detection - Fully Automated" -ForegroundColor Cyan
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
    Write-Host "Not logged in. Opening browser for login..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green

# Step 2: List all subscriptions
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
$selection = Read-Host "Select subscription number (1-$($activeSubscriptions.Count))"

$selectedSub = $activeSubscriptions[$selection - 1]
Write-Host ""
Write-Host "Selected: $($selectedSub.Name)" -ForegroundColor Green

# Step 3: Switch to selected subscription
Write-Host ""
Write-Host "Step 3: Switching to subscription..." -ForegroundColor Yellow

az account set --subscription $selectedSub.Id
Write-Host "Subscription set!" -ForegroundColor Green

# Step 4: Find PYXHEALTHFOWARDING App Service
Write-Host ""
Write-Host "Step 4: Finding PYXHEALTHFOWARDING App Service..." -ForegroundColor Yellow

$appService = az webapp list --query "[?contains(name,'PYXHEALTHFOWARDING') || contains(name,'FOWARDING') || contains(name,'pyxhealth')].{name:name, rg:resourceGroup, url:defaultHostName}" -o json | ConvertFrom-Json

if (-not $appService -or $appService.Count -eq 0) {
    Write-Host "App Service not found in this subscription." -ForegroundColor Red
    Write-Host "Searching all App Services..." -ForegroundColor Yellow
    
    $allApps = az webapp list --query "[].{name:name, rg:resourceGroup}" -o json | ConvertFrom-Json
    
    if ($allApps.Count -gt 0) {
        Write-Host ""
        Write-Host "Found these App Services:" -ForegroundColor Cyan
        $j = 1
        foreach ($app in $allApps) {
            Write-Host "  $j. $($app.name) (RG: $($app.rg))" -ForegroundColor White
            $j++
        }
        Write-Host ""
        $appSelection = Read-Host "Select App Service number"
        $appService = $allApps[$appSelection - 1]
    } else {
        Write-Host "No App Services found. Exiting." -ForegroundColor Red
        exit 1
    }
} else {
    $appService = $appService[0]
}

$AppServiceName = $appService.name
$ResourceGroupName = $appService.rg

Write-Host ""
Write-Host "Found App Service!" -ForegroundColor Green
Write-Host "  Name: $AppServiceName" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Cyan

# Step 5: Get App Service URL
Write-Host ""
Write-Host "Step 5: Getting App Service details..." -ForegroundColor Yellow

$webappUrl = az webapp show --name $AppServiceName --resource-group $ResourceGroupName --query "defaultHostName" -o tsv
Write-Host "URL: $webappUrl" -ForegroundColor Cyan

# Step 6: Get publishing credentials
Write-Host ""
Write-Host "Step 6: Getting publishing credentials..." -ForegroundColor Yellow

$publishProfile = az webapp deployment list-publishing-profiles --name $AppServiceName --resource-group $ResourceGroupName --query "[?publishMethod=='FTP']" -o json | ConvertFrom-Json
$ftpUser = $publishProfile[0].userName
$ftpPass = $publishProfile[0].userPWD
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $ftpUser, $ftpPass)))

Write-Host "Got credentials!" -ForegroundColor Green

# Step 7: Download current web.config
Write-Host ""
Write-Host "Step 7: Downloading current web.config..." -ForegroundColor Yellow

$kuduWebConfigUrl = "https://$AppServiceName.scm.azurewebsites.net/api/vfs/site/wwwroot/web.config"
$headersGet = @{Authorization = "Basic $base64Auth"}

try {
    $currentWebConfig = Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersGet -Method Get
    Write-Host "Downloaded current web.config!" -ForegroundColor Green
} catch {
    Write-Host "ERROR downloading web.config: $_" -ForegroundColor Red
    exit 1
}

# Step 8: Save backup
Write-Host ""
Write-Host "Step 8: Saving backup..." -ForegroundColor Yellow

$backupFolder = $PSScriptRoot
if (-not $backupFolder) { $backupFolder = Get-Location }
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupFolder "web.config.BACKUP-$timestamp.txt"

$currentWebConfig | Out-File -FilePath $backupPath -Encoding UTF8
Write-Host "BACKUP SAVED: $backupPath" -ForegroundColor Green

# Step 9: Show current rules
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "CURRENT RULES IN WEB.CONFIG:" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

try {
    [xml]$xmlDoc = $currentWebConfig
    $rules = $xmlDoc.configuration.'system.webServer'.rewrite.rules.rule
    
    Write-Host "Found $($rules.Count) existing rules:" -ForegroundColor Yellow
    Write-Host ""
    
    $ruleNum = 1
    foreach ($rule in $rules) {
        $ruleName = $rule.name
        Write-Host "  $ruleNum. $ruleName" -ForegroundColor White
        $ruleNum++
    }
} catch {
    Write-Host "Could not parse rules" -ForegroundColor Yellow
}

# Step 10: Check if status rule exists
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "CHECKING FOR STATUS RULE..." -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$statusRuleExists = $false
foreach ($rule in $rules) {
    if ($rule.name -eq "status-page" -or $rule.name -eq "status") {
        $statusRuleExists = $true
        Write-Host ""
        Write-Host "STATUS RULE ALREADY EXISTS - No web.config changes needed!" -ForegroundColor Green
        break
    }
}

if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Status rule NOT found - will add it" -ForegroundColor Yellow
}

# Step 11: Create new web.config with status rule
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Step 11: Adding status rule to web.config..." -ForegroundColor Yellow
    
    try {
        [xml]$xmlDoc = $currentWebConfig
        
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
        
        Write-Host "Status rule added to web.config!" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR creating new web.config: $_" -ForegroundColor Red
        Write-Host "Backup saved at: $backupPath" -ForegroundColor Yellow
        exit 1
    }
}

# Step 12: Create status.html
Write-Host ""
Write-Host "Step 12: Creating status.html..." -ForegroundColor Yellow

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

# Step 13: Confirm before deploying
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "READY TO DEPLOY" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "App Service: $AppServiceName" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host ""
Write-Host "WHAT WILL HAPPEN:" -ForegroundColor White
Write-Host "  1. Upload status.html" -ForegroundColor White
if (-not $statusRuleExists) {
    Write-Host "  2. Update web.config (add status rule at top)" -ForegroundColor White
    Write-Host "     - All existing $($rules.Count) rules UNCHANGED" -ForegroundColor Green
}
Write-Host ""
Write-Host "BACKUP: $backupPath" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Type YES to deploy"

if ($confirm -ne "YES") {
    Write-Host ""
    Write-Host "CANCELLED - No changes made." -ForegroundColor Yellow
    exit 0
}

# Step 14: Upload status.html
Write-Host ""
Write-Host "Uploading status.html..." -ForegroundColor Yellow

$kuduStatusUrl = "https://$AppServiceName.scm.azurewebsites.net/api/vfs/site/wwwroot/status.html"
$headersPut = @{
    Authorization = "Basic $base64Auth"
    "If-Match" = "*"
}

try {
    Invoke-RestMethod -Uri $kuduStatusUrl -Headers $headersPut -Method Put -Body $htmlContent -ContentType "text/html; charset=utf-8"
    Write-Host "status.html uploaded!" -ForegroundColor Green
} catch {
    Write-Host "ERROR uploading status.html: $_" -ForegroundColor Red
    exit 1
}

# Step 15: Upload modified web.config
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Uploading modified web.config..." -ForegroundColor Yellow
    
    try {
        Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersPut -Method Put -Body $newWebConfig -ContentType "application/xml; charset=utf-8"
        Write-Host "web.config updated!" -ForegroundColor Green
    } catch {
        Write-Host "ERROR uploading web.config: $_" -ForegroundColor Red
        Write-Host "RESTORE FROM: $backupPath" -ForegroundColor Yellow
        exit 1
    }
}

# Step 16: Add custom domain
Write-Host ""
Write-Host "Adding custom domain status.pyxhealth.com..." -ForegroundColor Yellow

try {
    az webapp config hostname add --webapp-name $AppServiceName --resource-group $ResourceGroupName --hostname "status.pyxhealth.com"
    Write-Host "Custom domain added!" -ForegroundColor Green
} catch {
    Write-Host "Domain pending - DNS CNAME needed first" -ForegroundColor Yellow
}

# Final Summary
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "COMPLETED:" -ForegroundColor Green
Write-Host "  [OK] status.html uploaded" -ForegroundColor Green
if (-not $statusRuleExists) {
    Write-Host "  [OK] web.config updated (status rule added)" -ForegroundColor Green
}
Write-Host "  [OK] All existing rules UNCHANGED" -ForegroundColor Green
Write-Host ""
Write-Host "BACKUP: $backupPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "CLIENT NEEDS TO ADD DNS CNAME:" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Host:  status" -ForegroundColor White
Write-Host "  Type:  CNAME" -ForegroundColor White
Write-Host "  Value: $webappUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "AFTER DNS:"
Write-Host "  1. Azure Portal > Add custom domain"
Write-Host "  2. Enable SSL certificate"
Write-Host "  3. Test https://status.pyxhealth.com"
Write-Host "  4. SHUTDOWN ON-PREMISES IIS SERVER"
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
