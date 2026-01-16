import azure.mgmt.compute
import datadog
import pagerduty

# Initialize Azure Connector
azure_client = azure.mgmt.compute.ComputeManagementClient(credentials, subscription_id)

# Datadog Configuration
api_key = 'YOUR_DATADOG_API_KEY'
app_key = 'YOUR_DATADOG_APP_KEY'
datadog.initialize(api_key=api_key, app_key=app_key)

# Function to create CPU usage monitor
def create_cpu_monitor(vm_name):
    return datadog.api.Monitor.create(  
        type='metric alert',  
        query='avg:system.cpu.idle{{host:{}}} < 15'.format(vm_name),  
        name='CPU Usage Alert for {}'.format(vm_name),  
        message='CPU usage above 85% on {}'.format(vm_name),  
        tags=['movit_auto', 'cpu_alert'],  
        options={'thresholds': {'critical': 85}}  
    )

# Function to create Memory usage monitor

def create_memory_monitor(vm_name):
    return datadog.api.Monitor.create(  
        type='metric alert',  
        query='avg:system.mem.used{{host:{}}} / avg:system.mem.total{{host:{}}} > 0.85'.format(vm_name, vm_name),  
        name='Memory Usage Alert for {}'.format(vm_name),  
        message='Memory usage above 85% on {}'.format(vm_name),  
        tags=['movit_auto', 'memory_alert'],  
        options={'thresholds': {'critical': 85}}  
    )

# Function to create VM Stopped monitor

def create_vm_stopped_monitor(vm_name):
    return datadog.api.Monitor.create(  
        type='service check',  
        query='service_check.vm.status{{host:{}}} == 0'.format(vm_name),  
        name='VM Stopped Alert for {}'.format(vm_name),  
        message='{} is stopped'.format(vm_name),  
        tags=['movit_auto', 'vm_stopped_alert']  
    )

# Target VMs
vms = ['MOVITAUTO', 'MOVEITXFR']
monitors = []

# Creating monitors for each VM
for vm in vms:
    monitors.append(create_cpu_monitor(vm))
    monitors.append(create_memory_monitor(vm))
    monitors.append(create_vm_stopped_monitor(vm))

# Note: PagerDuty integration and webhook service manager configuration would go here.
# For this implementation, we will focus on the Datadog part.
