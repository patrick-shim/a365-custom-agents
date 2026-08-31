param appName string
param location string
param environmentId string
param managedIdentityResourceId string
param acrLoginServer string
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
param tenantId string
param mcpTokenAudience string
param applicationInsightsConnectionString string

@description('Provider configuration supplied by the deployment so data-source tuning stays a parameter change.')
param providerSettings array = []

param tags object

var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var isPlaceholder = containerImage == placeholderImage
var effectivePort = isPlaceholder ? 80 : 8080
var baseEnvironment = [
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
]
var plainEnvironment = concat(baseEnvironment, providerSettings)

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
          name: 'weather'
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
        maxReplicas: 1
      }
    }
  }
}

output id string = app.id
output fqdn string = app.properties.configuration.ingress.fqdn
