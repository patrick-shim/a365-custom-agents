# Japan Tourist Expert Workspace Guide

This workspace contains one canonical shared backend and three channel-only frontend projects.

## Verified baseline

If you forked this repository, **change it freely** — it is a reference implementation and it is
yours. This section records the state the upstream baseline was validated at, so you can tell whether
a failure you are seeing is something you introduced or something that was already there.

| Baseline item | Verified value |
| --- | --- |
| .NET SDK | `10.0.110`, pinned in every `global.json` with `rollForward: latestPatch` |
| `a365-tourist-backend/JapanExpertAgent.slnx` | 17/17 projects, 0 warnings, 0 errors |
| `a365-tourist-agent-obo-directline/JapanExpert.OBO.DirectLine.slnx` | 2/2 projects, 0 warnings, 0 errors |
| Tests | 340 passed, 0 failed, 0 skipped |
| `a365-tourist-backend/tools/Invoke-LocalCi.ps1 -Strict` | 11 passed, 0 failed |
| `a365-tourist-backend/tools/Test-Repository.ps1 -Strict` | 30 passed, 0 failed |
| Contract pins and icons | Aligned across all three channels |

Reproduce it before changing anything:

```powershell
cd a365-tourist-backend
./tools/Invoke-LocalCi.ps1 -Strict
./tools/Test-Repository.ps1 -Strict
```

### Invariants worth preserving

These are not style preferences. Each one is enforced by `Test-Repository.ps1`, and breaking one
produces a system that looks fine and fails in production:

- The agent identity is never the host managed identity. The host user-assigned managed identity
  federates into the Blueprint; the Blueprint's inheritable permissions flow to each child identity.
- Foundry, Graph, and MCP tokens are acquired per resource, per turn, bound to the child identity.
  Do not collapse them into one token or cache them across turns.
- Purview evaluation is fail-closed. Do not add a fallback that lets an unevaluated turn through.
- Prompt Shields injection screening is fail-closed and covers two surfaces: the user prompt and
  tool **results**. Do not narrow it to one surface, and do not convert a block, transport error,
  non-success status, or unparsable body into a permissive path. Tool results are the indirect
  injection vector Purview does not inspect.
- MCP services validate a delegated `Mcp.Invoke` token and stay on internal ingress.
- MCP tool descriptions are part of the SHA-256 schema fingerprint. Editing a description without
  repinning the fingerprint fails the build, and that is deliberate.
- Deployments reference image digests, never mutable tags.

### If you are maintaining the upstream copy

The upstream working copy is change-controlled: no file, dependency, pin, or Azure resource changes
without an explicit, file-scoped instruction from the repository owner. Building, testing, and
running `a365-tourist-backend/tools/` validation are always allowed. A change being obviously correct
is not authorization.

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
<Country> Tourist Expert
```

For this workspace the base name is `Japan Tourist Expert`.

| Surface | Name | Example |
| --- | --- | --- |
| OBO Teams app (`name.short` and `name.full`) | `<base> (OBO)` | `Japan Tourist Expert (OBO)` |
| AI Teammate package (`name.full`) | `<base> (Teammate)` | `Japan Tourist Expert (Teammate)` |
| AI Teammate package (`name.short`) | `<base> (Team)` | `Japan Tourist Expert (Team)` |
| Agent 365 Blueprint | `<base> BP` | `Japan Tourist Expert BP` |
| Agent 365 child Agent Identity | `<base> ID` | `Japan Tourist Expert ID` |
| OBO channel Entra application | `<base> OBO Channel` | `Japan Tourist Expert OBO Channel` |
| Azure Bot `displayName` | `<base>` | `Japan Tourist Expert` |
| Workspace directory | `<country>-tourist-agent` | `japan-tourist-agent` |
| Azure resource group | shared by both products | `rg-a365-custom-agents` (koreacentral) |

Rules:

- The channel suffix is parenthesised and capitalised: `(OBO)` and `(Teammate)`. Do not use other
  spellings such as `TEAMMATE` or `Tourist Assistant`; always spell `Tourist` correctly.
- The Teams manifest schema caps `name.short` at 30 characters and `name.full` at 100.
  `<base> (Teammate)` is 31 characters, so the AI Teammate package carries the governed name in
  `name.full` and the 27-character `<base> (Team)` in `name.short`. This is a schema limit, not a
  style choice; restoring `(Teammate)` to `name.short` makes the package fail upload validation.
- `agentIdentityDisplayName` and `agentBlueprintDisplayName` in each `a365.config.json` are the CLI
  inputs that produce the Blueprint and Identity names; keep them in step with the table.
- `a365 publish` rewrites `manifest/manifest.json` and seeds `name.short` and `name.full` from
  `agentBlueprintDisplayName`, which is `Japan Tourist Expert BP`, not a package name. After every
  publish, restore the two package names from the table and repackage `manifest.zip` from the
  manifest directory; do not carry the Blueprint suffix into the package name.
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

M8 performs a clean product migration from Seoul Tourist to Japan Tourist Expert. Active source, .NET
identifiers, current documentation, MCP behavior, package branding, icons, Azure resources, and
Agent 365 registrations must become Japan Tourist Expert ground truth. M0-M7 remain explicitly historical.

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
   `/api/messages`, against one healthy Japan Tourist Expert revision before declaring M8 complete.

Current state: the backend is deployed into `rg-a365-custom-agents`, and OBO Teams and OBO Direct Line
both have live accepted turns covering Agent Identity resolution, fail-closed Purview, all four MCP
services, and the Foundry model call. AI Teammate has a built package but no live turn, so M8 stays
active until step 5 is satisfied for all three channels.

Every mutation still requires the active child milestone to allow it, a reviewed dry run and
rollback boundary, and explicit approval. Never weaken ownership or edit protected operational state
to make acceptance pass.
