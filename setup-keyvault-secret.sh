#!/bin/bash

# Script to set up Azure AD client secret in Key Vault
# Run this from a location that has access to the Key Vault (Container Apps, authorized VM, etc.)

set -e

VAULT_NAME="kv-ne-kmayz3"
SECRET_NAME="aad-client-secret"

# Check if secret value is provided as environment variable or argument
if [ -n "$AAD_CLIENT_SECRET" ]; then
    SECRET_VALUE="$AAD_CLIENT_SECRET"
elif [ -n "$1" ]; then
    SECRET_VALUE="$1"
else
    echo "Error: Azure AD client secret not provided"
    echo "Usage: $0 <secret-value>"
    echo "Or set AAD_CLIENT_SECRET environment variable"
    exit 1
fi

echo "Setting up Azure AD client secret in Key Vault..."

# Check if we can access the Key Vault
if ! az keyvault show --name "$VAULT_NAME" --query name -o tsv >/dev/null 2>&1; then
    echo "Error: Cannot access Key Vault $VAULT_NAME"
    echo "Make sure you're running this from a location with access to the Key Vault"
    exit 1
fi

# Set the secret
if az keyvault secret set --vault-name "$VAULT_NAME" --name "$SECRET_NAME" --value "$SECRET_VALUE" >/dev/null; then
    echo "✅ Successfully stored Azure AD client secret in Key Vault"
    echo "Secret name: $SECRET_NAME"
    echo "Vault: $VAULT_NAME"
else
    echo "❌ Failed to store secret in Key Vault"
    exit 1
fi

echo ""
echo "You can now safely deploy your applications using:"
echo "az deployment group create --resource-group ccp4i2-bicep-rg-ne --template-file bicep/infrastructure/applications.bicep --parameters @bicep/infrastructure/applications.parameters.json"
echo ""
echo "To run this script:"
echo "  export AAD_CLIENT_SECRET='your-secret-here'"
echo "  ./setup-keyvault-secret.sh"
echo "Or:"
echo "  ./setup-keyvault-secret.sh 'your-secret-here'"