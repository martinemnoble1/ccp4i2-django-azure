# Deploy Container App Script
#!/bin/bash

# Configuration
RESOURCE_GROUP="ccp4i2-rg"
ENVIRONMENT_NAME="ccp4i2-env"
CONTAINERAPP_NAME="ccp4i2-app"
ACR_NAME="ccp4i2acr"
STORAGE_ACCOUNT_NAME="ccp4i2storage"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🚀 Deploying CCP4i2 to Azure Container Apps${NC}"

# Get Azure subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${BLUE}📋 Using subscription: $SUBSCRIPTION_ID${NC}"

# Get database details
echo -e "${YELLOW}🗄️ Getting database connection details...${NC}"
DB_HOST=$(az postgres flexible-server show --resource-group $RESOURCE_GROUP --name ccp4i2-db --query fullyQualifiedDomainName -o tsv)
DB_PASSWORD=$(az postgres flexible-server show --resource-group $RESOURCE_GROUP --name ccp4i2-db --query administratorLoginPassword -o tsv)

if [ -z "$DB_HOST" ] || [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}❌ Database not found. Please run the infrastructure setup first.${NC}"
    exit 1
fi

# Generate Django secret key
DJANGO_SECRET_KEY=$(openssl rand -hex 32)

# Create environment file for secrets
cat > .env.deploy << EOF
AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
DB_HOST=$DB_HOST
DB_PASSWORD=$DB_PASSWORD
DJANGO_SECRET_KEY=$DJANGO_SECRET_KEY
EOF

echo -e "${YELLOW}🔐 Created deployment environment file${NC}"

# Login to ACR
echo -e "${YELLOW}🔑 Logging into Azure Container Registry...${NC}"
az acr login --name $ACR_NAME

# Deploy the container app
echo -e "${YELLOW}🚀 Deploying container app...${NC}"
az containerapp create \
  --name $CONTAINERAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT_NAME \
  --yaml azure/container-app.yml \
  --query properties.configuration.ingress.fqdn

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"

    # Get the application URL
    APP_URL=$(az containerapp show --name $CONTAINERAPP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
    echo -e "${GREEN}🌐 Application URL: https://$APP_URL${NC}"

    echo -e "${BLUE}📝 Next steps:${NC}"
    echo "1. Upload your CCP4 data to the Azure File Share"
    echo "2. Run database migrations if needed"
    echo "3. Configure custom domain (optional)"
    echo "4. Set up monitoring and logging"
else
    echo -e "${RED}❌ Deployment failed. Check the logs above for details.${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 CCP4i2 is now running on Azure Container Apps!${NC}"
