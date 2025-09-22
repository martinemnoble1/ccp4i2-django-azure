#!/bin/bash

# CCP4 BINARY.setup Only - Container Apps Job
# This script creates a container job that only executes the BINARY.setup command
# Assumes CCP4 files are already extracted in the Azure File Share

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

echo -e "${BLUE}🔧 CCP4 BINARY.setup Execution (Container Apps)${NC}"
echo -e "${BLUE}===============================================${NC}"

echo "🔧 Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Storage Account: $STORAGE_ACCOUNT_NAME"
echo "   ACR: $ACR_NAME"
echo "   Container Apps Environment: $CONTAINER_APPS_ENV_NAME"

# Create setup script content focusing only on BINARY.setup execution
BINARY_SETUP_SCRIPT='#!/bin/bash
set -e
echo "===== CCP4 BINARY.setup Execution Started ====="
echo "Time: $(date)"
echo ""

# Initial directory check
echo "===== Initial Environment Check ====="
echo "Starting directory: $(pwd)"
echo "Available mount points:"
mount | grep -E "(ccp4|mnt)" || echo "No CCP4 or /mnt mount points found"
echo ""
echo "Contents of /mnt:"
ls -la /mnt/ 2>/dev/null || echo "❌ /mnt directory not accessible"
echo ""

# Check if /mnt/ccp4data exists and is accessible
if [ ! -d "/mnt/ccp4data" ]; then
    echo "❌ ERROR: /mnt/ccp4data directory does not exist!"
    echo "Available directories in /mnt:"
    ls -la /mnt/ 2>/dev/null || echo "Cannot access /mnt directory"
    echo ""
    echo "This indicates the Azure File Share is not properly mounted."
    exit 1
fi

if [ ! -r "/mnt/ccp4data" ]; then
    echo "❌ ERROR: /mnt/ccp4data directory is not readable!"
    ls -la /mnt/ccp4data 2>/dev/null || echo "Cannot read /mnt/ccp4data"
    exit 1
fi

# Change to CCP4 data directory with error checking
echo "===== Changing to CCP4 Data Directory ====="
echo "Attempting to change to /mnt/ccp4data..."
cd /mnt/ccp4data || {
    echo "❌ ERROR: Failed to change to /mnt/ccp4data directory!"
    echo "Current directory: $(pwd)"
    echo "This indicates a file system or mount issue."
    exit 1
}

echo "✅ Successfully changed to CCP4 data directory"
echo "Current working directory: $(pwd)"
echo ""

echo "Contents of /mnt/ccp4data:"
ls -la
echo ""

# Look for extracted CCP4 directory
echo "Looking for CCP4 installation directory..."
CCP4_DIRS=(
    "ccp4-9.0.011"
    "ccp4-9"
    "$(find . -maxdepth 2 -name "ccp4*" -type d | head -1)"
)

CCP4_DIR=""
for dir in "${CCP4_DIRS[@]}"; do
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        CCP4_DIR="$dir"
        echo "✅ Found CCP4 directory: $CCP4_DIR"
        break
    fi
done

if [ -z "$CCP4_DIR" ]; then
    echo "❌ ERROR: No CCP4 directory found!"
    echo "Available directories:"
    find . -maxdepth 2 -type d
    echo ""
    echo "Please ensure CCP4 has been extracted to the file share first."
    exit 1
fi

# Navigate to CCP4 directory
echo "===== Navigating to CCP4 Directory ====="
echo "Changing to CCP4 directory: $CCP4_DIR"
cd "$CCP4_DIR" || {
    echo "❌ ERROR: Failed to change to CCP4 directory: $CCP4_DIR"
    echo "Current directory: $(pwd)"
    echo "Available directories:"
    ls -la
    exit 1
}

echo "✅ Successfully changed to CCP4 directory"
echo "Current directory: $(pwd)"
echo ""

echo "Contents of CCP4 directory:"
ls -la
echo ""

# Check for BINARY.setup file and examine it
if [ ! -f "BINARY.setup" ]; then
    echo "❌ ERROR: BINARY.setup file not found!"
    echo "Looking for setup-related files:"
    find . -maxdepth 2 -name "*setup*" -o -name "*install*" -o -name "BINARY*"
    echo ""
    echo "Available files in current directory:"
    ls -la
    exit 1
fi

echo "✅ Found BINARY.setup file"
echo "File details:"
ls -la BINARY.setup
echo ""

# Examine the BINARY.setup script to understand available options
echo "📋 Examining BINARY.setup script for available options..."
echo "Looking for --run-from-script and other options:"
grep -n -A2 -B2 -i "run-from-script\|usage\|help\|options" BINARY.setup | head -20 || echo "No obvious option documentation found"
echo ""
echo "Checking if --run-from-script is supported:"
if grep -q "run-from-script" BINARY.setup; then
    echo "✅ --run-from-script option found in BINARY.setup"
else
    echo "⚠️  --run-from-script option not found, will use fallback methods"
fi
echo ""

# Make BINARY.setup executable
echo "Making BINARY.setup executable..."
chmod +x BINARY.setup
echo ""

# Check environment before execution
echo "===== Environment Check ====="
echo "USER: $USER"
echo "HOME: $HOME"
echo "PWD: $PWD"
echo "PATH: $PATH"
echo "SHELL: $SHELL"
echo "Available disk space:"
df -h /mnt/ccp4data
echo ""

# Set up environment variables that CCP4 setup might need
export CCP4_INSTALL_DIR="$(pwd)"
export CCP4_MASTER="$(pwd)"
echo "Set CCP4_INSTALL_DIR=$CCP4_INSTALL_DIR"
echo "Set CCP4_MASTER=$CCP4_MASTER"
echo ""

echo "===== Starting BINARY.setup Execution ====="
echo "Command: ./BINARY.setup --run-from-script"
echo "Time: $(date)"
echo ""

# Execute BINARY.setup with detailed output using --run-from-script for non-interactive execution
set +e  # Temporarily disable exit on error to capture the exit code
echo "Executing BINARY.setup with --run-from-script (non-interactive mode)..."

# Primary execution method using --run-from-script
echo "Attempt 1: Using source with --run-from-script"
. ./BINARY.setup --run-from-script 2>&1 | tee /tmp/binary_setup_output.log
SETUP_EXIT_CODE=${PIPESTATUS[0]}

if [ $SETUP_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  First attempt failed with exit code: $SETUP_EXIT_CODE"
    echo "Attempt 2: Using bash with --run-from-script"
    bash ./BINARY.setup --run-from-script 2>&1 | tee -a /tmp/binary_setup_output.log
    SETUP_EXIT_CODE=${PIPESTATUS[0]}
fi

if [ $SETUP_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  Second attempt failed with exit code: $SETUP_EXIT_CODE"
    echo "Attempt 3: Using sh with --run-from-script"
    sh ./BINARY.setup --run-from-script 2>&1 | tee -a /tmp/binary_setup_output.log
    SETUP_EXIT_CODE=${PIPESTATUS[0]}
fi

if [ $SETUP_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  All --run-from-script attempts failed. Trying fallback methods..."
    echo "Attempt 4: Using direct execution with --run-from-script"
    ./BINARY.setup --run-from-script 2>&1 | tee -a /tmp/binary_setup_output.log
    SETUP_EXIT_CODE=${PIPESTATUS[0]}
fi

if [ $SETUP_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  Fallback attempt: Using automatic license acceptance (legacy method)"
    echo "y" | ./BINARY.setup 2>&1 | tee -a /tmp/binary_setup_output.log
    SETUP_EXIT_CODE=${PIPESTATUS[0]}
fi

echo ""
echo "===== BINARY.setup Execution Results ====="
echo "Final exit code: $SETUP_EXIT_CODE"
echo "Time: $(date)"
echo "Current directory: $(pwd)"
echo ""

# Verify we are still in the correct directory
if [ "$(pwd)" != "/mnt/ccp4data/${CCP4_DIR}" ]; then
    echo "⚠️  WARNING: Directory changed during execution!"
    echo "Expected: /mnt/ccp4data/${CCP4_DIR}"
    echo "Actual: $(pwd)"
fi

if [ $SETUP_EXIT_CODE -eq 0 ]; then
    echo "✅ BINARY.setup completed successfully!"
else
    echo "❌ BINARY.setup failed with exit code: $SETUP_EXIT_CODE"
    echo ""
    echo "===== Diagnostic Information ====="
    echo "Last 50 lines of output:"
    tail -50 /tmp/binary_setup_output.log
    echo ""
    echo "Error analysis:"
    grep -i "error\|fail\|exception" /tmp/binary_setup_output.log | tail -10
fi

echo ""
echo "===== Post-setup Directory Contents ====="
echo "Contents of $(pwd):"
ls -la
echo ""

echo "Looking for CCP4 environment setup files:"
find . -name "ccp4.setup*" -o -name "*.csh" -o -name "*.sh" | head -10
echo ""

echo "===== Final Status ====="
if [ $SETUP_EXIT_CODE -eq 0 ]; then
    echo "🎉 CCP4 BINARY.setup execution completed successfully!"
    echo "Next steps:"
    echo "1. Verify CCP4 installation by checking environment setup files"
    echo "2. Test CCP4 commands in your application container"
else
    echo "💥 CCP4 BINARY.setup execution failed"
    echo "Check the diagnostic information above for details"
    echo "The complete output log is available at: /tmp/binary_setup_output.log"
fi

echo "Execution finished at: $(date)"
exit $SETUP_EXIT_CODE'

echo -e "${YELLOW}📦 Creating CCP4 BINARY.setup job...${NC}"

# Get subscription ID
SUBSCRIPTION_ID=$(${AZ_CLI} account show --query id -o tsv)

# Ensure storage mount exists in Container Apps environment
echo -e "${YELLOW}🔍 Checking if storage mount exists...${NC}"
if ! ${AZ_CLI} containerapp env storage show \
    --name "$CONTAINER_APPS_ENV_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-name "ccp4data-mount" &>/dev/null; then
    
    echo -e "${YELLOW}📦 Storage mount 'ccp4data-mount' not found. Creating it...${NC}"
    
    # Get storage account key
    STORAGE_KEY=$(${AZ_CLI} storage account keys list \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" -o tsv)
    
    if [ -z "$STORAGE_KEY" ]; then
        echo -e "${RED}❌ Failed to retrieve storage account key${NC}"
        exit 1
    fi
    
    # Create the storage mount
    ${AZ_CLI} containerapp env storage set \
        --name "$CONTAINER_APPS_ENV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-name "ccp4data-mount" \
        --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
        --azure-file-account-key "$STORAGE_KEY" \
        --azure-file-share-name "ccp4data" \
        --access-mode "ReadWrite"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Storage mount 'ccp4data-mount' created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create storage mount${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Storage mount 'ccp4data-mount' already exists${NC}"
fi

# Verify the storage mount configuration
echo -e "${YELLOW}🔍 Verifying storage mount configuration...${NC}"
${AZ_CLI} containerapp env storage show \
    --name "$CONTAINER_APPS_ENV_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-name "ccp4data-mount" \
    --output table

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Storage mount verification failed${NC}"
    exit 1
fi

echo -e "${YELLOW}🔍 Verifying Azure File share accessibility...${NC}"
${AZ_CLI} storage file list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --share-name "ccp4data" \
    --output table 2>/dev/null || echo -e "${YELLOW}⚠️  Could not list file share contents (this is normal if no files exist yet)${NC}"

# Create the job YAML configuration
cat > /tmp/ccp4-binary-setup-job.yaml << EOF
properties:
  configuration:
    manualTriggerConfig:
      parallelism: 1
      replicaCompletionCount: 1
    replicaRetryLimit: 2
    replicaTimeout: 3600
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
    - name: ccp4-binary-setup
      image: $ACR_LOGIN_SERVER/ccp4i2/server:${IMAGE_TAG:-latest}
      resources:
        cpu: 1.0
        memory: 2.0Gi
      command:
      - /bin/bash
      args:
      - -c
      - |
$(echo "$BINARY_SETUP_SCRIPT" | sed 's/^/        /')
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

echo -e "${YELLOW}📋 Creating Container Apps job for BINARY.setup...${NC}"

# First, try to delete existing job if it exists
${AZ_CLI} containerapp job delete --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --yes 2>/dev/null || true

# Create the new job
${AZ_CLI} containerapp job create \
  --name ccp4-binary-setup-job \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APPS_ENV_NAME \
  --yaml /tmp/ccp4-binary-setup-job.yaml

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create Container Apps job${NC}"
    echo -e "${YELLOW}💡 The YAML approach failed. This might be due to complex volume mount syntax.${NC}"
    echo -e "${YELLOW}💡 Container Apps jobs with Azure File mounts work best with YAML configuration.${NC}"
    echo -e "${RED}❌ Please ensure:${NC}"
    echo "   1. The Container Apps environment is properly configured"
    echo "   2. The 'ccp4data-mount' storage exists in the environment"
    echo "   3. The Azure File share 'ccp4data' is accessible"
    echo ""
    echo -e "${YELLOW}💡 You can try running the mount-storage.sh script first:${NC}"
    echo "   cd .."
    echo "   ./mount-storage.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ CCP4 BINARY.setup job created successfully!${NC}"
echo ""
echo -e "${YELLOW}🚀 To start the BINARY.setup execution, run:${NC}"
echo "${AZ_CLI} containerapp job start --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP"
echo ""
echo -e "${YELLOW}📋 To monitor the job execution:${NC}"
echo "${AZ_CLI} containerapp job execution list --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --output table"
echo ""
echo -e "${YELLOW}📋 To view real-time job logs:${NC}"
echo "${AZ_CLI} containerapp job logs show --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --follow"
echo ""
echo -e "${YELLOW}📋 To view completed job logs:${NC}"
echo "${AZ_CLI} containerapp job logs show --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP"
echo ""
echo -e "${YELLOW}🗑️ To clean up after completion:${NC}"
echo "${AZ_CLI} containerapp job delete --name ccp4-binary-setup-job --resource-group $RESOURCE_GROUP --yes"

# Clean up temporary file
rm -f /tmp/ccp4-binary-setup-job.yaml

echo ""
echo -e "${BLUE}🎯 What this job does:${NC}"
echo "1. ✅ Assumes CCP4 files are already extracted"
echo "2. 🔍 Locates the CCP4 installation directory"
echo "3. 🔧 Executes BINARY.setup with multiple fallback methods"
echo "4. 📊 Provides detailed diagnostic output"
echo "5. ✅ Reports success/failure with actionable information"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "1. Run the start command above to execute BINARY.setup"
echo "2. Monitor the logs to see real-time progress"
echo "3. Check the execution results"
echo "4. If successful, verify CCP4 setup in your application container"
echo "5. Clean up the job when finished"