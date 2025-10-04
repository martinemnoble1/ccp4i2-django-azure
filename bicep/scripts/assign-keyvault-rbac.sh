#!/bin/bash
# Assign Key Vault Secrets User role to all container apps in this environment
# Uses .env.deployment for resource group and key vault name

set -e

ENV_FILE=".env.deployment"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "Environment file $ENV_FILE not found."
  exit 1
fi

# List of container app and job names (update if needed)
APPS=("ccp4i2-bicep-server" "ccp4i2-bicep-web" "ccp4i2-bicep-worker" "ccp4i2-bicep-maintenance-job" "ccp4i2-bicep-management")
ROLE="Key Vault Secrets User"

# Get Key Vault resource ID
KV_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
if [ -z "$KV_ID" ]; then
  echo "❌ Could not find Key Vault $KEY_VAULT_NAME in $RESOURCE_GROUP"
  exit 1
fi

echo "Assigning $ROLE to container apps and jobs for Key Vault: $KEY_VAULT_NAME"
for APP in "${APPS[@]}"; do
  if [[ "$APP" == *"job"* ]]; then
    PRINCIPAL_ID=$(az containerapp job show -g "$RESOURCE_GROUP" -n "$APP" --query identity.principalId -o tsv 2>/dev/null)
  else
    PRINCIPAL_ID=$(az containerapp show -g "$RESOURCE_GROUP" -n "$APP" --query identity.principalId -o tsv 2>/dev/null)
  fi
  if [ -z "$PRINCIPAL_ID" ] || [ "$PRINCIPAL_ID" == "null" ]; then
    echo "⚠️  Could not get principalId for $APP (may not be deployed yet or does not exist)"
    continue
  fi
  echo "Assigning $ROLE to $APP ($PRINCIPAL_ID)"
  az role assignment create --assignee "$PRINCIPAL_ID" --role "$ROLE" --scope "$KV_ID" 2>/dev/null || echo "⚠️  Failed to assign role to $APP (may already have it or other issue)"
  echo "✅ $ROLE assigned to $APP"
  sleep 1
  # Sleep to avoid throttling

done

echo "All assignments attempted."
