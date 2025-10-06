# Deployment Error Fixes

## Issues Found and Fixed

### 1. ❌ Container Apps Subnet Size Error
**Error:** `The environment network configuration is invalid: Provided subnet must have a size of at least /23`

**Fix Applied:**
- Changed Container Apps subnet from `/24` to `/23`
- Updated subnet address ranges to accommodate larger subnet:
  - Container Apps: `10.0.1.0/23` (minimum required size)
  - Private Endpoints: `10.0.3.0/24` 
  - Management: `10.0.4.0/24`

### 2. ❌ ACR SKU Not Supporting Private Endpoints
**Error:** `The current registry SKU does not support private endpoint connection. Please upgrade your registry to premium SKU`

**Fix Applied:**
- Changed ACR SKU from `Basic` to `Premium`
- Added `publicNetworkAccess: 'Disabled'` for private endpoint only access
- Updated ACR name to be shorter and globally unique

### 3. ❌ Key Vault Name Already Exists
**Error:** `The vault name 'ccp4i2-keyvault-ne' is already in use` (with soft delete)

**Fix Applied:**
- Made Key Vault name globally unique using `uniqueString(resourceGroup().id)`
- Added soft-delete vault purging to deployment script
- Updated naming pattern: `ccp4i2-bicep-kv-ne-{uniqueString}`

### 4. ⚠️ Storage Account Name Uniqueness
**Preventive Fix:**
- Made storage account name globally unique using `uniqueString(resourceGroup().id)`
- Updated naming pattern: `ccp4bicepstor{env}{uniqueString}`

### 5. ⚠️ Prefix Consistency
**Fix Applied:**
- Updated deployment scripts to use consistent prefix `ccp4i2-bicep`
- Ensured all resources use the same naming convention

## Updated Resource Names

### Before (Potentially Conflicting):
```
ACR: ccp4i2acrne01
Storage: ccp4i2storagene  
Key Vault: ccp4i2-keyvault-ne
```

### After (Globally Unique):
```
ACR: ccp4acrne{uniqueString}
Storage: ccp4bicepstorne{uniqueString}
Key Vault: ccp4i2-bicep-kv-ne-{uniqueString}
```

## Network Configuration Updated

### New Subnet Layout:
```
VNet: 10.0.0.0/16
├── Container Apps: 10.0.1.0/23 (512 IPs - meets /23 requirement)
├── Private Endpoints: 10.0.3.0/24 (256 IPs)
└── Management: 10.0.4.0/24 (256 IPs)
```

## Script Updates

### deploy-infrastructure.sh:
- Added soft-delete Key Vault purging
- Updated prefix to `ccp4i2-bicep`
- Added validation checks

### deploy-applications.sh:
- Updated prefix to match infrastructure
- Enhanced network validation

## Next Steps

1. **Run the deployment again:**
   ```bash
   ./deploy-master.sh
   ```

2. **If you still see Key Vault issues:**
   - The script will attempt to purge soft-deleted vaults
   - Manual purge: `az keyvault purge --name <vault-name> --location northeurope`

3. **Monitor the deployment:**
   - Container Apps subnet will now have sufficient IP space (/23)
   - ACR Premium SKU will support private endpoints
   - All resource names will be globally unique

The deployment should now succeed with these fixes!