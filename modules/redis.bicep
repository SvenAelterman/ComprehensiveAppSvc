param namingStructure string
param location string = resourceGroup().location
param tags object

param deployPrivateEndpoint bool = true
param privateEndpointResourceGroupName string = ''
param privateDnsZoneId string = ''
param privateEndpointSubnetId string = ''

var abbreviation = 'redis'

resource redis 'Microsoft.Cache/redis@2022-06-01' = {
  name: replace(namingStructure, '{rtype}', abbreviation)
  location: location
  properties: {
    sku: {
      capacity: 1
      family: 'C'
      name: 'Standard'
    }
    enableNonSslPort: false
    redisVersion: '6'
    publicNetworkAccess: deployPrivateEndpoint ? 'Disabled' : 'Enabled'
  }
  tags: tags
}

var peName = replace(namingStructure, '{rtype}', abbreviation)

resource peRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (deployPrivateEndpoint) {
  name: privateEndpointResourceGroupName
  scope: subscription()
}

module pe 'networking/privateEndpoint.bicep' = if (deployPrivateEndpoint) {
  name: 'redis-pe'
  scope: peRg
  params: {
    location: location
    connectionGroupIds: [
      'redisCache'
    ]
    peName: peName
    privateDnsZoneId: privateDnsZoneId
    privateEndpointSubnetId: privateEndpointSubnetId
    privateLinkServiceId: redis.id
    tags: tags
  }
}

output redisCacheName string = redis.name
output customDnsConfigs array = pe.outputs.peCustomDnsConfigs
output nicIds array = pe.outputs.nicIds
