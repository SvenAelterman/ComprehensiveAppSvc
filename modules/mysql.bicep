param location string
param namingStructure string
param delegateSubnetId string
param virtualNetworkId string
param virtualNetworkName string

@secure()
param dbAdminPassword string
param dbAdminUserName string = 'dbadmin'

// Optional parameters (acceptable defaults)
param storageGB int = 20
param databaseName string
param mySqlVersion string = '8.0.21'

// Construct the MySQL server name - must be lowercase
var mySQLServerName = toLower(replace(namingStructure, '{rtype}', 'mysql'))

// Create a private DNS zone to host the MySQL Flexible Server records
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${mySQLServerName}.private.mysql.database.azure.com'
  location: 'global'
}

// Link the private DNS zone to the workload VNet
resource dnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: virtualNetworkName
  parent: dnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: false
  }
}

// Create the MySQL Flexible Server
resource mySQL 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: mySQLServerName
  location: location
  dependsOn: [
    dnsZoneVnetLink
  ]
  sku: {
    name: 'Standard_D2ds_v4'
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: dbAdminUserName
    administratorLoginPassword: dbAdminPassword
    storage: {
      autoGrow: 'Enabled'
      iops: 360
      storageSizeGB: storageGB
    }
    version: mySqlVersion
    backup: {
      geoRedundantBackup: 'Disabled'
      backupRetentionDays: 7
    }
    network: {
      delegatedSubnetResourceId: delegateSubnetId
      privateDnsZoneResourceId: dnsZone.id
    }
  }
}

// Turn off requirement for TLS to connect to MySQL as Craft does not appear to support it
#disable-next-line BCP245
resource dbConfig 'Microsoft.DBForMySql/flexibleServers/configurations@2021-05-01' = {
  name: '${mySQL.name}/require_secure_transport'
  #disable-next-line BCP073
  properties: {
    value: 'OFF'
    source: 'user-override'
  }
}

// Deploy a database
module db 'mysql-db.bicep' = {
  name: 'db'
  params: {
    mySqlName: mySQL.name
    dbName: databaseName
  }
}

output fqdn string = mySQL.properties.fullyQualifiedDomainName
output dbName string = databaseName
output serverName string = mySQLServerName
output id string = mySQL.id
