$ErrorActionPreference = "Stop"

$spName = "databricks-jobs-service-principal"
$spAppId = "d519efa6-3cb5-4fa0-8535-c657175be154"

$account = az account show | ConvertFrom-Json

$reportFile = "Databricks-Setup-Complete-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup - Complete</title>
<style>
body{font-family:Arial,sans-serif;margin:40px;background:linear-gradient(135deg,#667eea,#764ba2);color:#2d3748}
.container{max-width:1200px;margin:0 auto;background:#fff;padding:40px;border-radius:15px;box-shadow:0 20px 60px rgba(0,0,0,0.3)}
h1{color:#2d3748;border-bottom:4px solid #667eea;padding-bottom:20px;font-size:32px}
h2{color:#4a5568;margin-top:40px;border-bottom:3px solid #e2e8f0;padding-bottom:15px;font-size:24px}
h3{color:#667eea;margin-top:25px;font-size:20px}
table{width:100%;border-collapse:collapse;margin:25px 0;box-shadow:0 2px 8px rgba(0,0,0,0.1)}
th,td{border:1px solid #e2e8f0;padding:15px;text-align:left}
th{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;font-weight:bold;font-size:14px}
tr:nth-child(even){background:#f7fafc}
tr:hover{background:#edf2f7}
.success{color:#38a169;font-weight:bold;font-size:18px}
.info-box{background:#e6fffa;border-left:5px solid #38a169;padding:20px;margin:20px 0;border-radius:5px}
.warning-box{background:#fff3cd;border-left:5px solid #ffc107;padding:20px;margin:20px 0;border-radius:5px}
.workspace-card{background:#f7fafc;border:2px solid #667eea;padding:25px;margin:20px 0;border-radius:10px;box-shadow:0 4px 12px rgba(0,0,0,0.1)}
.workspace-card h3{margin-top:0;color:#667eea}
.footer{margin-top:60px;padding-top:30px;border-top:3px solid #e2e8f0;text-align:center;color:#718096;font-size:14px}
ul{line-height:1.8}
li{margin:8px 0}
.highlight{background:#fef3c7;padding:2px 6px;border-radius:3px;font-weight:bold}
.check{color:#38a169;font-size:20px;font-weight:bold}
</style>
</head>
<body>
<div class="container">

<h1>🎉 Databricks Service Principal Setup - COMPLETE</h1>

<div class="info-box">
<p><strong>Setup Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Configured By:</strong> $($account.user.name)</p>
<p><strong>Subscription:</strong> $($account.name)</p>
<p><strong>Status:</strong> <span class="success">✓ FULLY CONFIGURED</span></p>
</div>

<h2>📋 Service Principal Details</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td><strong>Display Name</strong></td><td>$spName</td></tr>
<tr><td><strong>Application ID</strong></td><td><span class="highlight">$spAppId</span></td></tr>
<tr><td><strong>Status</strong></td><td><span class="success">ACTIVE ✓</span></td></tr>
<tr><td><strong>Created/Updated</strong></td><td>$(Get-Date -Format 'MMMM dd, yyyy')</td></tr>
</table>

<h2>🏢 Databricks Workspaces Configured</h2>

<div class="workspace-card">
<h3><span class="check">✓</span> Workspace 1: pyx-warehouse-prod (PREPROD)</h3>
<p><strong>URL:</strong> <a href="https://adb-2756318924173706.6.azuredatabricks.net" target="_blank">adb-2756318924173706.6.azuredatabricks.net</a></p>
<p><strong>Resource Group:</strong> rg-warehouse-preprod</p>
<p><strong>Configuration:</strong></p>
<ul>
<li><span class="check">✓</span> Service principal added to <strong>admins</strong> group</li>
<li><span class="check">✓</span> Service principal added to <strong>prod-datateam</strong> group</li>
<li><span class="check">✓</span> 5 users configured with appropriate permissions</li>
</ul>
</div>

<div class="workspace-card">
<h3><span class="check">✓</span> Workspace 2: pyxlake-databricks (PROD)</h3>
<p><strong>URL:</strong> <a href="https://adb-3248848193480666.6.azuredatabricks.net" target="_blank">adb-3248848193480666.6.azuredatabricks.net</a></p>
<p><strong>Resource Group:</strong> rg-adls-poc</p>
<p><strong>Configuration:</strong></p>
<ul>
<li><span class="check">✓</span> Service principal added to <strong>admins</strong> group</li>
<li><span class="check">✓</span> Service principal added to <strong>datateam</strong> group</li>
<li><span class="check">✓</span> 5 users configured with appropriate permissions</li>
</ul>
</div>

<h2>👥 User Access Configuration</h2>

<table>
<tr>
<th>User</th>
<th>Permission Level</th>
<th>Workspace Access</th>
<th>Cluster Creation</th>
<th>Groups</th>
</tr>
<tr>
<td><strong>preyash.patel@pyxhealth.com</strong></td>
<td><span class="success">CAN_MANAGE</span></td>
<td><span class="check">✓</span></td>
<td><span class="check">✓</span></td>
<td>admins, prod-datateam</td>
</tr>
<tr>
<td>sheela@pyxhealth.com</td>
<td>READ-ONLY</td>
<td><span class="check">✓</span></td>
<td>—</td>
<td>—</td>
</tr>
<tr>
<td>brian.burge@pyxhealth.com</td>
<td>READ-ONLY</td>
<td><span class="check">✓</span></td>
<td>—</td>
<td>—</td>
</tr>
<tr>
<td>robert@pyxhealth.com</td>
<td>READ-ONLY</td>
<td><span class="check">✓</span></td>
<td>—</td>
<td>—</td>
</tr>
<tr>
<td>hunter@pyxhealth.com</td>
<td>READ-ONLY</td>
<td><span class="check">✓</span></td>
<td>—</td>
<td>—</td>
</tr>
</table>

<h2>🔐 What Each User Can Do</h2>

<div class="workspace-card">
<h3>Preyash Patel (CAN_MANAGE)</h3>
<p><strong>Allowed Actions:</strong></p>
<ul>
<li><span class="check">✓</span> Create and manage clusters</li>
<li><span class="check">✓</span> Run jobs and workflows</li>
<li><span class="check">✓</span> View all Databricks resources</li>
<li><span class="check">✓</span> Manage group memberships</li>
</ul>
<p><strong>Restricted Actions:</strong></p>
<ul>
<li>❌ Cannot delete workspaces</li>
<li>❌ Cannot create new groups</li>
<li>❌ Cannot modify workspace settings</li>
</ul>
</div>

<div class="workspace-card">
<h3>Other Users (READ-ONLY)</h3>
<p><strong>Users:</strong> Sheela, Brian Burge, Robert, Hunter</p>
<p><strong>Allowed Actions:</strong></p>
<ul>
<li><span class="check">✓</span> View notebooks and code</li>
<li><span class="check">✓</span> View job runs and results</li>
<li><span class="check">✓</span> View SQL queries and dashboards</li>
</ul>
<p><strong>Restricted Actions:</strong></p>
<ul>
<li>❌ Cannot create or modify anything</li>
<li>❌ Cannot run jobs</li>
<li>❌ Cannot create clusters</li>
</ul>
</div>

<h2>📊 Summary</h2>

<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Total Workspaces Configured</td><td><span class="success">2</span></td></tr>
<tr><td>Service Principals Created</td><td><span class="success">1</span></td></tr>
<tr><td>Users Configured</td><td><span class="success">5</span></td></tr>
<tr><td>Groups Configured</td><td><span class="success">4</span> (admins, prod-datateam, datateam, prod-catalog)</td></tr>
<tr><td>Setup Method</td><td>Hybrid (Automated + Manual UI)</td></tr>
<tr><td>Total Time</td><td>~2 hours</td></tr>
</table>

<div class="warning-box">
<h3>⚠️ Important Notes</h3>
<ul>
<li>Service principal was created using Azure AD and Cloud Shell automation</li>
<li>Workspace-level configuration completed manually in Databricks UI due to network restrictions</li>
<li>All users have been granted appropriate least-privilege access</li>
<li>Service principal can now be used for running automated jobs and workflows</li>
</ul>
</div>

<h2>✅ Next Steps</h2>
<ol>
<li>Update existing Databricks jobs to run as service principal (<span class="highlight">$spName</span>)</li>
<li>Test service principal permissions in both workspaces</li>
<li>Verify users can access their respective workspaces</li>
<li>Document any additional custom permissions needed for specific workflows</li>
<li>Set up monitoring and alerts for service principal activity</li>
</ol>

<div class="footer">
<p><strong>Report Generated By:</strong> Syed Rizvi</p>
<p><strong>Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Databricks Service Principal Setup - Successfully Completed</strong></p>
</div>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "HTML REPORT GENERATED!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host "File: $reportFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Opening report..." -ForegroundColor Yellow

Start-Process $reportFile

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host ""
