# Japan Expert Workspace Guide

This workspace contains one canonical shared backend and three channel-only frontend projects.

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

M8 performs a clean product migration from Seoul Tourist to Japan Expert. Active source, .NET
identifiers, current documentation, MCP behavior, package branding, icons, Azure resources, and
Agent 365 registrations must become Japan Expert ground truth. M0-M7 remain explicitly historical.

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
   `/api/messages`, against one healthy Japan Expert revision before declaring M8 complete.

Current state: the backend is deployed into `rg-a365-custom-agents`, and OBO Teams and OBO Direct Line
both have live accepted turns covering Agent Identity resolution, fail-closed Purview, all four MCP
services, and the Foundry model call. AI Teammate has a built package but no live turn, so M8 stays
active until step 5 is satisfied for all three channels.

Every mutation still requires the active child milestone to allow it, a reviewed dry run and
rollback boundary, and explicit approval. Never weaken ownership or edit protected operational state
to make acceptance pass.
