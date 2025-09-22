#!/bin/bash

# Azure Container Apps Creation Script

# Configuration
RESOURCE_GROUP="ccp4i2-rg-ne"
LOCATION="northeurope"
ENVIRONMENT_NAME="ccp4i2-env-ne"
ACR_NAME="ccp4i2acrne"
STORAGE_ACCOUNT_NAME="ccp4i2storagene"
DB_SERVER_NAME="ccp4i2-rbac-db"
SERVER_CPU=2.0
SERVER_MEMORY=4.0Gi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Creating Azure Container Apps for CCP4i2${NC}"

# Get database connection details
DB_HOST=$(az postgres flexible-server show --resource-group $RESOURCE_GROUP --name $DB_SERVER_NAME --query fullyQualifiedDomainName -o tsv)

# Retrieve database password from Key Vault
echo -e "${YELLOW}🔐 Retrieving database password from Key Vault...${NC}"
DB_PASSWORD=$(az keyvault secret show \
  --vault-name ccp4i2-keyvault-ne \
  --name database-admin-password \
  --query value -o tsv)

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}❌ Failed to retrieve database password from Key Vault${NC}"
    exit 1
fi


# Retrieve Django secret key from Key Vault
echo -e "${YELLOW}🔐 Retrieving Django secret key from Key Vault...${NC}"
DJANGO_SECRET_KEY=$(az keyvault secret show \
  --vault-name ccp4i2-keyvault-ne \
  --name django-secret-key \
  --query value -o tsv)

if [ -z "$DJANGO_SECRET_KEY" ]; then
    echo -e "${YELLOW}⚠️  Django secret key not found in Key Vault, generating new one...${NC}"
    DJANGO_SECRET_KEY=$(openssl rand -base64 32)
    # Store it in Key Vault for future use
    az keyvault secret set \
      --vault-name ccp4i2-keyvault-ne \
      --name django-secret-key \
      --value "$DJANGO_SECRET_KEY" \
      --output none
fi

# Enable ACR admin user
az acr update -n $ACR_NAME --admin-enabled true

# Get ACR credentials
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query 'passwords[0].value' -o tsv)

# Delete existing container app if it exists
echo -e "${YELLOW}🗑️ Cleaning up existing server container app...${NC}"
az containerapp delete \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --yes || true

# Wait for cleanup
sleep 5

# Create server container app with all configuration at once
echo -e "${YELLOW}🐳 Creating server container app with complete configuration...${NC}"
az containerapp create \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --image "$ACR_NAME.azurecr.io/ccp4i2/server:latest" \
  --registry-server "$ACR_NAME.azurecr.io" \
  --registry-username "$ACR_NAME" \
  --registry-password "$ACR_PASSWORD" \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 10 \
  --cpu $SERVER_CPU \
  --memory $SERVER_MEMORY \
  --secrets "db-password=$DB_PASSWORD" "secret-key=$DJANGO_SECRET_KEY" \
  --env-vars \
    "DJANGO_SETTINGS_MODULE=ccp4x.config.settings" \
    "DB_HOST=$DB_HOST" \
    "DB_USER=ccp4i2" \
    "DB_NAME=postgres" \
    "DB_PASSWORD=secretref:db-password" \
    "SECRET_KEY=secretref:secret-key" \
    "CCP4_DATA_PATH=/mnt/ccp4data" \
    "CCP4I2_PROJECTS_DIR=/mnt/ccp4data/ccp4i2-projects"

# Mount storage for server container
echo -e "${YELLOW}🔗 Mounting storage for server...${NC}"
export CONTAINER_NAME=ccp4i2-server
export IMAGE="$ACR_NAME.azurecr.io/ccp4i2/server:latest"
export CONTAINER_APP_NAME=ccp4i2-server
echo "N" | "$(dirname "$0")/mount-storage.sh"

# RE-SET cpu and memory (in case they were overwritten)
echo -e "${YELLOW}🔐 Re-setting cpu and memory after storage mounting...${NC}"
az containerapp update \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --cpu $SERVER_CPU \
  --memory $SERVER_MEMORY


# RE-SET SECRETS AFTER STORAGE MOUNTING (in case they were overwritten)
echo -e "${YELLOW}🔐 Re-setting secrets after storage mounting...${NC}"
az containerapp secret set \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --secrets \
    "db-password=$DB_PASSWORD" \
    "secret-key=$DJANGO_SECRET_KEY"

# RE-SET ENVIRONMENT VARIABLES AFTER STORAGE MOUNTING (in case they were overwritten)
echo -e "${YELLOW}🔧 Re-setting environment variables after storage mounting...${NC}"
az containerapp update \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    "DJANGO_SETTINGS_MODULE=ccp4x.config.settings" \
    "DB_HOST=$DB_HOST" \
    "DB_USER=ccp4i2" \
    "DB_NAME=postgres" \
    "DB_PASSWORD=secretref:db-password" \
    "SECRET_KEY=secretref:secret-key" \
    "CCP4_DATA_PATH=/mnt/ccp4data" \
    "CCP4I2_PROJECTS_DIR=/mnt/ccp4data/ccp4i2-projects"

# FORCE CONTAINER RESTART TO ENSURE NEW CONFIGURATION TAKES EFFECT
echo -e "${YELLOW}🔄 Forcing container restart to apply configuration...${NC}"
az containerapp revision restart \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --revision $(az containerapp revision list --name ccp4i2-server --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv) || true

# Wait for container to restart and check logs
echo -e "${YELLOW}⏳ Waiting for container to restart with new configuration...${NC}"
sleep 30

# Get the server URL first, then set web environment variables
echo -e "${YELLOW}🔗 Getting server URL and configuring web app...${NC}"
SERVER_URL=$(az containerapp show --name ccp4i2-server --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

echo -e "${YELLOW}📋 Checking logs for database connection...${NC}"
az containerapp logs show \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --since "2m" | grep -E "(connection|database|error|success|SSL)" || echo "No database logs found yet"

# Create web container app (simplified for now)
echo -e "${YELLOW}🌐 Creating web container app...${NC}"
az containerapp create \
  --name ccp4i2-web \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --image "$ACR_NAME.azurecr.io/ccp4i2/web:latest" \
  --registry-server "$ACR_NAME.azurecr.io" \
  --registry-username "$ACR_NAME" \
  --registry-password "$ACR_PASSWORD" \
  --target-port 3000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 5 \
  --env-vars \
    "BACKEND_URL=https://$SERVER_URL" \
  --cpu 0.5 \
  --memory 1.0Gi

# Get URLs
WEB_URL=$(az containerapp show --name ccp4i2-web --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
SERVER_URL=$(az containerapp show --name ccp4i2-server --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

echo -e "${GREEN}✅ Container Apps created successfully!${NC}"
echo -e "${YELLOW}📝 Application URLs:${NC}"
echo "Web App: https://$WEB_URL"
echo "Server API: https://$SERVER_URL"

# Final verification
echo -e "${YELLOW}🧪 Final verification - checking if environment variables are properly set...${NC}"
sleep 10

az containerapp logs show \
  --name ccp4i2-server \
  --resource-group $RESOURCE_GROUP \
  --since "1m" | grep -E "(ENTRYPOINT DEBUG|STARTUP SCRIPT DEBUG|DB_HOST|SECRET_KEY)" || echo "No debug output found yet"

echo -e "${YELLOW}🔍 Current firewall rules:${NC}"
az postgres flexible-server firewall-rule list \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --output table