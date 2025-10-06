#!/bin/bash
set -e

# Restore Management Container to Normal State
# Run this after CCP4 extraction completes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Restoring Management Container${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

# Load environment
if [ -f .env.deployment ]; then
    source .env.deployment
fi

RESOURCE_GROUP="ccp4i2-bicep-rg-ne"
PREFIX="ccp4i2-bicep"
MANAGEMENT_APP="${PREFIX}-management"

echo -e "\n${YELLOW}Restoring management container to interactive mode...${NC}"

az containerapp update \
    --name "$MANAGEMENT_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --command '/bin/bash' \
    --args '-c' 'export PYTHONPATH="/mnt/ccp4data/py-packages:$PYTHONPATH" && echo "Management container ready for interactive access" && tail -f /dev/null' \
    --output none

echo -e "${GREEN}✓${NC} Management container restored to normal state"
echo -e "\n${BLUE}You can now use it with:${NC}"
echo -e "  az containerapp exec --name $MANAGEMENT_APP --resource-group $RESOURCE_GROUP --command bash"
