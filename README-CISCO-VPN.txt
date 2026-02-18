# CISCO ANYCONNECT VPN - FIXED SCRIPTS

## WHY THE PREVIOUS SCRIPTS DID NOT WORK:

**THE PROBLEM:**
Cisco AnyConnect/Secure Client is NOT an Azure VPN Gateway!

- Cisco AnyConnect = Client software on your laptop
- Connects to Cisco VPN server (VM or on-premises appliance)
- NOT an Azure resource that PowerShell can detect

**WHAT I WAS TRYING TO DO:**
My scripts were looking for Azure VPN Gateway resources using:
```powershell
Get-AzVirtualNetworkGateway
```

This ONLY finds Azure VPN Gateways, NOT Cisco devices!

---

## THE SOLUTION:

**NEW SCRIPTS THAT WORK WITH CISCO:**

### 1. PreCheck-CiscoVPN.ps1
- Detects VPN IP ranges from EXISTING NSG rules
- If you already have NSG rules allowing your Cisco VPN, it will find them
- Shows you all the IP ranges currently allowed in your NSGs

### 2. SmartFix-CiscoVPN.ps1
- Tries to auto-detect VPN IP range from NSG rules
- If not found, ASKS you to enter it manually
- Updates NSG rules to allow ONLY your Cisco VPN IP range
- Generates SAS tokens for storage

---

## HOW TO USE:

### STEP 1: Run PreCheck
```powershell
.\PreCheck-CiscoVPN.ps1
```

This will scan all NSG rules and look for IP ranges that are already allowed. If you see your Cisco VPN IP range listed, great! If not, you'll need to provide it manually in Step 2.

### STEP 2: Run SmartFix
```powershell
.\SmartFix-CiscoVPN.ps1
```

If the script finds VPN IP ranges, it will use them automatically.

If NOT found, it will ask:
```
Enter Cisco VPN IP range (or press ENTER to skip NSG fixes):
```

**How to find your Cisco VPN IP range:**
1. Connect to Cisco AnyConnect
2. Open Command Prompt
3. Type: `ipconfig`
4. Look for "Cisco AnyConnect" adapter
5. Note the IP address (e.g., 10.100.5.123)
6. The range is usually the first 3 numbers with /24
   Example: If your IP is 10.100.5.123, the range is 10.100.5.0/24

OR ask your network team: "What is our Cisco AnyConnect VPN IP range?"

---

## EXAMPLE:

When you run SmartFix-CiscoVPN.ps1:

```
Cisco AnyConnect VPN is not an Azure resource
Please provide your VPN IP range manually

Example formats:
  10.0.0.0/8
  172.16.0.0/12
  192.168.1.0/24

Enter Cisco VPN IP range: 10.100.5.0/24
Using VPN range: 10.100.5.0/24

Dangerous Rules: 6

FIX NSG RULES
Will UPDATE rules to allow Cisco VPN only:
  - 10.100.5.0/24

[U] UPDATE rules (recommended)
[D] DELETE rules (dangerous)
[S] SKIP

Choose: U
```

---

## WHAT THESE SCRIPTS DO DIFFERENTLY:

**OLD SCRIPTS (Didn't Work):**
- Tried to find Azure VPN Gateway (doesn't exist for Cisco)
- Failed because Cisco AnyConnect is not an Azure resource

**NEW SCRIPTS (Work with Cisco):**
- Detect VPN IP ranges from existing NSG rules
- OR ask you to provide the range manually
- Update NSG rules to allow ONLY your Cisco VPN
- RDP/SSH still works through VPN
- Generate SAS tokens for storage

---

## FILES:

1. PreCheck-CiscoVPN.ps1 - Run first to scan
2. SmartFix-CiscoVPN.ps1 - Run second to fix

Both scripts:
- NO parameters needed
- NO param() blocks
- Will NOT ask for ResourceGroup
- Work with Cisco AnyConnect/Secure Client VPN

---

Created by: Syed Rizvi
Date: February 18, 2026

NOW IT WILL WORK WITH YOUR CISCO VPN!
