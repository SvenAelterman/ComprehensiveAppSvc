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
param kvAllowedIpAddress string
param certificatesOfficerPrincipalId string

// Optional parameters
param tags object = {}
param sequence int = 1
param namingConvention string = '{wloadname}-{env}-{rtype}-{loc}-{seq}'
param deploymentTime string = utcNow()

// Variables
var sequenceFormatted = format('{0:00}', sequence)

var deploymentNameStructure = '${workloadName}-${environment}-{rtype}-${deploymentTime}'
// Naming structure only needs the resource type ({rtype}) replaced
var namingStructure = replace(replace(replace(replace(namingConvention, '{env}', environment), '{loc}', location), '{seq}', sequenceFormatted), '{wloadname}', workloadName)

resource securityRg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: take(replace(namingStructure, '{rtype}', 'rg-security'), 64)
  location: location
  tags: tags
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

// Create the Key Vault with virtual network rules instead of private endpoint
module keyVaultModule 'modules/keyVault/keyVault.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv'), 64)
  scope: securityRg
  params: {
    location: location
    keyVaultName: keyVaultNameModule.outputs.shortName
    namingStructure: namingStructure
    allowedIpAddresses: [
      kvAllowedIpAddress
    ]
    allowPublicAccess: true
    tags: tags
  }
}

module rolesModule 'common-modules/roles.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'roles'), 64)
}

module kvRoleAssignmentModule 'common-modules/roleAssignments/roleAssignment-kv.bicep' = {
  name: take(replace(deploymentNameStructure, '{rtype}', 'kv-role'), 64)
  scope: securityRg
  params: {
    kvName: keyVaultModule.outputs.keyVaultName
    principalId: certificatesOfficerPrincipalId
    roleDefinitionId: rolesModule.outputs.roles['Key Vault Certificates Officer']
  }
}

output keyVaultName string = keyVaultModule.outputs.keyVaultName
output keyVaultResourceGroupName string = securityRg.name
