# CCP4 Data Backup and Restore System

This directory contains scripts to create and restore backups of your CCP4 data, ensuring you won't lose your valuable CCP4 installation even when cleaning up Azure resource groups.

## Overview

The backup system consists of two main scripts:
- `backup-ccp4-data.sh` - Creates a backup of CCP4 data in a separate resource group
- `restore-ccp4-data.sh` - Restores CCP4 data from backup to a new deployment

## When to Use

**Create Backup**: After your CCP4 extraction and setup is complete (usually takes ~20 minutes for the 12GB extracted data)

**Restore Backup**: When you create a new deployment and want to use previously extracted CCP4 data instead of re-extracting from the original tar.gz file

## Backup Process

### 1. Wait for CCP4 Extraction to Complete

First, ensure your CCP4 extraction is complete. Check the status:

```bash
/opt/homebrew/bin/az containerapp job execution list --name ccp4-setup-job --resource-group ccp4i2-bicep-rg-ne --output table
```

The status should show "Succeeded" instead of "Running".

### 2. Run the Backup Script

```bash
./backup-ccp4-data.sh
```

This script will:
- ✅ Create a new resource group: `ccp4-backup-rg-ne`
- ✅ Create a backup storage account with a unique name
- ✅ Create a backup file share: `ccp4data-backup`
- ✅ Copy all CCP4 data from your current deployment
- ✅ Verify the backup completed successfully
- ✅ Save backup information to `ccp4-backup-info.txt`

### 3. Backup Details

The backup will be created in:
- **Resource Group**: `ccp4-backup-rg-ne`
- **Location**: North Europe
- **Storage Account**: `ccp4backup[timestamp]` (unique name)
- **File Share**: `ccp4data-backup`
- **Expected Size**: ~12GB (full CCP4 installation)

## Restore Process

### 1. Prerequisites

- Have a new Azure deployment with a storage account
- Ensure the `ccp4-backup-info.txt` file is available
- Know your target resource group and storage account names

### 2. Run the Restore Script

```bash
./restore-ccp4-data.sh [backup_storage] [backup_rg] [backup_share] <target_storage> <target_rg> [target_share]
```

**Example**:
```bash
./restore-ccp4-data.sh "" "" "" "mystorageaccount" "my-new-rg" "ccp4data"
```

The script will automatically use the backup information from `ccp4-backup-info.txt` for the source parameters.

### 3. Restore Process

The script will:
- ✅ Verify the backup exists and is accessible
- ✅ Verify the target deployment exists
- ✅ Create the target file share if needed
- ✅ Copy all data from backup to target
- ✅ Verify the restore completed successfully

## File Structure After Backup

```
/
├── backup-ccp4-data.sh          # Backup script
├── restore-ccp4-data.sh         # Restore script
├── ccp4-backup-info.txt         # Backup configuration (created after backup)
└── README-BACKUP.md             # This documentation
```

## Important Notes

### Security
- The backup resource group is separate from your main deployment
- You can safely delete your main resource group without losing CCP4 data
- Storage account keys are handled securely during copy operations

### Performance
- Backup time: ~15-30 minutes for 12GB of data
- Restore time: ~15-30 minutes for 12GB of data
- Uses Azure CLI for reliable file copying

### Cost Optimization
- Backup uses Standard_LRS storage (lowest cost)
- You only pay for storage used (~12GB for CCP4)
- Consider deleting old backups when no longer needed

## Troubleshooting

### Backup Issues

**"Source share appears to be empty"**
- CCP4 extraction may still be in progress
- Wait for the Container Apps job to show "Succeeded" status
- Run the backup script again after extraction completes

**"Failed to create backup resource group"**
- Check your Azure CLI is authenticated
- Verify you have permission to create resource groups
- Try a different region if quota limits are reached

### Restore Issues

**"Target storage account not found"**
- Ensure your new deployment has been created first
- Verify the storage account name and resource group are correct
- Check that you have access to the target subscription

**"Restore size seems smaller than expected"**
- Some files may have failed to copy
- Check Azure CLI output for specific error messages
- Try running the restore script again

### Performance Issues

**Slow backup/restore speed**
- This is normal for large files over Azure networks
- Consider running during off-peak hours
- Monitor network connectivity if speeds are extremely slow

## Alternative: AzCopy Method

For faster copying, you can use AzCopy instead of Azure CLI:

1. Install AzCopy: https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10
2. The backup script includes AzCopy commands in the output
3. Use the generated SAS URLs for direct copying

## Cleanup

### Remove Backup (when no longer needed)
```bash
az group delete --name ccp4-backup-rg-ne --yes --no-wait
```

### Remove Backup Info File
```bash
rm ccp4-backup-info.txt
```

## Integration with CI/CD

You can integrate these scripts into your deployment pipeline:

1. **After CCP4 Setup**: Automatically run backup script
2. **New Deployments**: Automatically restore from backup instead of re-extracting
3. **Cleanup**: Include backup deletion in your cleanup procedures

## Next Steps

1. **Wait** for your current CCP4 extraction to complete
2. **Run** `./backup-ccp4-data.sh` to create your first backup
3. **Test** the restore process in a new deployment when ready
4. **Document** your backup strategy for your team

---

*Generated by CCP4 Azure Deployment Assistant*