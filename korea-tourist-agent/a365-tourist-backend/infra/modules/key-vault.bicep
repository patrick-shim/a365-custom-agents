param vaultName string
param location string
param tenantId string
param workspaceResourceId string
param tags object
param seedKtoServiceKey bool
param seedOpenMeteoApiKey bool
param seedOpenWeatherApiKey bool
param seedKoreaEximbankAuthKey bool
param seedForexRateApiKey bool

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

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: vault
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource ktoServiceKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (seedKtoServiceKey) {
  parent: vault
  name: 'kto-service-key'
  tags: tags
  properties: {
    value: ktoServiceKey
  }
}

resource openMeteoApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (seedOpenMeteoApiKey) {
  parent: vault
  name: 'open-meteo-api-key'
  tags: tags
  properties: {
    value: openMeteoApiKey
  }
}

resource openWeatherApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (seedOpenWeatherApiKey) {
  parent: vault
  name: 'open-weather-api-key'
  tags: tags
  properties: {
    value: openWeatherApiKey
  }
}

resource koreaEximbankAuthKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (seedKoreaEximbankAuthKey) {
  parent: vault
  name: 'korea-eximbank-auth-key'
  tags: tags
  properties: {
    value: koreaEximbankAuthKey
  }
}

resource forexRateApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = if (seedForexRateApiKey) {
  parent: vault
  name: 'forex-rate-api-key'
  tags: tags
  properties: {
    value: forexRateApiKey
  }
}

output id string = vault.id
output name string = vault.name
output vaultUri string = vault.properties.vaultUri
