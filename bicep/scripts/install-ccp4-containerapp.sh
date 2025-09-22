#!/bin/bash

# CCP4 Setup using Container Apps Job (stays in private VNet)
# This approach is more secure as it stays within the private VNet

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Setting up CCP4 Data Distribution (Container Apps)${NC}"
echo -e "${BLUE}===================================================${NC}"

echo "🔧 Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Storage Account: $STORAGE_ACCOUNT_NAME"
echo "   ACR: $ACR_NAME"
echo "   Container Apps Environment: $CONTAINER_APPS_ENV_NAME"

# Create a Container Apps job that runs in the private VNet
echo -e "${YELLOW}📦 Creating CCP4 setup job...${NC}"

# Create setup script content
SETUP_SCRIPT='#!/bin/bash
set -e
echo "Starting CCP4 setup..."
cd /mnt/ccp4data
echo "Contents of /mnt/ccp4data:"
ls -la
echo "Looking for CCP4 tar.gz files..."
CCP4_FILE=$(find . -name "*.tar.gz" -o -name "*.tgz" | head -1)
if [ -n "$CCP4_FILE" ]; then
    echo "Found CCP4 file: $CCP4_FILE"
    echo "File size: $(ls -lh $CCP4_FILE)"
    echo "Free space available:"
    df -h /mnt/ccp4data
    echo "Starting extraction (this may take 15-20 minutes for large files)..."
    echo "Note: This 3.6GB archive will extract to approximately 12GB"
    echo "Progress: Starting tar extraction..."
    
    # Use tar with verbose progress and better handling
    # First, clean up any partial extraction
    if [ -d "ccp4-9" ]; then
        echo "Removing partial extraction directory..."
        rm -rf ccp4-9
    fi
    
    echo "Starting fresh extraction with robust options..."
    tar -xzf "$CCP4_FILE" --checkpoint=1000 --checkpoint-action=echo="Extracted %{read}T" --ignore-failed-read --overwrite-dir
    
    # If that fails, try with different compression
    if [ $? -ne 0 ]; then
        echo "Standard extraction failed, trying alternative method..."
        gunzip -c "$CCP4_FILE" | tar -x --checkpoint=1000 --checkpoint-action=echo="Extracted files: %u" --ignore-failed-read
    fi
    
    echo "Extraction complete"
    echo "Contents after extraction:"
    ls -la
    # Look for CCP4 directory and setup script
    if [ -d "ccp4-9.0.011" ]; then
        cd ccp4-9.0.011
        echo "Found CCP4 directory: ccp4-9.0.011"
    elif [ -d "ccp4-9" ]; then
        cd ccp4-9
        echo "Found CCP4 directory: ccp4-9"
    else
        echo "Looking for CCP4 directory..."
        CCP4_DIR=$(find . -name "ccp4*" -type d | head -1)
        if [ -n "$CCP4_DIR" ]; then
            cd "$CCP4_DIR"
            echo "Found CCP4 directory: $CCP4_DIR"
        fi
    fi
    echo "Current directory:"
    pwd
    ls -la
    if [ -f "BINARY.setup" ]; then
        echo "Running BINARY.setup..."
        chmod +x BINARY.setup
        ./BINARY.setup
        echo "CCP4 setup complete!"
    else
        echo "BINARY.setup not found, listing available files:"
        find . -name "*setup*" -o -name "*install*"
        echo "Manual setup may be required"
    fi
else
    echo "Error: No CCP4 .tar.gz file found"
    exit 1
fi
echo "Setup process finished successfully"'

# Create the job YAML configuration
cat > /tmp/ccp4-setup-job.yaml << EOF
properties:
  configuration:
    manualTriggerConfig:
      parallelism: 1
      replicaCompletionCount: 1
    replicaRetryLimit: 1
    replicaTimeout: 7200
    triggerType: Manual
    registries:
    - server: $ACR_LOGIN_SERVER
      username: $ACR_NAME
      passwordSecretRef: registry-password
    secrets:
    - name: registry-password
      value: $(${AZ_CLI} acr credential show --name $ACR_NAME --query 'passwords[0].value' -o tsv)
  template:
    containers:
    - name: ccp4-setup
      image: $ACR_LOGIN_SERVER/ccp4i2/server:${IMAGE_TAG:-latest}
      resources:
        cpu: 2.0
        memory: 4.0Gi
      command:
      - /bin/bash
      args:
      - -c
      - |
$(echo "$SETUP_SCRIPT" | sed 's/^/        /')
      volumeMounts:
      - volumeName: ccp4data-volume
        mountPath: /mnt/ccp4data
    volumes:
    - name: ccp4data-volume
      storageType: AzureFile
      storageName: ccp4data-mount
  environmentId: /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/$CONTAINER_APPS_ENV_NAME
location: northeurope
EOF

# Get subscription ID
SUBSCRIPTION_ID=$(${AZ_CLI} account show --query id -o tsv)

# Update the YAML with correct subscription ID
sed -i.bak "s/\$SUBSCRIPTION_ID/$SUBSCRIPTION_ID/g" /tmp/ccp4-setup-job.yaml

echo -e "${YELLOW}📋 Creating Container Apps job...${NC}"
${AZ_CLI} containerapp job create \
  --name ccp4-setup-job \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APPS_ENV_NAME \
  --yaml /tmp/ccp4-setup-job.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create Container Apps job${NC}"
    echo -e "${YELLOW}💡 Trying alternative approach with individual parameters...${NC}"
    
    # Alternative approach - create job with individual parameters
    ${AZ_CLI} containerapp job create \
      --name ccp4-setup-job \
      --resource-group $RESOURCE_GROUP \
      --environment $CONTAINER_APPS_ENV_NAME \
      --trigger-type Manual \
      --replica-timeout 7200 \
      --replica-retry-limit 1 \
      --parallelism 1 \
      --replica-completion-count 1 \
      --image "$ACR_LOGIN_SERVER/ccp4i2/server:${IMAGE_TAG:-latest}" \
      --registry-server $ACR_LOGIN_SERVER \
      --registry-username $ACR_NAME \
      --registry-password $(${AZ_CLI} acr credential show --name $ACR_NAME --query 'passwords[0].value' -o tsv) \
      --cpu 2.0 \
      --memory 4.0Gi \
      --command "/bin/bash" \
      --args "-c,cd /mnt/ccp4data && echo 'CCP4 Setup Job Ready' && echo 'Found files:' && ls -la && echo 'Looking for .tar.gz files...' && find . -name '*.tar.gz' -o -name '*.tgz' && echo 'Ready for manual setup'"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to create Container Apps job with alternative method${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ CCP4 setup job created successfully!${NC}"
echo -e "${YELLOW}🚀 To start the setup, run:${NC}"
echo "${AZ_CLI} containerapp job start --name ccp4-setup-job --resource-group $RESOURCE_GROUP"
echo ""
echo -e "${YELLOW}📋 To monitor the job execution:${NC}"
echo "${AZ_CLI} containerapp job execution list --name ccp4-setup-job --resource-group $RESOURCE_GROUP --output table"
echo ""
echo -e "${YELLOW}📋 To view job logs:${NC}"
echo "${AZ_CLI} containerapp job logs show --name ccp4-setup-job --resource-group $RESOURCE_GROUP"
echo ""
echo -e "${YELLOW}🗑️ To clean up after completion:${NC}"
echo "${AZ_CLI} containerapp job delete --name ccp4-setup-job --resource-group $RESOURCE_GROUP --yes"

# Clean up temporary file
rm -f /tmp/ccp4-setup-job.yaml /tmp/ccp4-setup-job.yaml.bak

echo -e "${BLUE}🎯 Next Steps:${NC}"
echo "1. Start the job using the command above"
echo "2. Monitor the execution and logs"
echo "3. Once complete, verify the CCP4 installation in the file share"
echo "4. Clean up the job when finished"