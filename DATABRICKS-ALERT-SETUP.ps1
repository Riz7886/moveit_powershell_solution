# DATABRICKS COST ALERT AUTO-SETUP
# Automatically creates Azure budgets and email alerts

param(
    [Parameter(Mandatory=$false)]
    [int]$MonthlyBudget = 5000,
    
    [Parameter(Mandatory=$false)]
    [string[]]$AlertEmails = @(
        "preyash.patel@pyxhealth.com",
        "tony@pyxhealth.com", 
        "john@pyxhealth.com"
    )
)

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DATABRICKS ALERT AUTO-SETUP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monthly Budget: `$$MonthlyBudget" -ForegroundColor Yellow
Write-Host "Email Recipients: $($AlertEmails.Count)" -ForegroundColor Yellow
foreach ($email in $AlertEmails) {
    Write-Host "  - $email" -ForegroundColor White
}
Write-Host ""

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount | Out-Null
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot connect to Azure" -ForegroundColor Red
    exit
}

Write-Host ""

# Get all subscriptions
$subs = Get-AzSubscription
Write-Host "Found $($subs.Count) subscriptions" -ForegroundColor Green
Write-Host ""

$setupCount = 0
$errorCount = 0

foreach ($sub in $subs) {
    Write-Host "Subscription: $($sub.Name)" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "  Cannot access - skipping" -ForegroundColor Red
        $errorCount++
        continue
    }
    
    # Check if there are Databricks workspaces in this subscription
    $workspaces = Get-AzResource -ResourceType "Microsoft.Databricks/workspaces" -ErrorAction SilentlyContinue
    
    if (-not $workspaces -or $workspaces.Count -eq 0) {
        Write-Host "  No Databricks - skipping alert setup" -ForegroundColor Gray
        continue
    }
    
    Write-Host "  Found $($workspaces.Count) Databricks workspace(s)" -ForegroundColor Green
    Write-Host "  Setting up cost alerts..." -ForegroundColor Yellow
    
    # Budget name
    $budgetName = "Databricks-Monthly-Budget-$($sub.Name)"
    
    # Check if budget already exists
    $existingBudget = Get-AzConsumptionBudget -Name $budgetName -ErrorAction SilentlyContinue
    
    if ($existingBudget) {
        Write-Host "  Budget already exists - updating..." -ForegroundColor Yellow
        
        try {
            Remove-AzConsumptionBudget -Name $budgetName -ErrorAction Stop
            Write-Host "  Removed old budget" -ForegroundColor Green
        } catch {
            Write-Host "  Could not remove old budget: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Create filter for Databricks resources only
    $filter = New-AzConsumptionBudgetFilterObject -ResourceGroup $workspaces[0].ResourceGroupName
    
    # Create 4 notification thresholds
    $notifications = @{}
    
    # Alert 1: 50% of budget
    $notifications["Alert1-50Percent"] = New-AzConsumptionBudgetNotificationObject `
        -Enabled $true `
        -Operator GreaterThan `
        -Threshold 50 `
        -ContactEmail $AlertEmails `
        -ThresholdType Actual
    
    # Alert 2: 80% of budget
    $notifications["Alert2-80Percent"] = New-AzConsumptionBudgetNotificationObject `
        -Enabled $true `
        -Operator GreaterThan `
        -Threshold 80 `
        -ContactEmail $AlertEmails `
        -ThresholdType Actual
    
    # Alert 3: 100% of budget
    $notifications["Alert3-100Percent"] = New-AzConsumptionBudgetNotificationObject `
        -Enabled $true `
        -Operator GreaterThan `
        -Threshold 100 `
        -ContactEmail $AlertEmails `
        -ThresholdType Actual
    
    # Alert 4: 120% of budget (overage)
    $notifications["Alert4-120Percent"] = New-AzConsumptionBudgetNotificationObject `
        -Enabled $true `
        -Operator GreaterThan `
        -Threshold 120 `
        -ContactEmail $AlertEmails `
        -ThresholdType Actual
    
    # Create time period (current month + recurring)
    $startDate = Get-Date -Day 1
    $timePeriod = New-AzConsumptionBudgetTimePeriodObject -StartDate $startDate
    
    # Create the budget
    try {
        New-AzConsumptionBudget `
            -Name $budgetName `
            -Amount $MonthlyBudget `
            -Category Cost `
            -TimeGrain Monthly `
            -TimePeriod $timePeriod `
            -Notification $notifications `
            -ErrorAction Stop | Out-Null
        
        Write-Host "  SUCCESS: Budget created!" -ForegroundColor Green
        Write-Host "    Budget Name: $budgetName" -ForegroundColor White
        Write-Host "    Amount: `$$MonthlyBudget/month" -ForegroundColor White
        Write-Host "    Alerts: 50%, 80%, 100%, 120%" -ForegroundColor White
        Write-Host "    Emails: $($AlertEmails.Count) recipients" -ForegroundColor White
        Write-Host ""
        
        $setupCount++
        
    } catch {
        Write-Host "  ERROR: Could not create budget" -ForegroundColor Red
        Write-Host "  Reason: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        $errorCount++
    }
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Budgets created: $setupCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor $(if($errorCount -gt 0){"Red"}else{"Green"})
Write-Host ""

if ($setupCount -gt 0) {
    Write-Host "ALERT CONFIGURATION:" -ForegroundColor Cyan
    Write-Host "  Alert 1: 50% of budget (`$$($MonthlyBudget * 0.5))" -ForegroundColor White
    Write-Host "  Alert 2: 80% of budget (`$$($MonthlyBudget * 0.8))" -ForegroundColor White
    Write-Host "  Alert 3: 100% of budget (`$$MonthlyBudget)" -ForegroundColor White
    Write-Host "  Alert 4: 120% of budget (`$$($MonthlyBudget * 1.2)) - OVERAGE WARNING" -ForegroundColor Red
    Write-Host ""
    Write-Host "Email Recipients:" -ForegroundColor Cyan
    foreach ($email in $AlertEmails) {
        Write-Host "  - $email" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "All recipients will receive emails when thresholds are hit!" -ForegroundColor Green
}

Write-Host ""
Write-Host "To verify alerts in Azure Portal:" -ForegroundColor Yellow
Write-Host "  1. Go to portal.azure.com" -ForegroundColor White
Write-Host "  2. Search for 'Cost Management + Billing'" -ForegroundColor White
Write-Host "  3. Click 'Budgets' in left menu" -ForegroundColor White
Write-Host "  4. You should see 'Databricks-Monthly-Budget-*' budgets" -ForegroundColor White
Write-Host ""

Write-Host "DONE!" -ForegroundColor Green
