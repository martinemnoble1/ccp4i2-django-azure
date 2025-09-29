// Ubuntu VM in management subnet, with identity and NSG
param location string = resourceGroup().location
param vmName string = 'ccp4-maint-vm'
param adminUsername string = 'azureuser'
@secure()
param adminPassword string
param subnetId string
param storageAccountName string
param fileShareName string = 'ccp4data'
@secure()
param storageAccountKey string

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: base64(
        '''#cloud-config
runcmd:
  - apt-get update
  - apt-get install -y cifs-utils
  - mkdir -p /mnt/ccp4data
  - mount -t cifs //${storageAccountName}.file.core.windows.net/${fileShareName} /mnt/ccp4data -o vers=3.0,username=${storageAccountName},password=${storageAccountKey},dir_mode=0777,file_mode=0777,serverino
'''
      )
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}
