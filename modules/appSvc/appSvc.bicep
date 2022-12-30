param webAppName string
param location string
param subnetId string
param appSvcPlanId string
@description('The required FedRAMP logs will be sent to this workspace.')
param logAnalyticsWorkspaceId string
param tags object

param appSettings object = {}
@description('Specifies the Application Insights workspace to use. { instrumentationKey: "", connectionString: "" }')
param appInsights object = {}

param allowAccessSubnetIds array = []

var linuxFx = 'NODE|16-lts'

var hiddenRelatedTag = {
  'hidden-related:${appSvcPlanId}': 'empty'
}
// Merge the hidden tag with the parameter values
var actualTags = union(tags, hiddenRelatedTag)

var appInsightsInstrumentationKeySetting = (!empty(appInsights)) ? {
  APPINSIGHTS_INSTRUMENTATIONKEY: appInsights.instrumentationKey
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.connectionString
  ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
  XDT_MicrosoftApplicationInsights_Mode: 'default'
} : {}

// Merge the setting with the parameter values
var actualAppSettings = union(appSettings, appInsightsInstrumentationKeySetting)

// Define the IP security restrictions for the App Service
var ipSecurityRestrictions = [for (subnetId, i) in allowAccessSubnetIds: {
  action: 'Allow'
  tag: 'Default'
  priority: 100 + i
  vnetSubnetResourceId: subnetId
}]

resource appSvc 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  identity: {
    // Create a system assigned managed identity to read Key Vault secrets and pull container images
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appSvcPlanId
    virtualNetworkSubnetId: subnetId
    vnetRouteAllEnabled: true // This is the default value
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'

    siteConfig: {
      http20Enabled: true
      vnetRouteAllEnabled: true
      alwaysOn: true
      linuxFxVersion: linuxFx
      acrUseManagedIdentityCreds: true
      ftpsState: 'FtpsOnly'
      use32BitWorkerProcess: false

      logsDirectorySizeLimit: 35
      httpLoggingEnabled: true

      // Loop through all provided application settings
      appSettings: [for setting in items(actualAppSettings): {
        name: setting.key
        value: setting.value
      }]

      ipSecurityRestrictions: ipSecurityRestrictions

      #disable-next-line BCP037
      ipSecurityRestrictionsDefaultAction: empty(allowAccessSubnetIds) ? 'Allow' : 'Deny'

      // Do not use the same IP restrictions for the SCM site
      scmIpSecurityRestrictionsUseMain: false
    }
  }
  tags: actualTags
}

var appServiceLogCategories = [
  'AppServiceHttpLogs'
  'AppServiceConsoleLogs'
  'AppServiceAppLogs'
  'AppServiceAuditLogs'
  'AppServiceIPSecAuditLogs'
  'AppServicePlatformLogs'
]

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'Logging - ${appSvc.name}'
  scope: appSvc
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [for category in appServiceLogCategories: {
      enabled: true
      category: category
      retentionPolicy: {
        days: 365
        enabled: true
      }
    }]
  }
}

// LATER: Configure health check endpoint

output appSvcName string = appSvc.name
output principalId string = appSvc.identity.principalId
output actualIpSecurityRestrictions array = ipSecurityRestrictions
