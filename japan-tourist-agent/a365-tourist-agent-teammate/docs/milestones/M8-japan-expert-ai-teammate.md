# M8 Japan Expert AI Teammate migration

This frontend owns only source-safe Japan Expert AI Teammate metadata, icon assets, its contract pin,
and the approved Agent 365 package workflow. It will use `/api/messages`, the new shared Japan Expert
Blueprint audience, and dynamic child identity selection.

Protected Seoul CLI state and the historical OBO-side AI Teammate snapshot are not inputs. Clean
rehydration and package generation are complete: the CLI reused the shared Blueprint and produced the
Japan Expert package. Microsoft 365 licensing, Admin Center upload, instance creation, and
installation remain outstanding and require separate approval.

## Clean CLI workflow

Run from an empty owner-scoped operational directory, never from historical generated state:

```powershell
a365 setup all `
  --agent-name 'Japan Expert' `
  --tenant-id '<tenant-id>' `
  --aiteammate `
  --dry-run
```

The verified dry run skips Azure hosting, proposes one new multi-tenant Blueprint, permissions, and
deferred endpoint registration, and makes no changes. After approval, this AI Teammate setup runs
first so it creates the shared Blueprint but no OBO identity. The OBO workflow then uses the same
Blueprint display name and must report that it found and reused that Blueprint.

After setup and endpoint registration, run `a365 publish --agent-name 'Japan Expert' --aiteammate
--dry-run`. During the separately approved real publish workflow, use the CLI's
manifest-customization pause to apply only the source-owned icons from `assets/` and Japan Expert
descriptions to the freshly extracted template. Do not open or copy a Seoul package.

## 2026-08-31 - AI Teammate readiness review

Reviewed after OBO Teams acceptance passed. The operator had run the AI Teammate Agent 365 CLI flow
from this project folder.

Confirmed correct:

- The run reused the shared `Japan Expert Blueprint` and did not create a second blueprint. The tenant
  holds exactly one Japan Expert blueprint, one agent identity, and one OBO channel application.
- Blueprint delegated grants now cover Microsoft Graph (including the three Purview scopes), the
  Messaging Bot API (`AgentData.ReadWrite`), Agent Tools, Power Platform, Azure Machine Learning
  (`user_impersonation`), and the custom MCP API (`Mcp.Invoke`), with `allAllowed` inheritance for
  each resource so child identities inherit them.
- The host accepts `/api/messages` for the shared blueprint audience and resolves the child identity
  from the signed activity, matching `dynamic-child-agent-identity` in the contract pin.

Defect found and fixed in the canonical backend:

`ConnectionsMap` selects `ServiceConnection` for the agentic audience, so that connection
authenticates outbound `/api/messages` channel calls. It was configured with
`api://AzureADTokenExchange/.default`, which is not an audience the messaging service accepts. The
Agents SDK agentic token provider hardcodes the token-exchange audience for its own federated legs,
so this connection scope was never used for identity and only affected outbound replies. It now
requests `5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default`, the Messaging Bot API the blueprint holds
`AgentData.ReadWrite` against, matching both the Agent 365 CLI's own stamped value and the published
Microsoft sidecar sample. OBO is unaffected because it routes through `OboChannelConnection` on the
Bot Connector audience; three live OBO turns were re-run after the change and still pass.

Remaining work before AI Teammate acceptance, all requiring explicit approval:

1. No package exists yet. `a365 publish --aiteammate --dry-run` shows the generated manifest would
   carry CLI placeholder branding: name `Japan Expert Blueprint`, the default description, accent
   `#9ec9d9`, and Microsoft Corporation developer links. It must instead carry Japan Expert naming,
   the Japanese-flag `assets/color.png` and `assets/outline.png`, and the Japanese red accent used by
   the OBO package.
2. Microsoft 365 Admin Center upload, license assignment, and installation are operational steps that
   create the agent instance.
3. Foundry data-plane RBAC is per identity. Only the OBO child and the blueprint service principal
   hold `Cognitive Services User` on the existing Foundry account today. Each effective AI Teammate
   child runtime identity created at installation needs the same documented role before a live turn
   can reach the model.
4. The messaging endpoint registration is held by the Agent 365 service and is not exposed on the
   Entra blueprint object, so it must be confirmed from reviewed CLI output rather than assumed.

### Package generated

`a365 publish --aiteammate` produced `manifest/` and its package. The CLI prints an explicit
"Customize before packaging" list and ships placeholder branding with its own default icons, which
were confirmed by hash to differ from the source-owned assets. The generated package was therefore
completed through the documented workflow: Japan Expert naming and description, the Japanese red
accent `#BC002D`, developer links on the deployed host domain, version `1.0.0`, and the source-owned
`assets/color.png` and `assets/outline.png`, which are byte-identical to the icons in the accepted OBO
package.

The upload artifact is `manifest/Japan-Expert-AI-Teammate.zip`, containing `manifest.json`,
`agenticUserTemplateManifest.json`, `color.png`, and `outline.png`. The template still references the
shared blueprint over `activityProtocol`, and `manifest/` remains git-ignored operational state.

Still required and not yet done: Microsoft 365 Admin Center upload, license assignment, installation,
and the documented `Cognitive Services User` grant for each effective AI Teammate child identity that
installation creates. No live AI Teammate turn has been observed, so AI Teammate acceptance remains
open.

### Admin-facing package name

The AI Teammate package now uses `name.short` of `Japan Expert (Teammate)` (23 of the 30 allowed
characters) and `name.full` of `Japan Expert (Teammate) travel assistant`, at version `1.0.1`. The
Microsoft 365 Admin Center lists an uploaded custom agent by `name.short`, so this is the value that
distinguishes the AI Teammate agent from the OBO Teams app, which stays `Japan Expert`. Agentic user
instances created at installation derive from this package, so they inherit the same distinction.

The blueprint, agent identity, and OBO channel application keep their existing Entra display names
(`Japan Expert Blueprint`, `Japan Expert Identity`, `Japan Expert OBO Channel`); they are already
distinct from each other and the agent identity is shared with the accepted OBO channel, so renaming
it was deliberately avoided.
