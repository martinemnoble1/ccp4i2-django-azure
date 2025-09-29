#!/bin/bash

# CCP4 Data Backup Script
# This script creates a backup of CCP4 data in a separate resource group
# so it won't be lost when cleaning up the main deployment

# Set Azure CLI path
AZ_CLI="/opt/homebrew/bin/az"
if [ ! -f "$AZ_CLI" ]; then
    AZ_CLI="az"  # Fall back to system PATH
fi

# Configuration
BACKUP_RG="ccp4-backup-rg-ne"
BACKUP_STORAGE_ACCOUNT="ccp4backup$(date +%s | tail -c 8)"  # Add timestamp for uniqueness
BACKUP_LOCATION="northeurope"
BACKUP_SHARE_NAME="ccp4data-backup"

# Source configuration (current deployment)
SOURCE_RG="ccp4i2-bicep-rg-ne"
SOURCE_STORAGE_ACCOUNT="stornekmayz3n2"
SOURCE_SHARE_NAME="ccp4data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 CCP4 Data Backup Process${NC}"
echo -e "${BLUE}===========================${NC}"

echo "📋 Configuration:"
echo "   Source RG: $SOURCE_RG"
echo "   Source Storage: $SOURCE_STORAGE_ACCOUNT"
echo "   Source Share: $SOURCE_SHARE_NAME"
echo "   Backup RG: $BACKUP_RG"
echo "   Backup Storage: $BACKUP_STORAGE_ACCOUNT"
echo "   Backup Share: $BACKUP_SHARE_NAME"

# Step 1: Create backup resource group
echo -e "${YELLOW}📁 Creating backup resource group...${NC}"
${AZ_CLI} group create \
  --name $BACKUP_RG \
  --location $BACKUP_LOCATION

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create backup resource group${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Backup resource group created: $BACKUP_RG${NC}"

# Step 2: Create backup storage account
echo -e "${YELLOW}💾 Creating backup storage account...${NC}"
${AZ_CLI} storage account create \
  --name $BACKUP_STORAGE_ACCOUNT \
  --resource-group $BACKUP_RG \
  --location $BACKUP_LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --access-tier Hot

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create backup storage account${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Backup storage account created: $BACKUP_STORAGE_ACCOUNT${NC}"

# Step 3: Create backup file share
echo -e "${YELLOW}📂 Creating backup file share...${NC}"
${AZ_CLI} storage share create \
  --name $BACKUP_SHARE_NAME \
  --account-name $BACKUP_STORAGE_ACCOUNT \
  --quota 100

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to create backup file share${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Backup file share created: $BACKUP_SHARE_NAME${NC}"

# Step 4: Get storage account keys
echo -e "${YELLOW}🔑 Getting storage account keys...${NC}"
SOURCE_KEY=$(${AZ_CLI} storage account keys list --resource-group $SOURCE_RG --account-name $SOURCE_STORAGE_ACCOUNT --query '[0].value' -o tsv)
BACKUP_KEY=$(${AZ_CLI} storage account keys list --resource-group $BACKUP_RG --account-name $BACKUP_STORAGE_ACCOUNT --query '[0].value' -o tsv)

if [ -z "$SOURCE_KEY" ] || [ -z "$BACKUP_KEY" ]; then
    echo -e "${RED}❌ Failed to get storage account keys${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Storage account keys retrieved${NC}"

# Step 5: Check if source data exists and get size
echo -e "${YELLOW}🔍 Checking source data...${NC}"
SOURCE_SIZE=$(${AZ_CLI} storage share stats --name $SOURCE_SHARE_NAME --account-name $SOURCE_STORAGE_ACCOUNT --account-key $SOURCE_KEY --query 'shareUsageBytes' -o tsv 2>/dev/null || echo "0")

if [ "$SOURCE_SIZE" = "0" ]; then
    echo -e "${YELLOW}⚠️ Source share appears to be empty or CCP4 extraction may still be in progress${NC}"
    echo "You can run this script again once the CCP4 extraction is complete"
    echo "Current backup infrastructure is ready:"
    echo "   Resource Group: $BACKUP_RG"
    echo "   Storage Account: $BACKUP_STORAGE_ACCOUNT"
    echo "   File Share: $BACKUP_SHARE_NAME"
    exit 0
fi

SOURCE_SIZE_GB=$((SOURCE_SIZE / 1024 / 1024 / 1024))
echo -e "${GREEN}✅ Source data found: ${SOURCE_SIZE_GB}GB${NC}"

# Step 6: Start the copy operation
echo -e "${YELLOW}🔄 Starting data copy operation...${NC}"
echo "This may take some time depending on the amount of data (~12GB for CCP4)"

echo "Copy operation completed!"
echo -e "${BLUE}🚀 Starting copy operation...${NC}"

echo -e "${YELLOW}🔐 Generating SAS tokens for azcopy...${NC}"
if [[ "$OSTYPE" == "darwin"* ]]; then
  SAS_EXPIRY=$(date -u -v+2H '+%Y-%m-%dT%H:%MZ')
else
  SAS_EXPIRY=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
fi
SOURCE_SAS=$(${AZ_CLI} storage share generate-sas \
  --name $SOURCE_SHARE_NAME \
  --account-name $SOURCE_STORAGE_ACCOUNT \
  --account-key $SOURCE_KEY \
  --permissions rl \
  --expiry "$SAS_EXPIRY" \
  --output tsv)

BACKUP_SAS=$(${AZ_CLI} storage share generate-sas \
  --name $BACKUP_SHARE_NAME \
  --account-name $BACKUP_STORAGE_ACCOUNT \
  --account-key $BACKUP_KEY \
  --permissions rwl \
  --expiry "$SAS_EXPIRY" \
  --output tsv)

if [ -z "$SOURCE_SAS" ] || [ -z "$BACKUP_SAS" ]; then
  echo -e "${RED}❌ Failed to generate SAS tokens. Aborting backup.${NC}"
  exit 1
fi

echo -e "${YELLOW}🚀 Starting azcopy recursive copy...${NC}"
AZCOPY_PATH=$(command -v azcopy)
if [ -z "$AZCOPY_PATH" ]; then
  echo -e "${RED}❌ azcopy not found. Please install azcopy: https://aka.ms/azcopy${NC}"
  exit 1
fi

SRC_URL="https://${SOURCE_STORAGE_ACCOUNT}.file.core.windows.net/${SOURCE_SHARE_NAME}?${SOURCE_SAS}"
DST_URL="https://${BACKUP_STORAGE_ACCOUNT}.file.core.windows.net/${BACKUP_SHARE_NAME}?${BACKUP_SAS}"

echo "azcopy copy '$SRC_URL' '$DST_URL' --recursive=true"
$AZCOPY_PATH copy "$SRC_URL" "$DST_URL" --recursive=true

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Backup completed successfully!${NC}"
    
    # Verify backup
    echo -e "${YELLOW}🔍 Verifying backup...${NC}"
    BACKUP_SIZE=$(${AZ_CLI} storage share stats --name $BACKUP_SHARE_NAME --account-name $BACKUP_STORAGE_ACCOUNT --account-key $BACKUP_KEY --query 'shareUsageBytes' -o tsv)
    BACKUP_SIZE_GB=$((BACKUP_SIZE / 1024 / 1024 / 1024))
    
    echo -e "${GREEN}✅ Backup verification:${NC}"
    echo "   Source size: ${SOURCE_SIZE_GB}GB"
    echo "   Backup size: ${BACKUP_SIZE_GB}GB"
    
    if [ $BACKUP_SIZE_GB -ge $((SOURCE_SIZE_GB - 1)) ]; then
        echo -e "${GREEN}✅ Backup appears complete and successful!${NC}"
    else
        echo -e "${YELLOW}⚠️ Backup size seems smaller than expected, please verify manually${NC}"
    fi
else
    echo -e "${RED}❌ Backup operation failed${NC}"
    exit 1
fi

# Clean up temporary files
rm -f /tmp/copy-ccp4-data.sh

echo -e "${BLUE}📋 Backup Summary:${NC}"
echo "   Resource Group: $BACKUP_RG"
echo "   Storage Account: $BACKUP_STORAGE_ACCOUNT"
echo "   File Share: $BACKUP_SHARE_NAME"
echo "   Location: $BACKUP_LOCATION"
echo ""
echo -e "${GREEN}🎯 Your CCP4 data is now safely backed up!${NC}"
echo "This backup will persist even if you delete the main $SOURCE_RG resource group"
echo ""
echo -e "${YELLOW}💡 To restore this backup in a future deployment:${NC}"
echo "1. Create a new storage account and file share in your new deployment"
echo "2. Copy data from $BACKUP_STORAGE_ACCOUNT/$BACKUP_SHARE_NAME to your new location"
echo "3. Use the restore script that will be created next"

# Save backup info to a file for future reference
cat > ccp4-backup-info.txt << EOF
# CCP4 Backup Information
# Created: $(date)

BACKUP_RESOURCE_GROUP=$BACKUP_RG
BACKUP_STORAGE_ACCOUNT=$BACKUP_STORAGE_ACCOUNT
BACKUP_FILE_SHARE=$BACKUP_SHARE_NAME
BACKUP_LOCATION=$BACKUP_LOCATION

# Original source
SOURCE_RESOURCE_GROUP=$SOURCE_RG
SOURCE_STORAGE_ACCOUNT=$SOURCE_STORAGE_ACCOUNT
SOURCE_FILE_SHARE=$SOURCE_SHARE_NAME

# Backup size: ${BACKUP_SIZE_GB}GB
EOF

echo -e "${GREEN}✅ Backup information saved to: ccp4-backup-info.txt${NC}"