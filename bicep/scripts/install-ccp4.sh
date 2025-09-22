#!/bin/bash

# Setup script for CCP4 data distribution in Private VNet
# Run this after infrastructure deployment is complete

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$BICEP_DIR/.env.deployment"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "❌ .env.deployment not found. Run deploy-infrastructure.sh first."
    exit 1
fi

# Set Azure CLI path
AZ_CLI="/opt/homebrew/bin/az"
if [ ! -f "$AZ_CLI" ]; then
    AZ_CLI="az"  # Fall back to system PATH
fi

# Get additional required variables
STORAGE_ACCOUNT_NAME=$(${AZ_CLI} storage account list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
CONTAINER_APPS_ENV_NAME=$(${AZ_CLI} containerapp env list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)

echo "🔧 Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Storage Account: $STORAGE_ACCOUNT_NAME"
echo "   ACR: $ACR_NAME"
echo "   Container Apps Environment: $CONTAINER_APPS_ENV_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Setting up CCP4 Data Distribution (Private VNet)${NC}"
echo -e "${BLUE}=================================================${NC}"

# For private VNet, we need to temporarily enable public access
echo -e "${YELLOW}🔧 Temporarily enabling public access for setup...${NC}"

# Enable ACR public access temporarily
echo -e "${YELLOW}📦 Enabling ACR public access...${NC}"
${AZ_CLI} acr update --name $ACR_NAME --public-network-enabled true

# Enable Storage Account public access temporarily  
echo -e "${YELLOW}💾 Enabling Storage public access...${NC}"
${AZ_CLI} storage account update \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --allow-blob-public-access true \
  --public-network-access Enabled \
  --default-action Allow

# Get storage account key
STORAGE_KEY=$(${AZ_CLI} storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv)

# Check if CCP4 file exists
echo -e "${YELLOW}📤 Checking for CCP4 distribution file...${NC}"
CCP4_FILES=$(${AZ_CLI} storage file list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --account-key "$STORAGE_KEY" \
  --share-name ccp4data \
  --query "[?contains(name, '.tar.gz') || contains(name, '.tgz')].name" -o tsv)

if [ -z "$CCP4_FILES" ]; then
    echo -e "${YELLOW}📤 No CCP4 .tar.gz file found. Please upload it first:${NC}"
    echo "${AZ_CLI} storage file upload --account-name $STORAGE_ACCOUNT_NAME --account-key '$STORAGE_KEY' --share-name ccp4data --source /path/to/your/ccp4-distribution.tar.gz --path ccp4-distribution.tar.gz"
    echo ""
    echo -e "${YELLOW}Press Enter when you have uploaded the file...${NC}"
    read
    
    # Re-check for files
    CCP4_FILES=$(${AZ_CLI} storage file list \
      --account-name $STORAGE_ACCOUNT_NAME \
      --account-key "$STORAGE_KEY" \
      --share-name ccp4data \
      --query "[?contains(name, '.tar.gz') || contains(name, '.tgz')].name" -o tsv)
fi

if [ -z "$CCP4_FILES" ]; then
    echo -e "${RED}❌ No CCP4 .tar.gz file found after upload check${NC}"
    exit 1
fi

CCP4_FILE=$(echo "$CCP4_FILES" | head -n 1)
echo -e "${GREEN}✅ Found CCP4 file: ${NC}$CCP4_FILE"

# Create the setup container with public access
echo -e "${YELLOW}📦 Creating setup container instance...${NC}"

# Create setup script that will run in container
SETUP_SCRIPT="
#!/bin/bash
set -e
echo 'Starting CCP4 setup...'
cd /mnt/ccp4data
echo 'Contents of /mnt/ccp4data:'
ls -la
echo 'Looking for CCP4 file: $CCP4_FILE'
if [ -f \"\$CCP4_FILE\" ]; then
    echo 'Extracting \$CCP4_FILE...'
    tar -xzf \"\$CCP4_FILE\"
    echo 'Extraction complete'
    echo 'Contents after extraction:'
    ls -la
    # Look for CCP4 directory and setup script
    if [ -d \"ccp4-9.0.011\" ]; then
        cd ccp4-9.0.011
        echo 'Found CCP4 directory: ccp4-9.0.011'
    elif [ -d \"ccp4-9\" ]; then
        cd ccp4-9
        echo 'Found CCP4 directory: ccp4-9'
    else
        echo 'Looking for CCP4 directory...'
        find . -name 'ccp4*' -type d | head -1 | xargs cd
    fi
    echo 'Current directory:'
    pwd
    ls -la
    if [ -f \"BINARY.setup\" ]; then
        echo 'Running BINARY.setup...'
        chmod +x BINARY.setup
        ./BINARY.setup
        echo 'CCP4 setup complete!'
    else
        echo 'BINARY.setup not found, listing available files:'
        find . -name '*setup*' -o -name '*install*'
    fi
else
    echo 'Error: CCP4 file not found: \$CCP4_FILE'
    exit 1
fi
echo 'Setup process finished'
"

${AZ_CLI} container create \
  --resource-group $RESOURCE_GROUP \
  --name ccp4-setup \
  --image "$ACR_LOGIN_SERVER/ccp4i2/server:${IMAGE_TAG:-latest}" \
  --registry-login-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_NAME \
  --registry-password $(${AZ_CLI} acr credential show --name $ACR_NAME --query 'passwords[0].value' -o tsv) \
  --azure-file-volume-account-name $STORAGE_ACCOUNT_NAME \
  --azure-file-volume-account-key "$STORAGE_KEY" \
  --azure-file-volume-share-name ccp4data \
  --azure-file-volume-mount-path /mnt/ccp4data \
  --restart-policy Never \
  --cpu 2 \
  --memory 4 \
  --os-type Linux \
  --environment-variables CCP4_FILE="$CCP4_FILE" \
  --command-line "/bin/bash -c '$SETUP_SCRIPT'"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create setup container${NC}"
    
    # Restore private access even on failure
    echo -e "${YELLOW}🔒 Restoring private access...${NC}"
    ${AZ_CLI} acr update --name $ACR_NAME --public-network-enabled false
    ${AZ_CLI} storage account update \
      --resource-group $RESOURCE_GROUP \
      --name $STORAGE_ACCOUNT_NAME \
      --allow-blob-public-access false \
      --public-network-access Disabled \
      --default-action Deny
    
    exit 1
fi

echo -e "${GREEN}✅ Setup container created${NC}"
echo -e "${YELLOW}📋 Monitor the setup progress:${NC}"
echo "${AZ_CLI} container logs --resource-group $RESOURCE_GROUP --name ccp4-setup --follow"

# Wait for completion
echo -e "${YELLOW}⏳ Waiting for setup to complete...${NC}"
${AZ_CLI} container wait --resource-group $RESOURCE_GROUP --name ccp4-setup --condition Terminated

# Show logs
echo -e "${YELLOW}📋 Setup logs:${NC}"
${AZ_CLI} container logs --resource-group $RESOURCE_GROUP --name ccp4-setup

# Get container exit code
EXIT_CODE=$(${AZ_CLI} container show \
  --resource-group $RESOURCE_GROUP \
  --name ccp4-setup \
  --query 'containers[0].instanceView.currentState.exitCode' -o tsv)

# Clean up the setup container
echo -e "${YELLOW}🧹 Cleaning up setup container...${NC}"
${AZ_CLI} container delete --resource-group $RESOURCE_GROUP --name ccp4-setup --yes

# Restore private access
echo -e "${YELLOW}🔒 Restoring private access for security...${NC}"
${AZ_CLI} acr update --name $ACR_NAME --public-network-enabled false
echo -e "${GREEN}✅ ACR private access restored${NC}"

${AZ_CLI} storage account update \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME \
  --allow-blob-public-access false \
  --public-network-access Disabled \
  --default-action Deny
echo -e "${GREEN}✅ Storage private access restored${NC}"

# Check results
if [ "$EXIT_CODE" = "0" ]; then
    echo -e "${GREEN}🎉 CCP4 data setup completed successfully!${NC}"
    
    # Verify extraction
    echo -e "${YELLOW}📋 Verifying installation...${NC}"
    ${AZ_CLI} storage file list \
      --account-name $STORAGE_ACCOUNT_NAME \
      --account-key "$STORAGE_KEY" \
      --share-name ccp4data \
      --output table
else
    echo -e "${RED}❌ CCP4 setup failed with exit code: $EXIT_CODE${NC}"
    exit 1
fi

echo -e "${BLUE}🔒 Security Status: All services returned to private access${NC}"
echo -e "${GREEN}✅ Ready for application deployment${NC}"