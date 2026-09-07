# Japan Tourist Expert OBO Teams frontend configuration

**Before any Agent 365 setup rerun:** CLI 1.1.214 can remove custom permissions missing from the
invoking config, even with `setup blueprint --no-endpoint`. Both this frontend and AI Teammate must
declare the same MCP, AzureML, and Cognitive Services `customBlueprintPermissions` for the shared
`Japan Tourist Expert BP`. Use the [required config example](../../a365-tourist-backend/docs/configuration.md#preserve-custom-blueprint-permissions-before-setup);
`customResourceScopes` is not the supported key. Have the approved operator reconcile both ignored
user configs before setup; never commit tenant-bound values.

The source package binds to `/api/messages/obo` through `backend-contract.lock.json`. The committed
pin names Japan Tourist Expert, `Asia/Tokyo`, `JPY`, `TokenValidation__Audiences__OnBehalfOf`, and
`configured-obo-child-agent-identity`; actual tenant identifiers remain in protected deployment and
CLI-owned state.

The current package source is `teams/appPackage/manifest.json`, the Japanese-flag `color.png` and
`outline.png` icons, and `teams/m365agents.yml`. `.a365/obo`, `.config/`, `teams/env/.env.*`, and
generated package output are local operational state. Never copy their identities, secrets, or
generated values into source.
`.a365/ai-teammate` is a protected historical snapshot and never the AI Teammate publication source.

The manifest variables preserve distinct identities:

| Variable | Meaning |
| --- | --- |
| `TEAMS_APP_ID` | Teams app/package catalog ID created by the clean package workflow. |
| `AGENT_APP_ID` | Separate OBO channel application and Azure Bot `msaAppId`; it is not the OBO child Agent Identity. |
| `AGENT_HOST_DOMAIN` | Domain of the shared backend whose protected OBO route receives Bot activities. |

`teams/appPackage/build/` is not deployment source. Regenerate and validate a candidate only through
the approved Teams/Agent 365 CLI workflow. Reject a dry run that reuses any Seoul Blueprint, child,
channel application, endpoint registration, or generated package. M8 must create the new Japan Tourist Expert
identity boundary while preserving `/api/messages/obo` and the two-child architecture.

Structural source CI is offline. Live channel validation and any package, registration, consent, or
tenant mutation remain separately gated under M8.

The root [`obo-teams-ci.yml`](../../.github/workflows/obo-teams-ci.yml) workflow validates this
source boundary. The root
[`contract-alignment-ci.yml`](../../.github/workflows/contract-alignment-ci.yml) workflow compares
the committed pin with the canonical backend contract and the other frontend pins.
