# VM Deprecation Summary

## ✅ Completed Actions

### 1. Files Moved to Deprecated Folder
Moved the following files to `Deprecated/vm-cruft/`:
- `infrastructure/maintenance-vm.bicep`
- `infrastructure/maintenance-vm.json`
- `scripts/deploy-maintenance-vm.sh`

### 2. Created Deletion Script
Created `scripts/delete-maintenance-vm.sh` for cleaning up any existing VMs.

### 3. Verified No VMs Exist
Confirmed that no maintenance VMs are currently deployed in the resource group.

## Why the VM Was Deprecated

The maintenance VM used CIFS/SMB mounts which **cannot create symlinks**, breaking CCP4's shared library structure:
- `.so.2.0.1` → `.so.2.0` → `.so.2` → `.so` symlink chains fail
- Makes the untarred CCP4 distribution completely unusable

## Current Architecture (✅ Working)

**Container Apps Maintenance Job** uses the Azure Files CSI driver which:
- ✅ Properly supports symlinks
- ✅ Successfully installs CCP4 distribution
- ✅ Serverless (no idle costs)
- ✅ Uses shared managed identity

## If You Need to Access Files

**Don't use a VM with CIFS mount!** Instead use:

1. **Azure Storage Explorer** (GUI)
2. **Azure CLI file operations:**
   ```bash
   az storage file list --account-name <storage> --share-name ccp4data
   az storage file download --account-name <storage> --share-name ccp4data --path <file>
   ```
3. **Container Apps console:**
   ```bash
   az containerapp exec --name ccp4i2-bicep-server --resource-group ccp4i2-bicep-rg-ne
   ```

## Cleanup

If a maintenance VM exists (it doesn't currently):
```bash
cd bicep
./scripts/delete-maintenance-vm.sh
```

---
**Date:** October 4, 2025  
**Status:** Deprecated and removed from active deployment
