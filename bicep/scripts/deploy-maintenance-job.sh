#!/bin/bash

# Deploy Maintenance Job for CCP4i2
# This script deploys the maintenance job for long-running tasks like tar extraction

set -e

# Load environment variables
if [ -f ".env.deployment" ]; then
    source ".env.deployment"
else
    echo "Error: .env.deployment file not found"
    exit 1
fi

# Set default values
IMAGE_TAG_SERVER="${IMAGE_TAG_SERVER:-latest}"
RESOURCE_GROUP="${RESOURCE_GROUP:-ccp4i2-bicep-rg-ne}"

# Get Container Apps Environment ID
CONTAINER_APPS_ENV_ID=$(az containerapp env show \
    --name ccp4i2-bicep-env-ne \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

if [ -z "$CONTAINER_APPS_ENV_ID" ]; then
    echo "Error: Could not find Container Apps Environment"
    exit 1
fi

# Get PostgreSQL FQDN
POSTGRES_FQDN=$(az postgres flexible-server show \
    --name ccp4i2-bicep-db-ne \
    --resource-group $RESOURCE_GROUP \
    --query fullyQualifiedDomainName -o tsv)

if [ -z "$POSTGRES_FQDN" ]; then
    echo "Error: Could not find PostgreSQL server"
    exit 1
fi

echo "Deploying maintenance job..."
echo "Resource Group: $RESOURCE_GROUP"
echo "Container Apps Environment: $CONTAINER_APPS_ENV_ID"
echo "ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
echo "PostgreSQL: $POSTGRES_FQDN"
echo "Key Vault: $KEY_VAULT_NAME"
echo "Server Image Tag: $IMAGE_TAG_SERVER"

# Deploy the maintenance job
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file infrastructure/maintenance-job.bicep \
    --parameters \
        containerAppsEnvironmentId="$CONTAINER_APPS_ENV_ID" \
        acrLoginServer="$ACR_LOGIN_SERVER" \
        acrName="$ACR_NAME" \
        postgresServerFqdn="$POSTGRES_FQDN" \
        keyVaultName="$KEY_VAULT_NAME" \
        imageTagServer="$IMAGE_TAG_SERVER" \
        prefix=ccp4i2-bicep

echo "Maintenance job deployed successfully!"

echo ""
echo "To run the tar extraction job:"
echo "az containerapp job start --name ccp4i2-bicep-maintenance-job --resource-group $RESOURCE_GROUP"
echo ""
echo "To check job status:"
echo "az containerapp job execution list --name ccp4i2-bicep-maintenance-job --resource-group $RESOURCE_GROUP --output table"
echo ""
echo "To view job logs:"
echo "az containerapp job execution logs show --name ccp4i2-bicep-maintenance-job --resource-group $RESOURCE_GROUP --execution-name <execution-name>"