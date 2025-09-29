# Maintenance VM Deployment Guide

This guide describes how to deploy an Ubuntu VM into the management subnet of the CCP4i2 private VNet, with the `ccp4data` Azure File Share automatically mounted at `/mnt/ccp4data` for direct data maintenance.

## Prerequisites
- Infrastructure deployed (VNet, Storage Account, File Share)
- Azure CLI installed and logged in
- Resource group name and location

## Steps

### 1. Deploy the Maintenance VM

```bash
cd bicep/scripts
./deploy-maintenance-vm.sh <resource-group> <location>
```
- The script will:
  - Retrieve storage account name and key
  - Get the management subnet ID
  - Deploy the VM using the Bicep template
  - Mount the `ccp4data` file share at `/mnt/ccp4data` on startup

### 2. Access the VM

- Use Azure Portal or CLI to get the VM's private IP
- SSH into the VM:
  ```bash
  ssh azureuser@<vm-private-ip>
  ```
- The file share will be available at `/mnt/ccp4data`

### 3. Security Notes
- VM is deployed in the management subnet, isolated from public internet
- File share is mounted using storage account key (rotate regularly)
- For enhanced security, consider using Azure AD DS authentication for file shares

---

For troubleshooting or custom mount options, see [Azure Files Linux Mount Guide](https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-mount-files-linux).
