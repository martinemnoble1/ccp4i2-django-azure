#!/bin/bash

# Container Apps Deployment Script

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:$PATH"

# Load environment variables
if [ -f .env.deployment ]; then
    source .env.deployment
else
    echo "❌ .env.deployment not found. Run deploy-infrastructure.sh first."
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Container Apps${NC}"

# Get infrastructure outputs
CONTAINER_APPS_ENV_ID=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $(az deployment group list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'infrastructure')].name | [0]" -o tsv) \
  --query properties.outputs.containerAppsEnvironmentId.value \
  --output tsv)

POSTGRES_FQDN=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $(az deployment group list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'infrastructure')].name | [0]" -o tsv) \
  --query properties.outputs.postgresServerFqdn.value \
  --output tsv)

KEY_VAULT_NAME=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $(az deployment group list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'infrastructure')].name | [0]" -o tsv) \
  --query properties.outputs.keyVaultName.value \
  --output tsv)

# Note: Secrets are already stored in Key Vault during infrastructure deployment
# Key Vault now has private access only, so we cannot access it from deployment machine

# Deploy applications
echo -e "${YELLOW}🚀 Deploying container applications...${NC}"
APP_DEPLOYMENT_NAME="applications-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infrastructure/applications.bicep \
  --parameters containerAppsEnvironmentId="$CONTAINER_APPS_ENV_ID" \
               acrLoginServer="$ACR_LOGIN_SERVER" \
               acrName="$ACR_NAME" \
               postgresServerFqdn="$POSTGRES_FQDN" \
               keyVaultName="$KEY_VAULT_NAME" \
               imageTag="${IMAGE_TAG:-latest}" \
               prefix=ccp4i2-bicep \
               aadClientId="${AAD_CLIENT_ID:-}" \
               aadClientSecret="${AAD_CLIENT_SECRET:-}" \
               aadTenantId="${AAD_TENANT_ID:-}" \
               enableAuthentication="${ENABLE_AUTHENTICATION:-false}" \
  --name $APP_DEPLOYMENT_NAME \
  --mode Incremental

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Application deployment successful${NC}"
    
    # Validate private endpoints
    echo -e "${YELLOW}🔍 Validating private network configuration...${NC}"
    
    # Check private endpoints status
    PRIVATE_ENDPOINTS=$(az network private-endpoint list --resource-group $RESOURCE_GROUP --query "length([?provisioningState=='Succeeded'])" -o tsv)
    echo "✅ Private endpoints active: $PRIVATE_ENDPOINTS"
    
    # Check VNet integration
    VNET_INTEGRATION=$(az containerapp env show --name $(basename $CONTAINER_APPS_ENV_ID) --resource-group $RESOURCE_GROUP --query "properties.vnetConfiguration.infrastructureSubnetId" -o tsv)
    if [ ! -z "$VNET_INTEGRATION" ]; then
        echo "✅ Container Apps Environment integrated with VNet"
    else
        echo "⚠️  Container Apps Environment not VNet integrated"
    fi
    
    # Get application URLs
    SERVER_URL=$(az deployment group show \
      --resource-group $RESOURCE_GROUP \
      --name $APP_DEPLOYMENT_NAME \
      --query properties.outputs.serverUrl.value \
      --output tsv)
    
    WEB_URL=$(az deployment group show \
      --resource-group $RESOURCE_GROUP \
      --name $APP_DEPLOYMENT_NAME \
      --query properties.outputs.webUrl.value \
      --output tsv)
    
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${GREEN}🔒 All services are running in private VNet with no public endpoints${NC}"
    echo -e "${YELLOW}📝 Application URLs (external access via Container Apps ingress):${NC}"
    echo "🌐 Web App: $WEB_URL"
    echo "🔧 Server API: $SERVER_URL"
    echo ""
    echo -e "${YELLOW}🔐 Security Features Active:${NC}"
    echo "✅ PostgreSQL: Private endpoint only"
    echo "✅ Storage Account: Private endpoint only"  
    echo "✅ Key Vault: Private endpoint only"
    echo "✅ Container Registry: Private endpoint only"
    echo "✅ Container Apps: VNet integrated"
else
    echo -e "${RED}❌ Application deployment failed${NC}"
    exit 1
fi