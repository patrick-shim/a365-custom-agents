# Japan Tourist Expert Shared Backend Guide

Read `docs/milestones/milestones.json` before any work and stay within the active milestone. Use
repository-contained architecture, configuration, deployment, and validation guidance as the source
of truth; use a Microsoft Foundry-specific skill only when one is actually available.

## Authority and frontend boundary

This is the canonical shared backend and the only project containing shared runtime behavior. Never
copy, restore, or derive backend behavior from a channel-only frontend.

Preserve one host with `/api/messages` and `/api/messages/obo`.
`contracts/frontend-backend-contract.json` is the versioned non-secret boundary for OBO Teams, OBO
Direct Line, and AI Teammate. Never add Teams packages, Direct Line clients, Agent 365 CLI state,
generated manifests, or tenant-bound identities here.

Historical deployment evidence under `.azure/` is protected operational state. Never copy,
hand-edit, publish, stage, commit, or use it as current source authority. M8 deployment work must use
fresh validation, an explicit rollback target, and the backend-owned deployment workflow.

## Boundaries

- `server/agent`: channel-independent prompts and Microsoft Agent Framework construction.
- `server/agent-host`: Agent 365 transport, identity, session state, Purview, and managed MCP loading.
- `server/integrations`: typed external provider clients.
- `server/mcp`: independently deployed HTTP MCP adapters with narrow contracts.
- `contracts`: versioned, non-secret frontend-to-backend integration contract.
- `infra`, `Dockerfile*`, and `tools`: the only deployment and backend validation authority.

Dependencies point inward from hosts and adapters. MCP services never reference the agent, and the
agent never references Teams or provider implementations.

## Commands

```powershell
dotnet build JapanExpertAgent.slnx --configuration Release
dotnet test JapanExpertAgent.slnx --configuration Release
./tools/Invoke-LocalCi.ps1 -OutputFormat Json
./tools/Test-Repository.ps1 -Strict -OutputFormat Json
dotnet run --project server/agent-host/JapanExpert.AgentHost --launch-profile Playground
```

PowerShell validation is offline/read-only unless an online switch is explicit. When a tools
specialist is available, it may gather sanitized Azure/Purview evidence; the scripts themselves must
never log in, deploy, grant consent, or mutate tenant policy.

## Active M8 migration and deployment

M8 brands the active product Japan Tourist Expert, retains the `JapanExpert` .NET identifiers, retunes MCP services for Japan, and
owns the clean deployment plus new Agent 365 registrations. Preserve `/api/messages`,
`/api/messages/obo`, their distinct audiences, one shared Blueprint with two child identities,
fail-closed Purview, fail-closed Prompt Shields injection screening across both the user prompt and
tool results, and the existing frontend/backend ownership boundary.

The backend is deployed into `rg-a365-custom-agents`, and OBO Teams and OBO Direct Line both have live
accepted turns. AI Teammate has a built package but no live turn, so M8 stays active. Two runtime
facts are easy to regress and are covered by tests: the host reaches the model through the Foundry
**account** endpoint plus `/openai/v1`, never the project-scoped path; and each federated connection
has exactly one correct audience, with `ServiceConnection` on the Agent 365 Messaging Bot API,
`OboServiceConnection` on Entra token exchange, and `OboChannelConnection` on the Bot Connector.

All new backend resources belong only in the existing `rg-a365-custom-agents` resource group. Refer
to the existing `a365-ai-foundry/default` project and `gpt-5.6-sol` deployment across resource groups;
do not recreate Foundry. Seoul deployment and registration records under M0-M7 are historical only
and cannot seed Japan Tourist Expert identities, packages, or deployment parameters.

Backend code, infrastructure, Docker assets, tests, tools, and deployment automation remain
exclusive to this project. Frontend package and channel operations belong to the owning frontend.
Every production or tenant mutation requires milestone authorization, a reviewed dry run and
rollback boundary, and explicit approval. Completion requires all three frontends to pass live
against the same backend revision; never solve drift by moving backend code into a frontend.
