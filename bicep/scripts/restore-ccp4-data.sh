#!/bin/bash

# CCP4 Data Restore Script
# This script restores CCP4 data from backup to a new deployment

# Set Azure CLI path
AZ_CLI="/opt/homebrew/bin/az"
if [ ! -f "$AZ_CLI" ]; then
    AZ_CLI="az"  # Fall back to system PATH
fi

# Check if backup info file exists
if [ ! -f "ccp4-backup-info.txt" ]; then
    echo "❌ Backup info file not found. Please provide backup details manually."
    echo "Usage: $0 [backup_storage_account] [backup_resource_group] [backup_file_share] [target_storage_account] [target_resource_group] [target_file_share]"
    exit 1
fi

# Load backup information
source ccp4-backup-info.txt

# Parse command line arguments or use defaults
BACKUP_STORAGE_ACCOUNT=${1:-$BACKUP_STORAGE_ACCOUNT}
BACKUP_RG=${2:-$BACKUP_RESOURCE_GROUP}
BACKUP_SHARE_NAME=${3:-$BACKUP_FILE_SHARE}
TARGET_STORAGE_ACCOUNT=${4:-""}
TARGET_RG=${5:-""}
TARGET_SHARE_NAME=${6:-"ccp4data"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 CCP4 Data Restore Process${NC}"
echo -e "${BLUE}===========================${NC}"

# Validate required parameters
if [ -z "$TARGET_STORAGE_ACCOUNT" ] || [ -z "$TARGET_RG" ]; then
    echo -e "${RED}❌ Missing target deployment information${NC}"
    echo "Please provide:"
    echo "  - Target storage account name"
    echo "  - Target resource group name"
    echo ""
    echo "Usage: $0 [backup_storage] [backup_rg] [backup_share] <target_storage> <target_rg> [target_share]"
    echo ""
    echo "Available backup:"
    echo "  Storage Account: $BACKUP_STORAGE_ACCOUNT"
    echo "  Resource Group: $BACKUP_RG"
    echo "  File Share: $BACKUP_SHARE_NAME"
    exit 1
fi

echo "📋 Restore Configuration:"
echo "   Source (Backup):"
echo "     Resource Group: $BACKUP_RG"
echo "     Storage Account: $BACKUP_STORAGE_ACCOUNT"
echo "     File Share: $BACKUP_SHARE_NAME"
echo "   Target (New Deployment):"
echo "     Resource Group: $TARGET_RG"
echo "     Storage Account: $TARGET_STORAGE_ACCOUNT"
echo "     File Share: $TARGET_SHARE_NAME"

# Step 1: Verify backup exists
echo -e "${YELLOW}🔍 Verifying backup exists...${NC}"
BACKUP_EXISTS=$(${AZ_CLI} storage account show --name $BACKUP_STORAGE_ACCOUNT --resource-group $BACKUP_RG --query 'name' -o tsv 2>/dev/null || echo "")

if [ -z "$BACKUP_EXISTS" ]; then
    echo -e "${RED}❌ Backup storage account not found: $BACKUP_STORAGE_ACCOUNT${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Backup storage account found${NC}"

# Step 2: Verify target storage account exists
echo -e "${YELLOW}🔍 Verifying target storage account...${NC}"
TARGET_EXISTS=$(${AZ_CLI} storage account show --name $TARGET_STORAGE_ACCOUNT --resource-group $TARGET_RG --query 'name' -o tsv 2>/dev/null || echo "")

if [ -z "$TARGET_EXISTS" ]; then
    echo -e "${RED}❌ Target storage account not found: $TARGET_STORAGE_ACCOUNT${NC}"
    echo "Please ensure your target deployment has been created first"
    exit 1
fi

echo -e "${GREEN}✅ Target storage account found${NC}"

# Step 3: Create target file share if it doesn't exist
echo -e "${YELLOW}📂 Ensuring target file share exists...${NC}"
${AZ_CLI} storage share create \
  --name $TARGET_SHARE_NAME \
  --account-name $TARGET_STORAGE_ACCOUNT \
  --quota 100 \
  --fail-on-exist false

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create or verify target file share${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Target file share ready: $TARGET_SHARE_NAME${NC}"

# Step 4: Get storage account keys
echo -e "${YELLOW}🔑 Getting storage account keys...${NC}"
BACKUP_KEY=$(${AZ_CLI} storage account keys list --resource-group $BACKUP_RG --account-name $BACKUP_STORAGE_ACCOUNT --query '[0].value' -o tsv)
TARGET_KEY=$(${AZ_CLI} storage account keys list --resource-group $TARGET_RG --account-name $TARGET_STORAGE_ACCOUNT --query '[0].value' -o tsv)

if [ -z "$BACKUP_KEY" ] || [ -z "$TARGET_KEY" ]; then
    echo -e "${RED}❌ Failed to get storage account keys${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Storage account keys retrieved${NC}"

# Step 5: Check backup size
echo -e "${YELLOW}🔍 Checking backup data size...${NC}"
BACKUP_SIZE=$(${AZ_CLI} storage share stats --name $BACKUP_SHARE_NAME --account-name $BACKUP_STORAGE_ACCOUNT --account-key $BACKUP_KEY --query 'shareUsageBytes' -o tsv)
BACKUP_SIZE_GB=$((BACKUP_SIZE / 1024 / 1024 / 1024))

echo -e "${GREEN}✅ Backup data size: ${BACKUP_SIZE_GB}GB${NC}"

# Step 6: Start the restore operation
echo -e "${YELLOW}🔄 Starting data restore operation...${NC}"
echo "This may take some time depending on the amount of data (~12GB for CCP4)"

# Create a temporary script for the restore operation
cat > /tmp/restore-ccp4-data.sh << 'EOF'
#!/bin/bash
set -e

AZ_CLI="/opt/homebrew/bin/az"
if [ ! -f "$AZ_CLI" ]; then
    AZ_CLI="az"
fi

BACKUP_RG="$1"
BACKUP_STORAGE="$2"
BACKUP_SHARE="$3"
TARGET_RG="$4"
TARGET_STORAGE="$5"
TARGET_SHARE="$6"

echo "Starting recursive restore from $BACKUP_STORAGE/$BACKUP_SHARE to $TARGET_STORAGE/$TARGET_SHARE"

# Get a list of all files to restore
echo "Scanning backup files..."
${AZ_CLI} storage file list \
  --share-name $BACKUP_SHARE \
  --account-name $BACKUP_STORAGE \
  --recursive \
  --output tsv \
  --query '[].name' > /tmp/restore_file_list.txt

TOTAL_FILES=$(wc -l < /tmp/restore_file_list.txt)
echo "Found $TOTAL_FILES files to restore"

COUNTER=0
while IFS= read -r file; do
    COUNTER=$((COUNTER + 1))
    echo "[$COUNTER/$TOTAL_FILES] Restoring: $file"
    
    # Create directory structure in destination if needed
    DIR=$(dirname "$file")
    if [ "$DIR" != "." ]; then
        ${AZ_CLI} storage directory create \
          --share-name $TARGET_SHARE \
          --account-name $TARGET_STORAGE \
          --name "$DIR" \
          --fail-on-exist false >/dev/null 2>&1 || true
    fi
    
    # Copy the file
    ${AZ_CLI} storage file copy start \
      --source-account-name $BACKUP_STORAGE \
      --source-share $BACKUP_SHARE \
      --source-path "$file" \
      --destination-account-name $TARGET_STORAGE \
      --destination-share $TARGET_SHARE \
      --destination-path "$file"
      
    if [ $((COUNTER % 10)) -eq 0 ]; then
        echo "Progress: $COUNTER/$TOTAL_FILES files restored"
    fi
done < /tmp/restore_file_list.txt

echo "Restore operation completed!"
rm -f /tmp/restore_file_list.txt
EOF

chmod +x /tmp/restore-ccp4-data.sh

echo -e "${BLUE}🚀 Starting restore operation...${NC}"
/tmp/restore-ccp4-data.sh "$BACKUP_RG" "$BACKUP_STORAGE_ACCOUNT" "$BACKUP_SHARE_NAME" "$TARGET_RG" "$TARGET_STORAGE_ACCOUNT" "$TARGET_SHARE_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Restore completed successfully!${NC}"
    
    # Verify restore
    echo -e "${YELLOW}🔍 Verifying restore...${NC}"
    TARGET_SIZE=$(${AZ_CLI} storage share stats --name $TARGET_SHARE_NAME --account-name $TARGET_STORAGE_ACCOUNT --account-key $TARGET_KEY --query 'shareUsageBytes' -o tsv)
    TARGET_SIZE_GB=$((TARGET_SIZE / 1024 / 1024 / 1024))
    
    echo -e "${GREEN}✅ Restore verification:${NC}"
    echo "   Backup size: ${BACKUP_SIZE_GB}GB"
    echo "   Restored size: ${TARGET_SIZE_GB}GB"
    
    if [ $TARGET_SIZE_GB -ge $((BACKUP_SIZE_GB - 1)) ]; then
        echo -e "${GREEN}✅ Restore appears complete and successful!${NC}"
    else
        echo -e "${YELLOW}⚠️ Restored size seems smaller than expected, please verify manually${NC}"
    fi
else
    echo -e "${RED}❌ Restore operation failed${NC}"
    exit 1
fi

# Clean up temporary files
rm -f /tmp/restore-ccp4-data.sh

echo -e "${BLUE}📋 Restore Summary:${NC}"
echo "   Target Resource Group: $TARGET_RG"
echo "   Target Storage Account: $TARGET_STORAGE_ACCOUNT"
echo "   Target File Share: $TARGET_SHARE_NAME"
echo "   Data Restored: ${TARGET_SIZE_GB}GB"
echo ""
echo -e "${GREEN}🎯 Your CCP4 data has been successfully restored!${NC}"
echo "You can now use this data in your new deployment"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "1. Update your Container Apps or other services to use the restored file share"
echo "2. Test that CCP4 applications can access the restored data"
echo "3. Consider creating a new backup of this restored data for future use"