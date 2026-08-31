// Role assignments on the shared Microsoft Foundry account, which lives in its own
// resource group. This module must be deployed with a scope of that resource group;
// assigning from the product resource group silently targets the wrong resource.
param foundryAccountName string

type Agent365AgentPrincipalIds = {
  agenticUser: string
  onBehalfOf: string
}

param agent365AgentPrincipalIds Agent365AgentPrincipalIds

@description('Object IDs that call the model through a delegated OBO token. The OBO turn is attributed to the signed-in user, so each caller needs Foundry data-plane access. Prefer a group object ID over individual users.')
param agentUserPrincipalIds string[] = []

@allowed(['User', 'Group', 'ServicePrincipal'])
param agentUserPrincipalType string = 'Group'

var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: foundryAccountName
}

resource agenticUserFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(agent365AgentPrincipalIds.agenticUser)) {
  name: guid(foundryAccount.id, agent365AgentPrincipalIds.agenticUser, cognitiveServicesOpenAIUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: agent365AgentPrincipalIds.agenticUser
    principalType: 'ServicePrincipal'
  }
}

resource onBehalfOfFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(agent365AgentPrincipalIds.onBehalfOf)) {
  name: guid(foundryAccount.id, agent365AgentPrincipalIds.onBehalfOf, cognitiveServicesOpenAIUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: agent365AgentPrincipalIds.onBehalfOf
    principalType: 'ServicePrincipal'
  }
}

resource agentUserOpenAIUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in agentUserPrincipalIds: {
    name: guid(foundryAccount.id, principalId, cognitiveServicesOpenAIUserRoleId)
    scope: foundryAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
      principalId: principalId
      principalType: agentUserPrincipalType
    }
  }
]

resource agentUserCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in agentUserPrincipalIds: {
    name: guid(foundryAccount.id, principalId, cognitiveServicesUserRoleId)
    scope: foundryAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
      principalId: principalId
      principalType: agentUserPrincipalType
    }
  }
]
