## Deployment

### Step 1: Set Environment Variable

```bash
export PAGERDUTY_ROUTING_KEY="your_routing_key_here"
```

### Step 2: Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

### Step 3: Configure Datadog Webhook

Run the auto-configuration script:

```bash
python3 ultimate_auto_configure.py
```

This will automatically configure:
- Datadog webhook
- CPU usage alerts (>85%) for MOVITAUTO and MOVEITXFR
- Memory usage alerts (>85%) for MOVITAUTO and MOVEITXFR
- VM stopped alerts for MOVITAUTO and MOVEITXFR
- PagerDuty integration

### Verify

```bash
curl http://localhost:5000/health
```

Service monitors: **MOVITAUTO, MOVEITXFR**

### Alerts Configured:
- CPU Usage > 85%
- Memory Usage > 85%
- VM Stopped/Down
