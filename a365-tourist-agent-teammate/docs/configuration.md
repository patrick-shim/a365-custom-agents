# AI Teammate configuration

The frontend binds to `/api/messages` through `backend-contract.lock.json`. The committed source pin
names `TokenValidation__Audiences__AgenticUser` and `dynamic-child-agent-identity`; actual Blueprint,
child, tenant, package, and registration values remain in protected CLI and deployment state.

`a365.config.json`, `a365.generated.config.json`, `.config/`, `manifest/`, package ZIPs, and
`.a365-workspace-detection.local.json` are local CLI-owned operational artifacts. Do not copy,
hand-edit, stage, commit, or delete them. Use the approved Agent 365/Admin Center workflow for
rehydration, validation, publication, licensing, instance creation, and installation.

The local CLI-owned manifest snapshot is version `1.1.4`, while the published package record is
version `1.1.5`. The protected `../a365-tourist-agent-obo/.a365/ai-teammate` snapshot is historical
output, not publication source.

The runtime contract uses the shared Blueprint audience and resolves the effective child identity
from each signed activity. Its delegated Purview token requires `Content.Process.User`,
`ProtectionScopes.Compute.User`, and `ContentActivity.Write`; the effective child runtime identity,
not the host UAMI, receives minimum Foundry data-plane RBAC.

Source CI validates the non-secret contract and SDK pin only. Operational package validation and
every tenant mutation require the active M7 scope, reviewed dry run, rollback boundary, and explicit
approval.

`global.json` pins .NET SDK `10.0.110` for approved Agent 365 CLI work. It is source-safe; the local
tool manifest and generated CLI state are not.
