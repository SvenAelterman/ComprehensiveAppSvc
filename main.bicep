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
param mySqlVersion string = '8.0.21'
param dbAdminLogin string = 'dbadmin'
@secure()
param dbAdminPassword string

// Application Gateway parameters
param configureAppGwTls bool = true
param kvCertificateName string = ''
param createHttpRedirectRoutingRules bool = true
// This is the ID of the secret, not a secret itself
#disable-next-line secure-secrets-in-params
param kvCertificateSecretId string = ''

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

// region Resource Groups
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
// endregion

// region Networking

// Create the route table for the Application Gateway subnet
module rtAppGwModule 'modules/networking/routeTable-appGw.bicep' = {
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
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          '*'
        ]
      }
    ]
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
      {
        service: 'Microsoft.KeyVault'
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
    serviceEndpoints: [
      // Allow compute resources in the default subnet to bypass App Svc IP restrictions
      {
        service: 'Microsoft.Web'
        locations: [
          '*'
        ]
      }
      // Allow compute resources to access the Key Vault
      {
        service: 'Microsoft.KeyVault'
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
module networkModule 'modules/networking/network.bicep' = {
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

// endregion

// region MySQL

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

module mySqlPrivateDnsZoneModule 'modules/networking/privateDnsZone.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zone-mysql'), 64)
  scope: networkingRg
  params: {
    zoneName: '${mySqlServerNameModule.outputs.shortName}.private.mysql.database.azure.com'
  }
}

module mySqlPrivateDnsZoneLinkModule 'modules/networking/privateDnsZoneVNetLink.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'dns-zone-link-mysql'), 64)
  scope: networkingRg
  params: {
    dnsZoneName: mySqlPrivateDnsZoneModule.outputs.zoneName
    vNetId: networkModule.outputs.vNetId
  }
}

// endregion

// Create a Bastion resource to access the management VM
module bastionModule 'modules/networking/bastion.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'bas'), 64)
  scope: networkingRg
  params: {
    location: location
    bastionSubnetId: networkModule.outputs.createdSubnets.azureBastionSubnet.id
    namingStructure: namingStructure
    tags: tags
  }
}

// region Create the management VM
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
// endregion

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
    mySqlVersion: mySqlVersion
    tags: tags
  }
  dependsOn: [
    mySqlPrivateDnsZoneLinkModule
    bastionModule
  ]
}

// Create a name for the Key Vault
module keyVaultNameModule 'common-modules/shortname.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-name'), 64)
  scope: securityRg
  params: {
    location: location
    environment: environment
    namingConvention: namingConvention
    resourceType: 'kv'
    sequence: sequence
    workloadName: workloadName
  }
}

// Determine which subnets to allow access to the KV via virtual network rules
var kvAllowedSubnetIds = [
  networkModule.outputs.createdSubnets.apps.id
  networkModule.outputs.createdSubnets.appgw.id
]
var defaultSubnetIdArray = deployDefaultSubnet ? [
  networkModule.outputs.createdSubnets.default.id
] : []

var actualKvAllowedSubnetIds = concat(kvAllowedSubnetIds, defaultSubnetIdArray)

// Create the Key Vault with virtual network rules instead of private endpoint
module keyVaultModule 'modules/keyVault/keyVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv'), 64)
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultNameModule.outputs.shortName
    namingStructure: namingStructure
    allowedSubnetIds: actualKvAllowedSubnetIds
    allowPublicAccess: true
    tags: tags
  }
}

// TODO: Create secrets for App Svc as necessary (database username, password)

// Deploy a Log Analytics Workspace
module logModule 'modules/log.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'log'), 64)
  scope: securityRg
  params: {
    location: location
    namingStructure: namingStructure
    tags: tags
  }
}

// Deploy Application Insights
module appInsightsModule 'modules/appInsights.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appi'), 64)
  scope: appsRg
  params: {
    location: location
    appInsightsName: replace(namingStructure, '{rtype}', 'appi')
    logAnalyticsWorkspaceId: logModule.outputs.workspaceId
    tags: tags
  }
}

var appSvcAllowedSubnetIds = [
  networkModule.outputs.createdSubnets.appgw.id
]

var actualAllowAccessSubnetIds = concat(appSvcAllowedSubnetIds, defaultSubnetIdArray)

// Deploy the App Services
module appSvcModule 'modules/appSvc/appSvc-main.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'app-main'), 64)
  scope: appsRg
  params: {
    location: location
    apiAppSettings: apiAppSettings
    webAppSettings: webAppSettings
    deploymentNameStructure: deploymentNameStructure
    keyVaultName: keyVaultModule.outputs.keyVaultName
    kvResourceGroupName: securityRg.name
    logAnalyticsWorkspaceId: logModule.outputs.workspaceId
    namingStructure: namingStructure
    subnetId: networkModule.outputs.createdSubnets.apps.id
    appInsights: {
      instrumentationKey: appInsightsModule.outputs.instrumentationKey
      connectionString: appInsightsModule.outputs.connectionString
    }
    allowAccessSubnetIds: actualAllowAccessSubnetIds
    tags: tags
  }
}

// region Deploy the Application Gateway, with or without TLS
var backends = [
  {
    name: 'api'
    appSvcName: appSvcModule.outputs.apiAppSvcName
    hostName: apiHostName
    // TODO: Change based on developer input
    customProbePath: '/hostingstart.html'
  }
  {
    name: 'web'
    appSvcName: appSvcModule.outputs.webAppSvcName
    hostName: webHostName
    customProbePath: ''
  }
]

// Deploy a user-assigned managed identity to allow the App GW to retrieve TLS certs from KV
module uamiModule 'modules/uami.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'uami'), 64)
  scope: securityRg
  params: {
    location: location
    identityName: replace(namingStructure, '{rtype}', 'uami')
    tags: tags
  }
}

module uamiKvRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-uami-kv'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: uamiModule.outputs.principalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Secrets User']
  }
}

module appGwModule 'modules/networking/appGw.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'appgw'), 64)
  scope: networkingRg
  params: {
    location: location
    appsRgName: appsRg.name
    backendAppSvcs: backends
    namingStructure: namingStructure
    subnetId: networkModule.outputs.createdSubnets.appgw.id
    uamiId: uamiModule.outputs.id
    tags: tags

    tlsConfiguration: configureAppGwTls ? {
      certificateName: kvCertificateName
      certificateSecretId: kvCertificateSecretId
    } : {}

    createHttpRedirectRoutingRules: configureAppGwTls ? createHttpRedirectRoutingRules : false
  }
  dependsOn: [
    appSvcModule
    uamiKvRoleAssignmentModule
  ]
}

// endregion

module rolesModule 'common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

// region Assign RBAC to the developer principal, if it's provided
resource readerSubscriptionRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerPrincipalId)) {
  name: guid(subscription().id, developerPrincipalId, 'Reader')
  properties: {
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles.Reader
  }
}

module contributorApiAppSvcRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-app.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-app-api-dev'), 64)
  scope: appsRg
  params: {
    appSvcName: appSvcModule.outputs.apiAppSvcName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles.Contributor
  }
}

module contributorWebAppSvcRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-app.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-app-web-dev'), 64)
  scope: appsRg
  params: {
    appSvcName: appSvcModule.outputs.webAppSvcName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles.Contributor
  }
}

module contributorAppGwRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-appGw.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-appgw-dev'), 64)
  scope: networkingRg
  params: {
    appGwName: appGwModule.outputs.appGwName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles.Contributor
  }
}

module kvSecretsUserRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-kv-secrets-dev'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Secrets Officer']
  }
}

module kvCertificatesOfficerRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-kv-certs-dev'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Certificates Officer']
  }
}

module kvReaderRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-kv-reader-dev'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Reader']
  }
}

module uamiOperatorRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-uami.bicep' = if (!empty(developerPrincipalId)) {
  name: take(replace(deploymentNameStructure, '{rtype}', 'role-uami-dev'), 64)
  scope: securityRg
  params: {
    principalId: developerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles['Managed Identity Operator']
    uamiName: uamiModule.outputs.name
  }
}

// endregion

output appGwPublicIpAddress string = appGwModule.outputs.publicIpAddress
