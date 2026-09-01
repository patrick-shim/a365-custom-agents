param registryName string
param vaultName string
param mapsAccountName string
param deployerObjectId string
param hostPrincipalId string
param attractionsPrincipalId string
param weatherPrincipalId string
param accommodationPrincipalId string
param currencyPrincipalId string
param grantAttractionsSecretAccess bool
param grantWeatherSecretAccess bool
param grantCurrencySecretAccess bool

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var azureMapsSearchAndRenderDataReaderRoleId = '6be48352-4f82-47c9-ad5e-0acacefdb005'

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: vaultName
}

resource ktoServiceKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: 'kto-service-key'
}

resource openMeteoApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: 'open-meteo-api-key'
}

resource openWeatherApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: 'open-weather-api-key'
}

resource koreaEximbankAuthKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: 'korea-eximbank-auth-key'
}

resource forexRateApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: 'forex-rate-api-key'
}

resource mapsAccount 'Microsoft.Maps/accounts@2023-06-01' existing = {
  name: mapsAccountName
}

resource deployerKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, deployerObjectId, keyVaultSecretsOfficerRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: deployerObjectId
    principalType: 'User'
  }
}

resource hostAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, hostPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: hostPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource attractionsAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, attractionsPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: attractionsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource weatherAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, weatherPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: weatherPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource accommodationAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, accommodationPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: accommodationPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource currencyAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, currencyPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: currencyPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource attractionsKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantAttractionsSecretAccess) {
  name: guid(ktoServiceKeySecret.id, attractionsPrincipalId, keyVaultSecretsUserRoleId)
  scope: ktoServiceKeySecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: attractionsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource weatherOpenMeteoKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantWeatherSecretAccess) {
  name: guid(openMeteoApiKeySecret.id, weatherPrincipalId, keyVaultSecretsUserRoleId)
  scope: openMeteoApiKeySecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: weatherPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource weatherOpenWeatherKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantWeatherSecretAccess) {
  name: guid(openWeatherApiKeySecret.id, weatherPrincipalId, keyVaultSecretsUserRoleId)
  scope: openWeatherApiKeySecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: weatherPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource currencyEximbankKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantCurrencySecretAccess) {
  name: guid(koreaEximbankAuthKeySecret.id, currencyPrincipalId, keyVaultSecretsUserRoleId)
  scope: koreaEximbankAuthKeySecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: currencyPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource currencyForexRateKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantCurrencySecretAccess) {
  name: guid(forexRateApiKeySecret.id, currencyPrincipalId, keyVaultSecretsUserRoleId)
  scope: forexRateApiKeySecret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: currencyPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource accommodationMapsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mapsAccount.id, accommodationPrincipalId, azureMapsSearchAndRenderDataReaderRoleId)
  scope: mapsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureMapsSearchAndRenderDataReaderRoleId)
    principalId: accommodationPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource attractionsMapsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mapsAccount.id, attractionsPrincipalId, azureMapsSearchAndRenderDataReaderRoleId)
  scope: mapsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureMapsSearchAndRenderDataReaderRoleId)
    principalId: attractionsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Foundry role assignments live in modules/foundry-role-assignments.bicep because the
// shared Foundry account is in a different resource group and must be assigned at that
// scope. Assigning it here would silently target this product's resource group.
