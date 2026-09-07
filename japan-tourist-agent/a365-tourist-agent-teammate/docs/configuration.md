# Japan Tourist Expert AI Teammate configuration

**Before any Agent 365 setup rerun:** CLI 1.1.214 can remove custom permissions missing from the
invoking config, even with `setup blueprint --no-endpoint`. Both this frontend and OBO must declare
the same MCP, AzureML, and Cognitive Services `customBlueprintPermissions` for the shared
`Japan Tourist Expert BP`. Use the [required config example](../../a365-tourist-backend/docs/configuration.md#preserve-custom-blueprint-permissions-before-setup);
`customResourceScopes` is not the supported key. Have the approved operator reconcile both ignored
user configs before setup; never commit tenant-bound values.

The frontend binds to `/api/messages` through `backend-contract.lock.json`. The committed source pin
names Japan Tourist Expert, `Asia/Tokyo`, `JPY`, `TokenValidation__Audiences__AgenticUser`, and
`dynamic-child-agent-identity`; actual Blueprint, child, tenant, package, and registration values
remain in protected CLI and deployment state.

`a365.config.json`, `a365.generated.config.json`, `.config/`, `manifest/`, package ZIPs, and
`.a365-workspace-detection.local.json` are local CLI-owned operational artifacts. Do not copy,
hand-edit, stage, commit, or delete them. Use the approved Agent 365/Admin Center workflow for
rehydration, validation, publication, licensing, instance creation, and installation.

The protected local Seoul manifest and published package records are historical and cannot seed M8.
Use `assets/color.png` and `assets/outline.png` as the Japan Tourist Expert source icons in the clean
owner-scoped Agent 365 package workflow. The protected
`../a365-tourist-agent-obo/.a365/ai-teammate` snapshot is historical output, not publication source.

The runtime contract uses the shared Blueprint audience and resolves the effective child identity
from each signed activity. Its delegated Purview token requires `Content.Process.User`,
`ProtectionScopes.Compute.User`, and `ContentActivity.Write`; the effective child runtime identity,
not the host UAMI, receives minimum Foundry data-plane RBAC.

Source CI validates the non-secret contract, SDK pin, and icon dimensions only. Operational package
validation and every tenant mutation require the active M8 scope, reviewed dry run, rollback
boundary, and explicit approval.

The root [`ai-teammate-ci.yml`](../../.github/workflows/ai-teammate-ci.yml) workflow also rejects
recursively tracked protected operational state and foreign source. The root
[`contract-alignment-ci.yml`](../../.github/workflows/contract-alignment-ci.yml) workflow compares
the committed pin with the canonical backend contract and the other frontend pins.

`global.json` pins .NET SDK `10.0.110` for approved Agent 365 CLI work. It is source-safe; the local
tool manifest and generated CLI state are not.
