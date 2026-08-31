// Japan Expert existing-backend update and rollback wrapper.
//
// Scope contract (M8):
//   * Resource-group scoped, so ARM cannot create a resource group from it.
//   * It updates only the five existing Container Apps in the deployment's own resource group.
//   * Every other resource it touches is an existing reference, including the cross-resource-group
//     Microsoft Foundry account.
//   * Update and rollback use the same template with two separately validated parameter sets.
targetScope = 'resourceGroup'

type Agent365AgentIds = {
  agenticUser: string
  onBehalfOf: string
}

type ContainerAppSetting = {
  name: string
  value: string
}

@description('The only approved backend resource group. The deployment fails if it targets any other group.')
@allowed([
  'rg-a365-custom-agents'
])
param targetResourceGroupName string = 'rg-a365-custom-agents'

// Deployment-time scope guard. The lookup below has exactly one key, so a deployment that targets
// any other resource group fails during ARM validation with an error that names the approved group.
var approvedDeploymentScopes = {
  '${toLower(targetResourceGroupName)}': targetResourceGroupName
}
var approvedDeploymentScope = approvedDeploymentScopes[toLower(resourceGroup().name)]

@description('Deterministic Japan Expert resource token. Lowercase alphanumeric only.')
@minLength(3)
@maxLength(16)
param resourceBaseName string = 'japanexpert'

@description('Existing Container Apps managed environment name.')
@minLength(2)
param containerAppEnvironmentName string = 'cae-${resourceBaseName}'

@description('Existing container registry name.')
@minLength(5)
param containerRegistryName string = 'cr${resourceBaseName}'

@description('Existing Application Insights component name.')
@minLength(1)
param applicationInsightsName string = 'appi-${resourceBaseName}'

@description('Existing agent host user-assigned managed identity name.')
@minLength(3)
param hostIdentityName string = 'id-agent-${resourceBaseName}'

@description('Existing attractions MCP user-assigned managed identity name.')
@minLength(3)
param attractionsIdentityName string = 'id-attract-${resourceBaseName}'

@description('Existing weather MCP user-assigned managed identity name.')
@minLength(3)
param weatherIdentityName string = 'id-weather-${resourceBaseName}'

@description('Existing accommodation MCP user-assigned managed identity name.')
@minLength(3)
param accommodationIdentityName string = 'id-stay-${resourceBaseName}'

@description('Existing currency MCP user-assigned managed identity name.')
@minLength(3)
param currencyIdentityName string = 'id-fx-${resourceBaseName}'

@description('Existing agent host Container App name.')
@minLength(2)
@maxLength(32)
param hostAppName string = 'ca-agent-${resourceBaseName}'

@description('Existing attractions MCP Container App name.')
@minLength(2)
@maxLength(32)
param attractionsAppName string = 'ca-attract-${resourceBaseName}'

@description('Existing weather MCP Container App name.')
@minLength(2)
@maxLength(32)
param weatherAppName string = 'ca-weather-${resourceBaseName}'

@description('Existing accommodation MCP Container App name.')
@minLength(2)
@maxLength(32)
param accommodationAppName string = 'ca-stay-${resourceBaseName}'

@description('Existing currency MCP Container App name.')
@minLength(2)
@maxLength(32)
param currencyAppName string = 'ca-fx-${resourceBaseName}'

@description('Existing Foundry account name. The OpenAI-compatible endpoint is derived from it.')
@minLength(2)
param foundryAccountName string = 'a365-ai-foundry'

@description('Existing Foundry model deployment name used by the agent host.')
@minLength(2)
param foundryModelDeploymentName string = 'gpt-5.6-sol'

@description('Optional Foundry endpoint override. Empty derives it from the existing account name.')
param foundryProjectEndpoint string = ''

@description('Immutable agent host image reference, normally a digest.')
@minLength(1)
param hostImage string

@description('Immutable attractions MCP image reference, normally a digest.')
@minLength(1)
param attractionsImage string

@description('Immutable weather MCP image reference, normally a digest.')
@minLength(1)
param weatherImage string

@description('Immutable accommodation MCP image reference, normally a digest.')
@minLength(1)
param accommodationImage string

@description('Immutable currency MCP image reference, normally a digest.')
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

param oboOAuthConnectionName string = 'japan-expert-obo'

// MCP provider configuration. Section and property names mirror the MCP service options classes.
// Keep these defaults identical to infra/main.bicep so an update or rollback never silently
// re-points a data source.

@description('User-Agent sent to OpenStreetMap Overpass and MET Norway. Must name the product and carry a public contact reference; never a mailbox or tenant identifier.')
@minLength(16)
param mcpUserAgent string = 'JapanExpertMcp/1.0 (+https://github.com/patrick-shim/a365-custom-agents)'

@description('OpenStreetMap Overpass interpreter endpoint used for Japan place search.')
@minLength(1)
param overpassEndpoint string = 'https://overpass-api.de/api/interpreter'

@description('Japan Meteorological Agency bosai forecast JSON prefix. Must end with a slash.')
@minLength(1)
param jmaForecastBaseAddress string = 'https://www.jma.go.jp/bosai/forecast/data/forecast/'

@description('Japan Meteorological Agency XML Atom alert feed address.')
@minLength(1)
param jmaAlertFeedAddress string = 'https://www.data.jma.go.jp/developer/xml/feed/extra.xml'

@description('Enables the guarded JMA bosai forecast source.')
param jmaForecastEnabled bool = true

@description('MET Norway Locationforecast base address used as the labelled current-conditions fallback. Must end with a slash.')
@minLength(1)
param metNorwayBaseAddress string = 'https://api.met.no/weatherapi/locationforecast/2.0/'

@description('Enables the MET Norway current-conditions fallback.')
param metNorwayEnabled bool = true

@description('Frankfurter v2 base address. Must end with a slash.')
@minLength(1)
param frankfurterBaseAddress string = 'https://api.frankfurter.dev/v2/'

@description('Frankfurter provider pin. ECB keeps every observation traceable to published central-bank reference rates.')
@minLength(1)
param frankfurterProviders string = 'ECB'

@description('Enables the Frankfurter exchange-rate source.')
param frankfurterEnabled bool = true

@description('European Central Bank SDMX data service base address used as the direct fallback. Must end with a slash.')
@minLength(1)
param ecbSdmxBaseAddress string = 'https://data-api.ecb.europa.eu/service/data/EXR/'

@description('Enables the direct ECB SDMX fallback.')
param ecbSdmxEnabled bool = true

@description('Overpass place-result cache lifetime in seconds. Long by design so a public community endpoint is not called once per turn. Zero disables caching.')
@minValue(0)
@maxValue(604800)
param placeSearchCacheTtlSeconds int = 86400

@description('JMA prefecture forecast cache lifetime in seconds.')
@minValue(0)
@maxValue(86400)
param weatherForecastCacheTtlSeconds int = 1800

@description('JMA warning and advisory cache lifetime in seconds. Deliberately short so a newly issued warning is never withheld.')
@minValue(0)
@maxValue(3600)
param weatherAlertCacheTtlSeconds int = 60

@description('MET Norway current-conditions cache lifetime in seconds.')
@minValue(0)
@maxValue(86400)
param weatherCurrentCacheTtlSeconds int = 600

@description('Exchange-rate cache lifetime in seconds. Reference rates publish once per business day.')
@minValue(0)
@maxValue(604800)
param exchangeRateCacheTtlSeconds int = 21600

param attractionsProviderSettings ContainerAppSetting[] = [
  {
    name: 'Overpass__Endpoint'
    value: overpassEndpoint
  }
  {
    name: 'Overpass__UserAgent'
    value: mcpUserAgent
  }
  {
    name: 'Cache__TtlSeconds'
    value: string(placeSearchCacheTtlSeconds)
  }
]

param weatherProviderSettings ContainerAppSetting[] = [
  {
    name: 'Jma__ForecastEnabled'
    value: string(jmaForecastEnabled)
  }
  {
    name: 'Jma__ForecastBaseAddress'
    value: jmaForecastBaseAddress
  }
  {
    name: 'Jma__AlertFeedAddress'
    value: jmaAlertFeedAddress
  }
  {
    name: 'MetNorway__Enabled'
    value: string(metNorwayEnabled)
  }
  {
    name: 'MetNorway__BaseAddress'
    value: metNorwayBaseAddress
  }
  {
    name: 'MetNorway__UserAgent'
    value: mcpUserAgent
  }
  {
    name: 'MetNorway__CoordinateDecimals'
    value: '4'
  }
  {
    name: 'Cache__ForecastTtlSeconds'
    value: string(weatherForecastCacheTtlSeconds)
  }
  {
    name: 'Cache__AlertTtlSeconds'
    value: string(weatherAlertCacheTtlSeconds)
  }
  {
    name: 'Cache__CurrentTtlSeconds'
    value: string(weatherCurrentCacheTtlSeconds)
  }
]

param accommodationProviderSettings ContainerAppSetting[] = [
  {
    name: 'Overpass__Endpoint'
    value: overpassEndpoint
  }
  {
    name: 'Overpass__UserAgent'
    value: mcpUserAgent
  }
  {
    name: 'Cache__TtlSeconds'
    value: string(placeSearchCacheTtlSeconds)
  }
]

param currencyProviderSettings ContainerAppSetting[] = [
  {
    name: 'Frankfurter__Enabled'
    value: string(frankfurterEnabled)
  }
  {
    name: 'Frankfurter__BaseAddress'
    value: frankfurterBaseAddress
  }
  {
    name: 'Frankfurter__Providers'
    value: frankfurterProviders
  }
  {
    name: 'EcbSdmx__Enabled'
    value: string(ecbSdmxEnabled)
  }
  {
    name: 'EcbSdmx__BaseAddress'
    value: ecbSdmxBaseAddress
  }
  {
    name: 'Cache__TtlSeconds'
    value: string(exchangeRateCacheTtlSeconds)
  }
]

resource environment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: containerAppEnvironmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: containerRegistryName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource hostIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: hostIdentityName
}

resource attractionsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: attractionsIdentityName
}

resource weatherIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: weatherIdentityName
}

resource accommodationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: accommodationIdentityName
}

resource currencyIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: currencyIdentityName
}

resource currentHost 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: hostAppName
}

resource currentAttractions 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: attractionsAppName
}

resource currentWeather 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: weatherAppName
}

resource currentAccommodation 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: accommodationAppName
}

resource currentCurrency 'Microsoft.App/containerApps@2026-01-01' existing = {
  name: currencyAppName
}

// The gpt-5.6-sol deployment is a Responses API model reached through the account-level
// OpenAI-compatible surface, so the host receives the Foundry account endpoint and the deployment
// name only, never a project route, a raw /openai/responses path, or an api-version.
var resolvedFoundryProjectEndpoint = empty(foundryProjectEndpoint)
  ? 'https://${foundryAccountName}.services.ai.azure.com'
  : foundryProjectEndpoint

module attractions './modules/attractions-mcp-container-app.bicep' = {
  name: 'live-attractions'
  params: {
    appName: currentAttractions.name
    location: resourceGroup().location
    environmentId: environment.id
    managedIdentityResourceId: attractionsIdentity.id
    acrLoginServer: registry.properties.loginServer
    containerImage: attractionsImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    providerSettings: attractionsProviderSettings
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
    providerSettings: weatherProviderSettings
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
    acrLoginServer: registry.properties.loginServer
    containerImage: accommodationImage
    tenantId: tenantId
    mcpTokenAudience: mcpApplicationId
    applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
    providerSettings: accommodationProviderSettings
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
    providerSettings: currencyProviderSettings
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
    foundryProjectEndpoint: resolvedFoundryProjectEndpoint
    foundryModelDeploymentName: foundryModelDeploymentName
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

output deploymentResourceGroupName string = resourceGroup().name
output deploymentScope string = approvedDeploymentScope
output hostUrl string = 'https://${host.outputs.fqdn}'
output updatedContainerAppIds array = [
  host.outputs.id
  attractions.outputs.id
  weather.outputs.id
  accommodation.outputs.id
  currency.outputs.id
]
