// Least-privilege role assignments for the Japan Tourist Assistant backend.
//
// Every assignment in this module is scoped to a resource in this template's own resource group.
// The active MCP data sources are credential-free public APIs, so no workload holds a data-plane
// role beyond registry pull. Foundry data-plane access for the Agent 365 child identities lives in
// the Foundry resource group and is therefore an explicit, separately approved runbook step.
param registryName string
param hostPrincipalId string
param attractionsPrincipalId string
param weatherPrincipalId string
param accommodationPrincipalId string
param currencyPrincipalId string

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource hostAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, hostPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: hostPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource attractionsAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, attractionsPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: attractionsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource weatherAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, weatherPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: weatherPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource accommodationAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, accommodationPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: accommodationPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource currencyAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, currencyPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: currencyPrincipalId
    principalType: 'ServicePrincipal'
  }
}
