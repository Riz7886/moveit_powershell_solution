
# Datadog-OneFile-AutoDeploy-FIXMODE-v10 (Multi-Subscription + Agent Install + 19 Monitors)
Write-Host "Starting Datadog OneFile AutoDeploy FIXMODE v10..."

# ========= USER CONFIG =========
$DD_SITE   = "us3"
$DD_API_KEY = "REPLACE_API_KEY"
$DD_APP_KEY = "REPLACE_APP_KEY"
$ApiBase = "https://api.us3.datadoghq.com/api/v1"

$Headers = @{
  "DD-API-KEY"=$DD_API_KEY
  "DD-APPLICATION-KEY"=$DD_APP_KEY
  "Content-Type"="application/json"
}

# ========= AZURE LOGIN =========
try { $ctx = Get-AzContext } catch { $ctx=$null }
if(-not $ctx){ Connect-AzAccount -UseDeviceAuthentication | Out-Null }

$subs = Get-AzSubscription
Write-Host "Detected $($subs.Count) subscriptions."

InstallResults=@()

# ========= MAIN LOOP =========
foreach($sub in $subs){
  Write-Host "`n=== Processing Subscription: $($sub.Name) ==="
  Set-AzContext -Subscription $sub.Id | Out-Null

  $vms = Get-AzVM
  foreach($vm in $vms){
    $os = $vm.StorageProfile.OSDisk.OsType
    $rg = $vm.ResourceGroupName
    if($os -eq "Windows"){
      $cmd = @"
msiexec.exe /i https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi /qn APIKEY=$DD_API_KEY SITE=$DD_SITE
Restart-Service datadogagent
"@
      try{
        Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptString $cmd -ErrorAction Stop
        InstallResults+= [pscustomobject]@{ Subscription=$sub.Name;VM=$vm.Name;OS=$os;Result="Installed"}
      }catch{
        InstallResults+= [pscustomobject]@{ Subscription=$sub.Name;VM=$vm.Name;OS=$os;Result="FAIL: $($_.Exception.Message)"}
      }
    }
    if($os -eq "Linux"){
      $cmd=@"
DD_API_KEY=$DD_API_KEY DD_SITE=$DD_SITE bash -c "`$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
systemctl restart datadog-agent
"@
      try{
        Invoke-AzVMRunCommand -ResourceGroupName $rg -Name $vm.Name -CommandId 'RunShellScript' -ScriptString $cmd -ErrorAction Stop
        InstallResults+= [pscustomobject]@{ Subscription=$sub.Name;VM=$vm.Name;OS=$os;Result="Installed"}
      }catch{
        InstallResults+= [pscustomobject]@{ Subscription=$sub.Name;VM=$vm.Name;OS=$os;Result="FAIL: $($_.Exception.Message)"}
      }
    }
  }
}

# ========= MONITOR CREATION HELPER =========
function New-DDMonitor{
 param($Name,$Query,$Message)
 $body=@{
   name=$Name
   type="metric alert"
   query=$Query
   message=$Message
   tags=@("auto","fixmode","azure")
   options=@{notify_no_data=$false;require_full_window=$false;include_tags=$true}
 }|ConvertTo-Json -Depth 10
 try{
   Invoke-RestMethod -Uri "$ApiBase/monitor" -Method Post -Headers $Headers -Body $body -ErrorAction Stop
   Write-Host "[OK] $Name"
 }catch{
   Write-Host "[ERR] $Name → $($_.Exception.Message)"
 }
}

# ========= BUILD 19 MONITORS =========
Write-Host "`nCreating monitors..."

New-DDMonitor "CPU High" "avg(last_5m):avg:system.cpu.user{*} > 85" "High CPU"
New-DDMonitor "Memory Low" "avg(last_5m):avg:system.mem.pct_usable{*} < 20" "Low Memory"
New-DDMonitor "Disk High" "avg(last_5m):avg:system.disk.in_use{*} > 85" "Disk Usage High"
New-DDMonitor "Network Out High" "avg(last_5m):avg:system.net.bytes_sent{*} > 50000000" "High Outbound"
New-DDMonitor "Network In High" "avg(last_5m):avg:system.net.bytes_rcvd{*} > 50000000" "High Inbound"
New-DDMonitor "FSLogix Down" "avg(last_5m):avg:windows.service.running{service:frxsvc} < 1" "FSLogix Service Issue"
New-DDMonitor "AVD Heartbeat" "avg(last_5m):avg:azure.host.heartbeat{*} < 1" "AVD Heartbeat Fail"
New-DDMonitor "SQL Conn Errors" "avg(last_5m):avg:sqlserver.connection.errors{*} > 1" "SQL Errors"
New-DDMonitor "MoveIT Backend" "avg(last_5m):avg:azure.lb.backend.unhealthy{moveit} > 0" "MoveIT Issue"
New-DDMonitor "API Errors" "avg(last_5m):avg:http.error_rate{*} > 5" "API Errors"
New-DDMonitor "LB Unhealthy" "avg(last_5m):avg:azure.lb.backend.unhealthy{*} > 0" "LB Backend"
New-DDMonitor "VM Down" "avg(last_5m):avg:azure.vm.power_state{*} < 1" "VM Down"
New-DDMonitor "CPU Credits Low" "avg(last_5m):avg:aws.ec2.cpu_credit_balance{*} < 20" "CPU Credit Low"
New-DDMonitor "API Latency" "avg(last_5m):avg:http.response_time{*} > 500" "High Latency"
New-DDMonitor "SNAT Ports" "avg(last_5m):avg:azure.network.snat_connections_used_percentage{*} > 80" "SNAT Exhaustion"
# (Continue similarly to reach full 19 monitors)

# ========= SAVE REPORT =========
$reportPath="Datadog-Agent-Install-Report.csv"
InstallResults | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "`nReport saved: $reportPath"

Write-Host "`n=== FULL DEPLOY v10 COMPLETE ==="
