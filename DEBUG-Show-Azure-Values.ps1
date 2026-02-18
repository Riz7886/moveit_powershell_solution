param(
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    DEBUG SCRIPT - SHOW ME WHAT AZURE IS RETURNING" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure connection
try {
    $context = Get-AzContext -ErrorAction Stop
    if (!$context) {
        Connect-AzAccount | Out-Null
        $context = Get-AzContext
    }
    Write-Host "Connected: $($context.Account.Id)" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "ERROR: Not connected!" -ForegroundColor Red
    exit 1
}

Write-Host "Getting NSGs..." -ForegroundColor Yellow
Write-Host ""

$nsgs = Get-AzNetworkSecurityGroup

Write-Host "Found $($nsgs.Count) NSGs" -ForegroundColor Green
Write-Host ""

foreach ($nsg in $nsgs) {
    Write-Host "NSG: $($nsg.Name)" -ForegroundColor Cyan
    Write-Host "  Rules: $($nsg.SecurityRules.Count)" -ForegroundColor White
    
    foreach ($rule in $nsg.SecurityRules) {
        Write-Host ""
        Write-Host "  Rule: $($rule.Name)" -ForegroundColor Yellow
        Write-Host "    Direction: $($rule.Direction)" -ForegroundColor Gray
        Write-Host "    Access: $($rule.Access)" -ForegroundColor Gray
        
        $src = $rule.SourceAddressPrefix
        Write-Host "    SourceAddressPrefix VALUE: $src" -ForegroundColor White
        Write-Host "    SourceAddressPrefix TYPE: $($src.GetType().Name)" -ForegroundColor Magenta
        
        # Test -contains on string vs array
        if ($src -is [string]) {
            Write-Host "    IT'S A STRING!" -ForegroundColor Red
            Write-Host "    Test: '$src' -contains '*' = $($src -contains '*')" -ForegroundColor Red
            Write-Host "    Test: '$src' -eq '*' = $($src -eq '*')" -ForegroundColor Green
        } elseif ($src -is [array]) {
            Write-Host "    IT'S AN ARRAY!" -ForegroundColor Green
            Write-Host "    Test: array -contains '*' = $($src -contains '*')" -ForegroundColor Green
        }
        
        $dst = $rule.DestinationPortRange
        Write-Host "    DestinationPortRange VALUE: $dst" -ForegroundColor White
        Write-Host "    DestinationPortRange TYPE: $($dst.GetType().Name)" -ForegroundColor Magenta
        
        if ($dst -is [string]) {
            Write-Host "    IT'S A STRING!" -ForegroundColor Red
            Write-Host "    Test: '$dst' -contains '22' = $($dst -contains '22')" -ForegroundColor Red
            Write-Host "    Test: '$dst' -eq '22' = $($dst -eq '22')" -ForegroundColor Green
        } elseif ($dst -is [array]) {
            Write-Host "    IT'S AN ARRAY!" -ForegroundColor Green
            Write-Host "    Test: array -contains '22' = $($dst -contains '22')" -ForegroundColor Green
        }
    }
    Write-Host ""
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "DEBUG COMPLETE - CHECK ABOVE TO SEE IF THEY ARE STRINGS!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
