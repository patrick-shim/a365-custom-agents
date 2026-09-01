extension microsoftGraphV1

param applicationName string
param displayName string
param tenantId string
param graphTags array

var mcpInvokeScopeId = guid(applicationName, 'Mcp.Invoke')
var audience = 'api://${tenantId}/${applicationName}'
var delegatedScope = '${audience}/Mcp.Invoke'

resource mcpApiApplication 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: applicationName
  displayName: displayName
  description: 'Single-tenant API for authenticated Japan Tourist Assistant MCP workloads.'
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    audience
  ]
  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        adminConsentDescription: 'Allow this Agent 365 identity to invoke protected Japan Tourist Assistant MCP tools.'
        adminConsentDisplayName: 'Invoke Japan Tourist Assistant MCP tools'
        id: mcpInvokeScopeId
        isEnabled: true
        type: 'Admin'
        userConsentDescription: 'Allow this Agent 365 identity to invoke protected Japan Tourist Assistant MCP tools.'
        userConsentDisplayName: 'Invoke Japan Tourist Assistant MCP tools'
        value: 'Mcp.Invoke'
      }
    ]
  }
  tags: graphTags
}

resource mcpApiServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  accountEnabled: true
  appId: mcpApiApplication.appId
  appRoleAssignmentRequired: false
  displayName: displayName
  tags: graphTags
}

output applicationId string = mcpApiApplication.appId
output audience string = audience
output delegatedScope string = delegatedScope
output servicePrincipalId string = mcpApiServicePrincipal.id
