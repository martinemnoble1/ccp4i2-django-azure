param storageAccountName string = 'ccp4storage${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location
param fileShareName string = 'ccp4fileshare'
param fileShareQuotaGB int = 100

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccount.name}/default/${fileShareName}'
  properties: {
    shareQuota: fileShareQuotaGB
  }
}

output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
output fileShareQuotaGB int = fileShareQuotaGB
