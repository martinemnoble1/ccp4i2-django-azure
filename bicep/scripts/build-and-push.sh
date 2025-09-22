#!/bin/bash

# Docker Build and Push Script

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to the correct working directory (relative to bicep directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="$(dirname "$SCRIPT_DIR")"

# Try to find the source code directory
POSSIBLE_DIRS=(
    "$BICEP_DIR/../../ccp4i2-django"
    "$BICEP_DIR/../ccp4i2-django" 
    "/Users/martinnoble/ccp4i2-django"
    "/Users/martinnoble/Developer/ccp4i2-devel"
    "/Users/martinnoble/Developer/CCP4i2Docker"
)

WORKING_DIR=""
for dir in "${POSSIBLE_DIRS[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/Dockerfile" ]; then
        WORKING_DIR="$dir"
        break
    fi
    # Also check for Docker subdirectory
    if [ -d "$dir" ] && [ -d "$dir/Docker" ] && [ -f "$dir/Docker/Dockerfile.server" ]; then
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

# Temporarily enable public access for ACR builds
echo -e "${YELLOW}🌐 Temporarily enabling ACR public access for builds...${NC}"
az acr update --name $ACR_NAME --public-network-enabled true

az acr login --name $ACR_NAME

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
  ./client

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build web image${NC}"
    exit 1
fi

# Note: nginx is not used in Container Apps architecture (built-in ingress)

# Update environment file with image tag (save back to bicep directory)
echo "IMAGE_TAG=$IMAGE_TAG" >> "$BICEP_DIR/.env.deployment"

# Disable public access to ACR again
echo -e "${YELLOW}🔒 Disabling ACR public access...${NC}"
az acr update --name $ACR_NAME --public-network-enabled false

echo -e "${GREEN}✅ All images built and pushed successfully${NC}"
echo -e "${YELLOW}📝 Image tag: $IMAGE_TAG${NC}"