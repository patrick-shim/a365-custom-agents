# Seoul Tourist Workspace Guide

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

## Active M7 coordination

M7 brings 100% of in-scope code, configuration contracts, infrastructure, and channel integrations
into alignment with the canonical backend, then proves all three frontends against one deployed
revision. "100% alignment" means zero unexplained drift in routes, audiences, authentication,
child-identity selection, Purview enforcement, MCP contracts, observability, package endpoints,
configuration, or revision provenance. It never means copying backend code into a frontend.

The current backend checkpoint is host revision `0000028`, digest
`sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`, with rollback revision
`0000027`, digest `sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`.
The four MCP services remain on revision `0000005`. Direct Line has isolated pre-model DLP evidence
against `0000028`; do not claim M7 complete until OBO Teams and AI Teammate also have sanitized live
acceptance recorded against that same revision.

M7 work proceeds by owner:

1. Fix shared behavior, infrastructure, deployment, MCP, identity selection, and Purview middleware
   only in `a365-tourist-backend`.
2. Fix only Teams package/channel surfaces in `a365-tourist-agent-obo`.
3. Fix only Direct Line client and acceptance surfaces in `a365-tourist-agent-obo-directline`.
4. Fix only authoritative Agent 365 package/channel surfaces in `a365-tourist-agent-teammate`.
5. Validate OBO Teams and Direct Line through `/api/messages/obo`, and AI Teammate through
   `/api/messages`, against one healthy revision before declaring M7 complete.

Every mutation still requires the active child milestone to allow it, a reviewed dry run and
rollback boundary, and explicit approval. Never weaken ownership or edit protected operational state
to make acceptance pass.
