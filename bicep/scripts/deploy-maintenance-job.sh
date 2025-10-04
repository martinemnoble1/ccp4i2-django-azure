
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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Container Apps${NC}"

# Function to check and register resource providers
check_resource_providers() {
    echo -e "${BLUE}🔍 Checking required resource providers...${NC}"

    # List of required providers for this deployment
    REQUIRED_PROVIDERS=("Microsoft.ServiceBus" "Microsoft.KeyVault" "Microsoft.DBforPostgreSQL" "Microsoft.ContainerRegistry" "Microsoft.App")

    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        REGISTRATION_STATE=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null)

        if [ "$REGISTRATION_STATE" != "Registered" ]; then
            echo -e "${YELLOW}📝 Registering $provider resource provider...${NC}"
            az provider register --namespace "$provider"
            echo -e "${GREEN}✅ $provider registered${NC}"
        else
            echo -e "${GREEN}✅ $provider already registered${NC}"
        fi
    done
}

# Function to get the most recent successful infrastructure deployment
get_successful_infrastructure_deployment() {
    echo -e "${BLUE}🔍 Finding successful infrastructure deployment...${NC}"

    # Get the most recent successful infrastructure deployment
    local deployment_name=$(az deployment group list \
        --resource-group $RESOURCE_GROUP \
        --query "[?properties.provisioningState=='Succeeded' && contains(name, 'infrastructure')].name" \
        -o tsv | sort | tail -1)

    if [ -z "$deployment_name" ]; then
        echo -e "${RED}❌ No successful infrastructure deployment found${NC}"
        echo -e "${YELLOW}💡 Run deploy-infrastructure.sh first${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Using infrastructure deployment: $deployment_name${NC}"
    # Set global variable
    INFRA_DEPLOYMENT="$deployment_name"
}

# Check resource providers first
check_resource_providers

# Get successful infrastructure deployment
if ! get_successful_infrastructure_deployment; then
    exit 1
fi

# Get infrastructure outputs from the successful deployment
echo -e "${BLUE}📋 Getting infrastructure outputs...${NC}"

CONTAINER_APPS_ENV_ID=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $INFRA_DEPLOYMENT \
  --query properties.outputs.containerAppsEnvironmentId.value \
  --output tsv)

if [ -z "$CONTAINER_APPS_ENV_ID" ]; then
    echo -e "${RED}❌ Could not get Container Apps Environment ID from deployment $INFRA_DEPLOYMENT${NC}"
    exit 1
fi

POSTGRES_FQDN=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $INFRA_DEPLOYMENT \
  --query properties.outputs.postgresServerFqdn.value \
  --output tsv)

if [ -z "$POSTGRES_FQDN" ]; then
    echo -e "${RED}❌ Could not get PostgreSQL FQDN from deployment $INFRA_DEPLOYMENT${NC}"
    exit 1
fi

KEY_VAULT_NAME=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $INFRA_DEPLOYMENT \
  --query properties.outputs.keyVaultName.value \
  --output tsv)

if [ -z "$KEY_VAULT_NAME" ]; then
    echo -e "${RED}❌ Could not get Key Vault name from deployment $INFRA_DEPLOYMENT${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Infrastructure outputs retrieved${NC}"

# Note: Secrets are already stored in Key Vault during infrastructure deployment
# Key Vault now has private access only, so we cannot access it from deployment machine

# Get shared identity outputs
CONTAINER_APPS_IDENTITY_ID=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $INFRA_DEPLOYMENT \
  --query properties.outputs.containerAppsIdentityId.value \
  --output tsv)

CONTAINER_APPS_IDENTITY_PRINCIPAL_ID=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $INFRA_DEPLOYMENT \
  --query properties.outputs.containerAppsIdentityPrincipalId.value \
  --output tsv)

if [ -z "$CONTAINER_APPS_IDENTITY_ID" ] || [ -z "$CONTAINER_APPS_IDENTITY_PRINCIPAL_ID" ]; then
    echo -e "${RED}❌ Could not get Container Apps Identity from deployment $INFRA_DEPLOYMENT${NC}"
    exit 1
fi

# Deploy applications
echo -e "${YELLOW}🚀 Deploying container applications...${NC}"
MAINTENANCE_JOB_DEPLOYMENT_NAME="maintenance-job-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file infrastructure/maintenance-job.bicep \
    --parameters \
        containerAppsEnvironmentId="$CONTAINER_APPS_ENV_ID" \
        acrLoginServer="$ACR_LOGIN_SERVER" \
        acrName="$ACR_NAME" \
        postgresServerFqdn="$POSTGRES_FQDN" \
        keyVaultName="$KEY_VAULT_NAME" \
        imageTagServer="${IMAGE_TAG_SERVER:-latest}" \
        prefix=ccp4i2-bicep \
        containerAppsIdentityId="$CONTAINER_APPS_IDENTITY_ID" \
  --name $MAINTENANCE_JOB_DEPLOYMENT_NAME \
  --mode Incremental

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Job deployment successful${NC}"
    
    # Grant Key Vault access to the shared identity
    echo -e "${YELLOW}🔐 Granting Key Vault access to shared identity...${NC}"
    az keyvault set-policy \
        --name "$KEY_VAULT_NAME" \
        --object-id "$CONTAINER_APPS_IDENTITY_PRINCIPAL_ID" \
        --secret-permissions get list \
        2>/dev/null || echo -e "${YELLOW}⚠️  Key Vault uses RBAC or policy already exists${NC}"
    
    echo -e "${GREEN}🎉 Maintenance job deployed successfully!${NC}"
    echo -e ""
    echo -e "${YELLOW}To run the tar extraction job:${NC}"
    echo -e "az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group $RESOURCE_GROUP"
    echo -e ""
    echo -e "${YELLOW}To check job status:${NC}"
    echo -e "az containerapp job execution list --name ccp4i2-bicep-maintenance-job --resource-group $RESOURCE_GROUP --output table"
else
    echo -e "${RED}❌ Job deployment failed${NC}"
    exit 1
fi