# M7 AI Teammate end-to-end alignment

> Historical Seoul Tourist record. M8 owns the Japan Expert package and registration migration.

Workspace paths in this document are written from the AI Teammate project root.

This frontend retains only its non-secret source contract and protected local Agent 365 package
boundary. All shared backend source and deployment remain owned by `../a365-tourist-backend`. The
historical OBO-side `.a365/ai-teammate` snapshot is not publication authority.

The local CLI-owned manifest snapshot is version `1.1.4`; the published package record is version
`1.1.5`. Rehydration, validation, publication, update, or installation must use the approved Agent
365 workflow with a reviewed dry run, rollback boundary, and explicit approval. Protected package
state is intentionally excluded from Git.

## 2026-08-17 reconciliation checkpoint

- The approved endpoint-only workflow registered the exact production `/api/messages` endpoint on
  the existing Blueprint without recreating the Blueprint or publishing a package.
- Microsoft Cognitive Services and the backend MCP API now both inherit scopes and roles; all seven
  Blueprint resource entries were reported effective.
- `ProtectionScopes.Compute.User` and `ContentActivity.Write` were added alongside the existing
  `Content.Process.User` Graph scope and received tenant admin consent. No unrelated Graph permission
  was added.
- The approved Foundry User data-plane role was assigned to the effective AI Teammate runtime
  identity, not the host UAMI. Existing route, audience, Blueprint, child identity, and package state
  were preserved.
- The prior protection-scope 403 and Foundry authorization prerequisites are therefore reconciled.
  A normal channel observation indicated operation, but the source evidence still needs a sanitized
  normal-turn, MCP, Purview, and observability replay explicitly tied to the final shared revision.

## Latest recorded shared-backend boundary

The latest repository-recorded shared host checkpoint is revision `0000028`; revision `0000027` was
the ARM-validated rollback target for that rollout. Exact immutable digests and rollback provenance
are maintained only in the
[shared backend record](../../../a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md). The
AI Teammate same-revision acceptance item was still open when M7 became historical; M8 requires fresh
Japan Expert registration and acceptance rather than replay against that Seoul revision.
