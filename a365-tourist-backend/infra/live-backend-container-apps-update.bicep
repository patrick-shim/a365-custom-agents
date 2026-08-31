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

param oboOAuthConnectionName string = 'seoul-tourist-obo'

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: 'cae-seoultour-dev-kc-ae23'
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: 'crseoultourdevkcae23'
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-seoultour-dev-kc-ae23'
}

resource foundry 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: 'fdy-seoultour-dev-kc-ae23'
}

resource azureMaps 'Microsoft.Maps/accounts@2023-06-01' existing = {
  name: 'maps-seoultour-dev-kc-ae23'
}

resource hostIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-agent-seoultour-dev-kc-ae23'
}

resource attractionsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-attract-seoultour-dev-kc-ae23'
}

resource weatherIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-weather-seoultour-dev-kc-ae23'
}

resource accommodationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-stay-seoultour-dev-kc-ae23'
}

resource currencyIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-fx-seoultour-dev-kc-ae23'
}

resource currentHost 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-agent-seoultour-dev-kc-ae23'
}

resource currentAttractions 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-attract-seoultour-dev-kc-ae23'
}

resource currentWeather 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-weather-seoultour-dev-kc-ae23'
}

resource currentAccommodation 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-stay-seoultour-dev-kc-ae23'
}

resource currentCurrency 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: 'ca-fx-seoultour-dev-kc-ae23'
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
    foundryEndpoint: foundry.properties.endpoint
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
