param location string
param namingStructure string
param uamiId string
param subnetId string

@description('Array of custom objects: { name: "for use in resource names", appSvcName: "", hostName: "URL", customProbePath: "/path/to/health/endpoint" }')
param backendAppSvcs array
param appsRgName string

param tags object = {}
param createHttpRedirectRoutingRules bool = true

// Retrieve existing App Service instances
resource appsRg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: appsRgName
  scope: subscription()
}

resource appSvcsRes 'Microsoft.Web/sites@2022-03-01' existing = [for appSvc in backendAppSvcs: {
  name: appSvc.appSvcName
  scope: appsRg
}]

// Create a public IP address for the App GW frontend
resource pip 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: replace(namingStructure, '{rtype}', 'pip-appgw')
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
  tags: tags
}

// region Application Gateway name variables
var appGwName = replace(namingStructure, '{rtype}', 'appgw')
var httpSettingsName = 'httpSettings443-'
var frontendIpName = 'appGwPublicFrontendIp'
var frontendPortNamePrefix = 'Public'
var backendAddressPoolNamePrefix = 'be-'
var routingRuleNamePrefix = 'rr-'
var httpListenerNamePrefix = 'l-http-'
var healthProbeNamePrefix = 'hp-'
var frontendPorts = [
  80
  443
]
// endregion

// If HTTP (to HTTPS) redirect rules are needed, double the number of routing rules
var routingRulesMultiplier = createHttpRedirectRoutingRules ? 2 : 1

// Determine which back ends need custom health probes and create an array
var probesArray = [for appSvc in backendAppSvcs: !empty(appSvc.customProbePath) ? {
  name: '${healthProbeNamePrefix}${appSvc.name}'
  properties: {
    pickHostNameFromBackendHttpSettings: true
    timeout: 30
    interval: 30
    path: appSvc.customProbePath
    protocol: 'Https'
  }
} : {}]
var actualProbesArray = filter(probesArray, p => !empty(p))

resource appGw 'Microsoft.Network/applicationGateways@2022-05-01' = {
  name: appGwName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    enableHttp2: true
    sslPolicy: {
      policyName: 'AppGwSslPolicy20220101'
    }

    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: frontendIpName
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [for port in frontendPorts: {

      name: '${frontendPortNamePrefix}${port}'
      properties: {
        port: port
      }
    }]
    backendAddressPools: [for (appSvc, i) in backendAppSvcs: {
      name: '${backendAddressPoolNamePrefix}${appSvc.name}'
      properties: {
        backendAddresses: [
          {
            fqdn: appSvcsRes[i].properties.enabledHostNames[0]
          }
        ]
      }
    }]
    backendHttpSettingsCollection: [for appSvc in backendAppSvcs: {
      name: '${httpSettingsName}${appSvc.name}'
      // Unfortunately, cannot dynamically add "probe" property, so need to duplicate most of the properties
      properties: !empty(appSvc.customProbePath) ? {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
        probe: {
          id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, '${healthProbeNamePrefix}${appSvc.name}')
        }
      } : {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
      }
    }]
    httpListeners: [for appSvc in backendAppSvcs: {
      name: '${httpListenerNamePrefix}${appSvc.name}'
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, frontendIpName)
        }
        frontendPort: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, '${frontendPortNamePrefix}80')
        }
        hostName: appSvc.hostName
        protocol: 'Http'
      }
    }]
    // Create two routing rules for each site
    requestRoutingRules: [for i in range(0, length(backendAppSvcs) * routingRulesMultiplier): {
      // First length(backendAppSvcs) - 1 iterations create the main routing rules; the second set of iterations create the HTTP redirects if needed
      name: (i < length(backendAppSvcs)) ? '${routingRuleNamePrefix}${backendAppSvcs[i].name}' : '${routingRuleNamePrefix}${backendAppSvcs[i - length(backendAppSvcs)].name}-http-redirect'
      properties: {
        ruleType: 'Basic'
        priority: 100 + i
        httpListener: (i < length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}${backendAppSvcs[i].name}')
        } : {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}${backendAppSvcs[i - length(backendAppSvcs)].name}')
        }
        backendAddressPool: (i < length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, '${backendAddressPoolNamePrefix}${backendAppSvcs[i].name}')
        } : {}
        backendHttpSettings: (i < length(backendAppSvcs)) ? {
          id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, '${httpSettingsName}${backendAppSvcs[i].name}')
        } : {
          // TODO: New backend Http settings for redirect
        }
      }
      // Even iterations are the main routing rule; odd iterations for the redirect rule
      // name: (i % 2 == 0) ? '${routingRuleNamePrefix}${backendAppSvcs[i / 2].name}' : '${routingRuleNamePrefix}${backendAppSvcs[(i / 2) - 1].name}-http-redirect'
      // properties: {
      //   ruleType: 'Basic'
      //   priority: 100 + i
      //   httpListener: (i % 2 == 0) ? {
      //     id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, '${httpListenerNamePrefix}${backendAppSvcs[i / 2].name}')
      //   } : {}
      //   backendAddressPool: (i % 2 == 0) ? {
      //     id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, '${backendAddressPoolNamePrefix}${backendAppSvcs[i / 2].name}')
      //   } : {}
      //   backendHttpSettings: (i % 2 == 0) ? {
      //     id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, '${httpSettingsName}${backendAppSvcs[i / 2].name}')
      //   } : {
      //     // TODO: New backend Http settings for redirect
      //   }
      // }
    }]
    probes: actualProbesArray
  }
  tags: tags
}

output appGwName string = appGwName
