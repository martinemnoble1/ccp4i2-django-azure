# Worker Container App Setup

## Overview
The worker container app processes long-running jobs from the Azure Service Bus queue. It uses the **same Docker image** as the Django server but with a different startup script (`startup-worker.sh` instead of `startup.sh`).

## Files Location
- `server/worker.py` - Queue monitoring script
- `server/startup-worker.sh` - Worker startup script
- Both files should be in your Django project's `server/` directory

## Django Integration

### 1. Add Worker Script and Startup Script to Container
The worker uses the same Docker image as the Django server but with a different startup script.

**Add to your Dockerfile:**
```dockerfile
# Copy worker script and startup script
COPY server/worker.py /usr/src/app/worker.py
COPY server/startup-worker.sh /usr/src/app/startup-worker.sh
RUN chmod +x /usr/src/app/worker.py /usr/src/app/startup-worker.sh
```

**Container Apps Configuration:**
- **Django Server**: Uses default `CMD ["/usr/src/app/startup.sh"]` (launches gunicorn)
- **Worker**: Uses `command: ['/usr/src/app/startup-worker.sh']` (launches queue monitor)### 2. Update Django Code to Enqueue Jobs
In your Django views that trigger long-running tasks:

```python
from azure.servicebus import ServiceBusClient
from azure.identity import DefaultAzureCredential
import json

def start_long_job(request):
    # Your existing logic...

    # Enqueue job for worker processing
    credential = DefaultAzureCredential()
    sb_client = ServiceBusClient(
        fully_qualified_namespace="ccp4i2-bicep-servicebus.servicebus.windows.net",
        credential=credential
    )

    job_data = {
        'id': 'unique-job-id',
        'task': 'ccp4_analysis',  # or 'data_processing'
        'parameters': {
            'input_file': 'path/to/file',
            'output_dir': '/mnt/results',
            # ... other parameters
        }
    }

    sender = sb_client.get_queue_sender(queue_name="ccp4i2-bicep-jobs")
    sender.send_messages(json.dumps(job_data))

    return JsonResponse({'status': 'queued', 'job_id': job_data['id']})
```

### 3. Implement Job Processing Logic
Update the `process_job()` function in `worker.py` to handle your specific job types:

```python
def process_job(job_data):
    task = job_data.get('task')
    if task == 'ccp4_analysis':
        # Your CCP4 processing logic
        result = run_ccp4_analysis(job_data['parameters'])
        return result
    elif task == 'data_processing':
        # Other processing logic
        result = process_data(job_data['parameters'])
        return result
    else:
        raise ValueError(f"Unknown task: {task}")
```

## Deployment
The worker is automatically deployed with the applications:

```bash
cd bicep
source .env.deployment && ./scripts/deploy-applications.sh
```

## Monitoring
- Check queue length: Azure Portal > Service Bus > Queues
- Monitor worker scaling: Container Apps > Revisions
- View logs: Container Apps > Log Stream

## Security
- ✅ Managed identity for Service Bus access
- ✅ Key Vault integration for secrets
- ✅ Private networking only
- ✅ RBAC-based access control