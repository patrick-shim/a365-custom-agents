# Korea Tourist Assistant Shared Backend Guide

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
hand-edit, publish, stage, commit, or use it as current source authority. M7 deployment work must use
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
dotnet build KoreaExpertAgent.slnx --configuration Release
dotnet test KoreaExpertAgent.slnx --configuration Release
./tools/Invoke-LocalCi.ps1 -OutputFormat Json
./tools/Test-Repository.ps1 -Strict -OutputFormat Json
dotnet run --project server/agent-host/KoreaExpert.AgentHost --launch-profile Playground
```

PowerShell validation is offline/read-only unless an online switch is explicit. When a tools
specialist is available, it may gather sanitized Azure/Purview evidence; the scripts themselves must
never log in, deploy, grant consent, or mutate tenant policy.

## Active M7 deployment alignment

M7 requires zero unexplained mismatch between source and deployment in routes, audiences,
authentication, child identity, Purview, MCP contracts, observability, configuration,
infrastructure, and revision provenance. The detailed checkpoint is
`docs/milestones/M7-end-to-end-alignment.md`; do not duplicate it as immutable authority elsewhere.

The current checkpoint is host revision `0000028`, with a fresh Purview wrapper per protected turn
and deferred wrapper disposal at host shutdown. The four MCP services remain on revision `0000005`.
Revision `0000027` is the verified host rollback boundary. Before any later deployment, read live
state again and review a fresh ARM validation, structured what-if, immutable candidate digest, and
rollback validation.

Backend code, infrastructure, Docker assets, tests, tools, and deployment automation remain
exclusive to this project. Frontend package and channel operations belong to the owning frontend.
Every production or tenant mutation requires milestone authorization, a reviewed dry run and
rollback boundary, and explicit approval. Completion requires all three frontends to pass live
against the same backend revision; never solve drift by moving backend code into a frontend.
