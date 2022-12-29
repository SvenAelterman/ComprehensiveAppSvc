param mySqlName string
param dbName string

resource db 'Microsoft.DBforMySQL/flexibleServers/databases@2021-05-01' = {
  name: '${mySqlName}/${dbName}'
  properties: {
    charset: 'utf8'
    collation: 'utf8_general_ci'
  }
}
