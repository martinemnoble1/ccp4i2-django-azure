@description('Container Apps Environment ID')
param containerAppsEnvironmentId string

@description('Azure Container Registry login server')
param acrLoginServer string

@description('Azure Container Registry name')
param acrName string

@description('PostgreSQL server FQDN - will resolve to private IP via private DNS zone')
param postgresServerFqdn string

@description('Key Vault name - accessed via private endpoint')
param keyVaultName string

@description('Container image tag')
param imageTag string = 'latest'

@description('Resource naming prefix')
param prefix string = 'ccp4i2-bicep'

@description('Azure AD Client ID for authentication (optional)')
param aadClientId string = ''

@description('Azure AD Client Secret for authentication (optional)')
@secure()
param aadClientSecret string = ''

@description('Azure AD Tenant ID for authentication (optional)')
param aadTenantId string = tenant().tenantId

@description('Enable Azure AD authentication')
param enableAuthentication bool = false

// Note: This template is designed to work with private VNet architecture
// - PostgreSQL is accessed via private endpoint (no public access)
// - Key Vault is accessed via private endpoint (no public access)
// - Storage Account is accessed via private endpoint (no public access)
// - Container Apps run in dedicated VNet subnet with proper delegation
// - All communication happens within the Azure private network

// Variables
var serverAppName = '${prefix}-server'
var webAppName = '${prefix}-web'
var managementAppName = 'ccp4i2-bicep-management'

// Existing resources
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Server Container App
resource serverApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: serverAppName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8000
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: acrLoginServer
          username: acrName
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'db-password'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/database-admin-password'
          identity: 'system'
        }
        {
          name: 'django-secret-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/django-secret-key'
          identity: 'system'
        }
        {
          name: 'aad-client-secret'
          value: aadClientSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'server'
          image: '${acrLoginServer}/ccp4i2/server:${imageTag}'
          resources: {
            cpu: json('2.0')
            memory: '4.0Gi'
          }
          env: [
            {
              name: 'DJANGO_SETTINGS_MODULE'
              value: 'ccp4x.config.settings'
            }
            {
              name: 'DB_HOST'
              value: postgresServerFqdn // Will resolve to private IP via private DNS zone
            }
            {
              name: 'DB_PORT'
              value: '5432'
            }
            {
              name: 'DB_USER'
              value: 'ccp4i2'
            }
            {
              name: 'DB_NAME'
              value: 'postgres'
            }
            {
              name: 'DB_PASSWORD'
              secretRef: 'db-password'
            }
            {
              name: 'SECRET_KEY'
              secretRef: 'django-secret-key'
            }
            {
              name: 'DB_SSL_MODE'
              value: 'require'
            }
            {
              name: 'DB_SSL_ROOT_CERT'
              value: 'true'
            }
            {
              name: 'DB_SSL_REQUIRE_CERT'
              value: 'false' // Private endpoint uses Azure's trusted certificates
            }
            {
              name: 'CCP4_DATA_PATH'
              value: '/mnt/ccp4data'
            }
            {
              name: 'CCP4I2_PROJECTS_DIR'
              value: '/mnt/ccp4data/ccp4i2-projects'
            }
            {
              name: 'ALLOWED_HOSTS'
              value: '${prefix}-web.*.azurecontainerapps.io,${prefix}-server.*.azurecontainerapps.io,localhost,127.0.0.1,*'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'ccp4data-volume'
              mountPath: '/mnt/ccp4data'
            }
            {
              volumeName: 'staticfiles-volume'
              mountPath: '/mnt/staticfiles'
            }
            {
              volumeName: 'mediafiles-volume'
              mountPath: '/mnt/mediafiles'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'ccp4data-volume'
          storageName: 'ccp4data-mount'
          storageType: 'AzureFile'
        }
        {
          name: 'staticfiles-volume'
          storageName: 'staticfiles-mount'
          storageType: 'AzureFile'
        }
        {
          name: 'mediafiles-volume'
          storageName: 'mediafiles-mount'
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

// Management Container App
resource managementApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: managementAppName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8000
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          username: acrName
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'db-password'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/database-admin-password'
          identity: 'system'
        }
        {
          name: 'django-secret-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/django-secret-key'
          identity: 'system'
        }
        {
          name: 'aad-client-secret'
          value: aadClientSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'management'
          image: '${acrLoginServer}/ccp4i2/server:${imageTag}'
          command: ['/bin/bash']
          args: ['-c', 'while true; do echo "Management container active: $(date)"; sleep 300; done']
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'DJANGO_SETTINGS_MODULE'
              value: 'ccp4x.config.settings'
            }
            {
              name: 'DB_HOST'
              value: postgresServerFqdn // Will resolve to private IP via private DNS zone
            }
            {
              name: 'DB_PORT'
              value: '5432'
            }
            {
              name: 'DB_USER'
              value: 'ccp4i2'
            }
            {
              name: 'DB_NAME'
              value: 'postgres'
            }
            {
              name: 'DB_PASSWORD'
              secretRef: 'db-password'
            }
            {
              name: 'SECRET_KEY'
              secretRef: 'django-secret-key'
            }
            {
              name: 'DB_SSL_MODE'
              value: 'require'
            }
            {
              name: 'DB_SSL_ROOT_CERT'
              value: 'true'
            }
            {
              name: 'DB_SSL_REQUIRE_CERT'
              value: 'false' // Private endpoint uses Azure's trusted certificates
            }
            {
              name: 'CCP4_DATA_PATH'
              value: '/mnt/ccp4data'
            }
            {
              name: 'CCP4I2_PROJECTS_DIR'
              value: '/mnt/ccp4data/ccp4i2-projects'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'ccp4data-volume'
              mountPath: '/mnt/ccp4data'
            }
            {
              volumeName: 'staticfiles-volume'
              mountPath: '/mnt/staticfiles'
            }
            {
              volumeName: 'mediafiles-volume'
              mountPath: '/mnt/mediafiles'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
        rules: []
      }
      volumes: [
        {
          name: 'ccp4data-volume'
          storageName: 'ccp4data-mount'
          storageType: 'AzureFile'
        }
        {
          name: 'staticfiles-volume'
          storageName: 'staticfiles-mount'
          storageType: 'AzureFile'
        }
        {
          name: 'mediafiles-volume'
          storageName: 'mediafiles-mount'
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

// Web Container App
resource webApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: webAppName
  location: resourceGroup().location
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: acrLoginServer
          username: acrName
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'aad-client-secret'
          value: aadClientSecret
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'web'
          image: '${acrLoginServer}/ccp4i2/web:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'BACKEND_URL'
              value: 'https://${serverApp.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'NEXT_PUBLIC_API_URL'
              value: 'https://${serverApp.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'API_BASE_URL'
              value: 'https://${serverApp.properties.configuration.ingress.fqdn}'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'staticfiles-volume'
              mountPath: '/mnt/staticfiles'
            }
            {
              volumeName: 'mediafiles-volume'
              mountPath: '/mnt/mediafiles'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'staticfiles-volume'
          storageName: 'staticfiles-mount'
          storageType: 'AzureFile'
        }
        {
          name: 'mediafiles-volume'
          storageName: 'mediafiles-mount'
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

// Authentication configuration for Server App
resource serverAppAuth 'Microsoft.App/containerApps/authConfigs@2023-05-01' = if (enableAuthentication) {
  name: 'current'
  parent: serverApp
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'AllowAnonymous'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: aadClientId
          clientSecretSettingName: 'aad-client-secret'
          openIdIssuer: '${environment().authentication.loginEndpoint}${aadTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            aadClientId
          ]
        }
      }
    }
  }
}

// Authentication configuration for Web App
resource webAppAuth 'Microsoft.App/containerApps/authConfigs@2023-05-01' = if (enableAuthentication) {
  name: 'current'
  parent: webApp
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      excludedPaths: [
        '/api/proxy/*'
        '/api/*'
        '/_next/*'
        '/favicon.ico'
        '/RDKit_minimal.wasm'
        '/static/*'
      ]
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: aadClientId
          clientSecretSettingName: 'aad-client-secret'
          openIdIssuer: '${environment().authentication.loginEndpoint}${aadTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            aadClientId
          ]
        }
      }
    }
  }
}

// Key Vault RBAC Role Assignment for Server App (Key Vault Secrets User)
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, serverApp.id, '4633458b-17de-408a-b874-0445c86b69e6', '2025-09-22-v2')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    ) // Key Vault Secrets User
    principalId: serverApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault RBAC Role Assignment for Management App (Key Vault Secrets User)
resource keyVaultRoleAssignmentManagement 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managementApp.id, '4633458b-17de-408a-b874-0445c86b69e6', '2025-09-22-v2')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    ) // Key Vault Secrets User
    principalId: managementApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output serverUrl string = 'https://${serverApp.properties.configuration.ingress.fqdn}'
output webUrl string = 'https://${webApp.properties.configuration.ingress.fqdn}'
output managementAppName string = managementApp.name
output serverPrincipalId string = serverApp.identity.principalId
output managementPrincipalId string = managementApp.identity.principalId
