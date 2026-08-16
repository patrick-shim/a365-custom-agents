targetScope = 'subscription'

type Agent365AgentIds = {
  agenticUser: string
  onBehalfOf: string
}

type Agent365AgentPrincipalIds = {
  agenticUser: string
  onBehalfOf: string
}

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
param location string

param sessionId string
param deployedBy string
param createdAt string

@minLength(36)
@maxLength(36)
param deployerObjectId string

@minLength(36)
@maxLength(36)
param tenantId string

param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param attractionsImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param weatherImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param accommodationImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param currencyImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

param agent365BlueprintId string = ''
param agent365AgentIds Agent365AgentIds = {
  agenticUser: ''
  onBehalfOf: ''
}
param agent365AgentPrincipalIds Agent365AgentPrincipalIds = {
  agenticUser: ''
  onBehalfOf: ''
}
param oboChannelAppId string = ''
param oboOAuthConnectionName string = 'seoul-tourist-obo'

@secure()
param ktoServiceKey string = ''

@secure()
param openMeteoApiKey string = ''

@secure()
param openWeatherApiKey string = ''

@secure()
param koreaEximbankAuthKey string = ''

@secure()
param forexRateApiKey string = ''

var resourceGroupName = 'rg-seoultour-dev-kc-ae23'
var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
}
var graphTags = [
  'app-onboard-skill:true'
  'app-onboard-session-id:${sessionId}'
  'created-at:${createdAt}'
  'environment:${environmentName}'
  'deployed-by:${deployedBy}'
]
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: resourceGroup
  params: {
    workspaceName: 'log-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module applicationInsights './modules/application-insights.bicep' = {
  name: 'application-insights'
  scope: resourceGroup
  params: {
    componentName: 'appi-seoultour-dev-kc-ae23'
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
  }
}

module containerRegistry './modules/container-registry.bicep' = {
  name: 'container-registry'
  scope: resourceGroup
  params: {
    registryName: 'crseoultourdevkcae23'
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: resourceGroup
  params: {
    vaultName: 'kv-seoultour-dev-kc-ae23'
    location: location
    tenantId: tenantId
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
    seedKtoServiceKey: false
    seedOpenMeteoApiKey: false
    seedOpenWeatherApiKey: false
    seedKoreaEximbankAuthKey: false
    seedForexRateApiKey: false
    ktoServiceKey: ktoServiceKey
    openMeteoApiKey: openMeteoApiKey
    openWeatherApiKey: openWeatherApiKey
    koreaEximbankAuthKey: koreaEximbankAuthKey
    forexRateApiKey: forexRateApiKey
  }
}

module containerAppEnvironment './modules/container-app-environment.bicep' = {
  name: 'container-app-environment'
  scope: resourceGroup
  params: {
    environmentName: 'cae-seoultour-dev-kc-ae23'
    location: location
    workspaceName: 'log-seoultour-dev-kc-ae23'
    tags: tags
  }
  dependsOn: [
    logAnalytics
  ]
}

module azureMaps './modules/azure-maps.bicep' = {
  name: 'azure-maps'
  scope: resourceGroup
  params: {
    accountName: 'maps-seoultour-dev-kc-ae23'
    tags: tags
  }
}

module hostManagedIdentity './modules/host-managed-identity.bicep' = {
  name: 'host-managed-identity'
  scope: resourceGroup
  params: {
    identityName: 'id-agent-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module attractionsManagedIdentity './modules/attractions-managed-identity.bicep' = {
  name: 'attractions-managed-identity'
  scope: resourceGroup
  params: {
    identityName: 'id-attract-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module weatherManagedIdentity './modules/weather-managed-identity.bicep' = {
  name: 'weather-managed-identity'
  scope: resourceGroup
  params: {
    identityName: 'id-weather-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module accommodationManagedIdentity './modules/accommodation-managed-identity.bicep' = {
  name: 'accommodation-managed-identity'
  scope: resourceGroup
  params: {
    identityName: 'id-stay-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module currencyManagedIdentity './modules/currency-managed-identity.bicep' = {
  name: 'currency-managed-identity'
  scope: resourceGroup
  params: {
    identityName: 'id-fx-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module foundryResource './modules/foundry-resource.bicep' = {
  name: 'foundry-resource'
  scope: resourceGroup
  params: {
    accountName: 'fdy-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
}

module foundryProject './modules/foundry-project.bicep' = {
  name: 'foundry-project'
  scope: resourceGroup
  params: {
    accountName: 'fdy-seoultour-dev-kc-ae23'
    projectName: 'proj-seoultour-dev-kc-ae23'
    location: location
    tags: tags
  }
  dependsOn: [
    foundryResource
  ]
}

module foundryModelDeployment './modules/foundry-model-deployment.bicep' = {
  name: 'foundry-model-deployment'
  scope: resourceGroup
  params: {
    accountName: 'fdy-seoultour-dev-kc-ae23'
    deploymentName: 'gpt-5.6-sol'
    tags: tags
  }
  dependsOn: [
    foundryResource
  ]
}

module mcpApiApplication './modules/mcp-api-application.bicep' = {
  name: 'mcp-api-application'
  scope: resourceGroup
  params: {
    applicationName: 'api-seoultour-dev-kc-ae23'
    displayName: 'api-seoultour-dev-kc-ae23'
    tenantId: tenantId
    graphTags: graphTags
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  scope: resourceGroup
  params: {
    registryName: 'crseoultourdevkcae23'
    vaultName: 'kv-seoultour-dev-kc-ae23'
    mapsAccountName: 'maps-seoultour-dev-kc-ae23'
    foundryAccountName: 'fdy-seoultour-dev-kc-ae23'
    deployerObjectId: deployerObjectId
    hostPrincipalId: hostManagedIdentity.outputs.principalId
    attractionsPrincipalId: attractionsManagedIdentity.outputs.principalId
    weatherPrincipalId: weatherManagedIdentity.outputs.principalId
    accommodationPrincipalId: accommodationManagedIdentity.outputs.principalId
    currencyPrincipalId: currencyManagedIdentity.outputs.principalId
    agent365AgentPrincipalIds: agent365AgentPrincipalIds
    grantAttractionsSecretAccess: false
    grantWeatherSecretAccess: false
    grantCurrencySecretAccess: false
  }
  dependsOn: [
    containerRegistry
    keyVault
    foundryResource
    azureMaps
  ]
}

module attractionsMcpContainerApp './modules/attractions-mcp-container-app.bicep' = {
  name: 'attractions-mcp-container-app'
  scope: resourceGroup
  params: {
    appName: 'ca-attract-seoultour-dev-kc-ae23'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: attractionsManagedIdentity.outputs.id
    managedIdentityClientId: attractionsManagedIdentity.outputs.clientId
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: attractionsImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    azureMapsClientId: azureMaps.outputs.clientId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module weatherMcpContainerApp './modules/weather-mcp-container-app.bicep' = {
  name: 'weather-mcp-container-app'
  scope: resourceGroup
  params: {
    appName: 'ca-weather-seoultour-dev-kc-ae23'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: weatherManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: weatherImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module accommodationMcpContainerApp './modules/accommodation-mcp-container-app.bicep' = {
  name: 'accommodation-mcp-container-app'
  scope: resourceGroup
  params: {
    appName: 'ca-stay-seoultour-dev-kc-ae23'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: accommodationManagedIdentity.outputs.id
    managedIdentityClientId: accommodationManagedIdentity.outputs.clientId
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: accommodationImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    azureMapsClientId: azureMaps.outputs.clientId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module currencyMcpContainerApp './modules/currency-mcp-container-app.bicep' = {
  name: 'currency-mcp-container-app'
  scope: resourceGroup
  params: {
    appName: 'ca-fx-seoultour-dev-kc-ae23'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: currencyManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: currencyImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module agentHostContainerApp './modules/agent-host-container-app.bicep' = {
  name: 'agent-host-container-app'
  scope: resourceGroup
  params: {
    appName: 'ca-agent-seoultour-dev-kc-ae23'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: hostManagedIdentity.outputs.id
    managedIdentityClientId: hostManagedIdentity.outputs.clientId
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: containerImage
    foundryEndpoint: foundryResource.outputs.endpoint
    tenantId: tenantId
    mcpAudience: mcpApiApplication.outputs.audience
    attractionsFqdn: attractionsMcpContainerApp.outputs.fqdn
    weatherFqdn: weatherMcpContainerApp.outputs.fqdn
    accommodationFqdn: accommodationMcpContainerApp.outputs.fqdn
    currencyFqdn: currencyMcpContainerApp.outputs.fqdn
    agent365BlueprintId: agent365BlueprintId
    agent365AgentIds: agent365AgentIds
    oboChannelAppId: oboChannelAppId
    oboOAuthConnectionName: oboOAuthConnectionName
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

output resourceGroupName string = resourceGroup.name
output agentHostUrl string = 'https://${agentHostContainerApp.outputs.fqdn}'
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output keyVaultName string = keyVault.outputs.name
output foundryProjectId string = foundryProject.outputs.id
output hostManagedIdentityClientId string = hostManagedIdentity.outputs.clientId
output hostManagedIdentityPrincipalId string = hostManagedIdentity.outputs.principalId
output mcpApiApplicationId string = mcpApiApplication.outputs.applicationId
output mcpApiAudience string = mcpApiApplication.outputs.audience
output mcpDelegatedScope string = mcpApiApplication.outputs.delegatedScope
output applicationImageRepositories object = {
  agentHost: '${containerRegistry.outputs.loginServer}/seoul-tourist-agent'
  attractions: '${containerRegistry.outputs.loginServer}/seoul-tourist-attractions'
  weather: '${containerRegistry.outputs.loginServer}/seoul-tourist-weather'
  accommodation: '${containerRegistry.outputs.loginServer}/seoul-tourist-accommodation'
  currency: '${containerRegistry.outputs.loginServer}/seoul-tourist-currency'
}
