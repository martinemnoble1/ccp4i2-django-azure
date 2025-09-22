#!/bin/bash

# Monitor CCP4 upload and restore security once complete

STORAGE_ACCOUNT_NAME=stornekmayz3n2
RESOURCE_GROUP=ccp4i2-bicep-rg-ne

echo "🔍 Monitoring CCP4 upload status..."

# Function to restore security
restore_security() {
    echo "🔒 Restoring storage account security..."
    /opt/homebrew/bin/az storage account update \
      --resource-group $RESOURCE_GROUP \
      --name $STORAGE_ACCOUNT_NAME \
      --default-action Deny \
      --allow-blob-public-access false \
      --public-network-access Disabled
    echo "✅ Security restored"
}

# Check if file exists in storage
check_upload() {
    /opt/homebrew/bin/az storage file list \
      --account-name $STORAGE_ACCOUNT_NAME \
      --account-key $(/opt/homebrew/bin/az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv) \
      --share-name ccp4data \
      --query "[?contains(name, 'ccp4-9.0.011')].{Name:name, Size:properties.contentLength}" \
      --output table
}

# Wait and check periodically
echo "⏳ Waiting for upload to complete..."
sleep 300  # Wait 5 minutes first
check_upload

# If you want to restore security manually after upload completes, run:
echo "📋 To restore security after upload completes, run:"
echo "    ./bicep/scripts/monitor-upload.sh restore"

if [ "$1" = "restore" ]; then
    restore_security
fi