# AI Teammate Frontend Milestones

The machine-readable current milestone is [milestones.json](milestones.json), validated by
[milestones.schema.json](milestones.schema.json). The backend protocol rules it follows are
documented in
[../../../a365-tourist-backend/docs/milestones/README.md](../../../a365-tourist-backend/docs/milestones/README.md);
where this summary and the JSON disagree, the JSON wins.

## Current milestone: M7

M7 preserves the completed backend-residue removal and validates this authoritative AI Teammate
package boundary end to end against the single shared backend. The non-secret contract pin is source;
CLI-generated configuration, manifests, and packages are protected local operational state. The
sanitized record is [M7-ai-teammate-alignment.md](M7-ai-teammate-alignment.md).

## Open acceptance

The current backend is revision `0000028`. Endpoint and inheritance reconciliation, tenant consent,
and Foundry User RBAC were completed through separately approved M7 operations, but a sanitized
same-revision replay remains open. Closing it requires normal-turn, MCP, Purview, and observability
evidence explicitly tied to `0000028`, with no raw prompts, tool data, or credentials in telemetry.

## Publication authority

The protected OBO-side `.a365/ai-teammate` snapshot in `../../../a365-tourist-agent-obo` is
historical output only and must never be used for publication. Only this project's CLI-owned state is
authority, and only through the approved Agent 365 rehydration and publication workflow.

The local CLI-owned manifest snapshot and the published package record are at different versions;
reconcile that divergence through the CLI, never by hand-editing generated state or fabricating an
artifact.

## Mutation rules

Approved Agent 365 package and tenant operations require the active M7 permission, a reviewed dry
run, an explicit rollback boundary, and explicit approval after the dry-run output has been shown.
Package references and configuration alone prove only code readiness — never registration, consent,
policy enforcement, publication, or instance approval. Never run `a365 cleanup blueprint` while any
child identity or sibling frontend exists.
