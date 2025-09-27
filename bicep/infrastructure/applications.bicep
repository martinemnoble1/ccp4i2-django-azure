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

@description('Azure AD Client ID for frontend authentication')
param aadClientId string

@description('Azure AD Tenant ID for frontend authentication')
param aadTenantId string

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
        external: true // Changed to allow browser access
        targetPort: 8000
        allowInsecure: true // Allow HTTP for internal VNet communication
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
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/'
                port: 8000
                host: 'localhost'
              }
              initialDelaySeconds: 60 // Reduced from 120 to comply with Azure limits (max 60)
              periodSeconds: 60 // Check less frequently
              failureThreshold: 3
              successThreshold: 1
              timeoutSeconds: 10 // Add timeout for slow responses
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/'
                port: 8000
                host: 'localhost'
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              failureThreshold: 3
              successThreshold: 1
              timeoutSeconds: 10
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/health/'
                port: 8000
                host: 'localhost'
              }
              initialDelaySeconds: 60 // Reduced from 180 to comply with Azure limits (max 60) - Django should start within 60 seconds
              periodSeconds: 30
              failureThreshold: 10 // Allow more failures during startup
              successThreshold: 1
              timeoutSeconds: 10
            }
          ]
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
              value: '${webAppName}.internal.whitecliff-258bc831.northeurope.azurecontainerapps.io,${serverAppName}.internal.whitecliff-258bc831.northeurope.azurecontainerapps.io,${serverAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io,${serverAppName},${webAppName},localhost,127.0.0.1,0.0.0.0,*'
            }
            {
              name: 'CORS_ALLOWED_ORIGINS'
              value: 'https://${webAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io'
            }
            {
              name: 'CORS_ALLOW_CREDENTIALS'
              value: 'True'
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
        minReplicas: 2
        maxReplicas: 10
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
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
              name: 'NEXT_PUBLIC_API_BASE_URL'
              value: 'https://${serverAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io'
            }
            {
              name: 'API_BASE_URL'
              value: 'https://${serverAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io'
            }
            {
              name: 'NEXT_PUBLIC_AAD_CLIENT_ID'
              value: aadClientId
            }
            {
              name: 'NEXT_PUBLIC_AAD_TENANT_ID'
              value: aadTenantId
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

// Authentication configuration for Server App removed - authentication now handled in frontend

// Authentication configuration for Web App removed - authentication now handled in frontend

// Key Vault RBAC Role Assignment for Server App (Key Vault Secrets User)
// NOTE: Role assignments are handled separately to avoid conflicts on redeployment
// resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(keyVault.id, serverApp.id, '4633458b-17de-408a-b874-0445c86b69e6', roleAssignmentSuffix)
//   scope: keyVault
//   properties: {
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       '4633458b-17de-408a-b874-0445c86b69e6'
//     ) // Key Vault Secrets User
//     principalId: serverApp.identity.principalId
//     principalType: 'ServicePrincipal'
//   }
// }

// Key Vault RBAC Role Assignment for Management App (Key Vault Secrets User)
// NOTE: Role assignments are handled separately to avoid conflicts on redeployment
// resource keyVaultRoleAssignmentManagement 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(keyVault.id, managementApp.id, '4633458b-17de-408a-b874-0445c86b69e6', roleAssignmentSuffix)
//   scope: keyVault
//   properties: {
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       '4633458b-17de-408a-b874-0445c86b69e6'
//     ) // Key Vault Secrets User
//     principalId: managementApp.identity.principalId
//     principalType: 'ServicePrincipal'
//   }
// }

// Outputs
output serverUrl string = 'https://${serverApp.properties.configuration.ingress.fqdn}'
output webUrl string = 'https://${webApp.properties.configuration.ingress.fqdn}'
output managementAppName string = managementApp.name
