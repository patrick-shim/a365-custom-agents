# Seoul Tourist AI Teammate Frontend Guide

Read `docs/milestones/milestones.json` before work. This project contains only the authoritative AI
Teammate channel boundary for the shared backend.

## Ownership

- `backend-contract.lock.json` is a committed, non-secret source pin for `/api/messages`, the
  Agentic User audience configuration, and dynamic child identity binding.
- `global.json` is the committed non-secret .NET SDK pin used by the approved Agent 365 CLI tooling.
- `a365.config.json`, `a365.generated.config.json`, `manifest/`, `.config/`, and
  `.a365-workspace-detection.local.json` are protected CLI-owned operational state. Never hand-edit,
  copy, stage, commit, or delete their tenant-bound values during source cleanup.
- The local CLI-owned manifest snapshot is version `1.1.4`; the published package record is version
  `1.1.5`. Rehydrate and reconcile through the approved Agent 365 workflow, never a source edit.
- The protected `.a365/ai-teammate` snapshot under `../a365-tourist-agent-obo` is historical output,
  not publication authority.
- `../a365-tourist-backend` exclusively owns shared runtime code, Azure resources, MCP services,
  integrations, tests, infrastructure, Docker assets, and deployment.

## Validation

The GitHub workflow validates the committed non-secret contract and SDK pin and proves protected CLI
state is not present in a clean checkout. Manifest validation, publication, instance creation, licensing, and
installation are operational Agent 365/Admin Center workflows and require reviewed CLI output,
rollback boundaries, and explicit approval.

## Active M7 status

The `/api/messages` endpoint registration and two existing inheritance entries have been reconciled.
The required delegated Graph scopes are consented, and the effective AI Teammate runtime identity has
Foundry User data-plane RBAC. These prerequisites preserve the shared Blueprint and dynamic child
identity model.

The current backend is revision `0000028`. A sanitized AI Teammate replay explicitly tied to
`0000028` is still required before claiming same-revision M7 completion. Preserve
`TokenValidation__Audiences__AgenticUser`, `/api/messages`, the shared Blueprint, and dynamic child
selection. Fix shared behavior only in `../a365-tourist-backend`; use only an approved owner-scoped
Agent 365 workflow for package or tenant reconciliation.
