targetScope = 'resourceGroup'

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

// Korea Expert deploys into its own resource group, in the same subscription as Japan Expert.
// The shared Microsoft Foundry account is reused across both products.
@minLength(1)
param targetResourceGroupName string = 'rg-a365-custom-agent-korea-expert'

var approvedDeploymentScopes = {
  '${toLower(targetResourceGroupName)}': targetResourceGroupName
}
var approvedDeploymentScope = approvedDeploymentScopes[toLower(resourceGroup().name)]

@minLength(3)
@maxLength(20)
param resourceBaseName string = 'koreaexpert'

@minLength(1)
param location string = resourceGroup().location

// Existing Microsoft Foundry (different resource group, same subscription).
// Referenced only; this template never creates, moves, or changes Foundry.
param foundryResourceGroupName string = 'rg-ai-foundry'
param foundryAccountName string = 'a365-ai-foundry'
param foundryProjectName string = 'default'
param foundryModelDeploymentName string = 'gpt-5.6-sol'
param foundryProjectEndpoint string = ''

@description('Object IDs allowed to reach the Foundry model through a delegated OBO turn. Prefer one group object ID.')
param agentUserPrincipalIds string[] = []

@allowed(['User', 'Group', 'ServicePrincipal'])
param agentUserPrincipalType string = 'Group'

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
param oboOAuthConnectionName string = 'korea-expert-obo'

// Azure Bot registration for the OBO Teams and Direct Line channels. Opt-in: the bot is only
// deployed when deployAzureBot is true and every channel prerequisite has been supplied.
param deployAzureBot bool = false
param azureBotName string = 'bot-${resourceBaseName}'
param azureBotDisplayName string = 'Korea Expert'
param azureBotSkuName string = 'F0'
param deployDirectLineChannel bool = true
param deployTeamsChannel bool = true
param deployOboOAuthConnection bool = true
param directLineSiteName string = 'korea-expert-directline'
param directLineTrustedOrigins array = []

@secure()
param oboChannelAppClientSecret string = ''
param oboOAuthScope string = ''

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

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
  'deployment-scope': approvedDeploymentScope
}
var graphTags = [
  'app-onboard-skill:true'
  'app-onboard-session-id:${sessionId}'
  'created-at:${createdAt}'
  'environment:${environmentName}'
  'deployed-by:${deployedBy}'
]
var resolvedFoundryProjectEndpoint = empty(foundryProjectEndpoint)
  ? 'https://${foundryAccountName}.services.ai.azure.com'
  : foundryProjectEndpoint

// Deploying the bot without a channel prerequisite resolves an absent key and fails the
// deployment early rather than registering a half-configured bot.
var botPhaseKeys = {
  valid: azureBotName
}
var botPhaseReady = deployDirectLineChannel && deployTeamsChannel && deployOboOAuthConnection && !empty(oboChannelAppId) && !empty(oboChannelAppClientSecret) && !empty(oboOAuthScope)
var validatedAzureBotName = deployAzureBot ? botPhaseKeys[botPhaseReady ? 'valid' : 'invalid'] : azureBotName

resource existingFoundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: foundryAccountName
  scope: resourceGroup(foundryResourceGroupName)
}

resource existingFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' existing = {
  parent: existingFoundryAccount
  name: foundryProjectName
}

resource existingFoundryModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' existing = {
  parent: existingFoundryAccount
  name: foundryModelDeploymentName
}

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    workspaceName: 'log-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module applicationInsights './modules/application-insights.bicep' = {
  name: 'application-insights'
  params: {
    componentName: 'appi-${resourceBaseName}'
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
  }
}

module containerRegistry './modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    registryName: 'cr${resourceBaseName}'
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
  }
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    vaultName: 'kv-${resourceBaseName}'
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
  params: {
    environmentName: 'cae-${resourceBaseName}'
    location: location
    workspaceName: 'log-${resourceBaseName}'
    tags: tags
  }
  dependsOn: [
    logAnalytics
  ]
}

module azureMaps './modules/azure-maps.bicep' = {
  name: 'azure-maps'
  params: {
    accountName: 'maps-${resourceBaseName}'
    tags: tags
  }
}

module hostManagedIdentity './modules/host-managed-identity.bicep' = {
  name: 'host-managed-identity'
  params: {
    identityName: 'id-agent-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module attractionsManagedIdentity './modules/attractions-managed-identity.bicep' = {
  name: 'attractions-managed-identity'
  params: {
    identityName: 'id-attract-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module weatherManagedIdentity './modules/weather-managed-identity.bicep' = {
  name: 'weather-managed-identity'
  params: {
    identityName: 'id-weather-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module accommodationManagedIdentity './modules/accommodation-managed-identity.bicep' = {
  name: 'accommodation-managed-identity'
  params: {
    identityName: 'id-stay-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module currencyManagedIdentity './modules/currency-managed-identity.bicep' = {
  name: 'currency-managed-identity'
  params: {
    identityName: 'id-fx-${resourceBaseName}'
    location: location
    tags: tags
  }
}

module mcpApiApplication './modules/mcp-api-application.bicep' = {
  name: 'mcp-api-application'
  params: {
    applicationName: 'api-${resourceBaseName}'
    displayName: 'api-${resourceBaseName}'
    tenantId: tenantId
    graphTags: graphTags
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    registryName: 'cr${resourceBaseName}'
    vaultName: 'kv-${resourceBaseName}'
    mapsAccountName: 'maps-${resourceBaseName}'
    deployerObjectId: deployerObjectId
    hostPrincipalId: hostManagedIdentity.outputs.principalId
    attractionsPrincipalId: attractionsManagedIdentity.outputs.principalId
    weatherPrincipalId: weatherManagedIdentity.outputs.principalId
    accommodationPrincipalId: accommodationManagedIdentity.outputs.principalId
    currencyPrincipalId: currencyManagedIdentity.outputs.principalId
    grantAttractionsSecretAccess: false
    grantWeatherSecretAccess: false
    grantCurrencySecretAccess: false
  }
  dependsOn: [
    containerRegistry
    keyVault
    azureMaps
  ]
}

module attractionsMcpContainerApp './modules/attractions-mcp-container-app.bicep' = {
  name: 'attractions-mcp-container-app'
  params: {
    appName: 'ca-attract-${resourceBaseName}'
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
  params: {
    appName: 'ca-weather-${resourceBaseName}'
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
  params: {
    appName: 'ca-stay-${resourceBaseName}'
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
  params: {
    appName: 'ca-fx-${resourceBaseName}'
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
  params: {
    appName: 'ca-agent-${resourceBaseName}'
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: hostManagedIdentity.outputs.id
    managedIdentityClientId: hostManagedIdentity.outputs.clientId
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: containerImage
    foundryEndpoint: resolvedFoundryProjectEndpoint
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

// Foundry data-plane roles are assigned in the shared Foundry resource group.
// The OBO turn calls the model with a delegated token, so it is attributed to the
// signed-in user; every caller therefore needs Foundry data-plane access. Supply a
// group object ID in agentUserPrincipalIds rather than listing individual users.
module foundryRoleAssignments './modules/foundry-role-assignments.bicep' = {
  name: 'foundry-role-assignments'
  scope: resourceGroup(foundryResourceGroupName)
  params: {
    foundryAccountName: foundryAccountName
    agent365AgentPrincipalIds: agent365AgentPrincipalIds
    agentUserPrincipalIds: agentUserPrincipalIds
    agentUserPrincipalType: agentUserPrincipalType
  }
}

var oboMessagingEndpoint = 'https://${agentHostContainerApp.outputs.fqdn}/api/messages/obo'

module azureBot './modules/azure-bot.bicep' = if (deployAzureBot) {
  name: 'azure-bot'
  params: {
    botName: validatedAzureBotName
    displayName: azureBotDisplayName
    messagingEndpoint: oboMessagingEndpoint
    msaAppId: oboChannelAppId
    msaAppTenantId: tenantId
    skuName: azureBotSkuName
    deployDirectLineChannel: deployDirectLineChannel
    deployTeamsChannel: deployTeamsChannel
    deployOAuthConnection: deployOboOAuthConnection
    directLineSiteName: directLineSiteName
    directLineTrustedOrigins: directLineTrustedOrigins
    oauthConnectionName: oboOAuthConnectionName
    oauthClientId: oboChannelAppId
    oauthClientSecret: oboChannelAppClientSecret
    oauthScopes: oboOAuthScope
    tags: tags
  }
}

output resourceGroupName string = resourceGroup().name
output deploymentScope string = approvedDeploymentScope
output agentHostUrl string = 'https://${agentHostContainerApp.outputs.fqdn}'
output oboMessagingEndpoint string = oboMessagingEndpoint
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output keyVaultName string = keyVault.outputs.name
output existingFoundryAccountId string = existingFoundryAccount.id
output existingFoundryProjectId string = existingFoundryProject.id
output existingFoundryModelDeploymentId string = existingFoundryModelDeployment.id
output existingFoundryProjectEndpoint string = resolvedFoundryProjectEndpoint
output hostManagedIdentityClientId string = hostManagedIdentity.outputs.clientId
output hostManagedIdentityPrincipalId string = hostManagedIdentity.outputs.principalId
output mcpApiApplicationId string = mcpApiApplication.outputs.applicationId
output mcpApiAudience string = mcpApiApplication.outputs.audience
output mcpDelegatedScope string = mcpApiApplication.outputs.delegatedScope
output applicationImageRepositories object = {
  agentHost: '${containerRegistry.outputs.loginServer}/korea-expert-agent'
  attractions: '${containerRegistry.outputs.loginServer}/korea-expert-attractions'
  weather: '${containerRegistry.outputs.loginServer}/korea-expert-weather'
  accommodation: '${containerRegistry.outputs.loginServer}/korea-expert-accommodation'
  currency: '${containerRegistry.outputs.loginServer}/korea-expert-currency'
}
