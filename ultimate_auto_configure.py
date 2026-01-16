import requests
import json

class AzureConnector:
    def __init__(self, azure_credentials):
        self.azure_credentials = azure_credentials

    def get_vm_metrics(self, vm_name):
        # Implement Azure SDK call to retrieve VM metrics
        pass

class DatadogConfigurator:
    def __init__(self, api_key):
        self.api_key = api_key

    def create_monitor(self, monitor_config):
        # Implement API call to Datadog to create a new monitor
        headers = {'Content-Type': 'application/json', 'DD-API-KEY': self.api_key}
        response = requests.post('https://api.datadoghq.com/api/v1/series', headers=headers, data=json.dumps(monitor_config))
        return response

class PagerDutyConfigurator:
    def __init__(self, api_key):
        self.api_key = api_key

    def create_webhook(self, webhook_config):
        # Implement API call to PagerDuty to create a new webhook
        headers = {'Authorization': f'Token token={self.api_key}', 'Content-Type': 'application/json'}
        response = requests.post('https://api.pagerduty.com/webhooks', headers=headers, data=json.dumps(webhook_config))
        return response

class WebhookServiceManager:
    def __init__(self, webhook_url):
        self.webhook_url = webhook_url

    def send_alert(self, message):
        # Implement sending alert to the webhook URL
        requests.post(self.webhook_url, json={'text': message})

class UltimateConfigurator:
    def __init__(self, azure_connector, datadog_configurator, pagerduty_configurator, webhook_service_manager):
        self.azure_connector = azure_connector
        self.datadog_configurator = datadog_configurator
        self.pagerduty_configurator = pagerduty_configurator
        self.webhook_service_manager = webhook_service_manager

    def configure_monitors(self, vm_names):
        for vm_name in vm_names:
            # Create Datadog monitors for CPU and Memory usage
            cpu_monitor_config = {'name': f'CPU Usage - {vm_name}', 'query': f'avg(last_5m):avg:azure.vm.cpu_usage{{vm_name:{vm_name}}} > 85', 'message': f'CPU usage exceeded 85% for {vm_name}', 'type': 'metric', 'options': {'thresholds': {'critical': 85}}}
            memory_monitor_config = {'name': f'Memory Usage - {vm_name}', 'query': f'avg(last_5m):avg:azure.vm.memory_usage{{vm_name:{vm_name}}} > 85', 'message': f'Memory usage exceeded 85% for {vm_name}', 'type': 'metric', 'options': {'thresholds': {'critical': 85}}}
            self.datadog_configurator.create_monitor(cpu_monitor_config)
            self.datadog_configurator.create_monitor(memory_monitor_config)

            # Create webhook for VM stopped alert
            webhook_config = {'name': f'VM Stopped - {vm_name}', 'url': self.webhook_service_manager.webhook_url}
            self.pagerduty_configurator.create_webhook(webhook_config)

# Example of how to use these classes
if __name__ == '__main__':
    azure_connector = AzureConnector(azure_credentials='YourAzureCredentials')
    datadog_configurator = DatadogConfigurator(api_key='YourDatadogAPIKey')
    pagerduty_configurator = PagerDutyConfigurator(api_key='YourPagerDutyAPIKey')
    webhook_service_manager = WebhookServiceManager(webhook_url='YourWebhookURL')
    configurator = UltimateConfigurator(azure_connector, datadog_configurator, pagerduty_configurator, webhook_service_manager)

    configurator.configure_monitors(vm_names=['MOVITAUTO', 'MOVEITXFR'])