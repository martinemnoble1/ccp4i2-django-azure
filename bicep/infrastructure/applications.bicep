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

@description('Web container image tag')
param imageTagWeb string = 'latest'

@description('Server container image tag')
param imageTagServer string = 'latest'

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
var workerAppName = '${prefix}-worker'

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
        {
          name: 'servicebus-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/servicebus-connection'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'server'
          image: '${acrLoginServer}/ccp4i2/server:${imageTagServer}'
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
                path: '/projects/'
                port: 8000
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
              name: 'DEBUG'
              value: 'true' // Ensure DEBUG is false in production
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
              value: '${serverAppName},${serverAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io,localhost,127.0.0.1,*'
            }
            {
              name: 'CORS_ALLOWED_ORIGINS'
              value: 'http://${webAppName},https://${webAppName}.whitecliff-258bc831.northeurope.azurecontainerapps.io'
            }
            {
              name: 'CORS_ALLOW_CREDENTIALS'
              value: 'True'
            }
            {
              name: 'SERVICE_BUS_CONNECTION_STRING'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'SERVICE_BUS_QUEUE_NAME'
              value: '${prefix}-jobs'
            }
            {
              name: 'FILE_UPLOAD_MAX_MEMORY_SIZE'
              value: '104857600' // 100MB in bytes
            }
            {
              name: 'DATA_UPLOAD_MAX_MEMORY_SIZE'
              value: '104857600' // 100MB in bytes
            }
            {
              name: 'FILE_UPLOAD_MAX_NUMBER_FILES'
              value: '10'
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
            name: 'cpu-scaling'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
          {
            name: 'memory-scaling'
            custom: {
              type: 'memory'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '20' // Lower threshold for faster scaling on file uploads
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

// Worker Container App
resource workerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: workerAppName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false // Internal only - no external access needed
        targetPort: 8000
        allowInsecure: true
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
          name: 'servicebus-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/servicebus-connection'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: '${acrLoginServer}/ccp4i2/server:${imageTagServer}'
          command: ['/usr/src/app/startup-worker.sh'] // Use worker startup script instead of Django server
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
              value: postgresServerFqdn
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
              value: 'false'
            }
            {
              name: 'CCP4_DATA_PATH'
              value: '/mnt/ccp4data'
            }
            {
              name: 'CCP4'
              value: '/mnt/ccp4data/ccp4-9'
            }
            {
              name: 'LD_LIBRARY_PATH'
              value: '/mnt/ccp4data/ccp4-9/lib'
            }
            {
              name: 'CCP4I2_PROJECTS_DIR'
              value: '/mnt/ccp4data/ccp4i2-projects'
            }
            {
              name: 'SERVICE_BUS_CONNECTION_STRING'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'SERVICE_BUS_QUEUE_NAME'
              value: '${prefix}-jobs'
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
        minReplicas: 0 // Scale to zero when no jobs
        maxReplicas: 5
        rules: [
          {
            name: 'queue-scaling'
            custom: {
              type: 'azure-servicebus'
              metadata: {
                queueName: '${prefix}-jobs'
                namespace: '${prefix}-servicebus'
                messageCount: '5' // Scale up when 5+ messages in queue
              }
              auth: [
                {
                  secretRef: 'servicebus-connection'
                  triggerParameter: 'connection'
                }
              ]
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
          image: '${acrLoginServer}/ccp4i2/web:${imageTagWeb}'
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
          env: [
            {
              name: 'NEXT_PUBLIC_API_BASE_URL'
              value: 'http://${serverAppName}'
            }
            {
              name: 'API_BASE_URL'
              value: 'http://${serverAppName}'
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
              volumeName: 'ccp4data-volume'
              mountPath: '/mnt/ccp4data'
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

// Key Vault RBAC Role Assignment for Worker App (Key Vault Secrets User)
// NOTE: Role assignments are handled separately to avoid conflicts on redeployment
// resource keyVaultRoleAssignmentWorker 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(keyVault.id, workerApp.id, '4633458b-17de-408a-b874-0445c86b69e6', roleAssignmentSuffix)
//   scope: keyVault
//   properties: {
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       '4633458b-17de-408a-b874-0445c86b69e6'
//     ) // Key Vault Secrets User
//     principalId: workerApp.identity.principalId
//     principalType: 'ServicePrincipal'
//   }
// }

// Outputs
output serverUrl string = 'https://${serverApp.properties.configuration.ingress.fqdn}'
output webUrl string = 'https://${webApp.properties.configuration.ingress.fqdn}'
output workerAppName string = workerApp.name
