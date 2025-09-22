using './management-vm.bicep'

param location = 'uksouth'
param vmName = 'management-vm'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'
param keyVaultName = 'dev4kvitihdp4e4vrho'
param vnetId = '/subscriptions/73fdecd0-baa0-4e89-877f-fb9adc5646d7/resourceGroups/ccp4i2-django-rg/providers/Microsoft.Network/virtualNetworks/dev4vnet'
param vmSubnetName = 'vmSubnet'
param storageAccountName = 'dev4storageitihdp4e4vrho'
param osDiskSizeGB = 64
param userAssignedIdentityId = '/subscriptions/73fdecd0-baa0-4e89-877f-fb9adc5646d7/resourcegroups/ccp4i2-django-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/dev4vmidentity'
