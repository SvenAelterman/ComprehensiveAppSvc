param keyVaultName string

@description('{ secret1: { name: "", description: "(optional)", value: "" }, secret2: {...} }')
@secure()
param secrets object

@description('Include the - at the end if desired')
param secretNamePrefix string = ''

// This is not a secret value
#disable-next-line secure-secrets-in-params
param secretValidityPeriod string = 'P2Y'

param expiryDateTime string = !empty(secretValidityPeriod) ? dateTimeAdd(utcNow(), secretValidityPeriod) : ''

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

var secretsArray = items(secrets)

resource secret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = [for secret in secretsArray: {
  name: '${secretNamePrefix}${replace(secret.value.name, '_', '')}'
  parent: keyVault
  properties: {
    contentType: contains(secret.value, 'description') ? secret.value.description : ''
    value: contains(secret.value, 'value') ? secret.value.value : ''
    attributes: {
      enabled: true
      exp: !empty(secretValidityPeriod) ? dateTimeToEpoch(expiryDateTime) : null
    }
  }
}]

// Output the names of the created secrets to enable referencing them from App Svc
// This is the shape expected by the appSvcKeyVaultRefs module
output createdSecrets array = [for i in range(0, length(secretsArray)): {
  '${secretsArray[i].value.name}': secret[i].name
}]
output secretsCount int = length(secretsArray)
