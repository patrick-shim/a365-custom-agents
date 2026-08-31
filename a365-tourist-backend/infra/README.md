# Korea Expert Agent infrastructure

This directory contains two backend-owned deployment paths:

- `main.bicep` is the resource-group-scope deployment of the five applications and their shared
  infrastructure.
- `live-backend-container-apps-update.bicep` is the resource-group-scope wrapper for updating the
  five existing Container Apps without recreating shared infrastructure.

Korea Expert deploys into its own resource group, `rg-a365-custom-agent-korea-expert`, in
`koreacentral`. It runs in the same subscription as Japan Expert but does not share Japan's
`rg-a365-custom-agents` group, so the two products can be managed and torn down independently. All
resource names derive from `resourceBaseName` (`koreaexpert`). `main.bicep` never creates the
resource group, and it refuses to deploy into any group other than `targetResourceGroupName`.

The existing `a365-ai-foundry` account, its `default` project, and the `gpt-5.6-sol` deployment in
`rg-ai-foundry` are shared with Japan Expert and referenced in place. This template never creates,
moves, or changes Foundry, and Korea Expert does not provision a Foundry account of its own.

### Create the resource group first

The target group is a prerequisite, not something this template provisions:

```powershell
az group create --name rg-a365-custom-agent-korea-expert --location koreacentral
```

> M7 is active. This is the only infrastructure and deployment source; the frontend projects are
> channel-only frontends. The deployment commands below are historical and operational reference only;
> they are not authorization to deploy, read tenant state, change identities, or run Agent 365 CLI
> workflows from this backend.

## Files

| Path | Role |
| --- | --- |
| `main.bicep` | `targetScope = 'resourceGroup'`; deploys into the existing shared resource group and orchestrates all modules |
| `main.parameters.json` | Checked-in non-secret parameters: `targetResourceGroupName` `rg-a365-custom-agent-korea-expert`, `resourceBaseName` `koreaexpert`, `location` `koreacentral`, the shared Foundry references, and placeholder provenance values |
| `live-backend-container-apps-update.bicep` | `targetScope = 'resourceGroup'`; updates only the five existing Container Apps |
| `live-backend-container-apps-update.json` | Checked-in compiled ARM form of the wrapper; must stay synchronized with its Bicep source |
| `bicepconfig.json` | Linter and analyzer configuration for both templates |
| `modules/` | 21 single-purpose modules; see the inventory below |

### Module inventory

All 21 modules are `.bicep` files under `modules/`:

| Group | Modules |
| --- | --- |
| Platform | `log-analytics`, `application-insights`, `container-registry`, `key-vault`, `container-app-environment` |
| Data plane | `azure-maps` |
| Foundry | `foundry-resource`, `foundry-project`, `foundry-model-deployment` |
| Identity | `host-managed-identity`, `attractions-managed-identity`, `weather-managed-identity`, `accommodation-managed-identity`, `currency-managed-identity` |
| Authorization | `mcp-api-application`, `role-assignments` |
| Workloads | `agent-host-container-app`, `attractions-mcp-container-app`, `weather-mcp-container-app`, `accommodation-mcp-container-app`, `currency-mcp-container-app` |

### `main.bicep` parameters

`environmentName`, `location`, `sessionId`, `deployedBy`, and `createdAt` come from
`main.parameters.json`; `deployerObjectId` and `tenantId` are supplied at invocation. The five image
parameters (`containerImage`, `attractionsImage`, `weatherImage`, `accommodationImage`,
`currencyImage`) each default to `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` so the
bootstrap phase can run before any application image exists. Agent 365 binding uses
`agent365BlueprintId`, the `Agent365AgentIds` and `Agent365AgentPrincipalIds` typed objects (each with
`agenticUser` and `onBehalfOf` members), `oboChannelAppId`, and `oboOAuthConnectionName`
(default `korea-expert-obo`). Five provider-secret parameters — `ktoServiceKey`, `openMeteoApiKey`,
`openWeatherApiKey`, `koreaEximbankAuthKey`, `forexRateApiKey` — all default to empty and are inactive
in the current deployment.

### `main.bicep` outputs

`resourceGroupName`, `agentHostUrl`, `containerRegistryLoginServer`, `keyVaultName`,
`foundryProjectId`, `hostManagedIdentityClientId`, `hostManagedIdentityPrincipalId`,
`mcpApiApplicationId`, `mcpApiAudience`, `mcpDelegatedScope`, and `applicationImageRepositories`.

### `live-backend-container-apps-update.bicep`

The wrapper takes five required image parameters (`hostImage`, `attractionsImage`, `weatherImage`,
`accommodationImage`, `currencyImage`), plus `tenantId`, `mcpApplicationId`, `mcpAudience`,
`agent365BlueprintId`, `agent365AgentIds`, `oboChannelAppId`, and `oboOAuthConnectionName`. It
references every piece of shared infrastructure with `existing` — the managed environment, registry,
Application Insights component, Foundry account, Azure Maps account, all five user-assigned
identities, and all five current Container Apps — so nothing outside the five workloads can be
created, replaced, or deleted. It returns `hostUrl` and `updatedContainerAppIds`.

## Architecture

```mermaid
flowchart LR
  Teammate[AI Teammate] -->|/api/messages| Host[Shared agent host Container App]
  OboTeams[OBO Teams package] -->|/api/messages/obo| Host
  DirectLine[OBO Direct Line client] -->|Direct Line v3| OboBot[OBO Azure Bot]
  OboBot -->|/api/messages/obo| Host
  Blueprint[One Blueprint] --> TeammateIdentity[Agent Identity + Agent User]
  Blueprint --> OBOIdentity[OBO Agent Identity]
  TeammateIdentity --> Teammate
  OBOIdentity -. OBO child mode .-> Host
  Host --> Attractions[Attractions MCP]
  Host --> Weather[Weather MCP]
  Host --> Accommodation[Accommodation MCP]
  Host --> Currency[Currency MCP]
  Host --> Foundry[Foundry gpt-5.6-sol]
  Foundry --> Project[Foundry project]
  Attractions & Accommodation --> Maps[Azure Maps]
  Host & Attractions & Weather & Accommodation & Currency --> ACR[Container Registry]
  Host & Attractions & Weather & Accommodation & Currency --> CAE[Container Apps environment]
  CAE --> Logs[Log Analytics]
  Host & Attractions & Weather & Accommodation & Currency --> AppI[Application Insights]
```

Only `ca-agent-koreaexpert` has external ingress. The four MCP apps use internal
ingress and validate the shared delegated `Mcp.Invoke` scope. Agent identity is never the host
UAMI: `a365` owns the Blueprint, BlueprintPrincipal, and each Agent Identity/Agentic User.

## Bootstrap and initial deployment

The five `main.bicep` image parameters default to the public Container Apps placeholder. In this phase,
Container Apps have no ACR registry entries, no Key Vault references, and no production settings.
RBAC is created so it can propagate before application images start.

Key Vault remains provisioned for optional future provider secrets, but the active five-app deployment
does not reference Key Vault from any workload. Its inactive KTO/Open-Meteo/OpenWeather/Eximbank/
ForexRateAPI plumbing is retained as historical optional infrastructure and is not changed during M7.

After the deployment gate is approved, phase 1 uses the checked-in parameter file and supplies the
deploying user's object ID at invocation time:

```powershell
$deployerObjectId = az ad signed-in-user show --query id -o tsv
$tenantId = $env:AZURE_TENANT_ID
$deploymentSessionId = '<deployment-session-id>'
$deploymentActor = '<operator-or-automation-id>'
$deploymentCreatedAt = '<ISO-8601-timestamp>'
az deployment sub create `
  --name koreaexpert-infra `
  --location koreacentral `
  --template-file infra/main.bicep `
  --parameters '@infra/main.parameters.json' `
  --parameters deployerObjectId=$deployerObjectId tenantId=$tenantId `
  --parameters sessionId=$deploymentSessionId deployedBy=$deploymentActor createdAt=$deploymentCreatedAt
```

Build immutable application images from the backend project root. The MCP image uses four independent
targets from `Dockerfile.mcp`.

```powershell
$tag = '<immutable-tag>'
az acr build --registry crkoreaexpert --image "korea-expert-agent:$tag" --file Dockerfile .
az acr build --registry crkoreaexpert --image "korea-expert-attractions:$tag" --file Dockerfile.mcp --target attractions .
az acr build --registry crkoreaexpert --image "korea-expert-weather:$tag" --file Dockerfile.mcp --target weather .
az acr build --registry crkoreaexpert --image "korea-expert-accommodation:$tag" --file Dockerfile.mcp --target accommodation .
az acr build --registry crkoreaexpert --image "korea-expert-currency:$tag" --file Dockerfile.mcp --target currency .
```

Agent 365 setup state and package commands belong only to their respective channel frontend
projects. This backend never contains `.a365` state or runs `a365` commands. The CLI, not
Bicep, creates child identities and delegated consent; preserve the shared Blueprint, do not
hand-edit generated state, and never run `a365 cleanup blueprint` while any child frontend exists.

Phase 2 requires the shared Blueprint ID and OBO child ID. AI Teammate child IDs are dynamic and
arrive in signed activities. Attractions and accommodation use Azure Maps managed identity, weather
uses public Open-Meteo, and currency uses Frankfurter/ECB reference rates, so no provider secrets
are required for the active deployment.

All four MCP Container Apps keep one production replica warm. The host discovers and validates all
four contracts before the model call, so scale-to-zero cold starts can exceed the Teams/Copilot
channel deadline even when each service is otherwise healthy.

```powershell
$acr = 'crkoreaexpert.azurecr.io'
$agent365AgentIds = @{
  agenticUser = ''
  onBehalfOf = $env:AGENT365_OBO_AGENT_ID
} | ConvertTo-Json -Compress
$agent365AgentPrincipalIds = @{
  agenticUser = ''
  onBehalfOf = $env:AGENT365_OBO_AGENT_PRINCIPAL_ID
} | ConvertTo-Json -Compress

az deployment sub create `
  --name koreaexpert-app `
  --location koreacentral `
  --template-file infra/main.bicep `
  --parameters '@infra/main.parameters.json' `
  --parameters deployerObjectId=$deployerObjectId tenantId=$tenantId `
  --parameters sessionId=$deploymentSessionId deployedBy=$deploymentActor createdAt=$deploymentCreatedAt `
  --parameters containerImage="$acr/korea-expert-agent:$tag" `
  --parameters attractionsImage="$acr/korea-expert-attractions:$tag" `
  --parameters weatherImage="$acr/korea-expert-weather:$tag" `
  --parameters accommodationImage="$acr/korea-expert-accommodation:$tag" `
  --parameters currencyImage="$acr/korea-expert-currency:$tag" `
  --parameters agent365BlueprintId="$env:AGENT365_BLUEPRINT_ID" `
  --parameters agent365AgentIds="$agent365AgentIds" `
  --parameters agent365AgentPrincipalIds="$agent365AgentPrincipalIds" `
  --parameters oboChannelAppId="$env:OBO_CHANNEL_APP_ID" `
  --parameters oboOAuthConnectionName='korea-expert-obo' `
  --parameters forexRateApiKey=''
```

## Existing-backend update workflow

M7 host or MCP updates use `live-backend-container-apps-update.bicep`, not the subscription bootstrap.
The wrapper requires immutable digest references for all five images and targets only the five
existing Container Apps. The current checkpoint is host revision `0000028`; revision `0000027` is
the verified host rollback, while all four MCP services remain on revision `0000005`. Exact digests
and sanitized evidence are recorded in
[`docs/milestones/M7-end-to-end-alignment.md`](../docs/milestones/M7-end-to-end-alignment.md).

Every candidate needs a new protected parameter set and a separately validated rollback parameter
set. Historical `.azure` plans and parameters are never current authority and never enter Git.

```powershell
az bicep build `
  --file infra/live-backend-container-apps-update.bicep `
  --outfile '<temporary-output-path>'

az deployment group validate `
  --resource-group '<resource-group>' `
  --template-file infra/live-backend-container-apps-update.bicep `
  --parameters '@<candidate-parameters.json>'

az deployment group what-if `
  --resource-group '<resource-group>' `
  --template-file infra/live-backend-container-apps-update.bicep `
  --parameters '@<candidate-parameters.json>' `
  --result-format FullResourcePayloads `
  --no-pretty-print
```

Review the structured result before approval: exactly five existing Container App modifications,
no creates or deletes, and every property delta explained. Reject identity, RBAC, SKU, location,
scale, ingress, route, audience, Blueprint, child-ID, secret, or unrelated drift. Validate the
rollback set through the same compile, ARM validation, and what-if boundary before deployment.

## Security and prerequisites

- Key Vault uses RBAC, soft delete, seven-day retention, and disabled public access. Active
  providers do not consume secrets. Purge protection is intentionally omitted.
- ACR admin and anonymous pull are disabled. All applications use UAMI-based AcrPull.
- Active providers use Azure managed identity or public, attributed APIs and require no provider keys.
- The host UAMI has AcrPull only. It has no direct Foundry, Purview, or MCP agent permission.
  Attractions and accommodation have Azure Maps Search and Render Data Reader. Other MCP workload
  roles are scoped to ACR.
- ACR and Key Vault diagnostics flow to `log-koreaexpert`. Application telemetry uses
  workspace-based Application Insights without local authentication.
- The MCP resource API is a separate application with a delegated `Mcp.Invoke` scope; it is not the
  agent application. A365 CLI owns Blueprint/Agent Identity permissions and consent.
- The two host routes use separate JWT schemes and channel app audiences. AI Teammate uses the
  shared Blueprint; OBO uses a single-tenant Azure Bot app. The SDK `ConnectionsMap` selects the
  matching outbound credential by incoming audience; downstream resource tokens remain child-bound.
- Both connection profiles use `FederatedCredentials`: the shared Blueprint is `ClientId` and the
  host UAMI is `FederatedClientId`. Agentic User auth resolves its child dynamically;
  `AgentIdentityObo.AgentId` selects the OBO child for `fmi_path` and child OBO.
- The Azure Bot OAuth connection `korea-expert-obo` must return an exchangeable user token for the
  delegated scope exposed by the shared Blueprint. Agent Framework must return that raw assertion;
  the host performs the child-bound parent-token and resource `/.default` exchanges explicitly.
- Review and minimize existing Blueprint Graph grants before creating the OBO child; inherited
  permissions are shared by design, even while WorkIQ is disabled in code.
- `Microsoft.Maps` must be registered before deployment. Provider registration is not performed by
  this scaffold.
- Agent 365 CLI 1.1.214 does not expose Foundry Azure RBAC assignment or binding this pre-created
  UAMI to the Blueprint FIC. Per-instance Foundry access and verified Blueprint federation are hard
  deployment gates; do not grant Foundry to the UAMI or duplicate Agent ID objects in Bicep.

## Validation

Compile without deploying:

```powershell
az bicep build --file infra/main.bicep --stdout > $null
az bicep build --file infra/live-backend-container-apps-update.bicep --stdout > $null
```

`live-backend-container-apps-update.json` is the checked-in compiled form of the resource-group
wrapper and must remain synchronized with its Bicep source. Compilation is local validation only;
deployment still requires fresh live validation, what-if review, rollback validation, and explicit
approval.
