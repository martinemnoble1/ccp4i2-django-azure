param location string = resourceGroup().location
param vmName string = 'ccp4setupvm'
param adminUsername string = 'azureuser'
param sshPublicKey string

param storageAccountName string
param fileShareName string

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
      customData: base64(concat('#cloud-config\n', cloudInitScript))
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '20_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
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

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
}

var subnet = vnet.properties.subnets[0]

var cloudInitScript = '''
#cloud-config
package_update: true
packages:
  - cifs-utils
  - wget
runcmd:
  - mkdir -p /mnt/ccp4
  - apt-get install -y cifs-utils wget
  - STORAGE_KEY=$(az storage account keys list --resource-group ${resourceGroup().name} --account-name ${storageAccountName} --query "[0].value" -o tsv)
  - echo "//${storageAccountName}.file.core.windows.net/${fileShareName} /mnt/ccp4 cifs vers=3.0,username=${storageAccountName},password=$STORAGE_KEY,dir_mode=0777,file_mode=0777,serverino" >> /etc/fstab
  - mount -a
  - wget -O /mnt/ccp4/ccp4-linux.tar.gz "https://www.ccp4.ac.uk/download/download_file.php?os=linux&pkg=ccp4-shelx-arp-x86_64&sid=dfb8b9af681ed41c9170045b966d049849da7d4c"
  - tar -xzvf /mnt/ccp4/ccp4-linux.tar.gz -C /mnt/ccp4
  # - bash /mnt/ccp4/ccp4-*/setup.sh
'''

output vmName string = vm.name
output vmPublicIP string = nic.properties.ipConfigurations[0].properties.publicIPAddress.id
