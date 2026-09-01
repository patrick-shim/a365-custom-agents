# Japan Tourist Assistant OBO Direct Line Frontend Guide

Read `docs/milestones/milestones.json` before work. This project contains only the Direct Line client
and acceptance boundary for the shared OBO route.

## Ownership

- `direct/` owns the .NET console client, focused tests, and synthetic prompt list.
- `backend-contract.lock.json` is a committed, non-secret source pin for `/api/messages/obo`, its OBO
  audience configuration, and the configured OBO child identity binding.
- `../a365-tourist-agent-obo` owns the OBO Teams package and protected OBO operational state.
- `../a365-tourist-agent-teammate` owns the authoritative AI Teammate package boundary.
- `../a365-tourist-backend` exclusively owns runtime code, Azure resources, MCP services, provider
  integrations, tests, infrastructure, Docker assets, and deployment.

This project must contain no Direct Line secret, private key, Teams package, Agent 365 CLI state,
generated manifest, or deployment asset. Secrets belong only in the current process environment.

## Commands

```powershell
dotnet test JapanExpert.OBO.DirectLine.slnx --configuration Release
dotnet run --project direct/JapanExpert.Direct
```

The root `../.github/workflows/direct-line-ci.yml` workflow runs the focused tests, validates the
contract pin, and rejects recursively tracked credentials, operational state, and foreign source.
The cross-project
`../.github/workflows/contract-alignment-ci.yml` workflow compares this pin and both other frontend
pins with the canonical backend contract.

## Active M8 status

Rename the solution, projects, namespaces, client identity, tests, and prompts to Japan Tourist Assistant while
preserving `/api/messages/obo`, OAuth completion, token renewal, and secret handling. A fresh Direct
Line site and OBO registration must be used after the reviewed M8 dry run; Seoul channel state and
evidence are historical only.

Use only approved synthetic Japan-oriented policy cases and correlate isolated host policy-block
evidence with zero model requests. Never use or expose real personal identifiers.

Preserve `/api/messages/obo`, `TokenValidation__Audiences__OnBehalfOf`, OAuth behavior, and token
renewal. Fix shared behavior only in `../a365-tourist-backend`.
Tenant, consent, route, audience, Purview, and policy changes still require a reviewed dry run,
rollback boundary, and explicit approval.
