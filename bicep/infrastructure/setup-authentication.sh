#!/bin/bash
# Azure Container Apps Authentication Setup Script
# This script configures Azure AD authentication for CCP4i2 Container Apps

set -e

echo "=== Azure Container Apps Authentication Setup ==="

# Check if required parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <CLIENT_ID> <CLIENT_SECRET>"
    echo ""
    echo "To get these values:"
    echo "1. Go to Azure Portal → Microsoft Entra ID → App registrations"
    echo "2. Find your 'CCP4i2 Container Apps Authentication' app registration"
    echo "3. Copy the Application (client) ID"
    echo "4. Go to Certificates & secrets → Create new client secret → Copy the value"
    echo ""
    echo "Example:"
    echo "  $0 12345678-1234-1234-1234-123456789012 'abc123def456ghi789'"
    exit 1
fi

CLIENT_ID="$1"
CLIENT_SECRET="$2"

# Load deployment environment
if [ ! -f ".env.deployment" ]; then
    echo "Error: .env.deployment file not found"
    echo "Please run this script from the bicep directory"
    exit 1
fi

source .env.deployment

echo "Configuring authentication with:"
echo "  Client ID: ${CLIENT_ID}"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo ""

# Update applications.json with authentication parameters
echo "Updating applications.json with authentication parameters..."
cat > infrastructure/applications.json << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "imageTag": {
      "value": "${IMAGE_TAG}"
    },
    "prefix": {
      "value": "ccp4i2-bicep"
    },
    "enableAuthentication": {
      "value": true
    },
    "aadClientId": {
      "value": "${CLIENT_ID}"
    },
    "aadClientSecret": {
      "value": "${CLIENT_SECRET}"
    }
  }
}
EOF

echo "✓ Updated applications.json with authentication settings"

# Deploy the updated applications
echo ""
echo "Deploying applications with authentication enabled..."
./scripts/deploy-applications.sh

echo ""
echo "=== Authentication Setup Complete ==="
echo ""
echo "🔐 Both Container Apps now require Azure AD authentication!"
echo ""
echo "📋 Next Steps:"
echo "1. Test access to your applications:"
echo "   • Web App: https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io"
echo "   • Server App: https://ccp4i2-bicep-server.whitecliff-258bc831.northeurope.azurecontainerapps.io"
echo ""
echo "2. Configure user access restrictions:"
echo "   • Go to Azure Portal → Microsoft Entra ID → Enterprise applications"
echo "   • Find 'CCP4i2 Container Apps Authentication'"
echo "   • Go to Users and groups → Add user/group"
echo "   • Enable 'Assignment required' in Properties"
echo ""
echo "3. Users will now see Azure AD login page when accessing your apps"
echo "4. After authentication, they'll be redirected to your applications"
echo ""
echo "🔍 To troubleshoot authentication issues:"
echo "   • Check Azure Portal → Container Apps → Authentication"
echo "   • Review authentication logs in Application Insights"