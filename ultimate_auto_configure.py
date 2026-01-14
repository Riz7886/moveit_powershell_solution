#!/usr/bin/env python3
"""
ULTIMATE AUTO-CONFIGURATION SCRIPT
Connects to Azure, Datadog, and PagerDuty
Configures everything automatically - webhooks, monitors, alerts

USAGE:
  python3 ultimate_auto_configure.py

REQUIRES:
  - Azure credentials (tenant, client, secret) - OPTIONAL
  - Datadog API key and App key - REQUIRED
  - PagerDuty routing key - REQUIRED
"""

import requests
import json
import sys
import time
from typing import Dict, List, Optional
from datetime import datetime


class AzureConnector:
    """Handles Azure authentication and VM discovery"""
    
    def __init__(self, tenant_id: str, client_id: str, client_secret: str, subscription_id: str):
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.subscription_id = subscription_id
        self.access_token = None
        
    def authenticate(self) -> bool:
        """Authenticate with Azure and get access token"""
        print("[AZURE] Authenticating...")
        
        url = f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
        
        data = {
            'grant_type': 'client_credentials',
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'scope': 'https://management.azure.com/.default'
        }
        
        try:
            response = requests.post(url, data=data, timeout=30)
            if response.status_code == 200:
                self.access_token = response.json()['access_token']
                print("✓ Azure authentication successful!")
                return True
            else:
                print(f"✗ Azure auth failed: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Azure auth error: {str(e)}")
            return False
    
    def find_target_vms(self, target_names: List[str]) -> List[Dict]:
        """Find target VMs in Azure subscription"""
        print(f"[AZURE] Searching for VMs: {', '.join(target_names)}...")
        
        if not self.access_token:
            print("✗ Not authenticated")
            return []
        
        url = f"https://management.azure.com/subscriptions/{self.subscription_id}/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"
        
        headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            response = requests.get(url, headers=headers, timeout=30)
            if response.status_code == 200:
                all_vms = response.json().get('value', [])
                found_vms = []
                
                for vm in all_vms:
                    vm_name = vm.get('name', '').upper()
                    if any(target in vm_name for target in target_names):
                        found_vms.append({
                            'name': vm['name'],
                            'id': vm['id'],
                            'location': vm['location'],
                            'resource_group': vm['id'].split('/')[4]
                        })
                        print(f"  ✓ Found: {vm['name']}")
                
                if not found_vms:
                    print("  ⚠ No matching VMs found")
                
                return found_vms
            else:
                print(f"✗ Failed to list VMs: {response.status_code}")
                return []
        except Exception as e:
            print(f"✗ Error finding VMs: {str(e)}")
            return []


class DatadogConfigurator:
    """Handles Datadog webhook and monitor configuration"""
    
    def __init__(self, api_key: str, app_key: str, webhook_url: str):
        self.api_key = api_key
        self.app_key = app_key
        self.webhook_url = webhook_url
        self.base_url = "https://api.datadoghq.com/api/v1"
        self.headers = {
            "DD-API-KEY": self.api_key,
            "DD-APPLICATION-KEY": self.app_key,
            "Content-Type": "application/json"
        }
        self.webhook_name = "PagerDuty-MoveIT-Webhook"
    
    def create_webhook(self) -> bool:
        """Create webhook integration in Datadog"""
        print("[DATADOG] Creating webhook...")
        
        webhook_payload = {
            "name": self.webhook_name,
            "url": self.webhook_url,
            "encode_as_form": False,
            "custom_headers": json.dumps({"Content-Type": "application/json"}),
            "payload": json.dumps({
                "hostname": "$HOSTNAME",
                "alert_type": "$ALERT_TYPE",
                "title": "$EVENT_TITLE",
                "body": "$EVENT_MSG",
                "priority": "$PRIORITY",
                "date": "$DATE",
                "org_id": "$ORG_ID",
                "alert_id": "$ALERT_ID",
                "alert_status": "$ALERT_STATUS",
                "alert_transition": "$ALERT_TRANSITION"
            })
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/integration/webhooks/configuration/webhooks",
                headers=self.headers,
                json=webhook_payload,
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                print(f"✓ Webhook '{self.webhook_name}' created!")
                return True
            elif response.status_code == 409:
                print(f"⚠ Webhook already exists, continuing...")
                return True
            else:
                print(f"✗ Failed to create webhook: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Error creating webhook: {str(e)}")
            return False
    
    def create_host_monitor(self, hostname: str) -> bool:
        """Create monitor for specific host"""
        print(f"[DATADOG] Creating monitor for {hostname}...")
        
        monitor_payload = {
            "name": f"MoveIT Alert - {hostname}",
            "type": "metric alert",
            "query": f'avg(last_5m):avg:system.cpu.idle{{host:{hostname}}} < 10',
            "message": f"""@webhook-{self.webhook_name}

**ALERT: {hostname} Critical Issue**

{{{{#is_alert}}}}
🚨 Host: {hostname}
Status: {{{{check_message}}}}
Time: {{{{last_triggered_at}}}}
Priority: {{{{priority}}}}

This alert is automatically sent to PagerDuty.
{{{{/is_alert}}}}

{{{{#is_recovery}}}}
✅ Host: {hostname} has RECOVERED
Recovery Time: {{{{last_triggered_at}}}}
{{{{/is_recovery}}}}
""",
            "tags": [
                f"host:{hostname}",
                "service:moveit",
                "team:infrastructure",
                "auto-configured:true",
                "priority:high"
            ],
            "priority": 1,
            "options": {
                "notify_audit": True,
                "locked": False,
                "timeout_h": 0,
                "include_tags": True,
                "no_data_timeframe": 10,
                "require_full_window": False,
                "new_host_delay": 300,
                "notify_no_data": True,
                "renotify_interval": 60,
                "escalation_message": f"ESCALATION: {hostname} issue persists!",
                "thresholds": {
                    "critical": 10,
                    "warning": 20
                }
            }
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/monitor",
                headers=self.headers,
                json=monitor_payload,
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                monitor_id = response.json().get('id')
                print(f"✓ Monitor created for {hostname} (ID: {monitor_id})")
                return True
            else:
                print(f"✗ Failed to create monitor for {hostname}: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Error creating monitor for {hostname}: {str(e)}")
            return False


class PagerDutyConfigurator:
    """Handles PagerDuty integration and testing"""
    
    def __init__(self, routing_key: str):
        self.routing_key = routing_key
        self.events_url = "https://events.pagerduty.com/v2/enqueue"
    
    def send_test_alert(self) -> bool:
        """Send test alert to PagerDuty"""
        print("[PAGERDUTY] Sending test alert...")
        
        payload = {
            "routing_key": self.routing_key,
            "event_action": "trigger",
            "payload": {
                "summary": "✓ Auto-Configuration Test - SUCCESS",
                "source": "ultimate_auto_configure.py",
                "severity": "info",
                "timestamp": datetime.utcnow().isoformat(),
                "custom_details": {
                    "message": "This is a test alert from the ultimate auto-configuration script",
                    "status": "Configuration completed successfully",
                    "configured_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
                }
            }
        }
        
        try:
            response = requests.post(
                self.events_url,
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=30
            )
            
            if response.status_code == 202:
                dedup_key = response.json().get('dedup_key')
                print(f"✓ Test alert sent successfully!")
                print(f"  Dedup Key: {dedup_key}")
                return True
            else:
                print(f"✗ PagerDuty test failed: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Error sending test alert: {str(e)}")
            return False


class WebhookServiceManager:
    """Manages the Flask webhook service deployment"""
    
    def __init__(self, webhook_url: str):
        self.webhook_url = webhook_url
        self.health_url = webhook_url.replace('/webhook', '/health')
    
    def check_health(self) -> bool:
        """Check if webhook service is running"""
        print("[WEBHOOK] Checking service health...")
        
        try:
            response = requests.get(self.health_url, timeout=10)
            if response.status_code == 200:
                health_data = response.json()
                print(f"✓ Webhook service is healthy!")
                print(f"  Status: {health_data.get('status')}")
                print(f"  Timestamp: {health_data.get('timestamp')}")
                return True
            else:
                print(f"⚠ Webhook service returned: {response.status_code}")
                return False
        except requests.exceptions.RequestException:
            print("✗ Webhook service is NOT running!")
            print("  ACTION REQUIRED: Deploy the webhook service first:")
            print("    1. export PAGERDUTY_ROUTING_KEY='your_key'")
            print("    2. chmod +x deploy.sh")
            print("    3. ./deploy.sh")
            return False


class UltimateConfigurator:
    """Master orchestrator for complete auto-configuration"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.results = {
            'azure_connected': False,
            'vms_found': [],
            'webhook_created': False,
            'monitors_created': [],
            'pagerduty_verified': False,
            'webhook_service_healthy': False
        }
    
    def run(self) -> Dict:
        """Execute complete configuration"""
        print("
" + "="*70)
        print("  ULTIMATE AUTO-CONFIGURATION - MOVEIT MONITORING SYSTEM")
        print("="*70 + "\n")
        
        target_vms = ["MOVITAUTO", "MOVEITXFR", "PYXSFTP"]
        
        # Step 1: Azure - Find VMs
        print("\n┌─ STEP 1: AZURE CONNECTION ─────────────────────────────────┐\n")
        if self.config.get('azure_tenant_id'):
            azure = AzureConnector(
                tenant_id=self.config['azure_tenant_id'],
                client_id=self.config['azure_client_id'],
                client_secret=self.config['azure_client_secret'],
                subscription_id=self.config['azure_subscription_id']
            )
            
            if azure.authenticate():
                self.results['azure_connected'] = True
                vms = azure.find_target_vms(target_vms)
                self.results['vms_found'] = vms
                
                # Update target list with actual VM names
                if vms:
                    target_vms = [vm['name'].upper() for vm in vms]
        else:
            print("⚠ Azure credentials not provided, using default VMs")
            self.results['azure_connected'] = None
        
        time.sleep(1)
        
        # Step 2: Datadog - Create webhook
        print("\n┌─ STEP 2: DATADOG WEBHOOK SETUP ────────────────────────────┐\n")
        datadog = DatadogConfigurator(
            api_key=self.config['datadog_api_key'],
            app_key=self.config['datadog_app_key'],
            webhook_url=self.config['webhook_url']
        )
        
        self.results['webhook_created'] = datadog.create_webhook()
        time.sleep(1)
        
        # Step 3: Datadog - Create monitors
        print("\n┌─ STEP 3: DATADOG MONITORS SETUP ───────────────────────────┐\n")
        for vm_name in target_vms:
            success = datadog.create_host_monitor(vm_name)
            self.results['monitors_created'].append({
                'host': vm_name,
                'success': success
            })
            time.sleep(0.5)
        
        # Step 4: PagerDuty - Test integration
        print("\n┌─ STEP 4: PAGERDUTY INTEGRATION TEST ───────────────────────┐\n")
        pagerduty = PagerDutyConfigurator(
            routing_key=self.config['pagerduty_routing_key']
        )
        
        self.results['pagerduty_verified'] = pagerduty.send_test_alert()
        time.sleep(1)
        
        # Step 5: Webhook service - Health check
        print("\n┌─ STEP 5: WEBHOOK SERVICE VERIFICATION ─────────────────────┐\n")
        webhook_service = WebhookServiceManager(
            webhook_url=self.config['webhook_url']
        )
        
        self.results['webhook_service_healthy'] = webhook_service.check_health()
        
        # Final summary
        self.print_summary()
        
        return self.results
    
    def print_summary(self):
        """Print configuration summary"""
        print("\n" + "="*70)
        print("  CONFIGURATION SUMMARY")
        print("="*70 + "\n")
        
        # Azure
        if self.results['azure_connected'] is None:
            print("Azure Connection:      ⊘ SKIPPED")
        elif self.results['azure_connected']:
            print(f"Azure Connection:      ✓ CONNECTED")
            print(f"VMs Found:             {len(self.results['vms_found'])}")
            for vm in self.results['vms_found']:
                print(f"  • {vm['name']} ({vm['location']})")
        else:
            print("Azure Connection:      ✗ FAILED")
        
        print()        
        # Datadog
        webhook_status = "✓ CREATED" if self.results['webhook_created'] else "✗ FAILED"
        print(f"Datadog Webhook:       {webhook_status}")
        
        monitors_success = sum(1 for m in self.results['monitors_created'] if m['success'])
        monitors_total = len(self.results['monitors_created'])
        print(f"Datadog Monitors:      {monitors_success}/{monitors_total} created")
        for monitor in self.results['monitors_created']:
            status = "✓" if monitor['success'] else "✗"
            print(f"  {status} {monitor['host']}")
        
        print()        
        # PagerDuty
        pd_status = "✓ VERIFIED" if self.results['pagerduty_verified'] else "✗ FAILED"
        print(f"PagerDuty Integration: {pd_status}")
        
        # Webhook Service
        ws_status = "✓ HEALTHY" if self.results['webhook_service_healthy'] else "✗ NOT RUNNING"
        print(f"Webhook Service:       {ws_status}")
        
        print("\n" + "="*70)        
        # Overall status
        all_critical_success = (
            self.results['webhook_created'] and
            monitors_success > 0 and
            self.results['pagerduty_verified']
        )
        
        if all_critical_success and self.results['webhook_service_healthy']:
            print("\n✓✓✓ CONFIGURATION COMPLETED SUCCESSFULLY! ✓✓✓")
            print("\nYour monitoring system is now fully operational.")
        elif all_critical_success:
            print("\n⚠ CONFIGURATION COMPLETED WITH WARNINGS")
            print("\nNEXT STEP: Deploy the webhook service:")
            print("  1. export PAGERDUTY_ROUTING_KEY='your_key'")
            print("  2. chmod +x deploy.sh")
            print("  3. ./deploy.sh")
        else:
            print("\n✗ CONFIGURATION FAILED")
            print("\nPlease review the errors above and try again.")
        
        print("\n" + "="*70 + "\n")


def main():
    print("""
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║      ULTIMATE AUTO-CONFIGURATION SCRIPT                          ║
║      Azure + Datadog + PagerDuty Integration                     ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
    ")
    
    print("\nThis script will configure:")
    print("  • Azure VM discovery (optional)")
    print("  • Datadog webhook integration")
    print("  • Datadog monitoring for MOVITAUTO, MOVEITXFR, PYXSFTP")
    print("  • PagerDuty alert routing")
    print("  • Webhook service verification")
    print()    
    # Collect credentials
    config = {}    
    # Azure (optional)
    print("─" * 70)
    print("AZURE CREDENTIALS (Optional - Press Enter to skip)")
    print("─" * 70)
    config['azure_tenant_id'] = input("Azure Tenant ID: ").strip()
    if config['azure_tenant_id']:
        config['azure_client_id'] = input("Azure Client ID: ").strip()
        config['azure_client_secret'] = input("Azure Client Secret: ").strip()
        config['azure_subscription_id'] = input("Azure Subscription ID: ").strip()
    
    # Datadog (required)
    print("\n" + "─" * 70)
    print("DATADOG CREDENTIALS (Required)")
    print("─" * 70)
    config['datadog_api_key'] = input("Datadog API Key: ").strip()
    config['datadog_app_key'] = input("Datadog Application Key: ").strip()
    
    # PagerDuty (required)
    print("\n" + "─" * 70)
    print("PAGERDUTY CREDENTIALS (Required)")
    print("─" * 70)
    config['pagerduty_routing_key'] = input("PagerDuty Routing Key: ").strip()
    
    # Webhook URL (required)
    print("\n" + "─" * 70)
    print("WEBHOOK SERVICE (Required)")
    print("─" * 70)
    config['webhook_url'] = input("Webhook URL (e.g., http://your-ip:5000/webhook): ").strip()
    
    # Validation
    required_fields = ['datadog_api_key', 'datadog_app_key', 'pagerduty_routing_key', 'webhook_url']
    missing = [f for f in required_fields if not config.get(f)]    
    if missing:
        print(f"\n✗ Error: Missing required fields: {', '.join(missing)}")
        sys.exit(1)    
    # Confirm
    print("\n" + "="*70)
    print("Ready to configure. This will:")
    print("  1. Connect to Azure (if credentials provided)")
    print("  2. Create Datadog webhook")
    print("  3. Create Datadog monitors for target VMs")
    print("  4. Test PagerDuty integration")
    print("  5. Verify webhook service")
    print("="*70)
    
    confirm = input("\nProceed? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("\nConfiguration cancelled.")
        sys.exit(0)    
    # Run configuration
    configurator = UltimateConfigurator(config)
    results = configurator.run()    
    # Exit code
    success = (
        results['webhook_created'] and
        any(m['success'] for m in results['monitors_created']) and
        results['pagerduty_verified']
    )    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nConfiguration cancelled by user.")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ FATAL ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)