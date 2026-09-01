# Secure backend configuration

All checked-in settings are non-secret defaults. Use Azure application settings, environment
variables, or .NET user secrets for identifiers and credentials. Environment variables use double
underscores to represent configuration sections.

This backend does not own or contain Agent 365 CLI state, package manifests, tenant-bound identity
values, or frontend registration artifacts. OBO Teams, OBO Direct Line, and AI Teammate frontends bind
through the non-secret frontend contract; protected deployment configuration supplies the Blueprint,
child, and audience values required by the shared host. This backend must not run `a365` commands.
An owning frontend may run an M7-authorized Agent 365 workflow only after a reviewed dry run,
rollback boundary, and explicit approval.

If any provider key has appeared in chat, logs, command history, or a committed file, revoke and
rotate it before deployment. Do not copy the exposed value into this backend project.

## Agent 365 ownership and runtime identity

The Korea Tourist Assistant product owns one Agent Identity Blueprint and two child identities:

| Frontend | Child identity | Endpoint | Runtime authority |
| --- | --- | --- | --- |
| AI Teammate | Agent Identity with an Agent User | `/api/messages` | The agent's Agentic User |
| OBO | Agent Identity without an Agent User | `/api/messages/obo` | The signed-in human, constrained by the OBO child identity |

Agent 365 CLI owns the Blueprint, BlueprintPrincipal, child identities, generated configuration,
permissions, endpoint registrations, and publication. Do not create those objects in application
code or Bicep, and never hand-edit `a365.generated.config.json`.

Frontend CLI state is owned only by the channel frontend that operates it:

- `a365-tourist-agent-teammate` owns the authoritative AI Teammate configuration and manifest state.
- `a365-tourist-agent-obo/.a365/obo` owns OBO static configuration and, after an approved setup, its
   child-instance state and generated manifests.
- `a365-tourist-agent-obo/.a365/ai-teammate` is protected historical output only. Do not copy,
   hand-edit, delete, or use it as an AI Teammate publication source.
- `a365-tourist-agent-obo-directline` has no Agent 365 CLI state.

The shared Blueprint must remain stable across both child identities. Never run `a365 cleanup
blueprint` while any child frontend exists. Any future OBO setup must run from the OBO Teams frontend
root and reject a dry run that proposes creating a Blueprint instead of reusing the existing one.

After both child identities exist, deployment consumes these values from their CLI-owned state:

| Generated field | Expected use |
| --- | --- |
| `agentBlueprintId` | The shared Blueprint application/client ID. Inject into both connection profiles, `PurviewDlp.ApplicationId`, and the observability Blueprint/client ID. |
| Tenant ID | Home tenant for both children. Inject into both connection authorities, Purview, token validation, and observability. Never check it into source. |
| Blueprint ID | Use as the AI Teammate Bot Connector audience and Agent Identity parent/resource application. |
| OBO channel app ID | Use as the `/api/messages/obo` Bot Connector audience, OBO package `AGENT_APP_ID`, and Bot Token Service OAuth client. |
| AI Teammate child ID | Resolve dynamically from the signed activity; validate acquired resource-token `appid`/`azp` against it. |
| OBO child ID | Inject as `agent365AgentIds.onBehalfOf`; use only for `fmi_path`, downstream OBO `client_id`, and child observability attribution. |
| `messagingEndpoint` | Register `/api/messages` for the AI Teammate and `/api/messages/obo` for OBO. |
| `completed` | Must be `true` before production traffic is enabled. |
| `resourceConsents` | Must be non-empty before production traffic is enabled. |

`agentBlueprintClientSecret`, when emitted for local workflows, is secret and is not one of the
non-secret deployment values above. Keep it in a supported secret store. Production identity must
use the CLI-owned Blueprint/FIC flow rather than copying that secret into source.

Production validates each endpoint with a separate JWT scheme and its registered channel audience. The HTTP endpoint
also establishes a per-turn frontend mode; the Agent Framework activity shape must match that mode
or the turn fails before model, Purview, or MCP access.

- Agentic User turns resolve the dynamic child identity with `GetAgenticInstanceId()`, acquire
   resource tokens through `AgenticAuthenticationService.GetAgenticUserTokenAsync`, and require each
   token's `appid`/`azp` to match that activity child.
- OBO turns use `AzureBotUserAuthorization` only to obtain a user assertion whose audience is the
   shared Blueprint. The host then requests a child-bound parent token with
   `fmi_path=<OBO child Agent Identity>`, and uses that parent token plus the user assertion in a
   child-client OBO request for each resource `/.default` scope. The exchange rejects tokens whose
   `appid`/`azp` is not the configured OBO child. The human `Activity.From.AadObjectId` remains the
   Purview caller identity.

The Container App user-assigned managed identity is bootstrap/infrastructure identity only. The
same UAMI authenticates the shared Blueprint for both child flows, but it is never treated as either
runtime child identity. Local developer fallback explicitly excludes managed identity authentication.

Both `ServiceConnection` and `OboServiceConnection` must use `AuthType=FederatedCredentials`:

- `ClientId`: shared Blueprint application ID.
- `FederatedClientId`: host Container App UAMI client ID.
- `ServiceConnection` has no static `AgentId`; Agentic User auth uses the signed activity child.
- `AgentIdentityObo.AgentId`: the OBO child Agent Identity application ID passed as `fmi_path` and
   used as the child OBO `client_id`. `OboServiceConnection` itself has no `AgentId` setting.

Do not use `UserManagedIdentity` for these profiles. In Agents SDK 1.4.83 that mode interprets
`ClientId` as the UAMI itself and creates a managed-identity client, which cannot perform the
confidential-client FMI or OBO exchanges required here.

## Agent host

| Environment variable | Purpose |
| --- | --- |
| `AgentHost__AzureOpenAIEndpoint` | Microsoft Foundry Azure OpenAI endpoint. The non-secret supplied endpoint is checked in. |
| `AgentHost__AzureOpenAIDeployment` | Deployment name; currently `gpt-5.6-sol`. |
| `AgentHost__AzureOpenAIModel` | Model label used by the host; currently `gpt-5.6-sol`. |
| `AgentIdentityAuthorization__AgenticUser__FoundryAuthHandlerName` | Agentic User Foundry handler; default `agentic-foundry`. |
| `AgentIdentityAuthorization__OnBehalfOf__FoundryAuthHandlerName` | Raw OBO user assertion handler; default `obo-user`. |
| `AgentIdentityAuthorization__AgenticUser__PurviewAuthHandlerName` | Agentic User Purview handler; default `agentic-purview`. |
| `AgentIdentityAuthorization__OnBehalfOf__PurviewAuthHandlerName` | Same raw OBO user assertion handler; default `obo-user`. |
| `AgentIdentityAuthorization__AgenticUser__InternalMcpAuthHandlerName` | Agentic User custom MCP handler; default `agentic-mcp`. |
| `AgentIdentityAuthorization__OnBehalfOf__InternalMcpAuthHandlerName` | Same raw OBO user assertion handler; default `obo-user`. |
| `AgentIdentityObo__AgentId` | OBO child Agent Identity application ID; required outside local development. |
| `AgentIdentityObo__BlueprintConnectionName` | Federated Blueprint connection used to obtain the `fmi_path` parent token; default `OboServiceConnection`. |
| `PurviewDlp__TenantId` | Human user's Microsoft Entra tenant ID used by Purview evaluation. |
| `PurviewDlp__ApplicationId` | Fallback Purview application location. Protected turns resolve the active frontend audience: Blueprint for Agentic User and the single-tenant channel app for OBO. |
| `PurviewDlp__UseCompatibilityProxy` | Enables the loopback-only request compatibility layer required by `Microsoft.Agents.AI.Purview` 1.17.0-rc1. Production sets this to `true`. |
| `PurviewDlp__CompatibilityProxyBaseUri` | Loopback-only proxy URI; default `http://127.0.0.1:8080/internal/purview/`. External callers receive 404. |
| `TokenValidation__Enabled` | Must remain `true` outside Development/Playground. |
| `TokenValidation__TenantId` | Exact home tenant accepted by both protected frontend modes. |
| `TokenValidation__Audiences__AgenticUser` | Shared Blueprint bot application ID accepted on `/api/messages`. |
| `TokenValidation__Audiences__OnBehalfOf` | Single-tenant OBO Azure Bot application ID accepted on `/api/messages/obo`. |
| `Agent365__EnableWorkIq` | Must remain `false`; Agent 365 Tooling 1.0 uses an MCP preview API incompatible with the custom MCP 2.1 client. |
| `InternalMcp__Enabled` | Enables the four protected custom MCP clients. Production deployment sets this to `true`. |
| `InternalMcp__UseAuthentication` | Must remain `true` outside local development. |
| `InternalMcp__Audience` | Single-tenant MCP API application ID URI, such as `api://<application-id>`. |
| `InternalMcp__AttractionsEndpoint` | Internal HTTPS MCP endpoint ending in `/mcp`. |
| `InternalMcp__WeatherEndpoint` | Internal HTTPS MCP endpoint ending in `/mcp`. |
| `InternalMcp__AccommodationEndpoint` | Internal HTTPS MCP endpoint ending in `/mcp`. |
| `InternalMcp__CurrencyEndpoint` | Internal HTTPS MCP endpoint ending in `/mcp`. |

The checked-in `AgentApplication.UserAuthorization.Handlers` section contains non-secret handler
and scope structure. Agentic handlers acquire resource tokens through `ServiceConnection`. OBO has
one Azure Bot handler that returns the raw Blueprint-audience user assertion:

| Handler | Required scope |
| --- | --- |
| `agentic-foundry` | `https://cognitiveservices.azure.com/.default` |
| `agentic-purview` | `https://graph.microsoft.com/Content.Process.User`, `https://graph.microsoft.com/ProtectionScopes.Compute.User`, and `https://graph.microsoft.com/ContentActivity.Write` |
| `agentic-mcp` | `<InternalMcp.Audience>/Mcp.Invoke` |
| `obo-user` | Blueprint delegated ingress scope configured on the Azure Bot OAuth connection; no automatic `OBOScopes` in Agent Framework. |

Purview resource tokens require the delegated Microsoft Graph scopes `Content.Process.User`,
`ProtectionScopes.Compute.User`, and `ContentActivity.Write`. The pinned RC1 package omits or
mis-serializes current Graph fields, so the host corrects activity casing, AI-agent metadata,
correlation IDs, and `Client-Request-Id` through a loopback-only proxy. Empty text emitted for an
intermediate function-call message is not sent to `processContent`; the corresponding tool
arguments and results remain independently evaluated by `ToolContentProtector` before execution.

The OBO Azure Bot OAuth connection defaults to the non-secret name `korea-tourist-assistant-obo`. Configure
that connection for the OBO bot so its initial user token targets the delegated scope exposed by the
shared Blueprint. Do not configure automatic `OBOConnectionName` or `OBOScopes` on `obo-user`; doing
so would mint downstream tokens as the Blueprint. The host uses `OboServiceConnection` to obtain the
child-bound parent token and then performs the child OBO exchange explicitly. Confirm the live scope
name and connection in the setup dry run and Teams/Azure Bot configuration; do not invent or commit
tenant identifiers.

Both modes place resource-specific access tokens inside one AsyncLocal turn scope. The scope remains
active through the complete agent run and is disposed afterward, so concurrent frontends and users
cannot share an Azure SDK or MCP bearer-token context.

Each protected turn also creates a new Purview-wrapped chat client. Protection-scope and ETag state
must never be shared between turns. The host registry retains each wrapper long enough for background
content-activity completion and disposes every created wrapper exactly once at application shutdown;
turn code must neither cache nor dispose it.

Production startup validates the Purview application ID and token-validation gate. Each protected
turn binds downstream token acquisition and observability to that route's configured child audience
and tenant, rejecting mismatched activity metadata. The OBO child setting must equal the OBO route
audience. Each protected turn also requires the human sender's Entra object ID; missing identity or
Purview service failure is rejected rather than sent to the model.

## Internal MCP authorization

All four MCP services use the same single-tenant resource API audience and require the delegated
`Mcp.Invoke` OAuth2 scope. Configure these values on every MCP Container App:

| Environment variable | Purpose |
| --- | --- |
| `McpAuthorization__TenantId` | Microsoft Entra tenant containing the MCP API registration. |
| `McpAuthorization__Audience` | API application/client ID GUID from the v2 access token `aud` claim. |
| `McpAuthorization__RequiredScope` | Required delegated scope in the space-delimited `scp` claim; default `Mcp.Invoke`. |

Agent 365 CLI 1.1.214 custom permissions support delegated scopes only. The custom MCP resource API
therefore exposes `Mcp.Invoke`; a future separately approved frontend-owned CLI workflow may grant
that delegated scope through the shared Blueprint to both children. The host requests
`<identifier-uri>/Mcp.Invoke` under the active frontend identity; every MCP initialize, list, and
invoke request carries that turn's token. MCP JWT validation checks the exact tenant and v2
application/client ID `aud` claim and authorizes `scp`, never `roles`.
Internal Container Apps ingress is still required, but is not a substitute for token validation.
`/health` remains anonymous for platform probes; `/mcp` is anonymous only in Development.

This backend deliberately provides no `a365` command. Permission previews and approved changes run
only from the owning frontend root under the active milestone, after a reviewed dry run and explicit
approval. Bicep does not assign Blueprint/inheritable permissions to the host UAMI.

## Deployment gates

1. Any future OBO Teams setup or reconciliation must reuse the existing Blueprint and OBO child
   identity. Reject a plan that creates, replaces, or deletes either object.
2. Agent 365 CLI 1.1.214 does not assign Foundry Azure RBAC. After each child exists, grant its
   effective runtime identity the minimum Foundry data-plane role, normally **Cognitive Services
   OpenAI User**. Do not grant the role to the host UAMI as a shortcut.
3. Verify the host UAMI's Blueprint federated identity credential and both connection profiles.
   Never duplicate the Blueprint or FIC in Bicep.
4. Configure and test the `korea-tourist-assistant-obo` Azure Bot OAuth connection against the shared
   Blueprint's delegated ingress scope before production OBO traffic.
5. Review the shared Blueprint's existing inherited Graph grants before modifying inherited
   permissions. Remove mail, files, sites, channel-message, or other WorkIQ-era grants that neither
   active frontend uses; a shared Blueprint intentionally propagates its permission ceiling to
   children.
6. WorkIQ remains disabled. Do not generate `ToolingManifest.json` or enable managed WorkIQ MCP
   loading for this milestone.

## Attractions

The active attractions and accommodation MCP services both use Azure Maps through
`DefaultAzureCredential`.

| Environment variable | Purpose |
| --- | --- |
| `AzureMaps__ClientId` | Azure Maps account client ID for the independently hosted attractions or accommodation MCP workload. |

Grant each workload identity the minimum Azure Maps Search and Render Data Reader access. Do not
configure an Azure Maps subscription key. The KTO TourAPI Service2 adapter remains compiled and tested
but is not wired into the active attractions MCP; the inactive KTO Key Vault/IaC plumbing is retained
as historical optional configuration and is not changed during M7.

## Weather

Open-Meteo is primary. Its public endpoint is for non-commercial evaluation and carries no uptime
guarantee. Production commercial use requires a subscription, attribution, the customer endpoint,
and its API key:

```powershell
$env:OpenMeteo__BaseAddress = "https://customer-api.open-meteo.com/v1/"
$env:OpenMeteo__ApiKey = "<commercial-open-meteo-key>"
$env:OpenMeteo__RequireCommercialLicense = "true"
```

OpenWeather One Call 4.0 is an optional fallback and government-alert source. It requires its own
One Call subscription and is disabled by default:

```powershell
$env:OpenWeather__Enabled = "true"
$env:OpenWeather__ApiKey = "<one-call-4-api-key>"
```

The OpenWeather key is sent in the required query parameter. Avoid URL logging on that MCP service.
Alert detail fan-out is capped by `OpenWeather__MaximumAlerts` (default `5`).

## Currency

The currency MCP tries Korea Eximbank daily reference rates, then ForexRateAPI, then the credential-free
Frankfurter/European Central Bank reference-rate provider. Enable one or more providers locally:

```powershell
$env:KoreaEximbank__Enabled = "true"
$env:KoreaEximbank__AuthKey = "<korea-eximbank-key>"
$env:ForexRateApi__Enabled = "true"
$env:ForexRateApi__ApiKey = "<forexrateapi-key>"
$env:Frankfurter__Enabled = "true"
$env:Frankfurter__BaseAddress = "https://api.frankfurter.dev/v1/"
```

Korea Eximbank publishes on business days around 11:00 KST, permits 1,000 calls per day, and returns
no data for non-business days or before publication. The adapter looks back at most seven days and
normalizes quoted units such as `JPY(100)`. Eximbank requires its key in the query string, so avoid
request-URL logging. ForexRateAPI authentication uses `X-API-KEY`, not a query parameter; its
freshness depends on the subscribed plan. Every quote returns source, rate type, observation time,
retrieval time, and a freshness note. The active deployment enables Frankfurter only; it uses European
Central Bank reference rates and requires no provider credential. Korea Eximbank and ForexRateAPI
remain available as configurable higher-priority fallbacks.

## Accommodation

Accommodation uses the same Azure Maps pattern as attractions. Set `AzureMaps__ClientId` to the Azure
Maps account client ID and grant the workload identity the minimum required Azure Maps data-plane
access. Do not configure a subscription key.

## Docker

Build from the backend project root:

```powershell
docker build --tag korea-expert-agent:local .
docker build --file Dockerfile.mcp --target attractions --tag korea-expert-attractions:local .
docker build --file Dockerfile.mcp --target weather --tag korea-expert-weather:local .
docker build --file Dockerfile.mcp --target accommodation --tag korea-expert-accommodation:local .
docker build --file Dockerfile.mcp --target currency --tag korea-expert-currency:local .
```

Every image listens on `8080`, runs as UID `1654`, and disables runtime diagnostics. The root
`Dockerfile` publishes the agent host; `Dockerfile.mcp` provides four independent final targets. In
Azure, expose only the host externally, use internal ingress for each MCP, inject configuration
through the hosting service, and attach managed identities. Do not bake environment files,
CLI-generated Agent 365 files, tenant IDs, or provider keys into an image.
