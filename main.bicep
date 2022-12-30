targetScope = 'subscription'

// Governance parameters
@allowed([
  'eastus'
  'eastus2'
])
param location string
@allowed([
  'TEST'
  'DEMO'
  'PROD'
])
param environment string
param workloadName string

// Virtual machine parameters
param vmLocalUserName string = 'AzureUser'
@secure()
param vmLocalPassword string
param intuneMdmRegister bool
param developerVmLoginAsAdmin bool
param vmComputerName string

// Database parameters
param mySqlVersion string = '8.3'
param dbAdminLogin string = 'dbadmin'
@secure()
param dbAdminPassword string

// App Svc parameters
@secure()
param dbAppSvcLogin string
@secure()
param dbAppSvcPassword string
param databaseName string

param apiAppSettings object
param webAppSettings object

param apiHostName string
param webHostName string

// Network parameters
@minValue(0)
@maxValue(128)
param vNetAddressSpaceOctet4Min int
param vNetAddressSpace string
@minValue(24)
@maxValue(25)
param vNetCidr int
@maxValue(28)
@minValue(27)
param subnetCidr int

@description('AAD principal that will be assigned permissions to App Svc, App GW, etc. (optional).')
param developerPrincipalId string = ''

// Optional parameters
param deployDefaultSubnet bool = true
param deployBastion bool = true
param tags object = {}
param sequence int = 1
param namingConvention string = '{wloadname}-{env}-{rtype}-{loc}-{seq}'
param deploymentTime string = utcNow()

// Variables
var sequenceFormatted = format('{0:00}', sequence)

var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) replaced
var namingStructure = replace(replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted), '{wloadname}', workloadName)

resource networkingRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-networking'), 64)
  location: location
  tags: tags
}

resource dataRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-data'), 64)
  location: location
  tags: tags
}

resource computeRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-compute'), 64)
  location: location
  tags: tags
}

resource securityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-security'), 64)
  location: location
  tags: tags
}

resource appsRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-apps'), 64)
  location: location
  tags: tags
}

// Create the route table for the Application Gateway subnet
module rtAppGwModule 'modules/routeTable-appGw.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'rt-appgw'), 64)
  scope: networkingRg
  params: {
    location: location
    namingStructure: namingStructure
    tags: tags
  }
}

var SubnetSize = 32 - subnetCidr
var subnetBoundaryArray = [for i in range(0, SubnetSize): 2]
var subnetBoundary = reduce(subnetBoundaryArray, 1, (cur, next) => cur * next)

// Create virtual network and subnets
var subnets = {
  mySql: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (0 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.DBforMySQL/flexibleServers'
    securityRules: []
    routeTable: ''
  }
  apps: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (1 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: 'Microsoft.Web/serverFarms'
    securityRules: []
    routeTable: ''
  }
  appgw: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (2 * subnetBoundary)))}/${subnetCidr}'
    // Allow the Application Gateway to access the App Services
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
    ]
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/appGw.json')
    routeTable: rtAppGwModule.outputs.routeTableId
  }
}

var defaultSubnet = deployDefaultSubnet ? {
  default: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (3 * subnetBoundary)))}/${subnetCidr}'
    // Allow compute resources in the default subnet to bypass App Svc IP restrictions
    serviceEndpoints: [
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
    ]
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/default.json')
    routeTable: ''
  }
} : {}

var azureBastionSubnet = deployBastion ? {
  AzureBastionSubnet: {
    addressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min + (4 * subnetBoundary)))}/${subnetCidr}'
    serviceEndpoints: []
    delegation: ''
    securityRules: loadJsonContent('content/nsgrules/bastion.json')
    routeTable: ''
  }
} : {}

var subnetsToDeploy = union(subnets, azureBastionSubnet, defaultSubnet)

// Create the basic network resources: Virtual Network + subnets, Network Security Groups
module networkModule 'modules/network.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'network'), 64)
  scope: networkingRg
  params: {
    location: location
    deploymentNameStructure: deploymentNameStructure
    subnetDefs: subnetsToDeploy
    vNetAddressPrefix: '${replace(vNetAddressSpace, '{octet4}', string(vNetAddressSpaceOctet4Min))}/${vNetCidr}'
    namingStructure: namingStructure
    tags: tags
  }
  dependsOn: [
    // Explicitly define this because Bicep might not pick up on the reference in the variable
    rtAppGwModule
  ]
}

// Construct the MySQL server name
module mySqlServerNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'mysql-name'), 64)
  scope: dataRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'mysql'
    sequence: sequence
    workloadName: workloadName
  }
}

module mySqlPrivateDnsZoneModule 'modules/privateDnsZone.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zone-mysql'), 64)
  scope: networkingRg
  params: {
    zoneName: '${mySqlServerNameModule.outputs.shortName}.private.mysql.database.azure.com'
  }
}

module mySqlPrivateDnsZoneLinkModule 'modules/privateDnsZoneVNetLink.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zone-link-mysql'), 64)
  scope: networkingRg
  params: {
    dnsZoneName: mySqlPrivateDnsZoneModule.outputs.zoneName
    vNetId: networkModule.outputs.vNetId
  }
}

// Create a Bastion resource to access the management VM
module bastionModule 'modules/bastion.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'bas'), 64)
  scope: networkingRg
  params: {
    location: location
    bastionSubnetId: networkModule.outputs.createdSubnets.azureBastionSubnet.id
    namingStructure: namingStructure
    tags: tags
  }
}

// Create the management VM
module vmModule 'modules/vm.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'vm'), 64)
  scope: computeRg
  params: {
    location: location
    adminPassword: vmLocalPassword
    adminUsername: vmLocalUserName
    subnetName: networkModule.outputs.createdSubnets.default.name
    virtualMachineName: replace(namingStructure, '{rtype}', 'vm')
    virtualMachineComputerName: vmComputerName
    virtualNetworkId: networkModule.outputs.vNetId
    intuneMdmRegister: intuneMdmRegister
    tags: tags
  }
}

// Create RBAC assignment to allow developers to sign in to the VM
module loginRoleAssignment 'common-modules/roleAssignments/roleAssignment-rg.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles-rg-dev'), 64)
  scope: computeRg
  params: {
    principalId: developerPrincipalId
    roleDefinitionId: developerVmLoginAsAdmin ? rolesModule.outputs.roles['Virtual Machine Administrator Login'] : rolesModule.outputs.roles['Virtual Machine User Login']
  }
}

module mySqlModule 'modules/mysql.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'mysql'), 64)
  scope: dataRg
  params: {
    location: location
    databaseName: databaseName
    dbAdminPassword: dbAdminPassword
    dbAdminUserName: dbAdminLogin
    delegateSubnetId: networkModule.outputs.createdSubnets.mySql.id
    mySqlServerName: mySqlServerNameModule.outputs.shortName
    dnsZoneId: mySqlPrivateDnsZoneModule.outputs.zoneId
    tags: tags
  }
  dependsOn: [
    mySqlPrivateDnsZoneLinkModule
    bastionModule
  ]
}

module rolesModule 'common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}
