#! /bin/sh

RESOURCE_GROUP="ccp4i2-rg-ne"
LOCATION="northeurope"
ENVIRONMENT_NAME="ccp4i2-env-ne"
CONTAINERAPP_NAME="ccp4i2-app-ne"
ACR_NAME="ccp4i2acrne"
STORAGE_ACCOUNT_NAME="ccp4i2storagene"

# Get storage account key
STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)
if [ -z "$STORAGE_ACCOUNT_KEY" ]; then
    echo "❌ Error: Could not retrieve storage account key"
    exit 1
fi

# Enable storage in the environment
echo -e "${YELLOW}🌐 Attaching storage to the environment...${NC}"
az containerapp env storage set \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --storage-name ccp4data-mount \
  --azure-file-account-name $STORAGE_ACCOUNT_NAME \
  --azure-file-account-key $STORAGE_ACCOUNT_KEY \
  --azure-file-share-name ccp4data \
  --access-mode ReadWrite
