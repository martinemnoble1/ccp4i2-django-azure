# Azure AD Authentication Setup Script
#!/bin/bash

# Configuration
RESOURCE_GROUP="ccp4i2-rg"
LOCATION="uksouth"
CONTAINERAPP_NAME="ccp4i2-app"
TENANT_ID=$(az account show --query tenantId -o tsv)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🔐 Setting up Azure AD Authentication for CCP4i2${NC}"

# Check if using existing app registration
if [ -z "$EXISTING_APP_ID" ]; then
    echo -e "${YELLOW}📝 Creating new Azure AD App Registration...${NC}"
    APP_ID=$(az ad app create \
      --display-name "CCP4i2 Application" \
      --web-redirect-uris "https://$CONTAINERAPP_NAME.azurecontainerapps.io/.auth/login/aad/callback" \
      --enable-id-token-issuance true \
      --enable-access-token-issuance false \
      --query appId -o tsv)
else
    echo -e "${YELLOW}📋 Using existing Azure AD App Registration: $EXISTING_APP_ID${NC}"
    APP_ID="$EXISTING_APP_ID"

    # Update redirect URIs for existing app
    echo -e "${YELLOW}🔄 Updating redirect URIs for existing app...${NC}"
    az ad app update \
      --id $APP_ID \
      --web-redirect-uris "https://$CONTAINERAPP_NAME.azurecontainerapps.io/.auth/login/aad/callback"
fi

echo -e "${BLUE}📋 App ID: $APP_ID${NC}"

# Create Service Principal
echo -e "${YELLOW}👤 Creating Service Principal...${NC}"
az ad sp create --id $APP_ID

# Get current user as admin
CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName -o tsv)

# Create security groups (optional - for group-based access)
echo -e "${YELLOW}👥 Creating security groups...${NC}"

# CCP4 Administrators group
ADMIN_GROUP_ID=$(az ad group create \
  --display-name "CCP4i2 Administrators" \
  --mail-nickname "ccp4i2-admins" \
  --description "Administrators with full access to CCP4i2" \
  --query id -o tsv)

# CCP4 Users group
USER_GROUP_ID=$(az ad group create \
  --display-name "CCP4i2 Users" \
  --mail-nickname "ccp4i2-users" \
  --description "Users with standard access to CCP4i2" \
  --query id -o tsv)

echo -e "${BLUE}👥 Admin Group ID: $ADMIN_GROUP_ID${NC}"
echo -e "${BLUE}👥 User Group ID: $USER_GROUP_ID${NC}"

# Add current user to admin group
echo -e "${YELLOW}👤 Adding current user to admin group...${NC}"
az ad group member add --group $ADMIN_GROUP_ID --member-id $(az ad user show --id $CURRENT_USER --query id -o tsv)

# Configure Container App Authentication
echo -e "${YELLOW}🔧 Configuring Container App authentication...${NC}"

# Create authentication configuration
cat > auth-config.json << EOF
{
  "globalValidation": {
    "unauthenticatedClientAction": "RedirectToLoginPage",
    "redirectToProvider": "aad",
    "excludedPaths": ["/.auth/login/aad/callback"]
  },
  "identityProviders": {
    "azureActiveDirectory": {
      "enabled": true,
      "registration": {
        "clientId": "$APP_ID",
        "clientSecretSettingName": "aad-client-secret",
        "openIdIssuer": "https://login.microsoftonline.com/$TENANT_ID/v2.0"
      },
      "validation": {
        "allowedAudiences": ["$APP_ID"]
      }
    }
  },
  "login": {
    "tokenStore": {
      "enabled": true,
      "tokenRefreshExtensionHours": 72,
      "fileSystem": {
        "directory": "/tmp/.tokens"
      }
    },
    "preserveUrlFragmentsForLogins": false,
    "allowedExternalRedirectUrls": ["https://$CONTAINERAPP_NAME.azurecontainerapps.io/*"],
    "cookieExpiration": {
      "convention": "FixedTime",
      "timeToExpiration": "08:00:00"
    }
  }
}
EOF

# Apply authentication to Container App
az containerapp auth set \
  --name $CONTAINERAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --config-file auth-config.json

# Create client secret
echo -e "${YELLOW}🔑 Creating client secret...${NC}"
CLIENT_SECRET=$(az ad app credential reset --id $APP_ID --query password -o tsv)

# Store client secret in Key Vault (recommended)
KEYVAULT_NAME="ccp4i2-kv"
echo -e "${YELLOW}🗝️ Creating Key Vault and storing secrets...${NC}"

az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

az keyvault secret set --vault-name $KEYVAULT_NAME --name "aad-client-secret" --value $CLIENT_SECRET

# Configure Key Vault access for Container App
echo -e "${YELLOW}🔗 Configuring Key Vault access...${NC}"
CONTAINERAPP_IDENTITY=$(az containerapp identity assign \
  --name $CONTAINERAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --system-assigned \
  --query principalId -o tsv)

az keyvault set-policy \
  --name $KEYVAULT_NAME \
  --object-id $CONTAINERAPP_IDENTITY \
  --secret-permissions get list

# Update Container App to use Key Vault secret
az containerapp secret set \
  --name $CONTAINERAPP_NAME \
  --resource-group $RESOURCE_GROUP \
  --secrets "aad-client-secret=secretref:$KEYVAULT_NAME,aad-client-secret"

echo -e "${GREEN}✅ Azure AD Authentication setup complete!${NC}"
echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo "  • App Registration ID: $APP_ID"
echo "  • Admin Group ID: $ADMIN_GROUP_ID"
echo "  • User Group ID: $USER_GROUP_ID"
echo "  • Key Vault: $KEYVAULT_NAME"
echo "  • Application URL: https://$CONTAINERAPP_NAME.azurecontainerapps.io"

echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Add users to the appropriate groups:"
echo "   az ad group member add --group $ADMIN_GROUP_ID --member-id <user-object-id>"
echo "   az ad group member add --group $USER_GROUP_ID --member-id <user-object-id>"
echo ""
echo "2. Configure group-based authorization in your Django app"
echo "3. Test authentication by visiting the application URL"
echo ""
echo "4. Optional: Configure conditional access policies in Azure AD"
echo "5. Optional: Set up multi-factor authentication requirements"

# Usage instructions for existing app registration
echo -e "${BLUE}💡 To use an existing app registration:${NC}"
echo "   export EXISTING_APP_ID='your-app-registration-id'"
echo "   ./setup-aad-auth.sh"

# Cleanup
rm auth-config.json
