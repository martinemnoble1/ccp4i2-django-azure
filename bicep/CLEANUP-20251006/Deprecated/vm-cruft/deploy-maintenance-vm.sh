# Source environment variables
ENV_FILE=".env.deployment"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "Environment file $ENV_FILE not found."
  exit 1
fi
#!/bin/bash
# Source environment variables
ENV_FILE=".env.deployment"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "Environment file $ENV_FILE not found."
  exit 1
fi
#!/bin/bash
# Deploy maintenance VM into VNet and mount ccp4data share
#set -e

if [ -z "$RESOURCE_GROUP" ]; then
  RESOURCE_GROUP="$1"
fi
if [ -z "$RESOURCE_GROUP" ]; then
  echo "ERROR: RESOURCE_GROUP is not set. Please set it in .env.deployment or pass as the first argument."
  exit 1
fi
LOCATION="northeurope"
VM_NAME="ccp4-maint-vm"
ADMIN_USERNAME="azureuser"
SUBNET_NAME="management-subnet"
INFRA_BICEP="infrastructure/infrastructure.bicep"
VM_BICEP="infrastructure/maintenance-vm.bicep"
VNET_NAME="ccp4i2-bicep-vnet-ne"
FILE_SHARE_NAME="ccp4data"

# Get Key Vault name from .env.deployment or Azure
KEY_VAULT_NAME="${KEY_VAULT_NAME:-$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)}"



STORAGE_ACCOUNT=stornekmayz3n2

# Get subnet ID
SUBNET_ID=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query id -o tsv)

STORAGE_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" --query "[0].value" -o tsv)

# Debug: print all inferred environment variables
echo "[DEBUG] Environment variables at script start:"
echo "LOCATION=$LOCATION"
echo "RESOURCE_GROUP=$RESOURCE_GROUP"
echo "VNET_NAME=$VNET_NAME"
echo "SUBNET_NAME=$SUBNET_NAME"
echo "VM_NAME=$VM_NAME"
echo "SUBNET_ID=$SUBNET_ID"
echo "ADMIN_USERNAME=$ADMIN_USERNAME"
echo "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT"
echo "FILE_SHARE_NAME=$FILE_SHARE_NAME"
echo "DEPLOYMENT_NAME=$DEPLOYMENT_NAME"
echo "STORAGE_KEY=$STORAGE_KEY"
echo "VM_BICEP=$VM_BICEP"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$VM_BICEP" \
  --parameters \
    location="$LOCATION" \
    vmName="$VM_NAME" \
    adminUsername="$ADMIN_USERNAME" \
    adminPassword="$(openssl rand -base64 16)" \
    subnetId="$SUBNET_ID" \
    storageAccountName="$STORAGE_ACCOUNT" \
    fileShareName="ccp4data" \
    storageAccountKey="$STORAGE_KEY"
echo "$a"
echo "VM deployed. ccp4data share will be mounted at /mnt/ccp4data on startup."
