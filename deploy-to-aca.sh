# Azure Container Apps Deployment Script
#!/bin/bash

# Configuration
RESOURCE_GROUP="ccp4i2-rg-ne"
LOCATION="northeurope"
ENVIRONMENT_NAME="ccp4i2-env-ne"
CONTAINERAPP_NAME="ccp4i2-app-ne"
ACR_NAME="ccp4i2acrne"
STORAGE_ACCOUNT_NAME="ccp4i2storagene"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting Azure Container Apps deployment for CCP4i2${NC}"

# Create resource group
echo -e "${YELLOW}📁 Creating resource group...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
echo -e "${YELLOW}🏗️ Creating Azure Container Registry...${NC}"
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic

# Wait for ACR to be ready
echo -e "${YELLOW}⏳ Waiting for ACR to be ready...${NC}"
sleep 60

# Login to ACR
echo -e "${YELLOW}🔑 Logging into Azure Container Registry...${NC}"
az acr login --name $ACR_NAME

# Build and push Docker images
echo -e "${YELLOW}🐳 Building and pushing Docker images...${NC}"

# Server build: Use ./server as context (excludes client/ and most root files)
az acr build --registry $ACR_NAME --image ccp4i2/server:latest --file Docker/Dockerfile.server ./server

# Web build: Use ./client as context (excludes server/ and node_modules/)
az acr build --registry $ACR_NAME --image ccp4i2/web:latest --file Docker/Dockerfile.web ./client

# Nginx build: Use ./Docker/nginx as context (minimal, targeted)
az acr build --registry $ACR_NAME --image ccp4i2/nginx:latest --file Docker/nginx/Dockerfile ./Docker/nginx

# Create storage account for persistent data
echo -e "${YELLOW}💾 Creating storage account...${NC}"
az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION --sku Standard_LRS --kind StorageV2

# Get storage account key
STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)

# Create file shares
echo -e "${YELLOW}📁 Creating Azure File Shares...${NC}"
az storage share create --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --name ccp4data
az storage share create --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --name staticfiles
az storage share create --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --name mediafiles

# Create Container Apps Environment
echo -e "${YELLOW}🌐 Creating Container Apps Environment...${NC}"
az containerapp env create \
  --name $ENVIRONMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION


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

# Create PostgreSQL database (Azure Database for PostgreSQL)
echo -e "${YELLOW}🗄️ Creating PostgreSQL database...${NC}"
az postgres flexible-server create \
  --name ccp4i2-db \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user ccp4i2 \
  --admin-password $(openssl rand -base64 16) \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15

# Get database connection details
DB_HOST=$(az postgres flexible-server show --resource-group $RESOURCE_GROUP --name ccp4i2-db --query fullyQualifiedDomainName -o tsv)
DB_PASSWORD=$(az postgres flexible-server show --resource-group $RESOURCE_GROUP --name ccp4i2-db --query administratorLoginPassword -o tsv)


# Create Key Vault (if not exists)
az keyvault create \
  --name ccp4i2-keyvault-ne \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

echo -e "${GREEN}✅ Infrastructure setup complete!${NC}"
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Update your environment variables with the database details"
echo "2. Run the container app creation script"
echo "3. Configure custom domain and SSL if needed"


