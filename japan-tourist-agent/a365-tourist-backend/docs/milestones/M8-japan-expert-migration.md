# M8 Japan Expert migration and clean deployment

M8 was explicitly requested on 2026-08-30. It replaces the active Seoul Tourist product boundary
with Japan Expert while preserving the four-project ownership model, `/api/messages`,
`/api/messages/obo`, their distinct audiences, one shared Blueprint with two child identities, and
fail-closed Purview enforcement.

M0-M7 remain historical records. They may retain Seoul names, revisions, resource names, and
acceptance evidence, but none of that state is Japan Expert deployment or registration authority.

## Fixed target

- Azure subscription: `<user-selected subscription>`.
- Backend resource group: existing `rg-a365-custom-agents`; M8 must not create another resource group.
- Foundry: existing `a365-ai-foundry` account and `default` project in the same subscription.
- Model deployment: existing `gpt-5.6-sol`.
- Frontends: OBO Teams and Direct Line use `/api/messages/obo`; AI Teammate uses `/api/messages`.

Subscription, tenant, principal, child-identity, channel-application, and package identifiers remain
protected operational values and must not be committed.

The 2026-08-30 read-only baseline found the backend resource group empty. The Foundry account,
project, and model deployment already exist in `rg-ai-foundry` and are not part of the create
boundary. `Microsoft.BotService` was not registered at that checkpoint; the 2026-08-31 read-only
recheck found it registered, so no provider mutation remains in the reviewed plan.

The user explicitly confirmed that Foundry remains in `rg-ai-foundry`; only new backend and Bot
resources belong in `rg-a365-custom-agents`.

Read-only preflight found no policy assignments at the target-group scope, the deterministic
`crjapanexpert` registry name available. The 2026-08-31 recheck found Korea Central
managed-environment usage at 25 of 50. Recheck all three immediately before deployment.

## Ordered workflow

1. Rename and validate all active source, projects, namespaces, tests, prompts, configuration,
   current documentation, and package branding.
2. Retune the four MCP services for Japan with attributed data sources and deterministic tests.
3. Compile infrastructure that creates Azure resources only in the existing backend resource group,
   creates only the reviewed MCP API application/service principal in Entra, and references the
   existing Foundry account across resource groups.
4. Build immutable host and MCP images, then collect a fresh live inventory, ARM validation,
   structured what-if, policy/quota/RBAC review, and explicit rollback plan.
5. From clean frontend roots, prepare Agent 365 dry runs for a new Japan Expert Blueprint, AI
   Teammate child, OBO child, endpoints, permissions, packages, and installations. Never use Seoul
   generated state as input.
6. Present the sanitized backend and Agent 365 dry runs and obtain separate explicit approval.
7. Only after approval, execute the exact reviewed changes and validate all three clients against one
   healthy revision.

## Japan data-source baseline

- Attractions and accommodation use OpenStreetMap Overpass data with ODbL attribution, bounded
  queries, caching, and a configurable endpoint. The 2026-08-31 live probe found the former
  `overpass.private.coffee` default returning 502/timeouts while `overpass-api.de` accepted the exact
  generated POST shape and returned the expected 0.6 JSON schema, so `overpass-api.de` is the current
  default. Public Nominatim and non-commercial MLIT P12/P33 datasets are not runtime dependencies.
- Forecasts and alerts use Japan Meteorological Agency data. Alert output relays attributed JMA
  content and never authors an unofficial Japanese warning. Any use of undocumented JMA JSON is
  isolated behind strict schema/staleness checks; the documented
  [JMA XML feed](https://xml.kishou.go.jp/xmlpull.html) remains the authoritative alert source.
- Current conditions may use an attributed third-party fallback only when clearly labelled as
  non-JMA data. Open-Meteo's non-commercial free tier is not the production default.
- Currency uses [Frankfurter](https://frankfurter.dev/) pinned to the ECB provider, with the
  [ECB data API](https://data.ecb.europa.eu/help/api/data) as fallback. JPY is the default travel
  currency and every quote includes its observation date and attribution.

The 2026-08-31 credential-free live schema probes succeeded for the JMA prefecture forecast JSON,
JMA Atom alert feed, MET Norway Locationforecast 2.0, Frankfurter v2's ECB-pinned array response, ECB
SDMX CSV, and the selected Overpass POST endpoint. These probes establish upstream schema
compatibility only; they are not production availability guarantees.

## 2026-08-31 phase-one dry-run evidence

- The target group still contained zero resources; exact-name Entra reads found zero
  `api-japanexpert`, `Japan Expert Blueprint`, or `Japan Expert` applications/service principals.
- The existing Foundry account and `gpt-5.6-sol` deployment were healthy, `crjapanexpert` remained
  available, all required resource providers were registered, and Korea Central managed-environment
  usage was 25 of 50.
- The live Bot OAuth provider catalog resolved `Aadv2` to provider ID
  `30dd229c-58e3-4a48-bdfd-91ec48eb906c`; the Bot connection template pins that resource-provider ID
  while retaining `Azure Active Directory v2` as its display name.
- Resource-group ARM validation passed against `rg-a365-custom-agents`.
- Structured incremental what-if reported 15 creates, five role assignments as `Unsupported` because
  their managed-identity principal IDs do not exist until deployment, zero modifies, and zero deletes.
  The 15 enumerated creates are one Log Analytics workspace, one Application Insights component, one
  ACR, one Container Apps environment, five workload identities, five Container Apps, and one ACR
  diagnostic setting.
- The Microsoft Graph Bicep extension's `api-japanexpert` application and service principal are part
  of the reviewed source boundary but are not enumerated by ARM what-if, so their separate zero-object
  read-back and rollback remain mandatory.
- The Bot phase is intentionally absent from phase one because `deployAzureBot=false`.

## Agent 365 preflight

The installed Agent 365 CLI is `1.1.214`. Clean config-free dry runs for both AI Teammate and OBO
completed without changes. A read-only Entra query found no application, service principal, or user
whose display name begins with `Japan Expert`. Requirements checks passed Azure authentication,
client-app configuration, and required PowerShell modules; automatic Frontier enrollment detection
remains unavailable. A separate read-only license inventory found available Agent Frontier capacity,
which must be rechecked before instance creation.

Post-dry-run read-back still found zero resources in the target backend group and zero Japan Expert
applications or service principals, confirming that no cloud mutation occurred.

The AI Teammate flow runs first and creates the shared Blueprint without an OBO identity. The OBO
flow uses the same `Japan Expert` base name; the CLI's display-name-first discovery must reuse the
existing Blueprint, then create the configured OBO identity and registration. Abort if read-back
shows more than one Japan Expert Blueprint.

### Resolved: binding the host managed identity to a clean Blueprint

Agent 365 CLI `1.1.214` has **no command-line option or API** to bind an externally deployed host
user-assigned managed identity during a config-free `a365 setup all --agent-name` run. Static
inspection of the installed tool package establishes this:

- The shipped API documentation for `Agent365Config.ManagedIdentityPrincipalId` reads: *"Principal ID
  of the managed identity. Can be set manually for migration scenarios. Read by BlueprintSubcommand
  for Federated Identity Credential creation."* It is a configuration property, not an input option.
- The CLI emits `Skipping Federated Identity Credential creation (no MSI Principal ID provided)`, so a
  config-free run creates the Blueprint with no host federated identity credential.
- The complete option inventory of the CLI contains no managed-identity, principal-id, or federated
  credential option, and `BlueprintCreationOptions` exposes only `DeferConsent`.
- The documented command surface for this version is `develop`, `develop-mcp`, `setup`, `publish`,
  `logs`, `query-entra`, and `cleanup`. There is no `config` command, so the remediation hint
  `a365 config init` that appears in one CLI message has no corresponding command in `1.1.214`.

**Resolution.** Official Microsoft Entra Agent ID guidance settles it: after `a365` creates the clean
Blueprint, add the deployed host managed identity as a Blueprint federated identity credential through
Microsoft Graph. This is the documented production path. It never edits generated CLI state, never
enters Bicep, and leaves the CLI owning the Blueprint, its permissions, and its registration.

| Field | Value |
| --- | --- |
| Request | `POST /v1.0/applications/<blueprint-application-object-id>/federatedIdentityCredentials` |
| `issuer` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| `subject` | host user-assigned managed identity **principal ID** |
| `audiences` | `api://AzureADTokenExchange` |
| `name` | a stable M8 credential name recorded in the change record |

Graph addresses the application by object ID on that path; the `appId` alternate key is available if
only the application ID is at hand.

The CLI's own credential path writes the identical shape - `{ name, issuer, subject, audiences }` with
issuer `https://login.microsoftonline.com/{TenantId}/v2.0` and subject set to the managed identity
principal ID - so a Graph-created credential is indistinguishable from one the CLI would have created
had its config carried the principal ID. Its idempotency and cleanup logic therefore recognise it:
`Federated Identity Credential already exists`, `No existing federated credential found with subject:
{Subject}`, and blueprint credential deletion during `a365 cleanup`.

**Boundary.** This is a separately reviewed tenant mutation. It runs only after the Blueprint exists
and only after explicit approval, never as part of a deployment, and never in Bicep.
`./tools/Test-Deployment.ps1` keeps that split honest: infrastructure must declare no Blueprint, agent
identity, or federated identity credential, must still publish `hostManagedIdentityPrincipalId` for
the handoff, and the runbook must document the approved Graph step with its issuer, subject, and
audience.

**Read-back.** `GET /v1.0/applications/<blueprint-application-object-id>/federatedIdentityCredentials`
must return exactly one M8 credential whose issuer names the expected tenant, whose subject equals the
host managed identity principal ID from the deployment output, and whose audience is
`api://AzureADTokenExchange`. Record the credential `id` in the change record.

**Rollback.** `DELETE /v1.0/applications/<blueprint-application-object-id>/federatedIdentityCredentials/<credential-id>`
for that one credential only. Never run `a365 cleanup blueprint` as a rollback for this step while
either child identity exists.

Ordering is fixed: the host managed identity must exist before Blueprint setup, and the host cannot
authenticate to the Blueprint connection profiles until this credential exists.

The OBO Agent Identity and OBO channel application are separate objects. The child identity performs
downstream token exchange; the single-tenant channel app is the inbound audience, Azure Bot
application, Teams manifest bot ID, and outbound Bot Connector credential. M8 creates a new Azure
Bot, Teams channel, Direct Line v3 site, and `japan-expert-obo` user OAuth connection in the target
resource group. Secrets remain process- or service-held operational values and never enter source or
dry-run output.

### Secure `japan-expert-obo` Bot Token Service boundary

CLI `1.1.214` owns the Blueprint and its delegated `access_agent_as_user` ingress scope, but it creates
no Azure Bot, channel, or OAuth connection in the Blueprint path. The backend therefore owns one
phase-gated Bot topology: the single-tenant Bot registration, Direct Line v3, Teams, and an Aadv2
`japan-expert-obo` connection. The OBO channel application remains distinct from both the Blueprint
and OBO child: it is the Bot `msaAppId`, inbound activity audience, Teams manifest bot ID, and OAuth
connection client; the configured OBO child still performs downstream token exchange.

The official
[`Microsoft.BotService/botServices/connections@2022-09-15`](https://learn.microsoft.com/azure/templates/microsoft.botservice/2022-09-15/botservices/connections)
contract marks `clientSecret` as sensitive and requires a secure parameter. M8 carries that value
through `@secure()` parameters at both Bicep boundaries, never gives it a committed value, never
outputs it, and never includes the Bot in the five-Container-App update wrapper. The official Teams
SSO shape supplies `tenantId` and `tokenExchangeUrl=api://botid-<channel-app-id>` to Aadv2. The
connection scope is the delegated ingress scope read back from the newly registered Japan Expert
Blueprint; it is not copied from Seoul state or guessed before registration.

The Bot phase is deployed. Its parameters came from a protected source outside the repository, ARM
validation and what-if showed exactly one bot, two channels, and one OAuth connection create, and the
mutation was separately approved. The channel application remains a distinct Entra object and is never
collapsed into the OBO child identity.

Teams SSO additionally requires the channel application to be a registered SSO resource: an
`api://botid-<channel-app-id>` identifier URI, an `access_as_user` delegated scope, pre-authorized
Microsoft first-party clients, a declared delegated permission to the Blueprint ingress scope, and
tenant-wide consent so every user is covered rather than only the first interactive consenter.

The `gpt-5.6-sol` deployment uses the Foundry Responses API. Runtime tokens target
`https://ai.azure.com/.default`. A clean `a365 setup permissions custom --dry-run` for the public
Azure Machine Learning Services application and delegated `user_impersonation` scope completed
without changes; execute that permission step only after the new Blueprint exists and the reviewed
registration mutation is approved. Both effective child identities also require the documented
built-in `Cognitive Services User` inference role on the existing Foundry account. That role permits
account key retrieval even though the host never uses keys; replace it with an inference-only custom
role only after that role is proven against this exact Responses deployment.

A separate clean custom-permission dry run covered the three delegated Microsoft Graph scopes used
by fail-closed Purview evaluation: `Content.Process.User`, `ProtectionScopes.Compute.User`, and
`ContentActivity.Write`. Standard setup output is not accepted as proof that these scopes or their
inheritance were applied; post-change read-back must verify them explicitly.

## Purview synthetic cases and policy change boundary

M8 acceptance uses exactly three reserved synthetic cases. Korean passport and Korean
resident-registration cases are retired; they remain only in the historical M2 and M7 records and are
not Japan Expert acceptance evidence.

| Case | Reserved shape | Committed? |
| --- | --- | --- |
| Japan passport | `ZZ` followed by 7 digits | Direct Line synthetic fixture only |
| Japanese residence card | `ZZ` followed by 8 digits followed by `ZZ` | Direct Line synthetic fixture only |
| Payment card | industry reserved test number | Direct Line synthetic fixture only |

`ZZ` is not issued for real Japanese travel or residence documents, so the first two shapes cannot
collide with a real document. The three exact values are confined to the frontend-owned
[`sensitive-information-type-test.json`](../../../a365-tourist-agent-obo-directline/direct/sensitive-information-type-test.json)
fixture and are never copied into backend source, parameter files, logs, or evidence output. Backend
`./tools/Test-Repository.ps1` enforces that boundary: it fails on any checksum-valid card-shaped
number in the backend and on any passport- or residence-card-shaped backend literal outside the
reserved prefix, reporting file, rule, and line without echoing the value.

### Reviewed policy and location change boundary

Seoul application locations and rules are not reusable as acceptance evidence, because Purview scopes
DLP evaluation to the application identity that submits content. A new Blueprint and a new OBO channel
application therefore need their own reviewed locations before acceptance can be claimed. No DLP or
Insider Risk policy may be created, updated, or removed under M8 without a separate approval; this
section records the proposed boundary only.

Proposed change set, to be reviewed and approved as one unit:

1. Add the new Japan Expert Blueprint application as a Purview policy location for the existing
   governed-AI DLP policy. Record its current locations first.
2. Add the new OBO channel application as a policy location for the same policy.
3. Confirm the policy already covers the sensitive information types behind the three reserved cases.
   Do not author a new rule if an existing rule already matches.
4. Leave every Insider Risk policy untouched. M2 indexing behaviour stays as recorded.

Evidence required before approval: the exact current location list, the exact proposed additions, the
rule identifiers that will evaluate the three cases, and the confirmation that no rule condition,
action, or severity changes.

Rollback: remove only the two added application locations and restore the captured location list. No
rule, condition, or action is modified, so rollback cannot alter enforcement for any other workload.

Read-only verification uses `./tools/Test-Purview.ps1 -RequireImplemented -Online -CheckTenantPolicy`,
which calls `Get-FeatureConfiguration -FeatureScenario KnowYourData` and never changes policy. A
direct `-ProbePolicy` call proves a policy-service outcome only; channel-level pre-model enforcement
still requires a governed turn plus sanitized host block evidence.

The host constructs the OpenAI-compatible base by appending `/openai/v1` to the Foundry **account**
endpoint. The project-scoped `/api/projects/<name>` form does not publish that surface on this
account and returns HTTP 404/403, so it must never be configured. The OpenAI Responses client
appends `/responses`, and v1 uses implicit versioning; no raw `responses?api-version=...` URL or API
version is copied into application configuration.

The Responses-to-`IChatClient` adapter in `Microsoft.Agents.AI.OpenAI` is currently marked
experimental by Agent Framework. The warning suppression is scoped to client construction, stored
response output is disabled, and the full Purview/function-invocation/telemetry pipeline remains
covered by tests. Revalidate the adapter before every dependency upgrade.

## Rollback boundary

Before mutation, record the exact empty target-group baseline, existing Foundry resource/model,
candidate image digests, generated deployment plan, and every proposed Entra/Agent 365 object. A
rollback deletes only M8-created resources and registrations or restores captured pre-change values.
It must not modify or delete the historical Seoul production boundary.

For Agent 365 rollback, remove M8-created instances/child identities and endpoint registrations
before removing `Japan Expert Blueprint`; never run Blueprint cleanup while either intended child
still exists. For Azure rollback, delete only resources listed by the M8 deployment operation log
from `rg-a365-custom-agents`; never delete the resource group or the cross-group Foundry account.
Remove the M8-created MCP API application, OBO channel application/credential, Azure Bot channels,
OAuth connection, and cross-group role assignments only by their captured M8 identifiers.

## 2026-08-31 - OBO live acceptance on host revision 0000004

The Direct Line to `/api/messages/obo` path now completes end to end. Four independent defects were
found and fixed. Each was proven against live production rather than inferred.

| Failure | Ground truth | Fix |
| --- | --- | --- |
| `JEX-AUTH-001` at `identity.resolve` | The Blueprint had no `inheritablePermissions` entry for Azure Machine Learning Services (`https://ai.azure.com`), and neither a grant nor an inheritance entry for the custom MCP API, so the child `.default` OBO exchanges had nothing to inherit. | Created `allAllowed` inheritance for the Azure ML and MCP API resource apps, plus a tenant-wide `Mcp.Invoke` grant on the Blueprint service principal. |
| Purview fail-closed rejection | The Blueprint Microsoft Graph grant lacked `Content.Process.User`, `ProtectionScopes.Compute.User`, and `ContentActivity.Write`, so `processContent` and `protectionScopes/compute` returned HTTP 403. | Added the three delegated scopes to the existing Graph grant. |
| Stale cached tokens | The active replica still held Graph tokens minted before the grant change. | Restarted the single active revision. |
| `JEX-INT-001` at `agent.run` | `AgentHost__FoundryProjectEndpoint` pointed at the project-scoped path. That path returns HTTP 404 for `/openai/v1/models` and HTTP 403 for `/openai/v1/responses`; the account endpoint returns HTTP 200. | Repointed the setting to the Foundry account endpoint in source, both templates, tests, and documentation, then deployed directly to production. |

`Cognitive Services User` remains the correct inference role. It carries
`Microsoft.CognitiveServices/*` and inherits to the project scope. A 401 seen while probing came from
an operator account that held no data action, not from an agent defect.

Deployment used the single-revision production path only, with no canary, traffic split, or parallel
environment. Host revision `0000004` is Healthy at 100 percent traffic and the four MCP revisions
remain `0000001` and Healthy. The rollback target is host revision `0000003`, which differs only by
the corrected Foundry endpoint.

Live evidence: a governed OBO turn returned a model answer, an OpenStreetMap-attributed Kyoto
attraction, and an ECB/Frankfurter USD-JPY reference rate, while Purview `processContent`,
`protectionScopes/compute`, and `contentActivities` and all four MCP services returned HTTP 200. The
Blueprint client secret printed by the operator `a365 setup all` run was revoked and no longer
exists.

## 2026-08-31 - Model failure classification and host revision 0000005

Live turns intermittently returned `JEX-INT-001` while Microsoft Foundry itself was healthy: the same
deployment, endpoint, and payload returned HTTP 200 with rate limits untouched (149 of 150 requests
remaining). The turn failed roughly 38 ms after Purview completed, which is far too fast for a model
round trip.

The cause of the blindness was a classification gap. `AgentFailureClassifier` handled
`RequestFailedException`, `MsalServiceException`, and `HttpRequestException`, but the Foundry
Responses client reports transport failures as `ClientResultException`. That type fell through to the
`Internal` fallback, so every model transport failure was reported as `JEX-INT-001` with no status
recorded. A throttled or unauthorized model call was indistinguishable from a genuine internal fault,
and the operator message was wrong.

The classifier now maps `ClientResultException.Status` through the same status table as the other
dependency exceptions, so a throttled model call correctly yields `JEX-DEP-002` and its "service is
busy" message. `GetDependencyStatus` exposes the transport status for the two turn-failure log
events, which now record `dependencyStatus`. The status is deliberately the only detail logged; the
exception message can carry service payload content and is never emitted.

Deployment used the single-revision production path. Host revision `0000005` runs image digest
`sha256:b576071ea5caaaf74053e3fefa377464e2f7bea82ef0241a385acc4266dd715e` and is Healthy at 100
percent traffic. The rollback target is digest
`sha256:075bc949bd07772e822883de829ea9d5d118c4b3a47c641010a466a7c29724c8`.

After the fresh replica, eleven consecutive live OBO turns succeeded, including tool-using prompts for
currency, weather, and attractions. The intermittent failures were last observed on the prior replica,
which had been running for about six and a half hours, so the next occurrence must be diagnosed from
the recorded `dependencyStatus` rather than assumed to be transient.

## 2026-08-31 - ServiceConnection audience correction and host revision 0000006

`Connections__ServiceConnection__Settings__Scopes__0` was carrying the Entra token-exchange audience
`api://AzureADTokenExchange/.default`. That value belongs to `OboServiceConnection`, which is the
connection that produces the child-bound parent assertion. `ServiceConnection` is instead the
`ConnectionsMap` default for outbound channel calls on `/api/messages`, so it must target the Agent 365
Messaging Bot API `5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default`. The agentic handlers were never
affected, because the SDK's agentic token provider hardcodes the token-exchange audience for its own
federated legs.

The corrected scope is now identical in all three source layers: the deployment template
`infra/modules/agent-host-container-app.bicep`, its compiled
`infra/live-backend-container-apps-update.json`, and the local
`server/agent-host/JapanExpert.AgentHost/appsettings.json`. `AgentIdentityAuthorizationOptionsTests`
pins one audience per connection, so a regression fails the backend suite rather than reaching a
deployment.

This was a configuration-only change, so no image was rebuilt. Host revision `0000006` runs the same
digest `sha256:b576071ea5caaaf74053e3fefa377464e2f7bea82ef0241a385acc4266dd715e` and is Healthy at 100
percent traffic, and the four MCP revisions remain `0000001` and Healthy. The rollback target is host
revision `0000005`, which is the same image and differs only by that one scope.

Verified read-only against the live deployment: `/api/health` and `/api/health/live` return
`healthy`; `/api/health/ready` returns `degraded`, which is the intended `MemoryStorage` signal and is
matched by `maxReplicas: 1`; `/api/messages` and `/api/messages/obo` both reject unauthenticated
callers with HTTP 401; every literal setting in the host and the four MCP templates matches the running
configuration; each app pulls from `crjapanexpert` with its own user-assigned identity and the registry
has no admin user. This entry records deployed state only. It is not authorization to deploy, and a
future mutation still requires a fresh what-if, an explicit rollback boundary, and approval.
