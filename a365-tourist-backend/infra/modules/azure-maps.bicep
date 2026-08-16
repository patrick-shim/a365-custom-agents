param accountName string
param tags object

resource account 'Microsoft.Maps/accounts@2023-06-01' = {
  name: accountName
  location: 'global'
  kind: 'Gen2'
  tags: tags
  sku: {
    name: 'G2'
  }
  properties: {
    disableLocalAuth: true
  }
}

output id string = account.id
output clientId string = account.properties.uniqueId
