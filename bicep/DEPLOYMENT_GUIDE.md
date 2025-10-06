# CCP4i2 Django Azure Deployment Guide

## Complete Deployment Process: From Tar File to Running Server

### Prerequisites

1. **CCP4 tar file** uploaded to Azure Files storage at `/mnt/ccp4data/ccp4-9.tar.gz`
2. **Azure CLI** installed and authenticated
3. **Docker images** built and pushed to ACR
4. **Resource group** created

---

## Step 1: Deploy Infrastructure

This creates the foundational Azure resources with shared managed identity.

```bash
cd bicep/scripts
./deploy-infrastructure.sh
```

**What this does:**
- Creates Container Apps Environment with VNet integration
- Creates PostgreSQL Flexible Server with private endpoint
- Creates Key Vault with private endpoint and RBAC
- Creates Storage Account with Azure Files shares
- Creates Service Bus namespace and queue
- **Creates shared user-assigned managed identity**
- Grants identity access to Key Vault (Key Vault Secrets User role)
- Mounts Azure Files shares to Container Apps Environment

**Outputs:**
- Container Apps Environment ID
- Shared Identity ID and Principal ID
- PostgreSQL server FQDN
- Key Vault name
- ACR login server

---

## Step 2: Extract CCP4 Tar File (One-Time Setup)

If the CCP4 distribution is not already extracted on the file share:

```bash
# Deploy a one-time job to extract the tar file
az containerapp job create \
  --name ccp4i2-bicep-extract-ccp4 \
  --resource-group ccp4i2-bicep-rg-ne \
  --environment ccp4i2-bicep-env-ne \
  --trigger-type Manual \
  --replica-timeout 28800 \
  --image mcr.microsoft.com/azure-cli \
  --cpu 2.0 \
  --memory 4.0Gi \
  --command "/bin/bash" \
  --args "-c" "cd /mnt/ccp4data && tar -xzf ccp4-9.tar.gz && echo 'Extraction complete'" \
  --env-vars "EXTRACTION_PATH=/mnt/ccp4data" \
  --registry-server ccp4acrnekmay.azurecr.io \
  --registry-username ccp4acrnekmay \
  --registry-password "<PASSWORD>" \
  --secrets "registry-password=<PASSWORD>" \
  --mi-user-assigned <IDENTITY_ID>

# Start the extraction job
az containerapp job start --name ccp4i2-bicep-extract-ccp4 --resource-group ccp4i2-bicep-rg-ne
```

**Alternative:** Use the existing maintenance job and modify its command.

---

## Step 3: Install Python Packages

**CRITICAL:** This must be done BEFORE deploying applications to ensure NumPy 1.x is installed.

### Option A: Using Maintenance Job (Recommended)

The maintenance-job.bicep is already configured with the correct package versions:

```bash
# Deploy the maintenance job
az deployment group create \
  --resource-group ccp4i2-bicep-rg-ne \
  --template-file bicep/infrastructure/maintenance-job.bicep \
  --parameters containerAppsEnvironmentId="<ENV_ID>" \
             acrLoginServer="ccp4acrnekmay.azurecr.io" \
             acrName="ccp4acrnekmay" \
             postgresServerFqdn="<POSTGRES_FQDN>" \
             keyVaultName="<KEYVAULT_NAME>" \
             imageTagServer="<IMAGE_TAG>" \
             containerAppsIdentityId="<IDENTITY_ID>"

# Start the job to install packages
az containerapp job start \
  --name ccp4i2-bicep-maintenance-job \
  --resource-group ccp4i2-bicep-rg-ne
```

**What this installs:**
All packages defined in `/usr/src/app/requirements.txt` within the container image, including:
- Django 3.2.25 (compatible with typing-extensions 3.x)
- asgiref 3.3.4 (compatible with typing-extensions 3.x)
- **numpy<2.0** (installs 1.26.4 - CRITICAL for CCP4 compatibility)
- **scipy<2.0** (installs 1.15.3 - compatible with NumPy 1.x)
- **pandas<3.0** (installs 2.3.3 - compatible with NumPy 1.x)
- All Azure packages (azure-servicebus, azure-identity, azure-keyvault-secrets, etc.)
- CCP4-related packages (gemmi, biopython, etc.)
- Web server packages (gunicorn, uvicorn, whitenoise)

**Note:** The package list is maintained in the `requirements.txt` file at the root of the repository, 
which is copied to `/usr/src/app/requirements.txt` during Docker image build.

**Installation location:** `/mnt/ccp4data/py-packages` (separate from CCP4's site-packages)

### Option B: Manual Installation via Management Container

```bash
# Deploy management container for interactive access
./deploy-management.sh

# Install packages manually
az containerapp exec \
  --name ccp4i2-bicep-management \
  --resource-group ccp4i2-bicep-rg-ne \
  --command 'python3 -m pip install --target /mnt/ccp4data/py-packages "numpy<2.0" "scipy<2.0" "pandas<3.0" django==3.2.25 asgiref==3.3.4 ...'
```

---

## Step 4: Deploy Applications

Once packages are installed, deploy the container apps:

```bash
cd bicep/scripts
./deploy-applications.sh
```

**What this deploys:**
- **Server App**: Django REST API with gunicorn + uvicorn workers
  - Command override: `export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && exec /usr/src/app/startup.sh`
  - Uses shared managed identity for Key Vault access
  - Mounts CCP4 data, static files, and media files
  - Health checks on `/health/` and `/projects/`
  
- **Worker App**: Background job processor (scaled to 0 by default)
  - Command override: `export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && exec /usr/src/app/startup-worker.sh`
  - Auto-scales based on Service Bus queue depth
  
- **Web App**: Next.js frontend
  - Serves static frontend
  - Proxies API requests to server app

---

## Step 5: Verify Deployment

```bash
# Get application URLs
SERVER_URL=$(az containerapp show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.configuration.ingress.fqdn -o tsv)

# Test health endpoint
curl -s "https://${SERVER_URL}/health/" | jq

# Test projects API
curl -s "https://${SERVER_URL}/projects/" | jq

# Check server logs
az containerapp logs show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --tail 50
```

**Expected results:**
- Health endpoint returns HTTP 200
- Projects API returns JSON array
- Server logs show "Starting gunicorn", "Listening at: http://0.0.0.0:8000"
- No NumPy compatibility warnings

---

## Key Architecture Decisions

### 1. Shared Managed Identity
All container apps use a single user-assigned managed identity:
- Simplifies RBAC management
- Single identity for Key Vault access
- Single identity for ACR pull

### 2. Two-Python Strategy
- **System python3** (Python 3.10): Used for installing packages via pip
  - Avoids Azure Files I/O hang when scanning CCP4's corrupted packages
  - Installation target: `/mnt/ccp4data/py-packages`
- **CCP4 Python** (Python 3.9): Used at runtime
  - Full CCP4 environment available
  - PYTHONPATH set to load `/mnt/ccp4data/py-packages` first

### 3. NumPy Version Pinning
**CRITICAL:** CCP4's compiled extensions (PySide2, shiboken2, etc.) were built against NumPy 1.x:
- Must use `numpy<2.0` (installs 1.26.4)
- NumPy 2.0+ breaks binary compatibility
- Also pin scipy<2.0 and pandas<3.0 for consistency

### 4. PYTHONPATH Configuration
Set in container command AFTER sourcing CCP4 setup:
```bash
export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && exec /usr/src/app/startup.sh
```
This ensures new packages take precedence over CCP4's packages.

### 5. Package Installation Pitfalls

**Do NOT install these packages** (they're built-in to Python 3.4+):
- ❌ `pathlib` - Python 2.7 backport that breaks Path.home()
- ❌ `configparser` - Built-in to Python 3
- ❌ `typing` - Built-in to Python 3.5+

**Avoid pip upgrade operations** on Azure Files:
- Use `pip install --target` (no uninstall needed)
- Never use `pip uninstall` on Azure Files mount (hangs for 8+ minutes)

---

## Troubleshooting

### Issue: "Module that was compiled using NumPy 1.x cannot be run in NumPy 2.0"

**Cause:** NumPy 2.x installed instead of 1.x

**Fix:**
```bash
# Remove NumPy 2.x
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "rm -rf /mnt/ccp4data/py-packages/numpy-2.* /mnt/ccp4data/py-packages/numpy"

# Install NumPy 1.x
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command 'python3 -m pip install --target /mnt/ccp4data/py-packages "numpy<2.0"'

# Restart server
az containerapp update --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars RESTART_TRIGGER=$(date +%s)
```

### Issue: "AttributeError: type object 'Path' has no attribute 'home'"

**Cause:** pathlib backport package installed

**Fix:**
```bash
# Remove pathlib backport
az containerapp exec --name ccp4i2-bicep-management --resource-group ccp4i2-bicep-rg-ne \
  --command "rm -rf /mnt/ccp4data/py-packages/pathlib*"

# Restart server
az containerapp update --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne \
  --set-env-vars RESTART_TRIGGER=$(date +%s)
```

### Issue: pip install hangs indefinitely

**Cause:** pip scanning corrupted packages in CCP4's site-packages on Azure Files mount

**Fix:** Use system python3 instead of ccp4-python for installation:
```bash
# DON'T: source /mnt/ccp4data/ccp4-9/bin/ccp4.setup-sh && ccp4-python -m pip install ...
# DO: python3 -m pip install --target /mnt/ccp4data/py-packages ...
```

### Issue: Import errors for Django packages

**Cause:** PYTHONPATH not set correctly

**Fix:** Ensure PYTHONPATH is set in container command AFTER CCP4 setup:
```bicep
command: ['/bin/bash']
args: ['-c', 'export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && exec /usr/src/app/startup.sh']
```

---

## Complete Automation Script

Here's a master script that does everything:

```bash
#!/bin/bash
set -e

echo "🚀 Starting CCP4i2 Django Azure Deployment..."

# Step 1: Deploy infrastructure
echo "📦 Deploying infrastructure..."
cd bicep/scripts
./deploy-infrastructure.sh

# Step 2: Install Python packages (maintenance job)
echo "🐍 Installing Python packages..."
./deploy-maintenance-job.sh
az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group ccp4i2-bicep-rg-ne

# Wait for package installation to complete
echo "⏳ Waiting for package installation..."
sleep 120

# Step 3: Deploy applications
echo "🌐 Deploying applications..."
./deploy-applications.sh

# Step 4: Verify deployment
echo "✅ Verifying deployment..."
SERVER_URL=$(az containerapp show \
  --name ccp4i2-bicep-server \
  --resource-group ccp4i2-bicep-rg-ne \
  --query properties.configuration.ingress.fqdn -o tsv)

echo "🔍 Testing health endpoint..."
curl -s "https://${SERVER_URL}/health/" | jq

echo "🔍 Testing projects API..."
curl -s "https://${SERVER_URL}/projects/" | jq

echo "✨ Deployment complete!"
echo "Server URL: https://${SERVER_URL}"
```

---

## Future Improvements

1. **Docker Image Pre-Configuration**
   - Pre-install NumPy 1.x in Docker image build
   - Eliminates need for runtime package installation
   - **Current approach:** Packages are installed at runtime via maintenance job using `requirements.txt`

2. **Init Container for Package Installation**
   - Use Container Apps init containers instead of maintenance job
   - Packages installed before main container starts

3. **Requirements.txt Management** ✅ **IMPLEMENTED**
   - ✅ requirements.txt with pinned versions created
   - ✅ Maintenance job uses requirements.txt from container image
   - ✅ To update: edit requirements.txt → rebuild image → redeploy maintenance job → run job

4. **Health Check Improvements**
   - Add database connectivity check to health endpoint
   - Add CCP4 environment validation

5. **Logging and Monitoring**
   - Configure Application Insights
   - Set up alerts for failed health checks
   - Monitor NumPy version at startup

---

## Package Update Workflow

To update Python packages:

1. Edit `requirements.txt` at repository root
2. Rebuild Docker image: `./scripts/build-and-push.sh`
3. Redeploy maintenance job: `./scripts/deploy-maintenance-job.sh` (uses new image)
4. Run maintenance job: `az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group ccp4i2-bicep-rg-ne`
5. Restart applications: `./scripts/deploy-applications.sh`

**Important:** Always maintain the `numpy<2.0`, `scipy<2.0`, and `pandas<3.0` constraints for CCP4 compatibility.

---

## Summary

**Minimum steps for fresh deployment:**

1. Upload CCP4 tar file to Azure Files
2. Run `./deploy-infrastructure.sh`
3. Run `./deploy-maintenance-job.sh` and start the job
4. Wait for package installation (check logs)
5. Run `./deploy-applications.sh`
6. Verify with `curl https://<SERVER_URL>/health/`

**Key success factors:**
- ✅ Use `numpy<2.0` constraint
- ✅ Install packages with system python3
- ✅ Set PYTHONPATH in command after CCP4 setup
- ✅ Never install pathlib or configparser
- ✅ Use shared managed identity for all apps
