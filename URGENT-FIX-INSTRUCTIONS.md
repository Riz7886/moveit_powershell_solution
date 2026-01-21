# 🚨 URGENT: Fix Datadog Monitoring - Step by Step Guide

## Problem
Your Datadog monitors are showing "NO DATA" because there's a **hostname mismatch**:
- Your monitors expect: `vm-moveit-auto` and `vm-moveit-xfr`
- Your agents are reporting: `MOVITAUTO` and `MOVEITXFR`

## Quick Fix (15 minutes total)

### Step 1: Verify Current Status

On **BOTH VMs**, open PowerShell as Administrator and run:

```powershell
.\Verify-DatadogAgent.ps1
```

This will show you:
- ✓ What hostname is currently configured
- ✓ If the agent is running
- ✓ What needs to be fixed

---

### Step 2: Fix the Hostname on FIRST VM (MOVITAUTO)

On the **MOVITAUTO** VM:

1. Open PowerShell **as Administrator**
2. Navigate to where you saved the scripts
3. Run:

```powershell
.\Fix-DatadogHostname.ps1 -NewHostname 'vm-moveit-auto'
```

**What this does:**
- Backs up your current config
- Updates the hostname to `vm-moveit-auto`
- Restarts the Datadog agent
- Shows you the new status

**Expected output:** You should see "HOSTNAME FIX COMPLETE!" in green

---

### Step 3: Fix the Hostname on SECOND VM (MOVEITXFR)

On the **MOVEITXFR** VM:

1. Open PowerShell **as Administrator**
2. Navigate to where you saved the scripts
3. Run:

```powershell
.\Fix-DatadogHostname.ps1 -NewHostname 'vm-moveit-xfr'
```

**Expected output:** You should see "HOSTNAME FIX COMPLETE!" in green

---

### Step 4: Verify the Fix

Wait **2-3 minutes**, then:

1. Go to Datadog: https://us3.datadoghq.com/infrastructure
2. You should now see TWO hosts:
   - ✓ `vm-moveit-auto`
   - ✓ `vm-moveit-xfr`
3. Both should be showing as **green/active**

---

### Step 5: Check Your Monitors

1. Go to: https://us3.datadoghq.com/monitors/manage
2. Filter by "MoveIT" monitors
3. They should now show **OK** (green) instead of "NO DATA" (gray)

---

## If Something Goes Wrong

### Problem: "Agent not installed"
**Solution:** Run the installation script first:
```powershell
.\Install-DatadogAgent-Production.ps1
```

### Problem: "Access Denied" or "Permission Error"
**Solution:** Make sure you're running PowerShell **as Administrator**
- Right-click PowerShell → "Run as Administrator"

### Problem: Script won't run (execution policy error)
**Solution:** Run this first:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Problem: Still showing "NO DATA" after 5 minutes
**Solution:** 
1. Check if agent is running:
   ```powershell
   Get-Service datadogagent
   ```
2. Check agent logs:
   ```powershell
   Get-Content "C:\ProgramData\Datadog\logs\agent.log" -Tail 50
   ```
3. Verify hostname in Datadog UI matches what you set

---

## Quick Command Reference

| Task | Command |
|------|---------|
| Verify agent status | `.\Verify-DatadogAgent.ps1` |
| Fix MOVITAUTO hostname | `.\Fix-DatadogHostname.ps1 -NewHostname 'vm-moveit-auto'` |
| Fix MOVEITXFR hostname | `.\Fix-DatadogHostname.ps1 -NewHostname 'vm-moveit-xfr'` |
| Check service status | `Get-Service datadogagent` |
| Restart agent manually | `Restart-Service datadogagent` |
| View agent status | `& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" status` |

---

## Timeline

- **0-5 min:** Run verification script on both VMs
- **5-10 min:** Run fix script on both VMs
- **10-15 min:** Wait for data to appear, verify in Datadog UI

---

## Success Criteria ✓

You'll know it's working when:
1. ✓ Infrastructure list shows `vm-moveit-auto` and `vm-moveit-xfr` as **green**
2. ✓ Monitors change from "NO DATA" to "OK"
3. ✓ You can see metrics coming in for both hosts

---

## Contact/Support

If you're still stuck after following these steps, check:
1. Firewall settings (agent needs outbound HTTPS to us3.datadoghq.com)
2. API key is correct in config
3. Agent logs for specific errors

---

**🎯 Expected Total Time: 10-15 minutes**

**👉 START HERE: Run `.\\Verify-DatadogAgent.ps1` on BOTH VMs**