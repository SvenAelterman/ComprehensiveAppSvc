param location string
param mySqlServerName string
param delegateSubnetId string
param dnsZoneId string
param tags object

@secure()
param dbAdminPassword string
param dbAdminUserName string = 'dbadmin'

// Optional parameters (acceptable defaults)
param storageGB int = 20
param databaseName string
param mySqlVersion string = '8.0.21'
param disableTlsRequirement bool = false

// Create the MySQL Flexible Server
resource mySql 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: mySqlServerName
  location: location
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
      privateDnsZoneResourceId: dnsZoneId
    }
  }
  tags: tags
}

// Turn off requirement for TLS to connect to MySQL
#disable-next-line BCP245
resource dbConfig 'Microsoft.DBforMySQL/flexibleServers/configurations@2021-12-01-preview' = if (disableTlsRequirement) {
  name: 'require_secure_transport'
  parent: mySql
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
    mySqlName: mySql.name
    dbName: databaseName
  }
}

output fqdn string = mySql.properties.fullyQualifiedDomainName
output dbName string = databaseName
output serverName string = mySqlServerName
output id string = mySql.id
