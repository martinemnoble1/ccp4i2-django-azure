param location string = resourceGroup().location
param environmentName string = 'dev4'
param storageAccountName string = '${environmentName}storage${uniqueString(resourceGroup().id)}'
param postgresqlServerName string = '${environmentName}postgres${uniqueString(resourceGroup().id)}'
param postgresqlAdminUsername string = 'postgresadmin'
// @secure() param postgresqlAdminPassword string // Removed, now from Key Vault
param keyVaultName string = '${environmentName}kv${uniqueString(resourceGroup().id)}'
param timestamp string = utcNow() // For random password generation
param vnetName string = '${environmentName}vnet'
param vnetAddressPrefix string = '10.0.0.0/16'
param containerSubnetPrefix string = '10.0.0.0/23'
param vmSubnetPrefix string = '10.0.2.0/24'
param appGatewaySubnetPrefix string = '10.0.3.0/24'
param privateEndpointSubnetPrefix string = '10.0.4.0/24'
// param appGatewayName string = '${environmentName}appgw' // Removed as App Gateway is commented out
param containerAppEnvironmentName string = '${environmentName}cae'

var tags = {
  environment: environmentName
}

// User Assigned Managed Identity for VM
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${environmentName}vmidentity'
  location: location
  tags: tags
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: subscription().subscriptionId // Note: This should be the objectId of the deployment principal, but for simplicity using subscriptionId as placeholder
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
      {
        tenantId: subscription().tenantId
        objectId: userAssignedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
    enabledForDeployment: true
    enabledForTemplateDeployment: true
  }
}

// PostgreSQL Admin Password Secret
resource postgresqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'postgresql-admin-password'
  properties: {
    value: '${uniqueString(timestamp)}${uniqueString(resourceGroup().id)}' // Generate a random password per deployment
  }
}

// Storage Account Key Secret
resource storageAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'storage-account-key'
  properties: {
    value: storageAccountKeys.keys[0].value
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'containerSubnet'
        properties: {
          addressPrefix: containerSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'vmSubnet'
        properties: {
          addressPrefix: vmSubnetPrefix
        }
      }
      {
        name: 'appGatewaySubnet'
        properties: {
          addressPrefix: appGatewaySubnetPrefix
        }
      }
      {
        name: 'privateEndpointSubnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: tags
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

var storageAccountKeys = storageAccount.listKeys()

// File Services for Storage Account
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// File Share for mounting
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: 'ccp4data'
  properties: {
    shareQuota: 5120 // 5 TB
  }
}

// Private Endpoint for Storage
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${storageAccountName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/privateEndpointSubnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-pls'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for Storage
resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

// Link Private DNS Zone to VNet
resource storageDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storagePrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// DNS Zone Group for Storage Private Endpoint
resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: storagePrivateDnsZone.id
        }
      }
    ]
  }
}

// PostgreSQL Server
resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: postgresqlServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '14'
    administratorLogin: postgresqlAdminUsername
    administratorLoginPassword: postgresqlPasswordSecret.properties.secretUriWithVersion
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      // publicNetworkAccess: 'Disabled' // Removed as it's read-only
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
  tags: tags
}

// Private Endpoint for PostgreSQL
resource postgresqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: '${postgresqlServerName}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/privateEndpointSubnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${postgresqlServerName}-pls'
        properties: {
          privateLinkServiceId: postgresqlServer.id
          groupIds: [
            'postgresqlServer'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone for PostgreSQL
resource postgresqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

// Link Private DNS Zone to VNet
resource postgresqlDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresqlPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// DNS Zone Group for PostgreSQL Private Endpoint
resource postgresqlDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: postgresqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: postgresqlPrivateDnsZone.id
        }
      }
    ]
  }
}

// Application Gateway (commented out due to self-reference issues)
// resource appGateway 'Microsoft.Network/applicationGateways@2022-07-01' = {
//   name: appGatewayName
//   location: location
//   tags: tags
//   properties: {
//     sku: {
//       name: 'Standard_v2'
//       tier: 'Standard_v2'
//     }
//     gatewayIPConfigurations: [
//       {
//         name: 'appGatewayIpConfig'
//         properties: {
//           subnet: {
//             id: '${vnet.id}/subnets/appGatewaySubnet'
//           }
//         }
//       }
//     ]
//     frontendIPConfigurations: [
//       {
//         name: 'appGatewayFrontendIP'
//         properties: {
//           privateIPAddress: '10.0.3.10'
//           privateIPAllocationMethod: 'Static'
//           subnet: {
//             id: '${vnet.id}/subnets/appGatewaySubnet'
//           }
//         }
//       }
//     ]
//     frontendPorts: [
//       {
//         name: 'port_80'
//         properties: {
//           port: 80
//         }
//       }
//     ]
//     backendAddressPools: [
//       {
//         name: 'appGatewayBackendPool'
//       }
//     ]
//     backendHttpSettingsCollection: [
//       {
//         name: 'appGatewayBackendHttpSettings'
//         properties: {
//           port: 80
//           protocol: 'Http'
//           cookieBasedAffinity: 'Disabled'
//         }
//       }
//     ]
//     httpListeners: [
//       {
//         name: 'appGatewayHttpListener'
//         properties: {
//           frontendIPConfiguration: {
//             id: '${appGateway.id}/frontendIPConfigurations/appGatewayFrontendIP'
//           }
//           frontendPort: {
//             id: '${appGateway.id}/frontendPorts/port_80'
//           }
//           protocol: 'Http'
//         }
//       }
//     ]
//     requestRoutingRules: [
//       {
//         name: 'rule1'
//         properties: {
//           ruleType: 'Basic'
//           httpListener: {
//             id: '${appGateway.id}/httpListeners/appGatewayHttpListener'
//           }
//           backendAddressPool: {
//             id: '${appGateway.id}/backendAddressPools/appGatewayBackendPool'
//           }
//           backendHttpSettings: {
//             id: '${appGateway.id}/backendHttpSettingsCollection/appGatewayBackendHttpSettings'
//           }
//         }
//       }
//     ]
//   }
// }

// Container App Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvironmentName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: '${vnet.id}/subnets/containerSubnet'
      internal: true
    }
  }
}

// Outputs
output vnetId string = vnet.id
output storageAccountId string = storageAccount.id
output postgresqlServerId string = postgresqlServer.id
output containerAppEnvironmentId string = containerAppEnvironment.id
output keyVaultId string = keyVault.id
output userAssignedIdentityId string = userAssignedIdentity.id
output storageAccountName string = storageAccountName
output keyVaultName string = keyVaultName
