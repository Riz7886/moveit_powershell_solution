$ErrorActionPreference = "Stop"

$spName = "databricks-jobs-service-principal"
$spAppId = "d519efa6-3cb5-4fa0-8535-c657175be154"

$account = az account show | ConvertFrom-Json

$reportFile = "Databricks-Setup-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Databricks Service Principal Setup Report</title>
<style>
body{font-family:Arial,sans-serif;margin:40px;background:#f5f5f5;color:#333}
.container{max-width:1200px;margin:0 auto;background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
h1{color:#1a1a1a;border-bottom:3px solid #0066cc;padding-bottom:15px}
h2{color:#333;margin-top:30px;border-bottom:2px solid #ccc;padding-bottom:10px}
h3{color:#0066cc;margin-top:20px}
table{width:100%;border-collapse:collapse;margin:20px 0}
th,td{border:1px solid #ddd;padding:12px;text-align:left}
th{background:#0066cc;color:#fff;font-weight:bold}
tr:nth-child(even){background:#f9f9f9}
.success{color:#008000;font-weight:bold}
.info-box{background:#e6f3ff;border-left:4px solid #0066cc;padding:15px;margin:15px 0}
.workspace-box{background:#f9f9f9;border:1px solid #ddd;padding:20px;margin:15px 0;border-radius:5px}
.footer{margin-top:40px;padding-top:20px;border-top:2px solid #ddd;text-align:center;color:#666}
ul{line-height:1.8}
</style>
</head>
<body>
<div class="container">

<h1>Databricks Service Principal Setup Report</h1>

<div class="info-box">
<p><strong>Setup Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Configured By:</strong> $($account.user.name)</p>
<p><strong>Subscription:</strong> $($account.name)</p>
<p><strong>Status:</strong> <span class="success">COMPLETE</span></p>
</div>

<h2>Service Principal Details</h2>
<table>
<tr><th>Property</th><th>Value</th></tr>
<tr><td><strong>Display Name</strong></td><td>$spName</td></tr>
<tr><td><strong>Application ID</strong></td><td>$spAppId</td></tr>
<tr><td><strong>Status</strong></td><td><span class="success">ACTIVE</span></td></tr>
<tr><td><strong>Date</strong></td><td>$(Get-Date -Format 'MMMM dd, yyyy')</td></tr>
</table>

<h2>Databricks Workspaces Configured</h2>

<div class="workspace-box">
<h3>Workspace 1: pyx-warehouse-prod (PREPROD)</h3>
<p><strong>URL:</strong> <a href="https://adb-2756318924173706.6.azuredatabricks.net" target="_blank">adb-2756318924173706.6.azuredatabricks.net</a></p>
<p><strong>Resource Group:</strong> rg-warehouse-preprod</p>
<p><strong>Configuration Status:</strong></p>
<ul>
<li>Service principal added to admins group</li>
<li>Service principal added to prod-datateam group</li>
<li>5 users configured with permissions</li>
</ul>
</div>

<div class="workspace-box">
<h3>Workspace 2: pyxlake-databricks (PROD)</h3>
<p><strong>URL:</strong> <a href="https://adb-3248848193480666.6.azuredatabricks.net" target="_blank">adb-3248848193480666.6.azuredatabricks.net</a></p>
<p><strong>Resource Group:</strong> rg-adls-poc</p>
<p><strong>Configuration Status:</strong></p>
<ul>
<li>Service principal added to admins group</li>
<li>Service principal added to datateam group</li>
<li>5 users configured with permissions</li>
</ul>
</div>

<h2>User Access Configuration</h2>

<table>
<tr>
<th>User Email</th>
<th>Permission Level</th>
<th>Workspace Access</th>
<th>Cluster Creation</th>
<th>Groups</th>
</tr>
<tr>
<td><strong>preyash.patel@pyxhealth.com</strong></td>
<td><span class="success">MANAGER</span></td>
<td>YES</td>
<td>YES</td>
<td>admins, prod-datateam</td>
</tr>
<tr>
<td>sheela@pyxhealth.com</td>
<td>READ ONLY</td>
<td>YES</td>
<td>NO</td>
<td>None</td>
</tr>
<tr>
<td>brian.burge@pyxhealth.com</td>
<td>READ ONLY</td>
<td>YES</td>
<td>NO</td>
<td>None</td>
</tr>
<tr>
<td>robert@pyxhealth.com</td>
<td>READ ONLY</td>
<td>YES</td>
<td>NO</td>
<td>None</td>
</tr>
<tr>
<td>hunter@pyxhealth.com</td>
<td>READ ONLY</td>
<td>YES</td>
<td>NO</td>
<td>None</td>
</tr>
</table>

<h2>Permissions Summary</h2>

<div class="workspace-box">
<h3>Preyash Patel - MANAGER</h3>
<p><strong>Can Do:</strong></p>
<ul>
<li>Create and manage clusters</li>
<li>Run jobs and workflows</li>
<li>View all resources</li>
<li>Manage group memberships</li>
</ul>
<p><strong>Cannot Do:</strong></p>
<ul>
<li>Delete workspaces</li>
<li>Create new groups (requires account admin)</li>
<li>Add or remove users (requires account admin)</li>
</ul>
</div>

<div class="workspace-box">
<h3>Other Users - READ ONLY</h3>
<p><strong>Users:</strong> Sheela, Brian Burge, Robert, Hunter</p>
<p><strong>Can Do:</strong></p>
<ul>
<li>View notebooks and code</li>
<li>View job runs and results</li>
<li>View SQL queries and dashboards</li>
</ul>
<p><strong>Cannot Do:</strong></p>
<ul>
<li>Cannot create or modify anything</li>
<li>Cannot run jobs</li>
<li>Cannot create clusters</li>
</ul>
</div>

<h2>Setup Summary</h2>

<table>
<tr><th>Item</th><th>Count</th></tr>
<tr><td>Workspaces Configured</td><td><span class="success">2</span></td></tr>
<tr><td>Service Principals Created</td><td><span class="success">1</span></td></tr>
<tr><td>Users Configured</td><td><span class="success">5</span></td></tr>
<tr><td>Groups Configured</td><td><span class="success">4</span></td></tr>
<tr><td>Setup Method</td><td>Automated Script + Manual UI</td></tr>
</table>

<h2>Important Notes</h2>

<div class="info-box">
<p><strong>User Management Permissions:</strong></p>
<p>To grant Preyash the ability to add/remove users, you need account-level admin access.</p>
<p>Contact your Databricks account administrator (John or Tony) to grant Preyash "Workspace Admin" role at the account level.</p>
<p>They can do this at: https://accounts.cloud.databricks.com</p>
</div>

<h2>Next Steps</h2>
<ol>
<li>Update existing Databricks jobs to run as service principal: $spName</li>
<li>Test service principal permissions in both workspaces</li>
<li>Verify users can access their workspaces</li>
<li>Contact account admin to grant Preyash user management permissions</li>
<li>Set up monitoring for service principal activity</li>
</ol>

<div class="footer">
<p><strong>Report Generated By:</strong> Syed Rizvi</p>
<p><strong>Date:</strong> $(Get-Date -Format 'MMMM dd, yyyy hh:mm:ss tt')</p>
<p><strong>Databricks Service Principal Setup - Complete</strong></p>
</div>

</div>
</body>
</html>
"@

$html | Out-File $reportFile -Encoding UTF8

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "CLEAN HTML REPORT CREATED" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host "File: $reportFile" -ForegroundColor Cyan
Write-Host ""

Start-Process $reportFile

Write-Host "DONE!" -ForegroundColor Green
Write-Host ""
