#!/bin/bash

RESOURCE_GROUP="ccp4i2-rg-ne"
LOCATION="northeurope"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get your current user's object ID
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Assign Key Vault Secrets Officer role to read/write secrets
echo -e "${YELLOW}🔐 Assigning Key Vault Secrets Officer role...${NC}"
az role assignment create \
  --assignee $CURRENT_USER_ID \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/ccp4i2-keyvault-ne"

sleep 10  # Wait for role assignment to propagate

# Generate and store database password in Key Vault
echo -e "${YELLOW}🔑 Generating and storing database password...${NC}"
DB_PASSWORD=$(openssl rand -base64 16)
az keyvault secret set \
  --vault-name ccp4i2-keyvault-ne \
  --name database-admin-password \
  --value "$DB_PASSWORD"

# Store Django secret key as well
echo -e "${YELLOW}🔑 Generating and storing Django secret key...${NC}"
DJANGO_SECRET=$(openssl rand -base64 32)
az keyvault secret set \
  --vault-name ccp4i2-keyvault-ne \
  --name django-secret-key \
  --value "$DJANGO_SECRET"

# Create PostgreSQL database with stored password
echo -e "${YELLOW}🗄️ Creating PostgreSQL database...${NC}"
az postgres flexible-server create \
  --name ccp4i2-rbac-db \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user ccp4i2 \
  --admin-password "$DB_PASSWORD" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 15


echo -e "${GREEN}✅ Database password retrieved successfully${NC}"

# CONFIGURE DATABASE CONNECTIVITY FIRST
echo -e "${YELLOW}🔧 Configuring database connectivity...${NC}"

# Add Azure services firewall rule (allows Container Apps)
echo -e "${YELLOW}☁️ Adding Azure services firewall rule...${NC}"
az postgres flexible-server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --rule-name "AllowAllAzureServicesAndResourcesWithinAzureIps" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0 || echo "Azure services rule may already exist"

# Add current IP for management
CURRENT_IP=$(curl -s ipinfo.io/ip)
echo -e "${YELLOW}🌐 Adding firewall rule for current IP: $CURRENT_IP${NC}"
az postgres flexible-server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --rule-name "allow-current-ip" \
  --start-ip-address $CURRENT_IP \
  --end-ip-address $CURRENT_IP || echo "Current IP rule may already exist"

# Ensure public network access is enabled
echo -e "${YELLOW}🌍 Ensuring public network access is enabled...${NC}"
az postgres flexible-server update \
  --resource-group $RESOURCE_GROUP \
  --name $DB_SERVER_NAME \
  --public-network-access Enabled

# CREATE DATABASE USER IF NOT EXISTS (WITH SSL)
echo -e "${YELLOW}👤 Creating database user 'ccp4i2' if not exists...${NC}"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "postgres" -d "postgres" -p "5432" --set=sslmode=require -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'ccp4i2') THEN
        CREATE USER ccp4i2 WITH PASSWORD '$DB_PASSWORD';
        GRANT CONNECT ON DATABASE postgres TO ccp4i2;
        GRANT USAGE ON SCHEMA public TO ccp4i2;
        GRANT CREATE ON SCHEMA public TO ccp4i2;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ccp4i2;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ccp4i2;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ccp4i2;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ccp4i2;
        RAISE NOTICE 'User ccp4i2 created successfully';
    ELSE
        RAISE NOTICE 'User ccp4i2 already exists';
        -- Update password in case it changed
        ALTER USER ccp4i2 WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;
" 2>/dev/null || echo "User creation completed (may already exist)"

# TEST DATABASE CONNECTION (WITH SSL)
echo -e "${YELLOW}🧪 Testing database connection with SSL...${NC}"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "ccp4i2" -d "postgres" -p "5432" --set=sslmode=require -c "SELECT 1 as connection_test, current_user, current_database();" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Database connection test successful${NC}"
else
    echo -e "${RED}❌ Database connection test failed${NC}"
    echo -e "${YELLOW}🔍 Checking current firewall rules...${NC}"
    az postgres flexible-server firewall-rule list \
      --resource-group $RESOURCE_GROUP \
      --name $DB_SERVER_NAME \
      --output table
    
    echo -e "${YELLOW}🔍 Testing connection as admin user...${NC}"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "postgres" -d "postgres" -p "5432" --set=sslmode=require -c "SELECT current_user;" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}⚠️ Admin connection works, but ccp4i2 user connection fails. Recreating user...${NC}"
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "postgres" -d "postgres" -p "5432" --set=sslmode=require -c "
        DROP USER IF EXISTS ccp4i2;
        CREATE USER ccp4i2 WITH PASSWORD '$DB_PASSWORD';
        GRANT CONNECT ON DATABASE postgres TO ccp4i2;
        GRANT USAGE ON SCHEMA public TO ccp4i2;
        GRANT CREATE ON SCHEMA public TO ccp4i2;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ccp4i2;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ccp4i2;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ccp4i2;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ccp4i2;
        " 2>/dev/null
        
        # Test again
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "ccp4i2" -d "postgres" -p "5432" --set=sslmode=require -c "SELECT 1 as connection_test;" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Database connection test successful after user recreation${NC}"
        else
            echo -e "${RED}❌ Database connection still fails after user recreation${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Even admin connection fails. Check firewall rules and server status.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Database password stored in Key Vault: ccp4i2-keyvault-ne/database-admin-password${NC}"
echo -e "${GREEN}✅ Django secret key stored in Key Vault: ccp4i2-keyvault-ne/django-secret-key${NC}"
echo -e "${GREEN}✅ PostgreSQL database created: ccp4i2-db${NC}"