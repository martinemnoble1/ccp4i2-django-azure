#!/bin/bash

# Script to generate management-vm.bicepparam from Azure resources in a resource group
# Usage: ./generate-vm-params.sh <resource-group-name>

RG_NAME=$1

if [ -z "$RG_NAME" ]; then
    echo "Usage: $0 <resource-group-name>"
    exit 1
fi

echo "Retrieving Azure resources from resource group: $RG_NAME"

# Get Key Vault name (first one if multiple)
KEYVAULT_NAME=$(az keyvault list --resource-group $RG_NAME --query "[].name" -o tsv | head -1)
if [ -z "$KEYVAULT_NAME" ]; then
    echo "Error: No Key Vault found in resource group $RG_NAME"
    exit 1
fi
echo "Key Vault: $KEYVAULT_NAME"

# Get VNet ID (first one if multiple)
VNET_ID=$(az network vnet list --resource-group $RG_NAME --query "[].id" -o tsv | head -1)
if [ -z "$VNET_ID" ]; then
    echo "Error: No VNet found in resource group $RG_NAME"
    exit 1
fi
echo "VNet ID: $VNET_ID"

# Get Storage Account name (first one if multiple)
STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group $RG_NAME --query "[].name" -o tsv | head -1)
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "Error: No Storage Account found in resource group $RG_NAME"
    exit 1
fi
echo "Storage Account: $STORAGE_ACCOUNT_NAME"

# Get User Assigned Identity ID (first one if multiple)
USER_ASSIGNED_IDENTITY_ID=$(az identity list --resource-group $RG_NAME --query "[].id" -o tsv | head -1)
if [ -z "$USER_ASSIGNED_IDENTITY_ID" ]; then
    echo "Error: No User Assigned Identity found in resource group $RG_NAME"
    exit 1
fi
echo "User Assigned Identity ID: $USER_ASSIGNED_IDENTITY_ID"

# Generate the parameter file
cat > management-vm.bicepparam << EOF
using './management-vm.bicep'

param location = 'uksouth'
param vmName = 'management-vm'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'
param keyVaultName = '$KEYVAULT_NAME'
param vnetId = '$VNET_ID'
param vmSubnetName = 'vmSubnet'
param storageAccountName = '$STORAGE_ACCOUNT_NAME'
param osDiskSizeGB = 64
param userAssignedIdentityId = '$USER_ASSIGNED_IDENTITY_ID'
EOF

echo "Parameter file generated successfully: management-vm.bicepparam"
echo "You can now deploy the VM using:"
echo "az deployment group create --resource-group $RG_NAME --template-file management-vm.bicep --parameters management-vm.bicepparam"
