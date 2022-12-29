param location string
param subnetName string
param virtualNetworkId string
param virtualMachineName string
param adminUsername string
@secure()
param adminPassword string

param tags object = {}
param patchMode string = 'AutomaticByOS'
param enableHotpatching bool = false
param virtualMachineComputerName string = virtualMachineName
param enableAcceleratedNetworking bool = true
param osDiskType string = 'StandardSSD_LRS'
param osDiskDeleteOption string = 'Delete'
param nicDeleteOption string = 'Delete'
param virtualMachineSize string = 'Standard_D2s_v4'

param imageReference object = {
  publisher: 'microsoftwindowsdesktop'
  offer: 'office-365'
  sku: 'win10-22h2-avd-m365-g2'
  version: 'latest'
}

var vnetIdSplit = split(virtualNetworkId, '/')
var vnetResourceGroupName = vnetIdSplit[4]
var vnetName = last(vnetIdSplit)

resource vnetResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: vnetResourceGroupName
  scope: subscription()
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  name: vnetName
  scope: vnetResourceGroup
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-05-01' existing = {
  name: subnetName
  parent: vnet
}

// LATER: Add random 3 digits at the end
var networkInterfaceName = virtualMachineName

resource networkInterface 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: networkInterfaceName
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
    enableAcceleratedNetworking: enableAcceleratedNetworking
  }
  tags: tags
  dependsOn: []
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: virtualMachineName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'fromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        deleteOption: osDiskDeleteOption
      }
      imageReference: imageReference
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: nicDeleteOption
          }
        }
      ]
    }
    osProfile: {
      computerName: virtualMachineComputerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          enableHotpatching: enableHotpatching
          patchMode: patchMode
        }
      }
    }
    licenseType: 'Windows_Client'
  }
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

resource aadLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = {
  name: 'AADLoginForWindows'
  parent: virtualMachine
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    autoUpgradeMinorVersion: true
    typeHandlerVersion: '1.0'
    // The setting below is key to enrolling in Intune
    settings: {
      mdmId: '0000000a-0000-0000-c000-000000000000'
    }
  }
}

output vmName string = virtualMachine.name
output nicName string = networkInterfaceName
