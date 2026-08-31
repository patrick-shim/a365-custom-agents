param accountName string
param deploymentName string
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: account
  name: deploymentName
  tags: tags
  sku: {
    name: 'DataZoneStandard'
    capacity: 100
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5.6-sol'
      version: '2026-07-09'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

output id string = deployment.id
