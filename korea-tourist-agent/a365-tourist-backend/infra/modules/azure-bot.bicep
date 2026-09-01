// Azure Bot, OBO channels, and Bot Token Service connection for the Teams and Direct Line clients.
//
// Ownership: the Agent 365 CLI owns the Blueprint, the child identities, and the agent endpoint
// registration. It does not create Azure Bot resources, so the bot and its channels belong to this
// resource-group-scoped template. The OBO channel application is a separate single-tenant Entra
// application that must already exist; its ID is supplied as a parameter.
//
// Secrets: Direct Line site keys are never read or emitted. The OAuth client secret is accepted only
// as a secure ARM parameter, written to Bot Token Service, and never output.

@description('Azure Bot resource name, which is also the globally unique bot handle.')
@minLength(2)
@maxLength(64)
param botName string

@description('Display name shown to channel users.')
@minLength(1)
@maxLength(64)
param displayName string

@description('HTTPS messaging endpoint. Must be the protected OBO route on the deployed host.')
@minLength(1)
param messagingEndpoint string

@description('Application ID of the existing single-tenant OBO channel application.')
@minLength(36)
@maxLength(36)
param msaAppId string

@description('Entra tenant ID of the single-tenant OBO channel application.')
@minLength(36)
@maxLength(36)
param msaAppTenantId string

@description('Bot application type. The OBO channel application is single tenant.')
@allowed([
  'SingleTenant'
  'MultiTenant'
  'UserAssignedMSI'
])
param msaAppType string = 'SingleTenant'

@description('Azure Bot SKU.')
@allowed([
  'F0'
  'S1'
])
param skuName string = 'F0'

@description('Create the Direct Line channel and its site.')
param deployDirectLineChannel bool = true

@description('Create the Microsoft Teams channel.')
param deployTeamsChannel bool = true

@description('Create the Aadv2 Bot Token Service OAuth connection used by both OBO clients.')
param deployOAuthConnection bool = true

@description('Direct Line site name.')
@minLength(1)
param directLineSiteName string

@description('Trusted origins for the Direct Line site. A non-empty list enables secure-site enforcement.')
param directLineTrustedOrigins array = []

@description('Bot Token Service OAuth connection name.')
@minLength(2)
@maxLength(64)
param oauthConnectionName string = 'japan-expert-obo'

@description('Client ID used by the Aadv2 OAuth connection.')
@minLength(36)
@maxLength(36)
param oauthClientId string

@secure()
@description('Client secret written to Bot Token Service. Supply only through a protected parameter source.')
param oauthClientSecret string

@description('Space-delimited delegated scopes requested by the Aadv2 OAuth connection.')
@minLength(1)
param oauthScopes string

param tags object

var oauthInputKeys = {
  valid: oauthConnectionName
}
var validatedOAuthConnectionName = deployOAuthConnection
  ? oauthInputKeys[!empty(oauthClientSecret) && !empty(oauthScopes) ? 'valid' : 'invalid']
  : oauthConnectionName

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  kind: 'azurebot'
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    displayName: displayName
    endpoint: messagingEndpoint
    msaAppId: msaAppId
    msaAppType: msaAppType
    msaAppTenantId: msaAppTenantId
    isStreamingSupported: false
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource directLineChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = if (deployDirectLineChannel) {
  parent: bot
  name: 'DirectLineChannel'
  location: 'global'
  properties: {
    channelName: 'DirectLineChannel'
    properties: {
      sites: [
        {
          siteName: directLineSiteName
          isEnabled: true
          isV1Enabled: false
          isV3Enabled: true
          isSecureSiteEnabled: !empty(directLineTrustedOrigins)
          trustedOrigins: directLineTrustedOrigins
        }
      ]
    }
  }
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = if (deployTeamsChannel) {
  parent: bot
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      acceptedTerms: true
      enableCalling: false
      isEnabled: true
    }
  }
}

resource oauthConnection 'Microsoft.BotService/botServices/connections@2022-09-15' =
  if (deployOAuthConnection) {
    parent: bot
    name: validatedOAuthConnectionName
    location: 'global'
    kind: 'azurebot'
    tags: tags
    sku: {
      name: skuName
    }
    properties: {
      clientId: oauthClientId
      clientSecret: oauthClientSecret
      name: validatedOAuthConnectionName
      scopes: oauthScopes
      serviceProviderDisplayName: 'Azure Active Directory v2'
      serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c'
      parameters: [
        {
          key: 'tenantId'
          value: msaAppTenantId
        }
        {
          key: 'tokenExchangeUrl'
          value: 'api://botid-${oauthClientId}'
        }
      ]
    }
  }

// No key, secret, or token is exposed as output. Direct Line site keys are retrieved only through
// the approved post-deployment channel workflow documented in infra/README.md.
output id string = bot.id
output name string = bot.name
output messagingEndpoint string = bot.properties.endpoint
