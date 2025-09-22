#!/bin/bash

# Upload CCP4 tarball to Azure File Share
# Usage: ./fetch-ccp4-to-storage.sh [path-to-ccp4-tarball]

STORAGE_ACCOUNT_NAME="stornekmayz3n2"
RESOURCE_GROUP="ccp4i2-bicep-rg-ne"
FILE_SHARE_NAME="ccp4data"
CCP4_TARBALL="${1:-/Users/nmemn/Downloads/ccp4-9.0.010-shelx-arpwarp-linux64.tar.gz}"

echo "🔄 Uploading CCP4 tarball to Azure File Share..."
echo "📁 Storage Account: $STORAGE_ACCOUNT_NAME"
echo "📂 File Share: $FILE_SHARE_NAME"
echo "📦 Tarball: $CCP4_TARBALL"

# Check if tarball exists
if [ ! -f "$CCP4_TARBALL" ]; then
    echo "❌ Error: CCP4 tarball not found at $CCP4_TARBALL"
    echo "💡 Usage: $0 [path-to-ccp4-tarball]"
    echo "💡 Default: $0 /Users/nmemn/Downloads/ccp4-9.0.010-shelx-arpwarp-linux64.tar.gz"
    exit 1
fi

# Get storage account key
echo "🔑 Getting storage account key..."
STORAGE_KEY=$(/opt/homebrew/bin/az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query "[0].value" -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    echo "❌ Error: Could not retrieve storage account key"
    exit 1
fi

# Upload the tarball to Azure File Share
echo "📤 Uploading CCP4 tarball..."
/opt/homebrew/bin/az storage file upload \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_KEY \
    --share-name $FILE_SHARE_NAME \
    --source "$CCP4_TARBALL" \
    --path "$(basename "$CCP4_TARBALL")"

if [ $? -eq 0 ]; then
    echo "✅ CCP4 tarball uploaded successfully!"
    echo "📍 Location: $FILE_SHARE_NAME/$(basename "$CCP4_TARBALL")"
    echo ""
    echo "📝 Next steps:"
    echo "1. Deploy your Azure Container Apps application"
    echo "2. The containers will automatically extract and initialize CCP4"
    echo "3. Test your CCP4i2 application"
else
    echo "❌ Failed to upload CCP4 tarball"
    exit 1
fi
