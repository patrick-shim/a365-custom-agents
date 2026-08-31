param appName string
param location string
param environmentId string
param managedIdentityResourceId string
param managedIdentityClientId string
param acrLoginServer string
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param tenantId string
param mcpTokenAudience string
param azureMapsClientId string
param applicationInsightsConnectionString string
param tags object

var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var isPlaceholder = containerImage == placeholderImage
var effectivePort = isPlaceholder ? 80 : 8080
var plainEnvironment = [
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
    name: 'McpAuthorization__TenantId'
    value: tenantId
  }
  {
    name: 'McpAuthorization__Audience'
    value: mcpTokenAudience
  }
  {
    name: 'McpAuthorization__RequiredScope'
    value: 'Mcp.Invoke'
  }
  {
    name: 'AzureMaps__ClientId'
    value: azureMapsClientId
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
        external: false
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
          name: 'accommodation'
          image: containerImage
          env: isPlaceholder ? [] : plainEnvironment
          resources: {
            cpu: any('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: isPlaceholder ? '/' : '/health'
                port: effectivePort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: isPlaceholder ? '/' : '/health'
                port: effectivePort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
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
        maxReplicas: 3
      }
    }
  }
}

output id string = app.id
output fqdn string = app.properties.configuration.ingress.fqdn
