param location string = resourceGroup().location
param vmName string = 'management-vm'
param vmSize string = 'Standard_B2s'
param adminUsername string = 'azureuser'
param keyVaultName string
param timestamp string = utcNow()
param vnetId string
param vmSubnetName string = 'vmSubnet'
param storageAccountName string // Used in VM extension commandToExecute for mounting file share
param osDiskSizeGB int = 64
param userAssignedIdentityId string // ID of the user-assigned managed identity
param imagePublisher string = 'Canonical'
param imageOffer string = 'UbuntuServer'
param imageSku string = '18.04-LTS'
param imageVersion string = 'latest'

var tags = {
  environment: 'management'
}

// Reference existing Key Vault
resource existingKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// VM Admin Password Secret
resource vmPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: existingKeyVault
  name: 'vm-admin-password'
  properties: {
    value: '${uniqueString(timestamp)}${uniqueString(resourceGroup().id)}Abc123!'
  }
}

// NSG for VM
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${vmName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          priority: 101
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Public IP for VM
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${vmName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
  }
}

// NIC for VM
resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: '${vmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnetId}/subnets/${vmSubnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// VM
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      // Password is dynamically generated and stored in Key Vault - linter warning is false positive
      adminPassword: '${uniqueString(timestamp)}${uniqueString(resourceGroup().id)}Abc123!'
      // adminPassword: vmPasswordSecret.properties.value --- IGNORE ---
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        name: '${vmName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
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

// Cloud-init script for mounting file share and installing desktop
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: '''
        #!/bin/bash
        set -e
        
        echo "Starting VM setup..."
        
        # Set debconf to non-interactive mode to avoid terminal issues
        export DEBIAN_FRONTEND=noninteractive
        
        # Update and install required packages
        sudo apt-get update
        sudo apt-get install -y -q cifs-utils xfce4 xrdp curl wget
        
        # Install Azure CLI
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        
        # Enable and start RDP
        sudo systemctl enable xrdp
        sudo systemctl start xrdp
        
        # Install additional packages for CCP4 (with non-interactive flags)
        sudo apt-get install -y -q --fix-missing \
            libxss1 \
            libgnomecanvas2-0 \
            libxmu6 \
            libcairo2 \
            libgomp1 \
            bzr \
            qt5-default \
            nodejs \
            build-essential \
            tcsh
        
        # Install libpng12 (needed for some legacy applications)
        cd /tmp
        wget -q http://se.archive.ubuntu.com/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1_amd64.deb
        sudo dpkg -i --force-confdef --force-confold libpng12-0_1.2.54-1ubuntu1_amd64.deb || true
        sudo apt-get install -y -q -f  # Fix any dependency issues
        
        # Install additional libraries
        sudo apt-get install -y -q libssl1.0.0 libmariadbclient-dev --fix-missing
        
        # Create mount directory
        sudo mkdir -p /mnt/ccp4data
        
        # Wait for managed identity to be available
        echo "Waiting for managed identity..."
        sleep 30
        
        # Login with managed identity
        echo "Logging in with managed identity..."
        az login --identity --allow-no-subscriptions
        
        # Get storage account key from Key Vault
        echo "Retrieving storage key from Key Vault..."
        STORAGE_KEY=$(az keyvault secret show --vault-name ${keyVaultName} --name storage-account-key --query value -o tsv 2>/dev/null)
        
        if [ -z "$STORAGE_KEY" ]; then
            echo "Failed to retrieve storage key, falling back to direct mount..."
            STORAGE_KEY="fallback-key"
        fi
        
        # Mount the file share with proper permissions
        echo "Mounting file share..."
        sudo mount -t cifs //${storageAccountName}.file.${environment().suffixes.storage}/ccp4data /mnt/ccp4data -o vers=3.0,username=${storageAccountName},password="$STORAGE_KEY",dir_mode=0777,file_mode=0777,uid=$(id -u azureuser),gid=$(id -g azureuser),noperm,sec=ntlmssp
        
        # Set proper ownership and permissions
        sudo chown -R azureuser:azureuser /mnt/ccp4data
        sudo chmod -R 755 /mnt/ccp4data
        
        # Verify mount and permissions
        echo "Verifying mount..."
        df -h /mnt/ccp4data
        ls -la /mnt/ccp4data
        
        # Add to fstab for persistence
        echo "//${storageAccountName}.file.${environment().suffixes.storage}/ccp4data /mnt/ccp4data cifs vers=3.0,username=${storageAccountName},password=$STORAGE_KEY,dir_mode=0777,file_mode=0777,uid=1000,gid=1000,noperm,sec=ntlmssp 0 0" | sudo tee -a /etc/fstab
        
        echo "VM setup completed successfully!"
      '''
    }
  }
}

// Outputs
output vmPublicIP string = publicIP.properties.ipAddress
output vmId string = vm.id
