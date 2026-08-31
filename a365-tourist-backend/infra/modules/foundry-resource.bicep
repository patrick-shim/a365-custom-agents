param accountName string
param location string
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: accountName
  location: location
  kind: 'AIServices'
  tags: tags
  sku: {
    name: 'S0'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

output id string = account.id
output endpoint string = account.properties.endpoint
