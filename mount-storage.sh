#!/bin/bash

# Shell script to generate and apply Azure Container Apps volume mount YAML
# Specializes the boilerplate template using environment variables
# Handles Azure File storage management (delete/recreate for immutable properties)

# Configuration - Set these as environment variables or defaults
CONTAINER_NAME="${CONTAINER_NAME:-ccp4i2-server}"
IMAGE="${IMAGE:-ccp4i2acrne.azurecr.io/ccp4i2/server:latest}"
VOLUME_NAME="${VOLUME_NAME:-ccp4-data}"
MOUNT_PATH="${MOUNT_PATH:-/mnt/ccp4data}"
ENVIRONMENT_STORAGE_NAME="${ENVIRONMENT_STORAGE_NAME:-ccp4data-mount}"
RESOURCE_GROUP="${RESOURCE_GROUP:-ccp4i2-rg-ne}"
CONTAINER_APP_NAME="${CONTAINER_APP_NAME:-ccp4i2-server}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-ccp4i2-env-ne}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-ccp4i2storagene}"
STORAGE_SHARE_NAME="${STORAGE_SHARE_NAME:-ccp4data}"
ACCESS_MODE="${ACCESS_MODE:-ReadWrite}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to validate required variables
validate_variables() {
    if [ -z "$ENVIRONMENT_STORAGE_NAME" ] || [ -z "$STORAGE_ACCOUNT_NAME" ] || [ -z "$STORAGE_SHARE_NAME" ]; then
        echo -e "${RED}ERROR: ENVIRONMENT_STORAGE_NAME, STORAGE_ACCOUNT_NAME, and STORAGE_SHARE_NAME are required${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Variables validated${NC}"
}

# Function to delete environment storage
delete_environment_storage() {
    echo -e "${YELLOW}🗑️  Checking if environment storage exists...${NC}"
    
    if az containerapp env storage show \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-name "$ENVIRONMENT_STORAGE_NAME" &>/dev/null; then
        
        echo -e "${YELLOW}🗑️  Deleting existing environment storage...${NC}"
        if az containerapp env storage remove \
            --name "$ENVIRONMENT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-name "$ENVIRONMENT_STORAGE_NAME" \
            --yes; then
            echo -e "${GREEN}✅ Environment storage deleted${NC}"
        else
            echo -e "${RED}❌ Failed to delete environment storage${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}ℹ️  Environment storage does not exist, skipping deletion${NC}"
    fi
}

# Function to create environment storage
create_environment_storage() {
    echo -e "${YELLOW}📦 Creating new environment storage...${NC}"
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" -o tsv)
    
    if [ -z "$STORAGE_KEY" ]; then
        echo -e "${RED}❌ Failed to retrieve storage account key${NC}"
        return 1
    fi
    
    if az containerapp env storage set \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-name "$ENVIRONMENT_STORAGE_NAME" \
        --azure-file-account-name "$STORAGE_ACCOUNT_NAME" \
        --azure-file-account-key "$STORAGE_KEY" \
        --azure-file-share-name "$STORAGE_SHARE_NAME" \
        --access-mode "$ACCESS_MODE"; then
        echo -e "${GREEN}✅ Environment storage created${NC}"
    else
        echo -e "${RED}❌ Failed to create environment storage${NC}"
        return 1
    fi
}

# Function to handle storage update (delete and recreate if needed)
update_storage_if_needed() {
    echo -e "${YELLOW}🔄 Checking if storage update is needed...${NC}"
    
    # Check if storage exists with different properties
    if az containerapp env storage show \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-name "$ENVIRONMENT_STORAGE_NAME" &>/dev/null; then
        
        echo -e "${YELLOW}⚠️  Storage exists. To change share/account name, it must be deleted and recreated.${NC}"
        read -p "Do you want to delete and recreate the storage? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if ! delete_environment_storage; then
                return 1
            fi
            if ! create_environment_storage; then
                return 1
            fi
        else
            echo -e "${YELLOW}ℹ️  Skipping storage update${NC}"
        fi
    else
        echo -e "${GREEN}ℹ️  Storage does not exist, creating new...${NC}"
        if ! create_environment_storage; then
            return 1
        fi
    fi
}

# Function to generate YAML from boilerplate template
generate_yaml() {
    local yaml_file="temp-volume-mount.yml"
    
    cat <<EOF > "$yaml_file"
location: northeurope
properties:
  template:
    containers:
    - name: $CONTAINER_NAME
      image: $IMAGE
      volumeMounts:
      - volumeName: $VOLUME_NAME
        mountPath: $MOUNT_PATH
    volumes:
    - name: $VOLUME_NAME
      storageName: $ENVIRONMENT_STORAGE_NAME
EOF
    
    echo "$yaml_file"
}

# Function to apply YAML using Azure CLI
apply_yaml() {
    local yaml_file="$1"
    echo "In apply_yaml with file: $yaml_file"

    if [ ! -f "$yaml_file" ]; then
        echo -e "${RED}❌ YAML file $yaml_file does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🚀 Applying volume mount configuration...${NC}"
    
    if az containerapp update \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yaml "$yaml_file"; then
        echo -e "${GREEN}✅ Volume mount applied successfully${NC}"
    else
        echo -e "${RED}❌ Failed to apply volume mount${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${GREEN}🚀 Starting volume mount configuration${NC}"
    
    validate_variables
    
    if ! update_storage_if_needed; then
        echo -e "${RED}❌ Storage management failed${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}🔧 Generating and applying volume mount configuration...${NC}"
    local yaml_file
    yaml_file=$(generate_yaml)
    echo -e "${GREEN}✅ YAML generated: $yaml_file${NC}"
    
    if apply_yaml "$yaml_file"; then
        echo -e "${GREEN}🎉 Volume mount configuration complete!${NC}"
        echo -e "${YELLOW}📝 Next steps:${NC}"
        echo "1. Check container app logs for volume mount confirmation"
        echo "2. Verify CCP4 data is accessible at $MOUNT_PATH"
    else
        echo -e "${RED}❌ Configuration failed${NC}"
        exit 1
    fi
    
    # Cleanup
    rm -f "$yaml_file"
}

# Run main function
main "$@"
