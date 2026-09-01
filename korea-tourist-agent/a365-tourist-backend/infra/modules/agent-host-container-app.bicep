type Agent365AgentIds = {
  agenticUser: string
  onBehalfOf: string
}

param appName string
param location string
param environmentId string
param managedIdentityResourceId string
param managedIdentityClientId string
param acrLoginServer string
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param foundryEndpoint string

@description('Enables the Azure AI Content Safety Prompt Shields guard. On by default and fail-closed: a turn is rejected if the service cannot be reached, so disabling this removes prompt-injection screening entirely.')
param promptShieldEnabled bool = true

@description('Content Safety account endpoint for Prompt Shields, for example https://<account>.cognitiveservices.azure.com. A multi-service AIServices account already publishes this surface; a dedicated ContentSafety account works equally well. Plain configuration, so the guard does not depend on Foundry.')
param promptShieldEndpoint string = ''
param tenantId string
param mcpAudience string
param attractionsFqdn string
param weatherFqdn string
param accommodationFqdn string
param currencyFqdn string
param agent365BlueprintId string
param agent365AgentIds Agent365AgentIds
param oboChannelAppId string
param oboOAuthConnectionName string = 'korea-tourist-assistant-obo'
param applicationInsightsConnectionString string
param tags object

var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var isPlaceholder = containerImage == placeholderImage
var effectivePort = isPlaceholder ? 80 : 8080
var productionEnvironment = [
  {
    name: 'ASPNETCORE_ENVIRONMENT'
    value: 'Production'
  }
  {
    name: 'ASPNETCORE_HTTP_PORTS'
    value: '8080'
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsightsConnectionString
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: managedIdentityClientId
  }
  {
    name: 'ENABLE_A365_OBSERVABILITY_EXPORTER'
    value: 'true'
  }
  {
    name: 'OTEL_LOG_LEVEL'
    value: 'INFO'
  }
  {
    name: 'A365_OBSERVABILITY_LOG_LEVEL'
    value: 'info|warn|error'
  }
  {
    name: 'AgentHost__FoundryProjectEndpoint'
    value: foundryEndpoint
  }
  {
    name: 'AgentHost__FoundryModelDeployment'
    value: 'gpt-5.6-sol'
  }
  {
    name: 'Agent365__EnableWorkIq'
    value: 'false'
  }
  {
    name: 'PromptShield__Enabled'
    value: string(promptShieldEnabled)
  }
  {
    name: 'PromptShield__Endpoint'
    value: promptShieldEndpoint
  }
  {
    name: 'PurviewDlp__Enabled'
    value: 'true'
  }
  {
    name: 'PurviewDlp__TenantId'
    value: tenantId
  }
  {
    name: 'PurviewDlp__ApplicationId'
    value: agent365BlueprintId
  }
  {
    name: 'PurviewDlp__UseCompatibilityProxy'
    value: 'true'
  }
  {
    name: 'TokenValidation__Enabled'
    value: 'true'
  }
  {
    name: 'TokenValidation__TenantId'
    value: tenantId
  }
  {
    name: 'TokenValidation__Audiences__AgenticUser'
    value: agent365BlueprintId
  }
  {
    name: 'TokenValidation__Audiences__OnBehalfOf'
    value: oboChannelAppId
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-foundry__Type'
    value: 'AgenticUserAuthorization'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-foundry__Settings__Scopes__0'
    value: 'https://ai.azure.com/.default'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-foundry__Settings__AlternateBlueprintConnectionName'
    value: 'ServiceConnection'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-purview__Type'
    value: 'AgenticUserAuthorization'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-purview__Settings__Scopes__0'
    value: 'https://graph.microsoft.com/Content.Process.User'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-purview__Settings__Scopes__1'
    value: 'https://graph.microsoft.com/ProtectionScopes.Compute.User'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-purview__Settings__Scopes__2'
    value: 'https://graph.microsoft.com/ContentActivity.Write'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-purview__Settings__AlternateBlueprintConnectionName'
    value: 'ServiceConnection'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-mcp__Type'
    value: 'AgenticUserAuthorization'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-mcp__Settings__Scopes__0'
    value: '${mcpAudience}/Mcp.Invoke'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__agentic-mcp__Settings__AlternateBlueprintConnectionName'
    value: 'ServiceConnection'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__obo-user__Type'
    value: 'AzureBotUserAuthorization'
  }
  {
    name: 'AgentApplication__UserAuthorization__Handlers__obo-user__Settings__AzureBotOAuthConnectionName'
    value: oboOAuthConnectionName
  }
  {
    name: 'Connections__ServiceConnection__Settings__AuthType'
    value: 'FederatedCredentials'
  }
  {
    name: 'Connections__ServiceConnection__Settings__AuthorityEndpoint'
    value: '${environment().authentication.loginEndpoint}${tenantId}'
  }
  {
    name: 'Connections__ServiceConnection__Settings__ClientId'
    value: agent365BlueprintId
  }
  {
    name: 'Connections__ServiceConnection__Settings__FederatedClientId'
    value: managedIdentityClientId
  }
  {
    name: 'Connections__ServiceConnection__Settings__Scopes__0'
    value: '5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default'
  }
  {
    name: 'Connections__OboServiceConnection__Settings__AuthType'
    value: 'FederatedCredentials'
  }
  {
    name: 'Connections__OboServiceConnection__Settings__AuthorityEndpoint'
    value: '${environment().authentication.loginEndpoint}${tenantId}'
  }
  {
    name: 'Connections__OboServiceConnection__Settings__ClientId'
    value: agent365BlueprintId
  }
  {
    name: 'Connections__OboServiceConnection__Settings__FederatedClientId'
    value: managedIdentityClientId
  }
  {
    name: 'Connections__OboServiceConnection__Settings__Scopes__0'
    // Entra token exchange audience. This must not be the Agent 365 Messaging Bot
    // API scope used by ServiceConnection; each connection has exactly one audience.
    value: 'api://AzureADTokenExchange/.default'
  }
  {
    name: 'Connections__OboChannelConnection__Settings__AuthType'
    value: 'FederatedCredentials'
  }
  {
    name: 'Connections__OboChannelConnection__Settings__AuthorityEndpoint'
    value: '${environment().authentication.loginEndpoint}${tenantId}'
  }
  {
    name: 'Connections__OboChannelConnection__Settings__ClientId'
    value: oboChannelAppId
  }
  {
    name: 'Connections__OboChannelConnection__Settings__FederatedClientId'
    value: managedIdentityClientId
  }
  {
    name: 'Connections__OboChannelConnection__Settings__Scopes__0'
    value: 'https://api.botframework.com/.default'
  }
  {
    name: 'AgentIdentityObo__AgentId'
    value: agent365AgentIds.onBehalfOf
  }
  {
    name: 'AgentIdentityObo__BlueprintConnectionName'
    value: 'OboServiceConnection'
  }
  {
    name: 'ConnectionsMap__0__ServiceUrl'
    value: '*'
  }
  {
    name: 'ConnectionsMap__0__Audience'
    value: agent365BlueprintId
  }
  {
    name: 'ConnectionsMap__0__Connection'
    value: 'ServiceConnection'
  }
  {
    name: 'ConnectionsMap__1__ServiceUrl'
    value: '*'
  }
  {
    name: 'ConnectionsMap__1__Audience'
    value: oboChannelAppId
  }
  {
    name: 'ConnectionsMap__1__Connection'
    value: 'OboChannelConnection'
  }
  {
    name: 'Agent365Observability__TenantId'
    value: tenantId
  }
  {
    name: 'Agent365Observability__AgentBlueprintId'
    value: agent365BlueprintId
  }
  {
    name: 'Agent365Observability__ClientId'
    value: agent365BlueprintId
  }
  {
    name: 'InternalMcp__Enabled'
    value: 'true'
  }
  {
    name: 'InternalMcp__UseAuthentication'
    value: 'true'
  }
  {
    name: 'InternalMcp__Audience'
    value: mcpAudience
  }
  {
    name: 'InternalMcp__AttractionsEndpoint'
    value: 'https://${attractionsFqdn}/mcp'
  }
  {
    name: 'InternalMcp__WeatherEndpoint'
    value: 'https://${weatherFqdn}/mcp'
  }
  {
    name: 'InternalMcp__AccommodationEndpoint'
    value: 'https://${accommodationFqdn}/mcp'
  }
  {
    name: 'InternalMcp__CurrencyEndpoint'
    value: 'https://${currencyFqdn}/mcp'
  }
  {
    name: 'InternalMcp__MaximumContentCharacters'
    value: '65536'
  }
]

resource app 'Microsoft.App/containerApps@2026-01-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: effectivePort
        allowInsecure: false
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: isPlaceholder ? [] : [
        {
          server: acrLoginServer
          identity: managedIdentityResourceId
        }
      ]
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'agent-host'
          image: containerImage
          env: isPlaceholder ? [] : productionEnvironment
          resources: {
            cpu: any('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: isPlaceholder ? '/' : '/api/health/live'
                port: effectivePort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: isPlaceholder ? '/' : '/api/health/ready'
                port: effectivePort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 6
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output id string = app.id
output fqdn string = app.properties.configuration.ingress.fqdn
