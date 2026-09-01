# Japan Tourist Assistant agent workspace

> **LOCKED (2026-08-31).** This repository is frozen at a verified-good baseline. Do not modify any
> file, dependency, pin, or Azure resource without an explicit, file-scoped instruction from the
> repository owner. The authoritative rules are in [AGENTS.md](./AGENTS.md#change-lock).

Japan Tourist Assistant is a governed Microsoft travel agent for Japan. One shared C# backend serves three
channels: an OBO Teams app, an OBO Direct Line console client, and a Microsoft 365 AI Teammate.
Microsoft Agent Framework owns orchestration, Agent 365 owns runtime identity and transport,
Microsoft Purview protects prompt and response content fail-closed, and Japan travel data is served by
four independently deployed MCP services.

The backend is deployed once. Each frontend owns only its channel contract, package or client, and
acceptance evidence. No frontend contains backend code.

## Live status

| Channel | Route | Status |
| --- | --- | --- |
| OBO Teams | `/api/messages/obo` | Live and accepted in Microsoft Teams |
| OBO Direct Line | `/api/messages/obo` | Live and accepted from the console client |
| AI Teammate | `/api/messages` | Package built; awaiting Microsoft 365 licensing, upload, and install |

The backend, both OBO channels, Purview enforcement, all four MCP services, and the Foundry model call
are proven against one healthy production revision. AI Teammate acceptance is still open because no
live AI Teammate turn has run yet.

## Architecture

```mermaid
flowchart LR
  subgraph Channels
    Teams[OBO Teams package<br/>Japan Tourist Assistant]
    Direct[OBO Direct Line client]
    Teammate[AI Teammate package<br/>Japan Tourist Assistant Teammate]
  end

  Teams -->|Teams channel| Bot[Azure Bot<br/>bot-japanexpert]
  Direct -->|Direct Line v3| Bot
  Bot -->|/api/messages/obo| Host[Agent host<br/>ca-agent-japanexpert]
  Bot -->|japan-expert-obo| OAuth[Aadv2 OAuth connection]
  Teammate -->|/api/messages| Host

  subgraph Identity[Agent 365 identity]
    Blueprint[One shared Blueprint]
    Blueprint --> OboChild[OBO child Agent Identity]
    Blueprint --> TeammateChild[AI Teammate child identities]
  end
  Host -.resolves per turn.-> Identity

  Host --> Purview[Microsoft Purview<br/>fail-closed prompt and response DLP]
  Host --> Foundry[Existing a365-ai-foundry<br/>gpt-5.6-sol Responses API]
  Host --> Attractions[Attractions MCP]
  Host --> Weather[Weather MCP]
  Host --> Stay[Accommodation MCP]
  Host --> Currency[Currency MCP]

  Attractions & Stay --> OSM[OpenStreetMap Overpass]
  Weather --> JMA[JMA forecast and alerts]
  Weather -. labelled fallback .-> MetNo[MET Norway]
  Currency --> Frank[Frankfurter pinned to ECB]
  Currency -. fallback .-> ECB[ECB SDMX]
```

Only the agent host has external ingress. The four MCP apps use internal ingress and validate the
shared delegated `Mcp.Invoke` scope. Every MCP data source is a credential-free public HTTPS API, so
no workload holds a data-plane role or reads a provider secret.

## Projects and ownership

| Project | Owns | Backend route |
| --- | --- | --- |
| [`a365-tourist-backend`](a365-tourist-backend/README.md) | Shared runtime, MCP services, integrations, infrastructure, Docker assets, tests, tools, deployment | `/api/messages`, `/api/messages/obo` |
| [`a365-tourist-agent-obo`](a365-tourist-agent-obo/README.md) | OBO Teams package source and protected OBO CLI state | `/api/messages/obo` |
| [`a365-tourist-agent-obo-directline`](a365-tourist-agent-obo-directline/README.md) | Direct Line console client, focused tests, synthetic SIT list | `/api/messages/obo` |
| [`a365-tourist-agent-teammate`](a365-tourist-agent-teammate/README.md) | AI Teammate package boundary and protected CLI state | `/api/messages` |

The `a365-tourist-*` directory names are stable repository ownership boundaries kept for
compatibility. They are not product branding: active projects, namespaces, packages, prompts, Azure
resources, and current documentation all use Japan Tourist Assistant.

`a365-tourist-agent-obo-teammate/`, if present, is a separate excluded project. Do not inspect,
modify, stage, or commit it without specific human approval.

Per-project rules live in the backend [`AGENTS.md`](a365-tourist-backend/AGENTS.md), OBO Teams
[`AGENTS.md`](a365-tourist-agent-obo/AGENTS.md), Direct Line
[`AGENTS.md`](a365-tourist-agent-obo-directline/AGENTS.md), and AI Teammate
[`AGENTS.md`](a365-tourist-agent-teammate/AGENTS.md).

## Routes, audiences, and identity

Two protected host modes share one Blueprint and one deployment but keep separate audiences, child
identities, session keys, packages, and CLI state.

| | AI Teammate | OBO Teams and Direct Line |
| --- | --- | --- |
| Route | `/api/messages` | `/api/messages/obo` |
| Accepted audience | shared Blueprint application | OBO channel application |
| Child identity | resolved dynamically from the signed activity | the configured OBO child Agent Identity |
| Outbound channel connection | `ServiceConnection` | `OboChannelConnection` |

Three federated connection profiles exist, and each has exactly one correct audience:

| Connection | Audience | Purpose |
| --- | --- | --- |
| `ServiceConnection` | Agent 365 Messaging Bot API | Outbound `/api/messages` channel calls |
| `OboServiceConnection` | Entra token exchange | Child-bound parent assertion for the OBO exchange |
| `OboChannelConnection` | Bot Connector | Outbound `/api/messages/obo` channel replies |

The Agents SDK hardcodes the Entra token-exchange audience inside its agentic token provider, so
`ServiceConnection` scope affects only outbound channel calls. Details and rationale are in the
backend [configuration guide](a365-tourist-backend/docs/configuration.md).

Agent identity is never the host managed identity. The host user-assigned managed identity federates
into the Blueprint; the Blueprint's inheritable permissions flow to each child identity. Foundry
data-plane access is granted per child identity, never to the host managed identity.

## Azure resources

All backend resources live in the existing `rg-a365-custom-agents` resource group. The Foundry account
`a365-ai-foundry`, its `default` project, and the `gpt-5.6-sol` deployment are referenced in place from
their own resource group and are never created, moved, or recreated by this repository.

| Resource | Purpose |
| --- | --- |
| `ca-agent-japanexpert` | Agent host, external ingress, the only public endpoint |
| `ca-attract-japanexpert`, `ca-weather-japanexpert`, `ca-stay-japanexpert`, `ca-fx-japanexpert` | MCP services, internal ingress |
| `crjapanexpert` | Container registry for immutable image digests |
| `bot-japanexpert` | Azure Bot with the Teams channel, a Direct Line site, and the `japan-expert-obo` Aadv2 OAuth connection |

The host reaches the model through the Foundry **account** endpoint plus `/openai/v1`. The
project-scoped `/api/projects/<name>` form does not publish that surface and must not be configured.

## Deploy

The authoritative, reviewed runbook is
[`a365-tourist-backend/infra/README.md`](a365-tourist-backend/infra/README.md). It defines the dry-run
sequence, deterministic names, committed identifier policy, mutation boundary, and rollback
boundaries. The phases below are the map; follow the runbook for exact parameters.

Every cloud or tenant mutation requires the active milestone to allow it, a reviewed dry run, an
explicit rollback boundary, and separate explicit approval. Deployment uses the single-revision
production path only: no canary, traffic split, or parallel environment.

```powershell
cd a365-tourist-backend

# 0. Offline gates first
dotnet test JapanExpertAgent.slnx --configuration Release
./tools/Test-Repository.ps1 -Strict -OutputFormat Json
./tools/Test-Deployment.ps1 -OutputFormat Json
```

1. **Bootstrap infrastructure.** Deploy `infra/main.bicep` into `rg-a365-custom-agents` after ARM
   validation and a structured what-if. This creates the registry, Container Apps environment, managed
   identity, Log Analytics, Application Insights, and the five apps on placeholder images.
2. **Build and push immutable images.** Use `az acr build` for the host and MCP images, then resolve
   each tag to a digest. Deployments reference digests, never mutable tags.
3. **Deploy the images.** Re-run the template with the resolved digests.
4. **Create Agent 365 identity.** Run `a365 setup all` from the owning frontend project. This creates
   or reuses the single shared Blueprint, its inheritable permissions, and the child identity. It also
   prints a Blueprint client secret; treat it as exposed and revoke it if it is not needed.
5. **Deploy the Bot phase.** The phase-gated Bot module creates `bot-japanexpert`, the Teams channel,
   the Direct Line site, and the `japan-expert-obo` OAuth connection.
6. **Complete the Entra wiring.** This is outside the templates and is the step most often missed:
   - a federated identity credential from the host managed identity to the Blueprint and to the OBO
     channel application;
   - a service principal for the OBO channel application;
   - `inheritablePermissions` with `allAllowed` for **every** resource the agent calls, including
     Azure Machine Learning for the Foundry audience and the custom MCP API. `a365 setup all` does
     **not** cover the custom MCP API, so add that one explicitly with
     `a365 setup permissions custom --resource-app-id <mcp-api-application-id> --scopes Mcp.Invoke`.
     A child identity holds no grants of its own, so a missing entry makes the per-turn `/.default`
     exchange expand to an empty scope set and the turn fails at `identity.resolve` with
     `JEX-AUTH-001`. Confirm with `a365 query-entra inheritance`, which must report every resource
     effective, and never repair consent with `az ad app permission admin-consent` - it replaces the
     Blueprint's entire grant set;
   - tenant-wide delegated grants on the Blueprint, including the three Purview Graph scopes;
   - Teams SSO on the OBO channel application: an `api://botid-<appId>` identifier URI, an
     `access_as_user` scope, and pre-authorized Microsoft first-party clients;
   - the documented `Cognitive Services User` role on the Foundry account for each child identity.
7. **Build the channel packages.** See below.
8. **Validate live.** Run a governed turn per channel against one healthy revision and confirm Purview,
   MCP, and observability behaviour.

Production application updates and rollbacks use the restrictive wrapper
`infra/live-backend-container-apps-update.bicep`, which touches only the five Container Apps.

## Channel packages

| Channel | Built by | Output |
| --- | --- | --- |
| OBO Teams | Microsoft 365 Agents Toolkit from `a365-tourist-agent-obo/teams/appPackage` | `teams/appPackage/build/appPackage.<env>.zip`, named by [`m365agents.yml`](a365-tourist-agent-obo/teams/m365agents.yml) |
| AI Teammate | `a365 publish --aiteammate` from `a365-tourist-agent-teammate` | a CLI-named package ZIP under `manifest/` |

Both packages use the source-owned Japanese-flag icons and the Japanese red accent. The Agent 365 CLI
generates placeholder branding and its own default icons, so its printed "Customize before packaging"
step is mandatory, not optional.

The Admin Center lists an uploaded agent by the manifest's `name.short`. The Teams app is
`Japan Tourist Assistant` and the AI Teammate agent is `Japan Tourist Assistant (Teammate)` so administrators can tell them
apart. Generated packages are operational artifacts and stay out of Git.

## Validate

```powershell
cd a365-tourist-backend
dotnet test JapanExpertAgent.slnx --configuration Release
./tools/Invoke-LocalCi.ps1 -OutputFormat Json
./tools/Test-Repository.ps1 -Strict -OutputFormat Json

cd ../a365-tourist-agent-obo-directline
dotnet test JapanExpert.OBO.DirectLine.slnx --configuration Release
```

PowerShell validation is offline and read-only unless an online switch is explicit. The scripts never
sign in, deploy, grant consent, or mutate tenant policy.

Repository CI is split by owner:

- [`backend-ci.yml`](.github/workflows/backend-ci.yml) rejects tracked frontend or operational residue
  and runs the backend local CI gate.
- [`obo-teams-ci.yml`](.github/workflows/obo-teams-ci.yml) validates the OBO contract, source manifest,
  and tracked ownership boundary.
- [`direct-line-ci.yml`](.github/workflows/direct-line-ci.yml) validates the Direct Line client,
  contract, and tracked ownership boundary.
- [`ai-teammate-ci.yml`](.github/workflows/ai-teammate-ci.yml) validates the AI Teammate contract, SDK
  pin, and tracked ownership boundary.
- [`contract-alignment-ci.yml`](.github/workflows/contract-alignment-ci.yml) compares all three
  frontend locks with the canonical backend contract.

[`dependabot.yml`](.github/dependabot.yml) schedules weekly backend and Direct Line NuGet updates and
repository-wide GitHub Actions updates.

## Git safety

The repository intentionally excludes build output, local keys, `.env` files, `.azure`, `.a365`,
CLI-owned configuration, generated manifests and ZIPs, and tenant-bound evidence. Those files exist
locally, must be preserved, and must never be committed. Subscription, tenant, and application
identifiers are operational values and are never committed; only fixed non-secret names such as the
resource group, the Foundry account, its project, its endpoint, and the model deployment may appear in
source.

The three `backend-contract.lock.json` files are non-secret source pins and are expected to be
committed. Review ignored and staged paths before every commit:

```powershell
git status --short --ignored
git diff --cached --name-only
```

## Milestones

`a365-tourist-backend/docs/milestones/milestones.json` is the machine-readable source of truth and
`docs/milestones/README.md` holds the human protocol. M8 is the active milestone: the Japan Tourist Assistant
migration, the Japan MCP retune, single-resource-group deployment, clean Agent 365 registration, and
same-revision cross-channel acceptance. M0 through M7 are explicitly historical and grant no
deployment or registration authority.

Key records:

- [M8 shared backend migration and deployment](a365-tourist-backend/docs/milestones/M8-japan-expert-migration.md)
- [M8 OBO Teams](a365-tourist-agent-obo/docs/milestones/M8-japan-expert-obo.md)
- [M8 Direct Line](a365-tourist-agent-obo-directline/docs/milestones/M8-japan-expert-direct-line.md)
- [M8 AI Teammate](a365-tourist-agent-teammate/docs/milestones/M8-japan-expert-ai-teammate.md)

## Copilot guidance

Repository-wide rules are in [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
Registered specialists are [Japan Tourist Assistant Agent Builder](.github/agents/japan-expert-agent-builder.agent.md),
[Japan Tourist Assistant Solution Reviewer](.github/agents/japan-expert-solution-reviewer.agent.md),
[MCP Service Builder](.github/agents/mcp-service-builder.agent.md), and
[Tools Specialist](.github/agents/tools-specialist.agent.md).

Read [`AGENTS.md`](AGENTS.md) and the owning child `AGENTS.md` before changing code, deployment state,
or channel assets.
