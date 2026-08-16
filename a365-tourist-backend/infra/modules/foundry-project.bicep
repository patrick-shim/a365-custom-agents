param accountName string
param projectName string
param location string
param tags object

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Seoul Tourist Agent'
    description: 'Korea Central Microsoft Foundry project for the Seoul Tourist Agent.'
  }
}

output id string = project.id
output principalId string = project.identity.principalId
