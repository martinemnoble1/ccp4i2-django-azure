//Parameters
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

@description('Server container image tag')
param imageTagServer string = 'latest'

@description('Resource naming prefix')
param prefix string = 'ccp4i2-bicep'

@description('Shared Container Apps Identity ID')
param containerAppsIdentityId string

// Variables
var maintenanceJobName = '${prefix}-maintenance-job'

// Existing resources
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Maintenance Job for long-running tasks like tar extraction
resource maintenanceJob 'Microsoft.App/jobs@2023-05-01' = {
  name: maintenanceJobName
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsIdentityId}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 28800 // 8 hours for long-running tar extraction
      replicaRetryLimit: 3 // Allow 3 retries to help diagnose issues
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
          identity: containerAppsIdentityId
        }
        {
          name: 'django-secret-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/django-secret-key'
          identity: containerAppsIdentityId
        }
        {
          name: 'servicebus-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/servicebus-connection'
          identity: containerAppsIdentityId
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
          command: [
            'sh'
            '-c'
            'cd /mnt/ccp4data && mv ccp4-9 ccp4-9.unsafe3 && tar -xzf ccp4-9.0.011-shelx-arpwarp-linux64.tar.gz --checkpoint=1000 --checkpoint-action=exec="echo Extracted %u files..." && cd ccp4-9 && ./BINARY.setup --run-from-script && ccp4-python -m pip install -r /usr/src/app/requirements.txt'
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
