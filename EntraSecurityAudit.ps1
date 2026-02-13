param([string]$OutputPath = "$env:USERPROFILE\Desktop\EntraAudit")

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "ENTRA ID COMPLETE SECURITY AUDIT" -ForegroundColor Cyan  
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$az = Get-Command az -ErrorAction SilentlyContinue
if (!$az) {
    Write-Host "Installing Azure CLI..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
}

Write-Host "Logging in..." -ForegroundColor Yellow
az login --allow-no-subscriptions | Out-Null

Write-Host "Collecting comprehensive security data..." -ForegroundColor Cyan

# Tenant
Write-Host "  [1/15] Tenant info" -ForegroundColor Gray
$tenant = az account show | ConvertFrom-Json

# Users
Write-Host "  [2/15] Users" -ForegroundColor Gray
$users = az ad user list | ConvertFrom-Json

# Groups
Write-Host "  [3/15] Groups" -ForegroundColor Gray
$groups = az ad group list | ConvertFrom-Json

# Apps
Write-Host "  [4/15] Applications" -ForegroundColor Gray
$apps = az ad app list | ConvertFrom-Json

# Service Principals
Write-Host "  [5/15] Service Principals" -ForegroundColor Gray
$sps = az ad sp list --all | ConvertFrom-Json

# RBAC Role Assignments
Write-Host "  [6/15] RBAC Roles" -ForegroundColor Gray
$roles = az role assignment list | ConvertFrom-Json

# Subscriptions
Write-Host "  [7/15] Subscriptions" -ForegroundColor Gray
$subs = az account list | ConvertFrom-Json

# Conditional Access
Write-Host "  [8/15] Conditional Access Policies" -ForegroundColor Gray
$caJson = az rest --method GET --uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' 2>$null
if ($caJson) {
    $ca = $caJson | ConvertFrom-Json
    $caPolicies = $ca.value
} else {
    $caPolicies = @()
}

# Azure Policies
Write-Host "  [9/15] Azure Policies" -ForegroundColor Gray
$azPolicies = @()
foreach ($sub in $subs) {
    az account set --subscription $sub.id | Out-Null
    $pol = az policy assignment list | ConvertFrom-Json
    $azPolicies += $pol
}

# Resources, NSGs, Storage
$allRes = @()
$allVMs = @()
$nsgs = @()
$nsgRules = @()
$storage = @()
$keyVaults = @()

Write-Host "  [10/15] Resources" -ForegroundColor Gray
foreach ($sub in $subs) {
    az account set --subscription $sub.id | Out-Null
    
    $res = az resource list | ConvertFrom-Json
    $allRes += $res
    
    Write-Host "  [11/15] Virtual Machines" -ForegroundColor Gray
    $vms = az vm list -d | ConvertFrom-Json
    $allVMs += $vms
    
    Write-Host "  [12/15] Network Security Groups" -ForegroundColor Gray
    $nsg = az network nsg list | ConvertFrom-Json
    $nsgs += $nsg
    
    # NSG Rules
    foreach ($n in $nsg) {
        $rules = az network nsg rule list --nsg-name $n.name --resource-group $n.resourceGroup | ConvertFrom-Json
        foreach ($r in $rules) {
            $nsgRules += [PSCustomObject]@{
                NSG = $n.name
                Rule = $r.name
                Priority = $r.priority
                Direction = $r.direction
                Access = $r.access
                Protocol = $r.protocol
                SourcePort = $r.sourcePortRange
                DestPort = $r.destinationPortRange
                Source = $r.sourceAddressPrefix
                Dest = $r.destinationAddressPrefix
            }
        }
    }
    
    Write-Host "  [13/15] Storage Accounts" -ForegroundColor Gray
    $stor = az storage account list | ConvertFrom-Json
    $storage += $stor
    
    Write-Host "  [14/15] Key Vaults" -ForegroundColor Gray
    $kv = az keyvault list | ConvertFrom-Json
    $keyVaults += $kv
}

Write-Host "  [15/15] Analyzing security..." -ForegroundColor Gray

# Security Analysis
$findings = @()

# Check for open ports
$dangerousPorts = @(22, 3389, 1433, 3306, 5432, 27017)
foreach ($rule in $nsgRules) {
    if ($rule.Access -eq "Allow" -and $rule.Direction -eq "Inbound") {
        foreach ($port in $dangerousPorts) {
            if ($rule.DestPort -eq "*" -or $rule.DestPort -eq "$port") {
                if ($rule.Source -eq "*" -or $rule.Source -eq "Internet") {
                    $findings += [PSCustomObject]@{
                        Severity = "HIGH"
                        Category = "Network Security"
                        Finding = "Port $port open to Internet"
                        Resource = $rule.NSG
                        Recommendation = "Restrict source IP range"
                    }
                }
            }
        }
    }
}

# Check for public storage
foreach ($st in $storage) {
    if ($st.allowBlobPublicAccess -eq $true) {
        $findings += [PSCustomObject]@{
            Severity = "MEDIUM"
            Category = "Storage Security"
            Finding = "Public blob access enabled"
            Resource = $st.name
            Recommendation = "Disable public access"
        }
    }
}

# Check for overprivileged roles
$ownerCount = ($roles | Where-Object {$_.roleDefinitionName -eq "Owner"}).Count
if ($ownerCount -gt 5) {
    $findings += [PSCustomObject]@{
        Severity = "HIGH"
        Category = "RBAC"
        Finding = "$ownerCount Owner role assignments"
        Resource = "Subscription"
        Recommendation = "Review and reduce Owner assignments"
    }
}

# Check for no Conditional Access
if ($caPolicies.Count -eq 0) {
    $findings += [PSCustomObject]@{
        Severity = "CRITICAL"
        Category = "Identity Security"
        Finding = "No Conditional Access policies"
        Resource = "Entra ID"
        Recommendation = "Implement CA policies immediately"
    }
}

# Check for guest users
$guestCount = ($users | Where-Object {$_.userType -eq "Guest"}).Count
if ($guestCount -gt 10) {
    $findings += [PSCustomObject]@{
        Severity = "MEDIUM"
        Category = "Identity Security"
        Finding = "$guestCount guest users"
        Resource = "Entra ID"
        Recommendation = "Review guest access regularly"
    }
}

Write-Host "Generating comprehensive report..." -ForegroundColor Cyan

if (!(Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }

$file = Join-Path $OutputPath "EntraSecurityAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# Build HTML tables
$resTypesHtml = ""
$resTypes = $allRes | Group-Object type | Sort-Object Count -Descending | Select-Object -First 10
foreach ($rt in $resTypes) {
    $resTypesHtml += "<tr><td>$($rt.Name)</td><td>$($rt.Count)</td></tr>"
}

$rolesHtml = ""
$topRoles = $roles | Group-Object roleDefinitionName | Sort-Object Count -Descending | Select-Object -First 10
foreach ($r in $topRoles) {
    $rolesHtml += "<tr><td>$($r.Name)</td><td>$($r.Count)</td></tr>"
}

$caHtml = ""
foreach ($p in $caPolicies | Select-Object -First 20) {
    $state = $p.state
    $badge = if ($state -eq "enabled") {"<span class='badge-success'>Enabled</span>"} else {"<span class='badge-danger'>Disabled</span>"}
    $caHtml += "<tr><td>$($p.displayName)</td><td>$badge</td></tr>"
}

$nsgHtml = ""
foreach ($rule in $nsgRules | Where-Object {$_.Direction -eq "Inbound" -and $_.Access -eq "Allow"} | Select-Object -First 20) {
    $danger = if ($rule.Source -eq "*" -or $rule.Source -eq "Internet") {"<span class='badge-danger'>Internet</span>"} else {"<span class='badge-success'>Restricted</span>"}
    $nsgHtml += "<tr><td>$($rule.NSG)</td><td>$($rule.Rule)</td><td>$($rule.DestPort)</td><td>$danger</td></tr>"
}

$findingsHtml = ""
foreach ($f in $findings | Sort-Object Severity) {
    $badgeClass = switch ($f.Severity) {
        "CRITICAL" {"badge-critical"}
        "HIGH" {"badge-danger"}
        "MEDIUM" {"badge-warning"}
        default {"badge-info"}
    }
    $findingsHtml += "<tr><td><span class='$badgeClass'>$($f.Severity)</span></td><td>$($f.Category)</td><td>$($f.Finding)</td><td>$($f.Resource)</td><td>$($f.Recommendation)</td></tr>"
}

@"
<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<title>Entra ID Complete Security Audit</title>
<style>
body{font-family:Arial;background:linear-gradient(135deg,#667eea,#764ba2);padding:20px;margin:0}
.container{max-width:1600px;margin:0 auto;background:white;padding:40px;border-radius:15px;box-shadow:0 20px 60px rgba(0,0,0,0.3)}
h1{color:#0078d4;font-size:2.5em;margin-bottom:10px}
h2{color:#2b579a;font-size:1.8em;margin:40px 0 20px 0;border-bottom:3px solid #e1e1e1;padding-bottom:10px}
.header{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:30px;border-radius:10px;margin:20px 0}
.header p{margin:8px 0;font-size:1.1em}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:20px;margin:25px 0}
.stat{background:linear-gradient(135deg,#f093fb,#f5576c);color:white;padding:25px;border-radius:12px;text-align:center;box-shadow:0 5px 15px rgba(0,0,0,0.2);transition:transform 0.3s}
.stat:hover{transform:translateY(-5px)}
.stat-label{font-size:0.9em;opacity:0.95;margin-bottom:10px;text-transform:uppercase}
.stat-value{font-size:3em;font-weight:bold}
table{width:100%;border-collapse:collapse;margin:20px 0;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:white;padding:15px;text-align:left;font-size:0.9em}
td{padding:12px 15px;border-bottom:1px solid #e1e1e1;font-size:0.85em}
tr:hover{background:#f8f9fa}
.badge-success{background:#28a745;color:white;padding:5px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}
.badge-danger{background:#dc3545;color:white;padding:5px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}
.badge-warning{background:#ffc107;color:#333;padding:5px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}
.badge-critical{background:#8b0000;color:white;padding:5px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}
.badge-info{background:#17a2b8;color:white;padding:5px 12px;border-radius:20px;font-size:0.8em;font-weight:bold}
.alert{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:20px 0;border-radius:5px}
.alert-danger{background:#f8d7da;border-left:5px solid #dc3545}
.footer{margin-top:50px;padding-top:30px;border-top:2px solid #e1e1e1;text-align:center;color:#666}
</style></head><body>
<div class="container">

<h1>🛡️ Entra ID Complete Security Audit</h1>

<div class="header">
<h3>Tenant Information</h3>
<p><b>Tenant:</b> $($tenant.name)</p>
<p><b>ID:</b> $($tenant.tenantId)</p>
<p><b>User:</b> $($tenant.user.name)</p>
<p><b>Date:</b> $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss')</p>
</div>

$(if ($findings.Count -gt 0) {
"<div class='alert alert-danger'>
<h3>⚠️ Security Findings: $($findings.Count) Issues Detected</h3>
<p>Critical issues require immediate attention. Review findings below.</p>
</div>"
})

<h2>🔐 Security Findings</h2>
$(if ($findingsHtml) {
"<table><thead><tr><th>Severity</th><th>Category</th><th>Finding</th><th>Resource</th><th>Recommendation</th></tr></thead><tbody>$findingsHtml</tbody></table>"
} else {
"<p style='color:green;font-weight:bold'>✅ No security issues detected</p>"
})

<h2>👥 Identity & Access</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Total Users</div><div class="stat-value">$($users.Count)</div></div>
<div class="stat"><div class="stat-label">Enabled</div><div class="stat-value">$(($users | Where-Object {$_.accountEnabled}).Count)</div></div>
<div class="stat"><div class="stat-label">Disabled</div><div class="stat-value">$(($users | Where-Object {!$_.accountEnabled}).Count)</div></div>
<div class="stat"><div class="stat-label">Guest Users</div><div class="stat-value">$(($users | Where-Object {$_.userType -eq 'Guest'}).Count)</div></div>
<div class="stat"><div class="stat-label">Groups</div><div class="stat-value">$($groups.Count)</div></div>
<div class="stat"><div class="stat-label">Applications</div><div class="stat-value">$($apps.Count)</div></div>
</div>

<h2>🔐 Conditional Access Policies</h2>
$(if ($caHtml) {
"<table><thead><tr><th>Policy Name</th><th>State</th></tr></thead><tbody>$caHtml</tbody></table>"
} else {
"<div class='alert alert-danger'><b>⚠️ CRITICAL:</b> No Conditional Access policies configured!</div>"
})

<h2>🛡️ RBAC & Permissions</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Role Assignments</div><div class="stat-value">$($roles.Count)</div></div>
<div class="stat"><div class="stat-label">Owners</div><div class="stat-value">$(($roles | Where-Object {$_.roleDefinitionName -eq 'Owner'}).Count)</div></div>
<div class="stat"><div class="stat-label">Contributors</div><div class="stat-value">$(($roles | Where-Object {$_.roleDefinitionName -eq 'Contributor'}).Count)</div></div>
</div>
<h3>Top Role Assignments</h3>
<table><thead><tr><th>Role</th><th>Count</th></tr></thead><tbody>$rolesHtml</tbody></table>

<h2>🌐 Network Security</h2>
<div class="stats">
<div class="stat"><div class="stat-label">NSGs</div><div class="stat-value">$($nsgs.Count)</div></div>
<div class="stat"><div class="stat-label">NSG Rules</div><div class="stat-value">$($nsgRules.Count)</div></div>
<div class="stat"><div class="stat-label">Open Inbound</div><div class="stat-value">$(($nsgRules | Where-Object {$_.Direction -eq 'Inbound' -and $_.Access -eq 'Allow' -and ($_.Source -eq '*' -or $_.Source -eq 'Internet')}).Count)</div></div>
</div>
$(if ($nsgHtml) {
"<h3>Inbound Allow Rules</h3>
<table><thead><tr><th>NSG</th><th>Rule</th><th>Port</th><th>Source</th></tr></thead><tbody>$nsgHtml</tbody></table>"
})

<h2>📦 Azure Resources</h2>
<div class="stats">
<div class="stat"><div class="stat-label">Subscriptions</div><div class="stat-value">$($subs.Count)</div></div>
<div class="stat"><div class="stat-label">Total Resources</div><div class="stat-value">$($allRes.Count)</div></div>
<div class="stat"><div class="stat-label">Virtual Machines</div><div class="stat-value">$($allVMs.Count)</div></div>
<div class="stat"><div class="stat-label">Storage Accounts</div><div class="stat-value">$($storage.Count)</div></div>
<div class="stat"><div class="stat-label">Key Vaults</div><div class="stat-value">$($keyVaults.Count)</div></div>
</div>
<h3>Resource Types</h3>
<table><thead><tr><th>Type</th><th>Count</th></tr></thead><tbody>$resTypesHtml</tbody></table>

<h2>📋 Azure Policies</h2>
<p><b>Policy Assignments:</b> $($azPolicies.Count)</p>

<div class="footer">
<p><b>Complete Entra ID Security Audit</b></p>
<p>Generated: $(Get-Date -Format 'MMMM dd, yyyy HH:mm:ss') | By: $env:USERNAME</p>
<p style='margin-top:10px;font-size:0.9em'>Includes: Identity, RBAC, Network Security, NSG Rules, Storage, Policies, Security Findings</p>
</div>

</div></body></html>
"@ | Out-File -FilePath $file -Encoding UTF8

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "✅ COMPLETE SECURITY AUDIT FINISHED!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Security Summary:" -ForegroundColor Yellow
Write-Host "   - Users: $($users.Count)" -ForegroundColor White
Write-Host "   - Groups: $($groups.Count)" -ForegroundColor White
Write-Host "   - CA Policies: $($caPolicies.Count)" -ForegroundColor White
Write-Host "   - RBAC Roles: $($roles.Count)" -ForegroundColor White
Write-Host "   - NSGs: $($nsgs.Count)" -ForegroundColor White
Write-Host "   - NSG Rules: $($nsgRules.Count)" -ForegroundColor White
Write-Host "   - Resources: $($allRes.Count)" -ForegroundColor White
Write-Host "   - Security Findings: $($findings.Count)" -ForegroundColor $(if($findings.Count -gt 0){"Red"}else{"Green"})
Write-Host ""
Write-Host "📁 Report: $file" -ForegroundColor Cyan
Write-Host ""

Start-Process $file
