# Management Container

## Overview

The management container is a **long-lived interactive container** designed for debugging, maintenance, and administrative tasks. Unlike the production containers (server, web, worker), this container runs `tail -f /dev/null` to stay alive, allowing you to exec into it at any time.

## Purpose

This container provides a **full environment** with:
- ✅ All Azure File shares mounted (`/mnt/ccp4data`, `/mnt/staticfiles`, `/mnt/mediafiles`)
- ✅ All environment variables configured (database, Key Vault, Service Bus)
- ✅ Access to secrets via shared managed identity
- ✅ Python, Django, and all development tools
- ✅ Direct access to PostgreSQL via private endpoint
- ✅ Same network context as production containers

## Use Cases

### 1. **Interactive Django Shell**
```bash
./scripts/connect-management.sh
# Inside container:
python manage.py shell
```

### 2. **Database Operations**
```bash
./scripts/connect-management.sh
# Inside container:
python manage.py migrate
python manage.py dbshell
psql -h $DB_HOST -U $DB_USER -d $DB_NAME
```

### 3. **File System Debugging**
```bash
./scripts/connect-management.sh
# Inside container:
ls -la /mnt/ccp4data
cd /mnt/ccp4data/ccp4-9/lib
ldd libfoo.so  # Check library dependencies
readlink -f libfoo.so  # Follow symlinks
```

### 4. **Environment Inspection**
```bash
./scripts/connect-management.sh
# Inside container:
env | grep DB_
env | grep CCP4
printenv
```

### 5. **Testing Database Connectivity**
```bash
./scripts/connect-management.sh
# Inside container:
python -c "import psycopg2; conn = psycopg2.connect(host='$DB_HOST', user='$DB_USER', password='$DB_PASSWORD', database='$DB_NAME'); print('Connected successfully')"
```

## Deployment

### Deploy the Management Container
```bash
cd bicep
./scripts/deploy-management.sh
```

This will:
1. Get infrastructure outputs (environment, Key Vault, PostgreSQL, identity)
2. Deploy the management container with all mounts and secrets
3. Print the connection command

### Connect to the Container
**Easy way:**
```bash
cd bicep
./scripts/connect-management.sh
```

**Direct way:**
```bash
az containerapp exec \
  --resource-group ccp4i2-bicep-rg-ne \
  --name ccp4i2-bicep-management \
  --command bash
```

## Architecture

### Container Configuration
- **Image**: Same server image as production (`ccp4i2/server:latest`)
- **Command**: `/bin/bash -c 'echo "Management container ready" && tail -f /dev/null'`
- **No Ingress**: Not exposed via HTTP (exec access only)
- **No Health Probes**: Container stays running indefinitely
- **Identity**: Uses shared user-assigned managed identity
- **Resources**: 2.0 CPU, 4.0 GB memory

### Mounted Volumes
```
/mnt/ccp4data     → Azure File share (ccp4data-mount)
/mnt/staticfiles  → Azure File share (staticfiles-mount)
/mnt/mediafiles   → Azure File share (mediafiles-mount)
```

### Secrets Available
All secrets are retrieved from Key Vault via managed identity:
- `db-password` - PostgreSQL admin password
- `django-secret-key` - Django secret key
- `servicebus-connection` - Service Bus connection string

## Differences from Production Containers

| Aspect | Management Container | Production Containers |
|--------|---------------------|----------------------|
| Purpose | Debug/maintenance | Serve requests |
| Command | `tail -f /dev/null` | Django/Next.js server |
| Ingress | None | HTTP exposed |
| Health Probes | None | Liveness/Readiness/Startup |
| Access | `az containerapp exec` | HTTP requests |
| Replicas | 1 (fixed) | 1-10 (autoscaling) |

## Cost Considerations

The management container runs **continuously** with 2 CPU cores and 4 GB memory. 

**Monthly cost estimate**: ~$50-70 USD

If you only need occasional access, consider:
1. Delete the container when not needed
2. Redeploy when needed for debugging
3. Use the maintenance job for scheduled tasks

**To delete:**
```bash
az containerapp delete \
  --name ccp4i2-bicep-management \
  --resource-group ccp4i2-bicep-rg-ne \
  --yes
```

## Troubleshooting

### Container Won't Start
Check the logs:
```bash
az containerapp logs show \
  --name ccp4i2-bicep-management \
  --resource-group ccp4i2-bicep-rg-ne \
  --follow
```

### Can't Access Key Vault Secrets
Verify RBAC permissions:
```bash
# Check if shared identity has Key Vault Secrets User role
az role assignment list \
  --scope /subscriptions/<sub-id>/resourceGroups/ccp4i2-bicep-rg-ne/providers/Microsoft.KeyVault/vaults/kv-ne-<suffix> \
  --query "[?principalId=='<identity-principal-id>'].{Role:roleDefinitionName}" \
  -o table
```

### File Mounts Not Working
Check Container Apps Environment storage:
```bash
az containerapp env storage list \
  --name ccp4i2-bicep-env-ne \
  --resource-group ccp4i2-bicep-rg-ne \
  -o table
```

## See Also

- [Maintenance Job](./MAINTENANCE_JOB.md) - For scheduled/one-time tasks (CCP4 installation)
- [Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Deprecated VM](../Deprecated/VM_DEPRECATION.md) - Why we don't use VMs with CIFS mounts
