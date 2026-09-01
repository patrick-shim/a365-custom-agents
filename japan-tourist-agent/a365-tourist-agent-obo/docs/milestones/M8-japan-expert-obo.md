# M8 Japan Expert OBO Teams migration

This frontend owns only the Japan Expert OBO Teams source package, contract pin, source icons, and
approved channel workflow. It must use `/api/messages/obo` and the new OBO audience/child created by
the clean M8 Agent 365 workflow.

The existing protected Seoul operational state is historical and must not be inspected, copied,
edited, deleted, or used as input.

Package generation, publication, and installation are complete for this milestone: the clean workflow
created the new OBO child and channel application, the Microsoft 365 Agents Toolkit produced the
Japan Expert package, and a governed Teams turn has been accepted. Any further package or tenant
change still requires a reviewed dry run, an explicit rollback boundary, and separate approval.

## Clean CLI workflow

After the approved AI Teammate setup has created `Japan Expert Blueprint`, run from a separate empty
OBO operational directory:

```powershell
a365 setup all `
  --agent-name 'Japan Expert' `
  --tenant-id '<tenant-id>' `
  --authmode obo `
  --m365 `
  --dry-run
```

The config-free dry-run renderer does not query Entra and therefore displays a create plan. Before
real execution, a read-only Graph check must prove exactly one `Japan Expert Blueprint`. The real CLI
uses display-name-first discovery and must log `Found existing blueprint by display name`; abort if
it attempts to create a second Blueprint. It then creates the distinct OBO Agent Identity and
registration. Register the `/api/messages/obo` endpoint only after the new backend FQDN is known.

The OBO channel application remains distinct from the OBO child identity. The reviewed Azure phase
creates a new single-tenant channel app, Azure Bot, Teams and Direct Line channels, and
`japan-expert-obo` Bot Token Service connection. The channel app is the incoming JWT audience and
Teams manifest bot ID; the Agent Identity remains the child used for downstream token exchange.
Neither identifier may come from Seoul state.

The source Teams manifest and Japanese-flag icons remain the package authority. Generate and validate
the package through `teams/m365agents.yml`; do not use a historical generated ZIP.

## 2026-08-31 - Teams SSO token exchange (`invokeerror`)

Teams reported `Sign in for 'obo-user' completed without a token. Status=Exception/SignInFailure:
(invokeerror)`. Direct Line was unaffected because its magic-code sign-in never performs an SSO
token exchange; Teams sends a `signin/tokenExchange` invoke, which requires the channel application
to be configured as an SSO resource.

The Teams package was **not** the cause. The generated manifest already carried the correct
`bots[0].botId`, `copilotAgents.customEngineAgents[0].id`, `webApplicationInfo.id`, and
`webApplicationInfo.resource` of `api://botid-<oboChannelAppId>`, matching the Azure Bot OAuth
connection `tokenExchangeUrl`.

The OBO channel application registration was missing every SSO prerequisite:

| Property | Before | After |
| --- | --- | --- |
| `identifierUris` | empty | `api://botid-<oboChannelAppId>` |
| `api.requestedAccessTokenVersion` | unset | `2` |
| Exposed delegated scope | none | `access_as_user` (user consent) |
| `preAuthorizedApplications` | none | Teams desktop/mobile, Teams web, Microsoft 365 web/desktop, Outlook web/desktop/mobile, Exchange, SharePoint |
| `requiredResourceAccess` | none | the Blueprint `access_agent_as_user` delegated scope |
| Blueprint consent | `Principal` only, from one interactive sign-in | added `AllPrincipals` so every user works |

Because the Teams SSO token is issued for the channel application and then exchanged on behalf of the
user for the Blueprint scope, both the exposed scope and the downstream delegated declaration are
required. A per-user `Principal` grant is not sufficient for tenant rollout.

The package was rebuilt at version `1.0.1` so Teams and the admin portal replace the cached app.
Re-upload the package and reinstall the app; existing installs keep the previous version and its
cached, failing token. Direct Line acceptance was re-run after the change and still returns a
governed model answer, so the fix introduced no regression.
