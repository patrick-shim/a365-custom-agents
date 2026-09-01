// Japan Tourist Assistant shared backend bootstrap.
//
// Scope contract (M8):
//   * This template is resource-group scoped, so ARM cannot create a resource group from it.
//   * Every Azure resource it creates is in the deployment's own resource group. The MCP API
//     application and service principal are explicit Microsoft Graph tenant objects.
//   * The existing Microsoft Foundry account lives in another resource group and is referenced
//     as an existing resource only. This template never creates, moves, or changes Foundry.
//   * Cross-resource-group role assignments (Foundry data-plane access for the Agent 365 child
//     identities) are intentionally NOT declared here. They are an explicit, separately approved
//     runbook step so this template keeps a single-resource-group mutation boundary.
targetScope = 'resourceGroup'

type Agent365AgentIds = {
  agenticUser: string
  onBehalfOf: string
}

type ContainerAppSetting = {
  name: string
  value: string
}

// ---------------------------------------------------------------------------
// Deployment scope
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Naming and tagging
// ---------------------------------------------------------------------------

@description('Deterministic Japan Tourist Assistant resource token. Lowercase alphanumeric only; every resource name defaults from this value.')
@minLength(3)
@maxLength(16)
param resourceBaseName string = 'japanexpert'

@description('Environment tag value.')
@minLength(1)
@maxLength(64)
param environmentName string = resourceBaseName

@description('Azure region for regional resources. Defaults to the existing resource group location.')
@minLength(1)
param location string = resourceGroup().location

@description('Optional non-secret deployment actor recorded as a tag.')
param deployedBy string = ''

@description('Optional non-secret deployment session identifier recorded as a tag.')
param sessionId string = ''

@description('Optional ISO-8601 deployment timestamp recorded as a tag.')
param createdAt string = ''

@description('Entra tenant ID used for token validation and Purview. Supply at deployment time.')
@minLength(36)
@maxLength(36)
param tenantId string

@description('Log Analytics workspace name.')
@minLength(4)
@maxLength(63)
param logAnalyticsWorkspaceName string = 'log-${resourceBaseName}'

@description('Application Insights component name.')
@minLength(1)
@maxLength(255)
param applicationInsightsName string = 'appi-${resourceBaseName}'

@description('Container registry name. Alphanumeric only and globally unique.')
@minLength(5)
@maxLength(50)
param containerRegistryName string = 'cr${resourceBaseName}'

@description('Container registry SKU. Basic is sufficient for this single-region public-ingress workload.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySkuName string = 'Basic'

@description('Container Apps managed environment name.')
@minLength(2)
@maxLength(60)
param containerAppEnvironmentName string = 'cae-${resourceBaseName}'

@description('Agent host user-assigned managed identity name.')
@minLength(3)
@maxLength(128)
param hostIdentityName string = 'id-agent-${resourceBaseName}'

@description('Attractions MCP user-assigned managed identity name.')
@minLength(3)
@maxLength(128)
param attractionsIdentityName string = 'id-attract-${resourceBaseName}'

@description('Weather MCP user-assigned managed identity name.')
@minLength(3)
@maxLength(128)
param weatherIdentityName string = 'id-weather-${resourceBaseName}'

@description('Accommodation MCP user-assigned managed identity name.')
@minLength(3)
@maxLength(128)
param accommodationIdentityName string = 'id-stay-${resourceBaseName}'

@description('Currency MCP user-assigned managed identity name.')
@minLength(3)
@maxLength(128)
param currencyIdentityName string = 'id-fx-${resourceBaseName}'

@description('Agent host Container App name.')
@minLength(2)
@maxLength(32)
param hostAppName string = 'ca-agent-${resourceBaseName}'

@description('Attractions MCP Container App name.')
@minLength(2)
@maxLength(32)
param attractionsAppName string = 'ca-attract-${resourceBaseName}'

@description('Weather MCP Container App name.')
@minLength(2)
@maxLength(32)
param weatherAppName string = 'ca-weather-${resourceBaseName}'

@description('Accommodation MCP Container App name.')
@minLength(2)
@maxLength(32)
param accommodationAppName string = 'ca-stay-${resourceBaseName}'

@description('Currency MCP Container App name.')
@minLength(2)
@maxLength(32)
param currencyAppName string = 'ca-fx-${resourceBaseName}'

@description('Entra application name for the protected MCP resource API.')
@minLength(1)
@maxLength(120)
param mcpApiApplicationName string = 'api-${resourceBaseName}'

@description('Container registry repository prefix for the host and MCP images.')
@minLength(1)
param imageRepositoryPrefix string = 'japan-expert'

// ---------------------------------------------------------------------------
// Existing Microsoft Foundry (different resource group, same subscription)
// ---------------------------------------------------------------------------

@description('Resource group of the existing Foundry account. Referenced only; never created here.')
@minLength(1)
param foundryResourceGroupName string = 'rg-ai-foundry'

@description('Existing Foundry account name.')
@minLength(2)
param foundryAccountName string = 'a365-ai-foundry'

@description('Existing Foundry project name.')
@minLength(2)
param foundryProjectName string = 'default'

@description('Existing Foundry model deployment name used by the agent host.')
@minLength(2)
param foundryModelDeploymentName string = 'gpt-5.6-sol'

@description('Optional Foundry project endpoint override. Empty derives it from the existing account and project names.')
param foundryProjectEndpoint string = ''

@description('Object IDs allowed to reach the Foundry model through a delegated OBO turn. Prefer one group object ID.')
param agentUserPrincipalIds string[] = []

@allowed(['User', 'Group', 'ServicePrincipal'])
param agentUserPrincipalType string = 'Group'

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param attractionsImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param weatherImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param accommodationImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param currencyImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// ---------------------------------------------------------------------------
// Agent 365 and channel wiring (protected operational values, never committed)
// ---------------------------------------------------------------------------

param agent365BlueprintId string = ''
param agent365AgentIds Agent365AgentIds = {
  agenticUser: ''
  onBehalfOf: ''
}

@description('Service principal object IDs of the Agent 365 child identities, used for Foundry data-plane role assignments.')
param agent365AgentPrincipalIds Agent365AgentIds = {
  agenticUser: ''
  onBehalfOf: ''
}
param oboChannelAppId string = ''
@description('Bot Token Service OAuth connection name used by the OBO clients.')
@minLength(2)
@maxLength(64)
param oboOAuthConnectionName string = 'japan-expert-obo'

// ---------------------------------------------------------------------------
// MCP provider configuration
//
// Every active data source is credential-free and reached over HTTPS, so provider configuration is
// non-secret deployment configuration rather than a secret. Settings are parameters so an operator
// can move to a self-hosted or contracted endpoint without an infrastructure or code change.
// Section and property names mirror the MCP service options classes; numeric tuning that has no
// operational or licence consequence stays on the service defaults.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Azure Bot and Direct Line
//
// The Agent 365 CLI does not create Azure Bot resources, so the bot and its channels belong here.
// The bot requires the OBO channel application, which is registered outside this template, so it is
// deployed in a second phase once that application ID is available. The messaging endpoint is bound
// to the deployed host's protected OBO route inside this deployment, so no manual endpoint value is
// needed. Direct Line site keys are channel secrets and are never read, output, or logged here.
// ---------------------------------------------------------------------------

@description('Deploy the Azure Bot. Requires oboChannelAppId, so it stays false until the OBO channel application exists.')
param deployAzureBot bool = false

@description('Azure Bot resource name, which is also the globally unique bot handle.')
@minLength(2)
@maxLength(64)
param azureBotName string = 'bot-${resourceBaseName}'

@description('Azure Bot display name shown to channel users.')
@minLength(1)
@maxLength(64)
param azureBotDisplayName string = 'Japan Tourist Assistant'

@description('Azure Bot SKU.')
@allowed([
  'F0'
  'S1'
])
param azureBotSkuName string = 'F0'

@description('Create the Direct Line channel and its site with the Azure Bot.')
param deployDirectLineChannel bool = true

@description('Create the Microsoft Teams channel with the Azure Bot.')
param deployTeamsChannel bool = true

@description('Create the Aadv2 Bot Token Service OAuth connection with the Azure Bot.')
param deployOboOAuthConnection bool = true

@description('Direct Line site name for the OBO Direct Line client.')
@minLength(1)
param directLineSiteName string = 'japan-expert-directline'

@description('Trusted origins for the Direct Line site. A non-empty list enables secure-site enforcement.')
param directLineTrustedOrigins array = []

@secure()
@description('OBO channel application secret written to Bot Token Service. Supply only through a protected parameter source.')
param oboChannelAppClientSecret string = ''

@description('Space-delimited delegated scopes requested by the OBO Aadv2 connection. Read this from the fresh Blueprint registration.')
param oboOAuthScope string = ''

// ---------------------------------------------------------------------------

var baseTags = {
  environment: environmentName
  workload: resourceBaseName
  'deployment-scope': approvedDeploymentScope
  'managed-by': 'a365-tourist-backend/infra/main.bicep'
}
var tags = union(
  baseTags,
  empty(deployedBy) ? {} : { 'deployed-by': deployedBy },
  empty(sessionId) ? {} : { 'deployment-session-id': sessionId },
  empty(createdAt) ? {} : { 'created-at': createdAt }
)
var graphTags = concat(
  [
    'environment:${environmentName}'
    'workload:${resourceBaseName}'
    'managed-by:a365-tourist-backend/infra/main.bicep'
  ],
  empty(deployedBy) ? [] : ['deployed-by:${deployedBy}'],
  empty(sessionId) ? [] : ['deployment-session-id:${sessionId}']
)
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

// The gpt-5.6-sol deployment is a Responses API model reached through the account-level
// OpenAI-compatible surface. The project-scoped /api/projects/<name> path does not publish
// /openai/v1 on this account, so the host receives the account endpoint and the deployment name
// only. The host appends /openai/v1; the Responses client owns the /responses operation and v1
// uses implicit versioning.
var resolvedFoundryProjectEndpoint = empty(foundryProjectEndpoint)
  ? 'https://${foundryAccountName}.services.ai.azure.com'
  : foundryProjectEndpoint

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

module applicationInsights './modules/application-insights.bicep' = {
  name: 'application-insights'
  params: {
    componentName: applicationInsightsName
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    tags: tags
  }
}

module containerRegistry './modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    registryName: containerRegistryName
    location: location
    workspaceResourceId: logAnalytics.outputs.id
    skuName: containerRegistrySkuName
    tags: tags
  }
}

module containerAppEnvironment './modules/container-app-environment.bicep' = {
  name: 'container-app-environment'
  params: {
    environmentName: containerAppEnvironmentName
    location: location
    workspaceName: logAnalyticsWorkspaceName
    tags: tags
  }
  dependsOn: [
    logAnalytics
  ]
}

module hostManagedIdentity './modules/host-managed-identity.bicep' = {
  name: 'host-managed-identity'
  params: {
    identityName: hostIdentityName
    location: location
    tags: tags
  }
}

module attractionsManagedIdentity './modules/attractions-managed-identity.bicep' = {
  name: 'attractions-managed-identity'
  params: {
    identityName: attractionsIdentityName
    location: location
    tags: tags
  }
}

module weatherManagedIdentity './modules/weather-managed-identity.bicep' = {
  name: 'weather-managed-identity'
  params: {
    identityName: weatherIdentityName
    location: location
    tags: tags
  }
}

module accommodationManagedIdentity './modules/accommodation-managed-identity.bicep' = {
  name: 'accommodation-managed-identity'
  params: {
    identityName: accommodationIdentityName
    location: location
    tags: tags
  }
}

module currencyManagedIdentity './modules/currency-managed-identity.bicep' = {
  name: 'currency-managed-identity'
  params: {
    identityName: currencyIdentityName
    location: location
    tags: tags
  }
}

module mcpApiApplication './modules/mcp-api-application.bicep' = {
  name: 'mcp-api-application'
  params: {
    applicationName: mcpApiApplicationName
    displayName: mcpApiApplicationName
    tenantId: tenantId
    graphTags: graphTags
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    registryName: containerRegistryName
    hostPrincipalId: hostManagedIdentity.outputs.principalId
    attractionsPrincipalId: attractionsManagedIdentity.outputs.principalId
    weatherPrincipalId: weatherManagedIdentity.outputs.principalId
    accommodationPrincipalId: accommodationManagedIdentity.outputs.principalId
    currencyPrincipalId: currencyManagedIdentity.outputs.principalId
  }
  dependsOn: [
    containerRegistry
  ]
}

module attractionsMcpContainerApp './modules/attractions-mcp-container-app.bicep' = {
  name: 'attractions-mcp-container-app'
  params: {
    appName: attractionsAppName
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: attractionsManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: attractionsImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    providerSettings: attractionsProviderSettings
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module weatherMcpContainerApp './modules/weather-mcp-container-app.bicep' = {
  name: 'weather-mcp-container-app'
  params: {
    appName: weatherAppName
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: weatherManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: weatherImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    providerSettings: weatherProviderSettings
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module accommodationMcpContainerApp './modules/accommodation-mcp-container-app.bicep' = {
  name: 'accommodation-mcp-container-app'
  params: {
    appName: accommodationAppName
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: accommodationManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: accommodationImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    providerSettings: accommodationProviderSettings
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module currencyMcpContainerApp './modules/currency-mcp-container-app.bicep' = {
  name: 'currency-mcp-container-app'
  params: {
    appName: currencyAppName
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: currencyManagedIdentity.outputs.id
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: currencyImage
    tenantId: tenantId
    mcpTokenAudience: mcpApiApplication.outputs.applicationId
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    providerSettings: currencyProviderSettings
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

module agentHostContainerApp './modules/agent-host-container-app.bicep' = {
  name: 'agent-host-container-app'
  params: {
    appName: hostAppName
    location: location
    environmentId: containerAppEnvironment.outputs.id
    managedIdentityResourceId: hostManagedIdentity.outputs.id
    managedIdentityClientId: hostManagedIdentity.outputs.clientId
    acrLoginServer: containerRegistry.outputs.loginServer
    containerImage: containerImage
    foundryProjectEndpoint: resolvedFoundryProjectEndpoint
    foundryModelDeploymentName: foundryModelDeploymentName
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

// Foundry data-plane roles are assigned in the shared Foundry resource group. The OBO
// turn calls the model with a delegated token, so it is attributed to the signed-in
// user; every caller therefore needs Foundry data-plane access. Supply a group object
// ID in agentUserPrincipalIds rather than listing individual users.
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

output deploymentResourceGroupName string = resourceGroup().name
output deploymentScope string = approvedDeploymentScope
output agentHostUrl string = 'https://${agentHostContainerApp.outputs.fqdn}'
output oboMessagingEndpoint string = oboMessagingEndpoint
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output existingFoundryAccountId string = existingFoundryAccount.id
output existingFoundryProjectId string = existingFoundryProject.id
output existingFoundryModelDeploymentId string = existingFoundryModelDeployment.id
output existingFoundryProjectEndpoint string = resolvedFoundryProjectEndpoint
output hostManagedIdentityClientId string = hostManagedIdentity.outputs.clientId
output hostManagedIdentityPrincipalId string = hostManagedIdentity.outputs.principalId
output mcpApiApplicationId string = mcpApiApplication.outputs.applicationId
output mcpApiAudience string = mcpApiApplication.outputs.audience
output mcpDelegatedScope string = mcpApiApplication.outputs.delegatedScope
output containerAppNames object = {
  agentHost: hostAppName
  attractions: attractionsAppName
  weather: weatherAppName
  accommodation: accommodationAppName
  currency: currencyAppName
}
output azureBotName string = deployAzureBot ? azureBot!.outputs.name : ''
output azureBotMessagingEndpoint string = deployAzureBot ? azureBot!.outputs.messagingEndpoint : ''
output directLineSiteName string = deployAzureBot && deployDirectLineChannel ? directLineSiteName : ''
output applicationImageRepositories object = {
  agentHost: '${containerRegistry.outputs.loginServer}/${imageRepositoryPrefix}-agent'
  attractions: '${containerRegistry.outputs.loginServer}/${imageRepositoryPrefix}-attractions'
  weather: '${containerRegistry.outputs.loginServer}/${imageRepositoryPrefix}-weather'
  accommodation: '${containerRegistry.outputs.loginServer}/${imageRepositoryPrefix}-accommodation'
  currency: '${containerRegistry.outputs.loginServer}/${imageRepositoryPrefix}-currency'
}
