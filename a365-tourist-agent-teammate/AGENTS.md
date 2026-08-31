# Japan Expert AI Teammate Frontend Guide

> **LOCKED (2026-08-31).** This project is frozen at a verified-good baseline: the contract pin and
> SDK pin match the canonical backend contract and the icons are byte-identical across all three
> channels. Do not edit `backend-contract.lock.json`, `global.json`, or the icons, and do not
> hand-edit protected CLI-owned state such as `a365.config.json`, `a365.generated.config.json`,
> `manifest/`, or `.config/`, without an explicit, file-scoped instruction from the repository owner.
> Full rules are in [../AGENTS.md](../AGENTS.md#change-lock).
>
> This project's M8 acceptance is still open: no live AI Teammate turn has run against
> `/api/messages`. That remaining work is an operational Agent 365 workflow and still requires its
> own explicit approval; the lock is not an authorization to perform it.

Read `docs/milestones/milestones.json` before work. This project contains only the authoritative AI
Teammate channel boundary for the shared backend.

## Ownership

- `backend-contract.lock.json` is a committed, non-secret source pin for `/api/messages`, the
  Agentic User audience configuration, and dynamic child identity binding.
- `global.json` is the committed non-secret .NET SDK pin used by the approved Agent 365 CLI tooling.
- `assets/color.png` and `assets/outline.png` are the committed source-owned Japanese-flag icons for
  clean Japan Expert package generation.
- `a365.config.json`, `a365.generated.config.json`, `manifest/`, `.config/`, and
  `.a365-workspace-detection.local.json` are protected CLI-owned operational state. Never hand-edit,
  copy, stage, commit, or delete their tenant-bound values during source cleanup.
- Existing CLI-owned manifest and published package records are historical Seoul state. Rehydrate a
  new Japan Expert package through the approved Agent 365 workflow, never a source edit.
- The protected `.a365/ai-teammate` snapshot under `../a365-tourist-agent-obo` is historical output,
  not publication authority.
- `../a365-tourist-backend` exclusively owns shared runtime code, Azure resources, MCP services,
  integrations, tests, infrastructure, Docker assets, and deployment.

## Validation

The root `../.github/workflows/ai-teammate-ci.yml` workflow validates the committed non-secret
contract and SDK pin and rejects recursively tracked protected CLI state and foreign source. The
cross-project
`../.github/workflows/contract-alignment-ci.yml` workflow compares this pin and both other frontend
pins with the canonical backend contract. Manifest validation, publication, instance creation,
licensing, and installation are operational Agent 365/Admin Center workflows and require reviewed
CLI output, rollback boundaries, and explicit approval.

## Active M8 status

Rename source-safe metadata and icons to Japan Expert while preserving
`TokenValidation__Audiences__AgenticUser`, `/api/messages`, one shared Blueprint with two children,
and dynamic child selection. Prepare a clean Agent 365 workflow for a new Japan Expert Blueprint and
AI Teammate child. Existing Seoul endpoint, inheritance, consent, RBAC, package, generated state, and
installation records are historical only and must not be reused as M8 authority. Fix shared behavior
only in `../a365-tourist-backend`.
