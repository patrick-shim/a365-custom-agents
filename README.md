# Korea Tourist Assistant workspace

This monorepo is the source boundary for one shared Korea Tourist Assistant backend and three channel-only
frontends. The backend is deployed once; each frontend owns only its channel contract, package or
client, and acceptance workflow.

## Projects and routes

| Project | Owner boundary | Backend route |
| --- | --- | --- |
| [`a365-tourist-backend`](a365-tourist-backend) | Shared runtime, MCP, infrastructure, tests, tools, and deployment | `/api/messages`, `/api/messages/obo` |
| [`a365-tourist-agent-obo`](a365-tourist-agent-obo) | OBO Teams package source and protected operational state | `/api/messages/obo` |
| [`a365-tourist-agent-obo-directline`](a365-tourist-agent-obo-directline) | Direct Line console client, focused tests, and synthetic SIT list | `/api/messages/obo` |
| [`a365-tourist-agent-teammate`](a365-tourist-agent-teammate) | AI Teammate package boundary and protected CLI state | `/api/messages` |

The two protected host modes share one Agent 365 Blueprint and one deployed backend, but they keep
separate child Agent Identities, token audiences, packages, session keys, and CLI state:

| Mode | Route | Audience configuration | Identity binding |
| --- | --- | --- | --- |
| `agentic-user` | `/api/messages` | `TokenValidation__Audiences__AgenticUser` | `dynamic-child-agent-identity` |
| `on-behalf-of` | `/api/messages/obo` | `TokenValidation__Audiences__OnBehalfOf` | `configured-obo-child-agent-identity` |

OBO Teams and OBO Direct Line both reach the same `/api/messages/obo` route. Direct Line arrives
through an OBO Azure Bot using Direct Line v3 and the `korea-tourist-assistant-obo` OAuth connection; Teams
arrives through its published package. Because they share a route, audience, and child identity, they
also share DLP behavior — but each still owns its own acceptance evidence.

`a365-tourist-agent-obo-teammate/`, if present, is a separate excluded project. Do not inspect,
modify, stage, or commit it without specific human approval. It is excluded by the final entry in the
root [.gitignore](.gitignore).

## Contract alignment

[`a365-tourist-backend/contracts/frontend-backend-contract.json`](a365-tourist-backend/contracts/frontend-backend-contract.json)
is the authoritative, non-secret integration contract — `contractId: korea-expert-shared-backend`,
`contractVersion: 1.0.0`. It declares both frontend bindings, the three health endpoints
(`/api/health`, `/api/health/live`, `/api/health/ready`), and the MCP boundary: four services,
streamable-HTTP transport, delegated `Mcp.Invoke` authorization.

Each frontend repeats its matching subset in a committed `backend-contract.lock.json`. Unlike the
generated Agent 365 state around them, these lock files **are** non-secret source and are expected to
be in version control. `contract-alignment-ci.yml` compares all three against the backend contract and
fails the build on any drift.

## Continuous integration

Five workspace workflows in [.github/workflows](.github/workflows), all `windows-latest` with
`permissions: contents: read` and no cloud login:

| Workflow | Timeout | Scope |
| --- | --- | --- |
| `backend-ci.yml` | 25 min | .NET SDK `10.0.110`, then full backend local CI in Release |
| `ai-teammate-ci.yml` | 10 min | AI Teammate contract pin |
| `obo-teams-ci.yml` | 10 min | OBO Teams contract pin |
| `direct-line-ci.yml` | 10 min | Direct Line build, tests, and committed-credential rejection |
| `contract-alignment-ci.yml` | 5 min | Cross-project contract equality |

## Current deployment checkpoint

Rebuilt on 2026-09-01 into the shared resource group `rg-a365-custom-agents` in `koreacentral`,
alongside Japan Tourist Assistant. Every resource name is suffixed `koreaexpert`, so the two products
co-exist in one group without collision.

- Shared host `ca-agent-koreaexpert`: revision `0000001`, healthy, 100% traffic, `/api/health` 200.
- All four MCP services on revision `0000001` and healthy.
- Agent 365 objects were recreated from scratch: Blueprint `Korea Tourist Assistant BP`, child
  identity `Korea Tourist Assistant ID`, and a new agent registration.
- `a365 query-entra inheritance` reports 7 of 7 resources effective, including `api-koreaexpert`.
- Both federated identity credentials point at the rebuilt host managed identity.

Channel acceptance is open: the rebuild issued new Blueprint objects and a new OBO channel secret, so
no cached user token exists and the first turn of each channel returns a sign-in card. A governed turn
must be replayed and recorded per channel before this checkpoint counts as accepted.

This is a dated operational checkpoint, not deployment authority. The detailed sanitized record is
in [the backend M7 runbook](a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md).

## Agent Identity Entra wiring

The templates do not create Entra consent state. The child Agent Identity holds no grants of its own;
it inherits them from the Blueprint, so every resource the agent calls at runtime needs an
`inheritablePermissions` entry at `kind=allAllowed` **and** a grant on the Blueprint service principal.
A turn performs three on-behalf-of exchanges - Azure Machine Learning (the Foundry audience),
Microsoft Graph, and the custom `api-koreaexpert` MCP API - and each is requested with a `/.default`
scope, which Entra expands only from inherited permissions.

Missing the custom MCP API entry is the failure this repository hit: the Blueprint carried the
tenant-wide `Mcp.Invoke` grant but had no inheritance entry, so `.default` expanded to an empty scope
set and the exchange failed with `AADSTS65001` surfaced as `STA-AUTH-001`. Configure it with:

```powershell
cd a365-tourist-agent-obo
a365 setup permissions custom --resource-app-id <mcp-api-app-id> --scopes Mcp.Invoke
```

Verify before declaring a deployment healthy - the summary must cover every resource, including
`api-koreaexpert`:

```powershell
a365 query-entra inheritance
```

`Roles: WARN ... no app roles granted` is expected for delegated-only resources and does not affect
`Effective inheritance: OK`.

Never repair consent with `az ad app permission admin-consent`; it replaces the Blueprint's entire
grant set rather than adding to it.

## Validate

Run checks from the owning project root:

```powershell
cd a365-tourist-backend
./tools/Invoke-LocalCi.ps1 -OutputFormat Json
./tools/Test-Repository.ps1 -Strict -OutputFormat Json

cd ../a365-tourist-agent-obo-directline
dotnet test KoreaExpert.OBO.DirectLine.slnx --configuration Release
```

`Invoke-LocalCi.ps1` runs 11 gates: tool self-test, build, solution tests, three host health probes,
four MCP health probes, and process cleanup. Both solutions currently build with 0 warnings and
0 errors under `TreatWarningsAsErrors`; the backend suite passes 135 tests and the Direct Line suite
passes 5, with none failed or skipped.

The OBO Teams workflow validates its committed contract and source manifest. The AI Teammate workflow
validates its committed contract and rejects generated Agent 365 state in a clean checkout. Live
channel, package, tenant, and Purview acceptance is separate and requires the active M7 authorization,
a reviewed dry run and rollback boundary, and explicit approval for mutations.

## Git safety

The root repository intentionally excludes build output, local keys, `.env` files, `.azure`, `.a365`,
CLI-owned configuration, generated manifests/ZIPs, and tenant-bound evidence. These files may exist
locally and must be preserved, but they are not source and must never be committed. Review ignored
paths and the staged file list before each commit:

```powershell
git status --short --ignored
git diff --cached --name-only
```

Never commit `*.key`, `*.pem`, `*.pfx`, `*.p12`, `.env*` other than `.env.example`, or
`appsettings.Local.json`. Bearer tokens and API keys belong in process environment variables only —
never in source, command arguments, shell history, logs, or an appsettings file.

See [AGENTS.md](AGENTS.md) and each child `AGENTS.md` before changing code, deployment state, or
channel assets.
