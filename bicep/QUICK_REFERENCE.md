# CCP4i2 Django Azure - Quick Reference

## One-Command Complete Deployment

From a fresh Azure subscription with CCP4 tar file already uploaded:

```bash
cd bicep/scripts
./deploy-complete.sh
```

This automated script will:
1. ✅ Deploy all infrastructure (VNet, PostgreSQL, Key Vault, Storage, Service Bus)
2. ✅ Create shared managed identity for all services
3. ✅ Check for CCP4 installation
4. ✅ Install Python packages with correct NumPy version
5. ✅ Deploy Server, Worker, and Web applications
6. ✅ Verify deployment with health checks

---

## Manual Step-by-Step Deployment

### 1. Infrastructure
```bash
cd bicep/scripts
./deploy-infrastructure.sh
```

### 2. Extract CCP4 (if not already done)
```bash
# Via management container
./deploy-management.sh
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "cd /mnt/ccp4data && tar -xzf ccp4-9.tar.gz"
```

### 3. Install Python Packages
```bash
./deploy-maintenance-job.sh
az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group ccp4i2-bicep-rg-ne
```

**Note:** Package list is maintained in `requirements.txt` (copied to `/usr/src/app/requirements.txt` in container image).
To update packages, edit `requirements.txt` and rebuild the Docker image.

### 4. Deploy Applications
```bash
./deploy-applications.sh
```

---

## Critical Configuration Details

### NumPy Version Constraint
**Must use `numpy<2.0`** - CCP4's compiled extensions require NumPy 1.x
- ✅ Correct: `numpy<2.0` (installs 1.26.4)
- ❌ Wrong: `numpy` (installs 2.x)

### PYTHONPATH Configuration
Set in container command **after** sourcing CCP4 setup:
```bash
export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && exec /usr/src/app/startup.sh
```

### Package Installation Strategy
- **Install with:** system `python3` (Python 3.10)
- **Run with:** `ccp4-python` (Python 3.9)
- **Target:** `/mnt/ccp4data/py-packages`
- **Why:** Avoids Azure Files I/O hang from scanning corrupted packages

### Forbidden Packages
Never install these (built-in to Python 3):
- ❌ `pathlib` - Python 2.7 backport
- ❌ `configparser` - Built-in
- ❌ `typing` - Built-in

---

## Common Operations

### View Server Logs
```bash
az containerapp logs show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --tail 50 \
  --follow
```

### Restart Server
```bash
az containerapp update \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars RESTART=$(date +%s)
```

### Interactive Shell (Management Container)
```bash
az containerapp exec \
  --name ccp4i2-bicep-management \
  --resource-group ccp4i2-bicep-rg-ne \
  --command /bin/bash
```

### Check Application Status
```bash
az containerapp show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.runningStatus
```

### Test Health Endpoint
```bash
SERVER_URL=$(az containerapp show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.configuration.ingress.fqdn -o tsv)

curl https://${SERVER_URL}/health/
curl https://${SERVER_URL}/projects/
```

---

## Troubleshooting

### NumPy Version Error
```bash
# Remove NumPy 2.x
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "rm -rf /mnt/ccp4data/py-packages/numpy*"

# Install NumPy 1.x
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command 'python3 -m pip install --target /mnt/ccp4data/py-packages "numpy<2.0"'

# Restart
az containerapp update --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars RESTART=$(date +%s)
```

### Path.home() Error
```bash
# Remove pathlib backport
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "rm -rf /mnt/ccp4data/py-packages/pathlib*"

# Restart
az containerapp update --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars RESTART=$(date +%s)
```

### Reinstall All Packages
```bash
# Clean existing packages
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "rm -rf /mnt/ccp4data/py-packages"

# Run maintenance job
az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group ccp4i2-bicep-rg-ne

# Check job logs
az containerapp job logs show --name ccp4i2-bicep-maintenance-job --resource-group ccp4i2-bicep-rg-ne
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Azure Container Apps                    │
├──────────────┬──────────────┬──────────────┬────────────┤
│    Server    │    Worker    │     Web      │ Management │
│  Django API  │ Job Processor│   Next.js    │   (Debug)  │
│   Port 8000  │ Service Bus  │   Port 3000  │            │
└──────────────┴──────────────┴──────────────┴────────────┘
       │              │              │              │
       └──────────────┴──────────────┴──────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
    ┌───────▼────────┐    ┌────────▼─────────┐
    │  PostgreSQL    │    │   Azure Files    │
    │ Flexible Server│    │  - CCP4 Data     │
    │ (Private)      │    │  - Py-Packages   │
    └────────────────┘    │  - Static Files  │
                          └──────────────────┘
            │
    ┌───────▼────────┐
    │   Key Vault    │
    │  (RBAC-based)  │
    │  - DB Password │
    │  - Django Key  │
    └────────────────┘
```

**Key Features:**
- ✅ All services use shared user-assigned managed identity
- ✅ Private endpoints for PostgreSQL, Key Vault, Storage
- ✅ VNet integration for Container Apps
- ✅ Auto-scaling based on CPU, memory, HTTP traffic
- ✅ Azure Files with CSI driver (supports symlinks)

---

## Package Version Matrix

| Package | Version | Why |
|---------|---------|-----|
| NumPy | 1.26.4 | CCP4 binaries require NumPy 1.x |
| SciPy | 1.15.3 | Requires NumPy 1.x |
| Pandas | 2.3.3 | Compatible with NumPy 1.x |
| Django | 3.2.25 | LTS, compatible with typing-extensions 3.x |
| asgiref | 3.3.4 | No typing-extensions 4.x requirement |
| Gunicorn | 23.0.0 | Latest stable |
| Uvicorn | 0.20.0 | Compatible with asgiref 3.3.4 |

---

## Success Indicators

✅ Server health check returns HTTP 200
✅ Projects API returns JSON data
✅ Logs show "Starting gunicorn 23.0.0"
✅ Logs show "Listening at: http://0.0.0.0:8000"
✅ No NumPy compatibility warnings
✅ PySide2/shiboken2 imports succeed

---

## Files Modified for Automation

1. **`bicep/scripts/deploy-complete.sh`** - Master automation script
2. **`bicep/infrastructure/maintenance-job.bicep`** - Package installation job with NumPy constraint
3. **`bicep/infrastructure/applications.bicep`** - PYTHONPATH in command override
4. **`requirements.txt`** - Documented package versions with constraints
5. **`DEPLOYMENT_GUIDE.md`** - Comprehensive deployment documentation
