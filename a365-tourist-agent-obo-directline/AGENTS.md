# Korea Expert OBO Direct Line Frontend Guide

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
dotnet test KoreaExpert.OBO.DirectLine.slnx --configuration Release
dotnet run --project direct/KoreaExpert.Direct
```

## Active M7 status

The client and contract pin pass 5/5 focused tests. Against backend revision `0000028`, exactly three
approved synthetic cases—credit card, South Korean passport, and resident-registration number—were
sent with three-minute isolation gaps. Each was blocked before model access, model requests remained
zero in the covered interval, prompt values were not echoed, and no closed-channel warning appeared.

Broad 120-case SIT runs are useful for exploratory policy coverage but are not accepted as isolated
M7 pre-model evidence. Use a reviewed three-case input and an isolation interval for acceptance, then
correlate sanitized host policy-block evidence with zero model requests.

Preserve `/api/messages/obo`, `TokenValidation__Audiences__OnBehalfOf`, the existing OBO child
identity, OAuth behavior, and token renewal. Fix shared behavior only in `../a365-tourist-backend`.
Tenant, consent, route, audience, Purview, and policy changes still require a reviewed dry run,
rollback boundary, and explicit approval.
