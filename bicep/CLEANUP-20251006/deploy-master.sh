#!/bin/bash

# Master Deployment Script

# Ensure Homebrew paths are available
export PATH="/opt/homebrew/bin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 CCP4i2 Azure Container Apps Deployment${NC}"
echo -e "${BLUE}🔒 Private VNet Architecture with Enterprise Security${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "${YELLOW}📋 Deployment Overview:${NC}"
echo "• Infrastructure: Private VNet with dedicated subnets"
echo "• Security: Private endpoints for all services"
echo "• Database: PostgreSQL with private access only"
echo "• Storage: Private endpoint access only"
echo "• Key Vault: Private endpoint with RBAC"
echo "• Registry: Private endpoint for image pulls"
echo ""

# Step 1: Deploy Infrastructure
echo -e "${YELLOW}📋 Step 1: Deploying Infrastructure...${NC}"
./scripts/deploy-infrastructure.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Infrastructure deployment failed${NC}"
    exit 1
fi

# Step 2: Build and Push Images
echo -e "${YELLOW}📋 Step 2: Building and pushing Docker images...${NC}"
./scripts/build-and-push.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Image build/push failed${NC}"
    exit 1
fi

# Step 3: Deploy Applications
echo -e "${YELLOW}📋 Step 3: Deploying Container Apps...${NC}"
./scripts/deploy-applications.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Application deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}🎉 Full deployment completed successfully!${NC}"
echo -e "${GREEN}🔒 Enterprise-grade security architecture is now active${NC}"
echo ""
echo -e "${YELLOW}💡 Next Steps:${NC}"
echo "• To update applications: ./scripts/build-and-push.sh && ./scripts/deploy-applications.sh"
echo "• Monitor with: az containerapp logs show --name ccp4i2-server --resource-group ccp4i2-bicep-rg-ne"
echo "• See PRIVATE_VNET_DEPLOYMENT.md for detailed architecture information"
