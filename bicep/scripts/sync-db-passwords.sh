#!/bin/bash
# Database Password Synchronization Script
# Synchronizes Key Vault secrets and PostgreSQL user passwords after infrastructure redeployment

set -e

# Load environment variables
ENV_FILE="../.env.deployment"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "Environment file $ENV_FILE not found."
  exit 1
fi

# Configuration - should match your .env.deployment file
RESOURCE_GROUP="${RESOURCE_GROUP:-ccp4i2-bicep-rg-ne}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-ne-kmayz3}"
POSTGRES_SERVER="${POSTGRES_SERVER:-ccp4i2-bicep-db-ne}"
DB_ADMIN_USER="${DB_ADMIN_USER:-ccp4i2}"
DB_USER="${DB_USER:-ccp4i2}"
DB_NAME="${DB_NAME:-postgres}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to enable Key Vault public access
enable_kv_access() {
    log_info "Enabling Key Vault public access temporarily..."
    az keyvault update --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --public-network-access Enabled > /dev/null
    
    # Add current IP to Key Vault firewall (both IPv4 and IPv6)
    CURRENT_IP_V4=$(curl -4 -s https://ifconfig.me 2>/dev/null || echo "")
    CURRENT_IP_V6=$(curl -6 -s https://ifconfig.me 2>/dev/null || echo "")
    
    if [ ! -z "$CURRENT_IP_V4" ]; then
        log_info "Adding IPv4 address ($CURRENT_IP_V4) to Key Vault firewall..."
        az keyvault network-rule add --name "$KEY_VAULT_NAME" --ip-address "$CURRENT_IP_V4" > /dev/null 2>&1 || true
    fi
    
    if [ ! -z "$CURRENT_IP_V6" ]; then
        log_info "Adding IPv6 address ($CURRENT_IP_V6) to Key Vault firewall..."
        az keyvault network-rule add --name "$KEY_VAULT_NAME" --ip-address "$CURRENT_IP_V6" > /dev/null 2>&1 || true
    fi
    
    # Wait for firewall rule to propagate
    log_info "Waiting for Key Vault firewall rule to propagate..."
    sleep 10
    
    log_success "Key Vault public access enabled"
}

# Function to disable Key Vault public access
disable_kv_access() {
    log_info "Removing IP addresses from Key Vault firewall..."
    
    CURRENT_IP_V4=$(curl -4 -s https://ifconfig.me 2>/dev/null || echo "")
    CURRENT_IP_V6=$(curl -6 -s https://ifconfig.me 2>/dev/null || echo "")
    
    if [ ! -z "$CURRENT_IP_V4" ]; then
        az keyvault network-rule remove --name "$KEY_VAULT_NAME" --ip-address "$CURRENT_IP_V4" > /dev/null 2>&1 || true
    fi
    
    if [ ! -z "$CURRENT_IP_V6" ]; then
        az keyvault network-rule remove --name "$KEY_VAULT_NAME" --ip-address "$CURRENT_IP_V6" > /dev/null 2>&1 || true
    fi
    
    log_info "Disabling Key Vault public access..."
    az keyvault update --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --public-network-access Disabled > /dev/null
    log_success "Key Vault public access disabled"
}

# Function to add temporary firewall rule for current IP
add_temp_firewall_rule() {
    CURRENT_IP=$(curl -4 -s https://ifconfig.me)
    RULE_NAME="TempAccess_$(date +%Y%m%d_%H%M%S)"

    log_info "Adding temporary firewall rule for IPv4: $CURRENT_IP"
    az postgres flexible-server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$POSTGRES_SERVER" \
        --rule-name "$RULE_NAME" \
        --start-ip-address "$CURRENT_IP" \
        --end-ip-address "$CURRENT_IP" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Firewall rule '$RULE_NAME' created successfully"
        log_info "Waiting for firewall rule to propagate..."
        sleep 10
        echo "$RULE_NAME"  # Return the rule name for cleanup
    else
        log_error "Failed to create firewall rule"
        return 1
    fi
}

# Function to remove temporary firewall rule
remove_temp_firewall_rule() {
    RULE_NAME="$1"
    log_info "Removing temporary firewall rule: $RULE_NAME"
    az postgres flexible-server firewall-rule delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$POSTGRES_SERVER" \
        --rule-name "$RULE_NAME" \
        --yes > /dev/null
    log_success "Temporary firewall rule removed"
}

# Function to get admin password from Key Vault
get_admin_password() {
    log_info "Retrieving database admin password from Key Vault..."
    ADMIN_PASSWORD=$(az keyvault secret show \
        --vault-name "$KEY_VAULT_NAME" \
        --name database-admin-password \
        --query value -o tsv)

    if [ -z "$ADMIN_PASSWORD" ]; then
        log_error "Failed to retrieve admin password from Key Vault"
        exit 1
    fi

    log_success "Admin password retrieved"
    echo "$ADMIN_PASSWORD"
}

# Function to update db-password secret in Key Vault
update_db_password_secret() {
    ADMIN_PASSWORD="$1"

    log_info "Updating db-password secret in Key Vault..."
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name db-password \
        --value "$ADMIN_PASSWORD" > /dev/null

    log_success "db-password secret updated in Key Vault"
}

# Function to update PostgreSQL user password
update_db_user_password() {
    ADMIN_PASSWORD="$1"
    TEMP_RULE="$2"

    log_info "Connecting to PostgreSQL to update user password..."

    # Use the admin password to connect and update the user password
    PGPASSWORD="$ADMIN_PASSWORD" psql \
        --host="${POSTGRES_SERVER}.postgres.database.azure.com" \
        --port=5432 \
        --username="$DB_ADMIN_USER" \
        --dbname="$DB_NAME" \
        --command="ALTER USER \"$DB_USER\" PASSWORD '$ADMIN_PASSWORD';" \
        --quiet \
        --tuples-only

    if [ $? -eq 0 ]; then
        log_success "Database user password updated successfully"
    else
        log_error "Failed to update database user password"
        exit 1
    fi
}

# Function to verify the password update
verify_password_update() {
    ADMIN_PASSWORD="$1"
    TEMP_RULE="$2"

    log_info "Verifying password update..."

    # Try to connect as the regular user with the new password
    PGPASSWORD="$ADMIN_PASSWORD" psql \
        --host="${POSTGRES_SERVER}.postgres.database.azure.com" \
        --port=5432 \
        --username="$DB_USER" \
        --dbname="$DB_NAME" \
        --command="SELECT current_user;" \
        --quiet \
        --tuples-only > /dev/null

    if [ $? -eq 0 ]; then
        log_success "Password verification successful - user can connect"
    else
        log_error "Password verification failed - user cannot connect"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting database password synchronization..."
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Key Vault: $KEY_VAULT_NAME"
    log_info "PostgreSQL Server: $POSTGRES_SERVER"
    log_info "Database User: $DB_USER"
    echo

    # Step 1: Enable Key Vault access
    enable_kv_access

    # Step 2: Get admin password
    ADMIN_PASSWORD=$(get_admin_password)

    # Step 3: Update db-password secret
    update_db_password_secret "$ADMIN_PASSWORD"

    # Step 4: Add temporary firewall rule for database access
    log_info "Setting up database firewall access..."
    TEMP_RULE=$(add_temp_firewall_rule 2>&1 | grep -v "^{" | tail -1)
    
    if [ -z "$TEMP_RULE" ]; then
        log_error "Failed to create firewall rule"
        disable_kv_access
        exit 1
    fi

    # Step 5: Update database user password
    update_db_user_password "$ADMIN_PASSWORD" "$TEMP_RULE"

    # Step 6: Verify the update
    verify_password_update "$ADMIN_PASSWORD" "$TEMP_RULE"

    # Step 7: Clean up temporary firewall rule
    remove_temp_firewall_rule "$TEMP_RULE"

    # Step 8: Disable Key Vault public access
    disable_kv_access

    echo
    log_success "Database password synchronization completed successfully!"
    log_info "All passwords are now synchronized between Key Vault and PostgreSQL"
}

# Run main function
main "$@"