param(
    [string]$AppServiceName = "PYXHEALTHFOWARDING",
    [string]$ResourceGroupName = ""
)

Write-Host ""
Write-Host "=========================================================="
Write-Host "MIGRATE STATUS PAGE - SAFE VERSION"
Write-Host "Will show you changes BEFORE applying"
Write-Host "=========================================================="
Write-Host ""

# Step 1: Check Azure Login
Write-Host "Step 1: Checking Azure login..." -ForegroundColor Yellow
try {
    $accountJson = az account show
    $account = $accountJson | ConvertFrom-Json
    Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "Not logged in. Please login..." -ForegroundColor Yellow
    az login --use-device-code
    $accountJson = az account show
    $account = $accountJson | ConvertFrom-Json
    Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
}

# Step 2: Find App Service
Write-Host ""
Write-Host "Step 2: Finding App Service..." -ForegroundColor Yellow

$appInfoJson = az webapp show --name $AppServiceName --query "{rg:resourceGroup, url:defaultHostName}" -o json
$appInfo = $appInfoJson | ConvertFrom-Json

if (-not $appInfo) {
    Write-Host "ERROR: App Service '$AppServiceName' not found!" -ForegroundColor Red
    exit 1
}

$ResourceGroupName = $appInfo.rg
$webappUrl = $appInfo.url
Write-Host "Found: $AppServiceName" -ForegroundColor Green

# Step 3: Get publishing credentials
Write-Host ""
Write-Host "Step 3: Getting credentials..." -ForegroundColor Yellow

$publishProfile = az webapp deployment list-publishing-profiles --name $AppServiceName --resource-group $ResourceGroupName --query "[?publishMethod=='FTP']" -o json | ConvertFrom-Json
$ftpUser = $publishProfile[0].userName
$ftpPass = $publishProfile[0].userPWD
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $ftpUser, $ftpPass)))

Write-Host "Got credentials" -ForegroundColor Green

# Step 4: Download current web.config
Write-Host ""
Write-Host "Step 4: Downloading current web.config..." -ForegroundColor Yellow

$kuduWebConfigUrl = "https://$AppServiceName.scm.azurewebsites.net/api/vfs/site/wwwroot/web.config"
$headersGet = @{Authorization = "Basic $base64Auth"}

try {
    $currentWebConfig = Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersGet -Method Get
    Write-Host "Downloaded current web.config" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not download web.config - $_" -ForegroundColor Red
    exit 1
}

# Step 5: Save backup locally
Write-Host ""
Write-Host "Step 5: Saving backup..." -ForegroundColor Yellow

$backupFolder = $PSScriptRoot
if (-not $backupFolder) { $backupFolder = Get-Location }
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $backupFolder "web.config.BACKUP-$timestamp.txt"

$currentWebConfig | Out-File -FilePath $backupPath -Encoding UTF8
Write-Host "BACKUP SAVED: $backupPath" -ForegroundColor Green

# Step 6: Show current rules
Write-Host ""
Write-Host "=========================================================="
Write-Host "CURRENT WEB.CONFIG - EXISTING RULES:" -ForegroundColor Cyan
Write-Host "=========================================================="

try {
    [xml]$xmlDoc = $currentWebConfig
    $rules = $xmlDoc.configuration.'system.webServer'.rewrite.rules.rule
    
    Write-Host ""
    Write-Host "Found $($rules.Count) existing rules:" -ForegroundColor Yellow
    Write-Host ""
    
    $ruleNum = 1
    foreach ($rule in $rules) {
        $ruleName = $rule.name
        $actionType = $rule.action.type
        $actionUrl = $rule.action.url
        
        if ($actionUrl.Length -gt 60) {
            $actionUrl = $actionUrl.Substring(0, 57) + "..."
        }
        
        Write-Host "  $ruleNum. $ruleName" -ForegroundColor White
        Write-Host "     Type: $actionType" -ForegroundColor Gray
        Write-Host "     URL: $actionUrl" -ForegroundColor Gray
        Write-Host ""
        $ruleNum++
    }
} catch {
    Write-Host "Could not parse XML - showing raw content:" -ForegroundColor Yellow
    Write-Host $currentWebConfig
}

# Step 7: Check if status rule already exists
Write-Host "=========================================================="
Write-Host "CHECKING FOR EXISTING STATUS RULE..." -ForegroundColor Yellow
Write-Host "=========================================================="

$statusRuleExists = $false
foreach ($rule in $rules) {
    if ($rule.name -eq "status-page" -or $rule.name -eq "status") {
        $statusRuleExists = $true
        Write-Host ""
        Write-Host "STATUS RULE ALREADY EXISTS!" -ForegroundColor Green
        Write-Host "No changes needed to web.config" -ForegroundColor Green
        break
    }
}

if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Status rule NOT found - will add it" -ForegroundColor Yellow
}

# Step 8: Create new web.config with status rule (using proper XML)
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "=========================================================="
    Write-Host "CREATING NEW WEB.CONFIG WITH STATUS RULE..." -ForegroundColor Yellow
    Write-Host "=========================================================="
    
    try {
        [xml]$xmlDoc = $currentWebConfig
        
        # Create the new status rule
        $newRule = $xmlDoc.CreateElement("rule")
        $newRule.SetAttribute("name", "status-page")
        $newRule.SetAttribute("stopProcessing", "true")
        
        # Create match element
        $match = $xmlDoc.CreateElement("match")
        $match.SetAttribute("url", ".*")
        $newRule.AppendChild($match) | Out-Null
        
        # Create conditions element
        $conditions = $xmlDoc.CreateElement("conditions")
        $add = $xmlDoc.CreateElement("add")
        $add.SetAttribute("input", "{HTTP_HOST}")
        $add.SetAttribute("pattern", "^status\.pyxhealth\.com$")
        $conditions.AppendChild($add) | Out-Null
        $newRule.AppendChild($conditions) | Out-Null
        
        # Create action element - REWRITE not REDIRECT
        $action = $xmlDoc.CreateElement("action")
        $action.SetAttribute("type", "Rewrite")
        $action.SetAttribute("url", "status.html")
        $newRule.AppendChild($action) | Out-Null
        
        # Insert as FIRST rule
        $rulesNode = $xmlDoc.configuration.'system.webServer'.rewrite.rules
        $firstRule = $rulesNode.FirstChild
        $rulesNode.InsertBefore($newRule, $firstRule) | Out-Null
        
        # Convert back to string
        $stringWriter = New-Object System.IO.StringWriter
        $xmlWriter = New-Object System.Xml.XmlTextWriter($stringWriter)
        $xmlWriter.Formatting = [System.Xml.Formatting]::Indented
        $xmlDoc.WriteTo($xmlWriter)
        $newWebConfig = $stringWriter.ToString()
        
        Write-Host "New web.config created successfully" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR creating new web.config: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Backup is saved at: $backupPath" -ForegroundColor Yellow
        exit 1
    }
    
    # Step 9: Show what will be added
    Write-Host ""
    Write-Host "=========================================================="
    Write-Host "NEW RULE TO BE ADDED (as FIRST rule):" -ForegroundColor Cyan
    Write-Host "=========================================================="
    Write-Host ""
    Write-Host '  <rule name="status-page" stopProcessing="true">' -ForegroundColor Green
    Write-Host '    <match url=".*" />' -ForegroundColor Green
    Write-Host '    <conditions>' -ForegroundColor Green
    Write-Host '      <add input="{HTTP_HOST}" pattern="^status\.pyxhealth\.com$" />' -ForegroundColor Green
    Write-Host '    </conditions>' -ForegroundColor Green
    Write-Host '    <action type="Rewrite" url="status.html" />' -ForegroundColor Green
    Write-Host '  </rule>' -ForegroundColor Green
    Write-Host ""
    
    # Step 10: Show all rules after change
    Write-Host "=========================================================="
    Write-Host "RULES AFTER CHANGE:" -ForegroundColor Cyan
    Write-Host "=========================================================="
    Write-Host ""
    Write-Host "  1. status-page (NEW - serves status.html)" -ForegroundColor Green
    
    $ruleNum = 2
    foreach ($rule in $rules) {
        Write-Host "  $ruleNum. $($rule.name) (UNCHANGED)" -ForegroundColor White
        $ruleNum++
    }
    Write-Host ""
}

# Step 11: Create status.html content
Write-Host "=========================================================="
Write-Host "STATUS.HTML CONTENT:" -ForegroundColor Cyan
Write-Host "=========================================================="
Write-Host ""
Write-Host "  Pyx Health System Status"
Write-Host "  All Systems Are Operational, with no current reported incidents."
Write-Host "  Click HERE to return to the Pyx Health Service Portal"
Write-Host "  (Links to: https://pyxhealth.samanage.com)"
Write-Host ""

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

# Step 12: CONFIRM BEFORE MAKING ANY CHANGES
Write-Host "=========================================================="
Write-Host "CONFIRMATION REQUIRED" -ForegroundColor Yellow
Write-Host "=========================================================="
Write-Host ""
Write-Host "WHAT WILL HAPPEN:" -ForegroundColor Cyan
Write-Host "  1. Upload status.html to App Service"
if (-not $statusRuleExists) {
    Write-Host "  2. Upload modified web.config (with status rule FIRST)"
    Write-Host "     - All existing rules UNCHANGED"
    Write-Host "     - Only adding ONE new rule at the top"
}
Write-Host ""
Write-Host "BACKUP LOCATION: $backupPath" -ForegroundColor Green
Write-Host ""
Write-Host "If anything goes wrong, you can restore from backup."
Write-Host ""

$confirm = Read-Host "Type YES to proceed (anything else cancels)"

if ($confirm -ne "YES") {
    Write-Host ""
    Write-Host "CANCELLED - No changes made." -ForegroundColor Yellow
    Write-Host "Backup saved at: $backupPath" -ForegroundColor Cyan
    exit 0
}

# Step 13: Upload status.html
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
    Write-Host "No changes made to web.config" -ForegroundColor Yellow
    exit 1
}

# Step 14: Upload modified web.config (only if status rule didn't exist)
if (-not $statusRuleExists) {
    Write-Host ""
    Write-Host "Uploading modified web.config..." -ForegroundColor Yellow
    
    try {
        Invoke-RestMethod -Uri $kuduWebConfigUrl -Headers $headersPut -Method Put -Body $newWebConfig -ContentType "application/xml; charset=utf-8"
        Write-Host "web.config updated!" -ForegroundColor Green
    } catch {
        Write-Host "ERROR uploading web.config: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "RESTORE BACKUP:" -ForegroundColor Yellow
        Write-Host "  The backup is at: $backupPath"
        Write-Host "  Upload it manually via Azure Portal > Kudu"
        exit 1
    }
}

# Step 15: Try to add custom domain
Write-Host ""
Write-Host "Adding custom domain..." -ForegroundColor Yellow

try {
    az webapp config hostname add --webapp-name $AppServiceName --resource-group $ResourceGroupName --hostname "status.pyxhealth.com"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Custom domain added!" -ForegroundColor Green
    } else {
        Write-Host "Domain pending - DNS CNAME needed first" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Domain pending - DNS CNAME needed first" -ForegroundColor Yellow
}

# Final Summary
Write-Host ""
Write-Host "=========================================================="
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "=========================================================="
Write-Host ""
Write-Host "COMPLETED:" -ForegroundColor Green
Write-Host "  [OK] status.html uploaded"
if (-not $statusRuleExists) {
    Write-Host "  [OK] web.config updated (status rule added)"
}
Write-Host "  [OK] All existing $($rules.Count) rules UNCHANGED"
Write-Host ""
Write-Host "BACKUP: $backupPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "=========================================================="
Write-Host "CLIENT NEEDS TO ADD DNS CNAME:" -ForegroundColor Yellow
Write-Host "=========================================================="
Write-Host ""
Write-Host "  Host:  status"
Write-Host "  Type:  CNAME"
Write-Host "  Value: $webappUrl"
Write-Host ""
Write-Host "=========================================================="
Write-Host ""
Write-Host "AFTER DNS:"
Write-Host "  1. Azure Portal > Add custom domain"
Write-Host "  2. Enable SSL certificate"
Write-Host "  3. Test https://status.pyxhealth.com"
Write-Host "  4. SHUTDOWN ON-PREMISES IIS"
Write-Host ""
Write-Host "=========================================================="
