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

// Keyless Foundry Responses inference is authorized by Cognitive Services User at the account
// scope. The retired OpenAI-specific data-plane role is deliberately not assigned here;
// `Test-Deployment.ps1` fails the build when a template references it by name or by role ID.
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: foundryAccountName
}

resource agenticUserFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(agent365AgentPrincipalIds.agenticUser)) {
  name: guid(foundryAccount.id, agent365AgentPrincipalIds.agenticUser, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: agent365AgentPrincipalIds.agenticUser
    principalType: 'ServicePrincipal'
  }
}

resource onBehalfOfFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(agent365AgentPrincipalIds.onBehalfOf)) {
  name: guid(foundryAccount.id, agent365AgentPrincipalIds.onBehalfOf, cognitiveServicesUserRoleId)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: agent365AgentPrincipalIds.onBehalfOf
    principalType: 'ServicePrincipal'
  }
}

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
