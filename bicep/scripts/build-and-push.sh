#!/bin/bash

# Docker Build and Push Script

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling function
cleanup_on_error() {
    echo -e "${RED}❌ Build failed. Cleaning up...${NC}"
    if [ ! -z "$ACR_NAME" ] && [ ! -z "$ORIGINAL_DEFAULT_ACTION" ]; then
        echo -e "${YELLOW}🔧 Restoring ACR network security settings...${NC}"
        az acr update --name $ACR_NAME --default-action $ORIGINAL_DEFAULT_ACTION 2>/dev/null || true
    fi
    if [ ! -z "$ACR_NAME" ]; then
        echo -e "${YELLOW}📋 Current ACR configuration:${NC}"
        az acr show --name $ACR_NAME --query "{publicNetworkAccess: publicNetworkAccess, defaultAction: networkRuleSet.defaultAction, allowedIPs: networkRuleSet.ipRules[].ipAddressOrRange}" -o table 2>/dev/null || true
    fi
    exit 1
}

# Set up error handling (will be disabled for IP detection)
trap cleanup_on_error ERR

# Change to the correct working directory (relative to bicep directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$(dirname "$SCRIPT_DIR")"

# Try to find the source code directory
POSSIBLE_DIRS=(
    "$BICEP_DIR/../../../ccp4i2-django"
    "$BICEP_DIR/../../ccp4i2-django" 
)

WORKING_DIR=""
for dir in "${POSSIBLE_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/Docker/Dockerfile.web" ]; then
        WORKING_DIR="$dir"
        break
    fi
    if [ -d "$dir" ] && [ -f "$dir/Docker/Dockerfile.web" ]; then
        WORKING_DIR="$dir"
        break
    fi
done

echo -e "${GREEN}🐳 Building and pushing Docker images${NC}"
echo -e "${YELLOW}📁 Working directory: $WORKING_DIR${NC}"

# Check if working directory exists and has a Dockerfile
if [ -z "$WORKING_DIR" ] || [ ! -d "$WORKING_DIR" ]; then
    echo -e "${RED}❌ Working directory not found or invalid: $WORKING_DIR${NC}"
    echo -e "${YELLOW}Please ensure the source code directory exists and contains a Dockerfile${NC}"
    echo -e "${YELLOW}Searched in the following locations:${NC}"
    for dir in "${POSSIBLE_DIRS[@]}"; do
        echo "  - $dir"
    done
    exit 1
fi

cd "$WORKING_DIR"

# Load environment variables from bicep directory
if [ -f "$BICEP_DIR/.env.deployment" ]; then
    source "$BICEP_DIR/.env.deployment"
else
    echo "❌ .env.deployment not found. Run deploy-infrastructure.sh first."
    exit 1
fi

# Login to ACR
echo -e "${YELLOW}🔑 Logging into Azure Container Registry...${NC}"

# Get current public IP address
echo -e "${YELLOW}🌐 Getting current public IP address...${NC}"
set +e  # Disable exit on error for IP detection
CURRENT_IP=$(curl -s https://ipinfo.io/ip 2>/dev/null || curl -s https://api.ipify.org 2>/dev/null || echo "unknown")
set -e  # Re-enable exit on error

if [ "$CURRENT_IP" = "unknown" ]; then
    echo -e "${RED}❌ Could not determine public IP address${NC}"
    echo -e "${YELLOW}⚠️  You may need to manually add your IP to ACR firewall${NC}"
    echo -e "${YELLOW}⚠️  Continuing with ACR login attempt...${NC}"
else
    echo -e "${GREEN}📍 Current public IP: $CURRENT_IP${NC}"
    
    # Check if current IP is already in ACR firewall rules
    echo -e "${YELLOW}🔍 Checking ACR firewall rules...${NC}"
    set +e  # Disable exit on error for this check
    EXISTING_IP=$(az acr show --name $ACR_NAME --query "networkRuleSet.ipRules[?contains(ipAddressOrRange, '$CURRENT_IP')].ipAddressOrRange" -o tsv 2>/dev/null)
    set -e  # Re-enable exit on error
    
    if [ -z "$EXISTING_IP" ]; then
        echo -e "${YELLOW}➕ Adding current IP to ACR firewall...${NC}"
        az acr network-rule add --name $ACR_NAME --ip-address $CURRENT_IP
        echo -e "${GREEN}✅ IP address added to ACR firewall${NC}"
    else
        echo -e "${GREEN}✅ Current IP already allowed in ACR firewall${NC}"
    fi
fi

# Ensure public access is enabled for ACR builds
echo -e "${YELLOW}🌐 Ensuring ACR public access is enabled...${NC}"
az acr update --name $ACR_NAME --public-network-enabled true

# Temporarily disable network restrictions for Azure build agents
echo -e "${YELLOW}🔧 Temporarily allowing all access for ACR builds...${NC}"
ORIGINAL_DEFAULT_ACTION=$(az acr show --name $ACR_NAME --query "networkRuleSet.defaultAction" -o tsv)
echo -e "${YELLOW}📝 Original default action: $ORIGINAL_DEFAULT_ACTION${NC}"

# Set default action to Allow to bypass firewall during builds
az acr update --name $ACR_NAME --default-action Allow

echo -e "${YELLOW}🔐 Logging into ACR...${NC}"
set +e  # Disable exit on error for ACR login
az acr login --name $ACR_NAME
LOGIN_RESULT=$?
set -e  # Re-enable exit on error

if [ $LOGIN_RESULT -ne 0 ]; then
    echo -e "${RED}❌ ACR login failed${NC}"
    echo -e "${YELLOW}💡 Try running 'az login' to refresh authentication${NC}"
    echo -e "${YELLOW}💡 Or check if your IP is allowed in ACR firewall rules${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ACR login successful${NC}"

# Generate image tag
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)

# Build and push images
echo -e "${YELLOW}🔨 Building server image...${NC}"
az acr build \
  --registry $ACR_NAME \
  --image ccp4i2/server:$IMAGE_TAG \
  --image ccp4i2/server:latest \
  --file Docker/Dockerfile.server \
  ./server

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build server image${NC}"
    exit 1
fi

echo -e "${YELLOW}🔨 Building web image...${NC}"
az acr build \
  --registry $ACR_NAME \
  --image ccp4i2/web:$IMAGE_TAG \
  --image ccp4i2/web:latest \
  --file Docker/Dockerfile.web \
  --build-arg NEXT_PUBLIC_AAD_CLIENT_ID=$NEXT_PUBLIC_AAD_CLIENT_ID \
  --build-arg NEXT_PUBLIC_AAD_TENANT_ID=$NEXT_PUBLIC_AAD_TENANT_ID \
  ./client

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build web image${NC}"
    exit 1
fi

# Note: nginx is not used in Container Apps architecture (built-in ingress)

# Update environment file with image tag (save back to bicep directory)
echo "IMAGE_TAG=$IMAGE_TAG" >> "$BICEP_DIR/.env.deployment"

# Restore original ACR network default action
echo -e "${YELLOW}🔧 Restoring ACR network security settings...${NC}"
echo -e "${YELLOW}📝 Restoring default action to: $ORIGINAL_DEFAULT_ACTION${NC}"
az acr update --name $ACR_NAME --default-action $ORIGINAL_DEFAULT_ACTION

# Security note: Keep IP firewall rules but can optionally disable public access
echo -e "${YELLOW}🔒 Managing ACR security configuration...${NC}"
if [ "$CURRENT_IP" != "unknown" ]; then
    echo -e "${GREEN}✅ Current IP ($CURRENT_IP) will remain in firewall allow list${NC}"
else
    echo -e "${YELLOW}⚠️  Current IP could not be determined, check firewall manually if needed${NC}"
fi

# Uncomment the next line if you want to disable public access after builds
# (Note: This will block access for other IPs, keeping only the firewall allow list)
# az acr update --name $ACR_NAME --public-network-enabled false

echo -e "${GREEN}✅ All images built and pushed successfully${NC}"
echo -e "${YELLOW}📝 Image tag: $IMAGE_TAG${NC}"
echo -e "${YELLOW}🔐 Security: ACR public access enabled with IP firewall restrictions${NC}"

# Display current ACR network configuration
echo -e "${YELLOW}📋 Current ACR network configuration:${NC}"
az acr show --name $ACR_NAME --query "{publicNetworkAccess: publicNetworkAccess, defaultAction: networkRuleSet.defaultAction, allowedIPs: networkRuleSet.ipRules[].ipAddressOrRange}" -o table