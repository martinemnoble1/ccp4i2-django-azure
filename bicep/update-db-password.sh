#!/bin/bash
# Script to update PostgreSQL user password to match Key Vault/env file

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔐 PostgreSQL User Password Update Script${NC}"
echo "=========================================="

# Get current IP for firewall rule
CURRENT_IP=$(curl -4 -s ifconfig.me | tr -d '%')
echo -e "${YELLOW}Current IP: $CURRENT_IP${NC}"

# Load environment variables
if [ -f ".env.deployment" ]; then
    source .env.deployment
    echo -e "${GREEN}✅ Loaded .env.deployment${NC}"
else
    echo -e "${RED}❌ .env.deployment file not found${NC}"
    exit 1
fi

# Get password from Key Vault
echo -e "${YELLOW}🔑 Retrieving password from Key Vault...${NC}"
KV_PASSWORD=$(az keyvault secret show --vault-name kv-ne-kmayz3 --name database-admin-password --query "value" --output tsv)

if [ -z "$KV_PASSWORD" ]; then
    echo -e "${RED}❌ Failed to retrieve password from Key Vault${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Password retrieved from Key Vault${NC}"
echo "Password length: ${#KV_PASSWORD} characters"

# Add temporary firewall rule
echo -e "${YELLOW}🔥 Adding temporary firewall rule...${NC}"
RULE_NAME="TempUpdate_$(date +%Y%m%d_%H%M%S)"

az postgres flexible-server firewall-rule create \
  --name ccp4i2-bicep-db-ne \
  --resource-group ccp4i2-bicep-rg-ne \
  --rule-name "$RULE_NAME" \
  --start-ip-address $CURRENT_IP \
  --end-ip-address $CURRENT_IP > /dev/null

echo -e "${GREEN}✅ Temporary firewall rule added: $RULE_NAME${NC}"

# Wait for firewall rule to propagate
echo -e "${YELLOW}⏳ Waiting for firewall rule to take effect...${NC}"
sleep 15

# Test connection
echo -e "${YELLOW}🔍 Testing connection to PostgreSQL...${NC}"
if PGPASSWORD="$KV_PASSWORD" psql "sslmode=require host=ccp4i2-bicep-db-ne.postgres.database.azure.com user=ccp4i2 dbname=postgres" -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Connection successful - password is already correct!${NC}"
    UPDATE_NEEDED=false
else
    echo -e "${YELLOW}⚠️ Connection failed - password update needed${NC}"
    UPDATE_NEEDED=true
fi

# Update password if needed
if [ "$UPDATE_NEEDED" = true ]; then
    echo -e "${YELLOW}🔄 Updating PostgreSQL user password...${NC}"
    
    # Try to connect as admin user to update the password
    PGPASSWORD="$KV_PASSWORD" psql "sslmode=require host=ccp4i2-bicep-db-ne.postgres.database.azure.com user=ccp4i2 dbname=postgres" -c "ALTER USER ccp4i2 PASSWORD '$KV_PASSWORD';" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Password updated successfully${NC}"
    else
        echo -e "${RED}❌ Failed to update password${NC}"
        echo "This might happen if the current password is different."
        echo "You may need to use the admin account or reset the password via Azure CLI."
    fi
fi

# Clean up firewall rule
echo -e "${YELLOW}🧹 Removing temporary firewall rule...${NC}"
az postgres flexible-server firewall-rule delete \
  --name ccp4i2-bicep-db-ne \
  --resource-group ccp4i2-bicep-rg-ne \
  --rule-name "$RULE_NAME" \
  --yes > /dev/null

echo -e "${GREEN}✅ Temporary firewall rule removed${NC}"

echo -e "${GREEN}🎉 Script completed successfully!${NC}"
echo -e "${YELLOW}Note: Your database password should now match the Key Vault value.${NC}"