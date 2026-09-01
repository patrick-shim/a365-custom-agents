targetScope = 'resourceGroup'

type Agent365AgentIds = {
  agenticUser: string
  onBehalfOf: string
}

@minLength(1)
param hostImage string

@minLength(1)
param attractionsImage string

@minLength(1)
param weatherImage string

@minLength(1)
param accommodationImage string

@minLength(1)
param currencyImage string

@minLength(36)
@maxLength(36)
param tenantId string

@minLength(36)
@maxLength(36)
param mcpApplicationId string

@minLength(1)
param mcpAudience string

@minLength(36)
@maxLength(36)
param agent365BlueprintId string

param agent365AgentIds Agent365AgentIds

@minLength(36)
@maxLength(36)
param oboChannelAppId string

param oboOAuthConnectionName string = 'korea-tourist-assistant-obo'

@minLength(3)
@maxLength(20)
param resourceBaseName string = 'koreaexpert'

// Shared Microsoft Foundry account name; the Responses base URL is derived from it.
param foundryAccountName string = 'a365-ai-foundry'

@description('Enables the Azure AI Content Safety Prompt Shields guard on the agent host. The guard is fail-closed, so enable it only once the child identity can reach the Content Safety endpoint.')
param promptShieldEnabled bool = false

@description('Content Safety endpoint for Prompt Shields. Empty derives the Content Safety surface of the referenced multi-service account, so no extra Azure resource is required.')
param promptShieldEndpoint string = ''

var resolvedPromptShieldEndpoint = empty(promptShieldEndpoint)
  ? 'https://${foundryAccountName}.cognitiveservices.azure.com'
  : promptShieldEndpoint

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: 'cae-${resourceBaseName}'
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: 'cr${resourceBaseName}'
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-${resourceBaseName}'
}

resource azureMaps 'Microsoft.Maps/accounts@2023-06-01' existing = {
  name: 'maps-${resourceBaseName}'
}

resource hostIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-agent-${resourceBaseName}'
}

resource attractionsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-attract-${resourceBaseName}'
}

resource weatherIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-weather-${resourceBaseName}'
}

resource accommodationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-stay-${resourceBaseName}'
}

resource currencyIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-fx-${resourceBaseName}'
}

resource currentHost 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-agent-${resourceBaseName}'
}

resource currentAttractions 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-attract-${resourceBaseName}'
}

resource currentWeather 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-weather-${resourceBaseName}'
}

resource currentAccommodation 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-stay-${resourceBaseName}'
}

resource currentCurrency 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-fx-${resourceBaseName}'
}

module attractions './modules/attractions-mcp-container-app.bicep' = {
  name: 'live-attractions'
  params: {
    appName: currentAttractions.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: attractionsIdentity.id
    managedIdentityClientId: attractionsIdentity.properties.clientId
    acrLoginServer: registry.properties.loginServer
    containerImage: attractionsImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    azureMapsClientId: azureMaps.properties.uniqueId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    tags: currentAttractions.tags ?? {}
  }
}

module weather './modules/weather-mcp-container-app.bicep' = {
  name: 'live-weather'
  params: {
    appName: currentWeather.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: weatherIdentity.id
    acrLoginServer: registry.properties.loginServer
    containerImage: weatherImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    tags: currentWeather.tags ?? {}
  }
}

module accommodation './modules/accommodation-mcp-container-app.bicep' = {
  name: 'live-accommodation'
  params: {
    appName: currentAccommodation.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: accommodationIdentity.id
    managedIdentityClientId: accommodationIdentity.properties.clientId
    acrLoginServer: registry.properties.loginServer
    containerImage: accommodationImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    azureMapsClientId: azureMaps.properties.uniqueId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    tags: currentAccommodation.tags ?? {}
  }
}

module currency './modules/currency-mcp-container-app.bicep' = {
  name: 'live-currency'
  params: {
    appName: currentCurrency.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: currencyIdentity.id
    acrLoginServer: registry.properties.loginServer
    containerImage: currencyImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    tags: currentCurrency.tags ?? {}
  }
}

module host './modules/agent-host-container-app.bicep' = {
  name: 'live-agent-host'
  params: {
    appName: currentHost.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: hostIdentity.id
    managedIdentityClientId: hostIdentity.properties.clientId
    acrLoginServer: registry.properties.loginServer
    containerImage: hostImage
    // The account's published endpoint is the cognitiveservices form, which does not
    // serve /openai/v1. The Responses client needs the services.ai.azure.com base.
    foundryEndpoint: 'https://${foundryAccountName}.services.ai.azure.com'
    promptShieldEnabled: promptShieldEnabled
    promptShieldEndpoint: resolvedPromptShieldEndpoint
    tenantId: tenantId
    mcpAudience: mcpAudience
    attractionsFqdn: currentAttractions.properties.configuration.ingress.fqdn
    weatherFqdn: currentWeather.properties.configuration.ingress.fqdn
    accommodationFqdn: currentAccommodation.properties.configuration.ingress.fqdn
    currencyFqdn: currentCurrency.properties.configuration.ingress.fqdn
    agent365BlueprintId: agent365BlueprintId
    agent365AgentIds: agent365AgentIds
    oboChannelAppId: oboChannelAppId
    oboOAuthConnectionName: oboOAuthConnectionName
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    tags: currentHost.tags ?? {}
  }
  dependsOn: [
    attractions
    weather
    accommodation
    currency
  ]
}

output hostUrl string = 'https://${host.outputs.fqdn}'
output updatedContainerAppIds array = [
  host.outputs.id
  attractions.outputs.id
  weather.outputs.id
  accommodation.outputs.id
  currency.outputs.id
]
