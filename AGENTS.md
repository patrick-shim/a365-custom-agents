# Japan Tourist Assistant Workspace Guide

> **LOCKED (2026-08-31).** This workspace is frozen at a verified-good baseline. Do not modify any
> file, dependency, pin, or resource without an explicit, file-scoped instruction from the repository
> owner. Read [Change lock](#change-lock) before taking any action.

This workspace contains one canonical shared backend and three channel-only frontend projects.

## Change lock

This workspace is **locked**. It was rebuilt from scratch and fully validated on 2026-08-31, and is
frozen at that baseline.

| Baseline item | Verified value |
| --- | --- |
| .NET SDK | `10.0.110`, pinned in every `global.json` with `rollForward: latestPatch` |
| `a365-tourist-backend/JapanExpertAgent.slnx` | 17/17 projects, 0 warnings, 0 errors |
| `a365-tourist-agent-obo-directline/JapanExpert.OBO.DirectLine.slnx` | 2/2 projects, 0 warnings, 0 errors |
| Tests | 340 passed, 0 failed, 0 skipped |
| `a365-tourist-backend/tools/Invoke-LocalCi.ps1 -Strict` | 11 passed, 0 failed |
| Contract pins and icons | Aligned across all three channels |
| Deployment | Backend live in `rg-a365-custom-agents`; OBO Teams and OBO Direct Line accepted |

### Prohibited without explicit approval

Do not edit, rename, move, refactor, reformat, or tidy any file. Do not add, remove, or upgrade a
package. Do not change a version pin, target framework, analyzer setting, or `global.json`. Do not
modify `infra/`, `Dockerfile*`, or `.github/workflows/`. Do not mutate any Azure resource or Agent
365 registration. Do not hand-edit, regenerate, or delete protected operational state. Do not stage,
commit, revert, or clean the working tree on the owner's behalf.

Opportunistic cleanup is the exact failure mode this lock exists to prevent. A change being
obviously correct, harmless, idiomatic, or an improvement is not authorization.

### Always allowed

Reading any file. Building, testing, and running `a365-tourist-backend/tools/` validation, which is
offline and read-only. Reporting findings, including a proposed diff that is described but not
applied.

### Unlocking

An unlock is per-task and must come from the repository owner as an explicit instruction naming the
files or the project to change. "Fix it", "make it better", a failing build, or a green CI run are
not unlocks. When a task is authorized:

1. Change only the named scope, inside the one owning project.
2. Leave this lock section intact.
3. Re-run the owning project's validation and report the result.
4. If the change would alter any row in the baseline table above, stop and confirm first.

## Naming rules

Every user-visible and directory-object name derives from one product base name:

```
<Country> Tourist Assistant
```

For this workspace the base name is `Japan Tourist Assistant`.

| Surface | Name | Example |
| --- | --- | --- |
| OBO Teams app (`name.short` and `name.full`) | `<base> (OBO)` | `Japan Tourist Assistant (OBO)` |
| AI Teammate package (`name.full`) | `<base> (Teammate)` | `Japan Tourist Assistant (Teammate)` |
| AI Teammate package (`name.short`) | `<base> (Team)` | `Japan Tourist Assistant (Team)` |
| Agent 365 Blueprint | `<base> BP` | `Japan Tourist Assistant BP` |
| Agent 365 child Agent Identity | `<base> ID` | `Japan Tourist Assistant ID` |
| OBO channel Entra application | `<base> OBO Channel` | `Japan Tourist Assistant OBO Channel` |
| Azure Bot `displayName` | `<base>` | `Japan Tourist Assistant` |
| Workspace directory | `<country>-tourist-agent` | `japan-tourist-agent` |
| Azure resource group | shared by both products | `rg-a365-custom-agents` (koreacentral) |

Rules:

- The channel suffix is parenthesised and capitalised: `(OBO)` and `(Teammate)`. Do not use other
  spellings such as `TEAMMATE`, `Expert`, `Tourist Agent`, or `Tour Assistant`.
- The Teams manifest schema caps `name.short` at 30 characters and `name.full` at 100.
  `<base> (Teammate)` is 34 characters, so the AI Teammate package carries the governed name in
  `name.full` and the 30-character `<base> (Team)` in `name.short`. This is a schema limit, not a
  style choice; restoring `(Teammate)` to `name.short` makes the package fail upload validation.
- `agentIdentityDisplayName` and `agentBlueprintDisplayName` in each `a365.config.json` are the CLI
  inputs that produce the Blueprint and Identity names; keep them in step with the table.
- `a365 publish` rewrites `manifest/manifest.json` and seeds `name.short` and `name.full` from
  `agentBlueprintDisplayName`, which yields the 33-character `Japan Tourist Assistant Blueprint`
  and overflows `name.short`. The CLI reports this as `EXCEEDS 30 chars`. After every publish,
  restore the two names from the table and repackage `manifest.zip` from the manifest directory.
- Renaming a directory object changes its display name only. Never delete or recreate a Blueprint,
  Agent Identity, or channel application to rename it: the object IDs are referenced by the container
  app settings, the bot OAuth connection, and the Foundry role assignments.
- Azure resource names, Entra `identifierUris`, bot OAuth connection names, .NET namespaces, assembly
  names, and image repositories are separate identifier schemes. They are deliberately **not**
  governed by this table, because they are bound to deployed infrastructure and consent state.

## Source authority

- `a365-tourist-backend` is the only source for shared host behavior, agent orchestration, MCP
  services, integrations, infrastructure, Docker assets, backend tests, validation tools, and Azure
  deployment automation.
- `a365-tourist-agent-obo` owns only the OBO Teams package source, protected OBO operational state,
  and the contract pin for `/api/messages/obo`.
- `a365-tourist-agent-obo-directline` owns only the OBO Direct Line client, focused tests, synthetic
  prompt list, and the contract pin for `/api/messages/obo`.
- `a365-tourist-agent-teammate` owns only the AI Teammate package boundary, protected CLI state, and
  the contract pin for `/api/messages`.
- `a365-tourist-agent-obo-teammate/` is a separate project. Do not inspect, change, stage, or commit
  it without separate, specific human approval.

No frontend may recreate, copy, or deploy backend code. OBO Teams and Direct Line share
`/api/messages/obo`; AI Teammate uses `/api/messages`. All three consume the single backend Azure
deployment.

## Operational and Git boundaries

Agent 365 generated configuration, manifests, ZIP packages, identities, secrets, tenant-bound
environment files, and deployment evidence are operational artifacts. Preserve them locally, but
never copy, hand-edit, stage, commit, or delete them during source cleanup. Rehydrate frontend state
only through its approved CLI workflow.

The root `.gitignore` is the workspace safety boundary. Before every commit, verify ignored paths,
review the complete staged file list, and run the owning project's secret/repository checks. The
three `backend-contract.lock.json` files are non-secret source pins and are expected to be committed;
generated Agent 365 state is not.

## Working rules

- Read the child project's `AGENTS.md` and `docs/milestones/milestones.json` before making changes.
- Scope commands and mutations to one owning child project at a time.
- Change shared runtime behavior only in `a365-tourist-backend`.
- Preserve `/api/messages`, `/api/messages/obo`, their distinct audiences, the shared Blueprint,
  and the two-child identity model.
- Treat deployment revisions and digests recorded in documentation as a checkpoint, not standing
  authorization. Re-read live state and produce a fresh what-if and rollback boundary before a
  future mutation.

## Active M8 coordination

M8 performs a clean product migration from Seoul Tourist to Japan Tourist Assistant. Active source, .NET
identifiers, current documentation, MCP behavior, package branding, icons, Azure resources, and
Agent 365 registrations must become Japan Tourist Assistant ground truth. M0-M7 remain explicitly historical.

All new backend resources must be deployed only into the existing `rg-a365-custom-agents` resource
group in the user-selected subscription. The existing `a365-ai-foundry` account, `default` project,
and `gpt-5.6-sol` deployment are referenced in place and must not be recreated or moved. Subscription,
tenant, identity, and package identifiers remain protected operational values and are never committed.

M8 work proceeds by owner:

1. Fix shared behavior, infrastructure, deployment, MCP, identity selection, and Purview middleware
   only in `a365-tourist-backend`.
2. Fix only Teams package/channel surfaces in `a365-tourist-agent-obo`.
3. Fix only Direct Line client and acceptance surfaces in `a365-tourist-agent-obo-directline`.
4. Fix only authoritative Agent 365 package/channel surfaces in `a365-tourist-agent-teammate`.
5. Validate OBO Teams and Direct Line through `/api/messages/obo`, and AI Teammate through
   `/api/messages`, against one healthy Japan Tourist Assistant revision before declaring M8 complete.

Current state: the backend is deployed into `rg-a365-custom-agents`, and OBO Teams and OBO Direct Line
both have live accepted turns covering Agent Identity resolution, fail-closed Purview, all four MCP
services, and the Foundry model call. AI Teammate has a built package but no live turn, so M8 stays
active until step 5 is satisfied for all three channels.

Every mutation still requires the active child milestone to allow it, a reviewed dry run and
rollback boundary, and explicit approval. Never weaken ownership or edit protected operational state
to make acceptance pass.
