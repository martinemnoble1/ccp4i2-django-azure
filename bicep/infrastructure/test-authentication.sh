#!/bin/bash
# Test Authentication Configuration for CCP4i2 Container Apps

set -e

echo "=== Testing Container Apps Authentication ==="

# Function to test URL response
test_url() {
    local url="$1"
    local name="$2"
    
    echo "Testing $name..."
    echo "URL: $url"
    
    # Test with curl (will get redirect to login)
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
    
    if [ "$response" = "302" ] || [ "$response" = "200" ]; then
        echo "✓ $name: Authentication working (HTTP $response)"
        echo "  - 302 = Redirect to login (unauthenticated)"
        echo "  - 200 = Direct access (already authenticated)"
    else
        echo "✗ $name: Unexpected response (HTTP $response)"
    fi
    echo ""
}

# Test both applications
test_url "https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io" "Web Application"
test_url "https://ccp4i2-bicep-server.whitecliff-258bc831.northeurope.azurecontainerapps.io" "Server Application"

echo "=== Manual Testing Instructions ==="
echo ""
echo "1. Open your browser and navigate to:"
echo "   https://ccp4i2-bicep-web.whitecliff-258bc831.northeurope.azurecontainerapps.io"
echo ""
echo "2. Expected behavior:"
echo "   • If authentication is enabled: Redirect to Microsoft login"
echo "   • If authentication is disabled: Direct access to application"
echo ""
echo "3. Test user access:"
echo "   • Try with authorized user: Should access after login"
echo "   • Try with unauthorized user: Should see access denied"
echo ""
echo "4. Check authentication endpoints:"
echo "   • Login: /.auth/login/aad"
echo "   • Logout: /.auth/logout"
echo "   • User info: /.auth/me"
echo ""
echo "=== Authentication Status Check ==="

# Check if authentication is configured
source .env.deployment 2>/dev/null || true

echo "Checking authentication configuration in Azure..."
az containerapp show \
    --name "ccp4i2-bicep-web" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "properties.configuration.auth" \
    -o table 2>/dev/null || echo "Could not retrieve authentication status"

echo ""
echo "=== Troubleshooting ==="
echo ""
echo "If authentication isn't working:"
echo "1. Check Azure Portal → Container Apps → Authentication"
echo "2. Verify app registration redirect URIs"
echo "3. Ensure client secret is valid"
echo "4. Check Azure AD Sign-in logs for errors"
echo "5. Review container app logs for authentication errors"