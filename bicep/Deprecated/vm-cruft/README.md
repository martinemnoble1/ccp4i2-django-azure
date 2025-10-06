# Deprecated: Maintenance VM (CIFS Cruft)

## Why Deprecated

The maintenance VM approach has been **deprecated and replaced** by the Container Apps maintenance job.

### The Problem with the VM

The maintenance VM used **CIFS/SMB mounting** to access Azure Files, which has critical limitations:

1. **No symlink support** - CIFS mounts return "Operation not supported" when creating symlinks
2. **Breaks CCP4 installation** - CCP4's shared libraries rely on symlink chains like:
   ```
   libfoo.so.2.0.1 → libfoo.so.2.0 → libfoo.so.2 → libfoo.so
   ```
3. **Makes untarred distribution unusable** - Without symlinks, the CCP4 suite cannot run

### The Better Solution

**Use the Container Apps maintenance job instead:**

✅ **Proper symlink support** - Uses Azure Files CSI driver, not CIFS  
✅ **Serverless** - Only runs when needed, no idle VM costs  
✅ **Integrated** - Uses the same shared managed identity as other apps  
✅ **Reliable** - Successfully extracts and installs CCP4 distribution  

### Deployment Commands

**To deploy the maintenance job:**
```bash
cd bicep
./scripts/deploy-maintenance-job.sh
```

**To run CCP4 installation:**
```bash
az containerapp job start \
  --name ccp4i2-bicep-maintenance-job \
  --resource-group ccp4i2-bicep-rg-ne
```

**To delete any existing maintenance VM:**
```bash
cd bicep
./scripts/delete-maintenance-vm.sh
```

## Files Moved to This Folder

- `maintenance-vm.bicep` - VM deployment template (DEPRECATED)
- `maintenance-vm.json` - VM parameters (DEPRECATED)
- `deploy-maintenance-vm.sh` - VM deployment script (DEPRECATED)

## Date Deprecated

October 4, 2025

## Reason

CIFS mount limitations with symlinks make VM approach fundamentally unsuitable for CCP4 installation.
Container Apps maintenance job with CSI driver is the correct architecture.
