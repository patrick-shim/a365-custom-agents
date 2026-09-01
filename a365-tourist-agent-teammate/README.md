# Japan Tourist Assistant AI Teammate frontend

> **LOCKED (2026-08-31).** Frozen at a verified-good baseline: contract pin, SDK pin, and icons all
> aligned across channels. Change nothing without explicit owner approval. Acceptance remains open —
> no live turn has run against `/api/messages` — and that work needs its own approval. See
> [../AGENTS.md](../AGENTS.md#change-lock).

This project owns the authoritative Microsoft 365 AI Teammate package boundary and the non-secret
contract pin for the canonical shared backend route `/api/messages`. Shared runtime, MCP,
infrastructure, Docker, tests, tools, and Azure deployment live only in
`../a365-tourist-backend`.

| Surface | Ownership |
| --- | --- |
| `backend-contract.lock.json` | Committed, non-secret source contract |
| `global.json` | Committed .NET SDK pin for approved Agent 365 CLI tooling |
| [`assets/color.png`, `assets/outline.png`](assets/README.md) | Source-owned Japanese-flag package icons |
| `a365.config.json`, `a365.generated.config.json`, `.config/` | Protected local Agent 365 state |
| `manifest/`, package ZIP, workspace detection file | Protected generated operational state |

Protected Seoul state remains on the operator workstation but is intentionally excluded from Git and
is not M8 input. Rehydrate a new Japan Tourist Assistant package through the approved Agent 365 workflow and
source-owned icon assets. The historical `.a365/ai-teammate` snapshot in
`../a365-tourist-agent-obo` is never publication authority.

## Contract and runtime identity

The contract pin fixes:

- product `Japan Tourist Assistant`, default time zone `Asia/Tokyo`, and default currency `JPY`;
- route `/api/messages`;
- audience setting `TokenValidation__Audiences__AgenticUser`;
- identity binding `dynamic-child-agent-identity`.

The new shared Blueprint requires the delegated Purview scopes `Content.Process.User`,
`ProtectionScopes.Compute.User`, and `ContentActivity.Write`. The clean M8 workflow must establish
endpoint registration, effective inheritance, tenant consent, and minimum Foundry data-plane RBAC
again; historical Seoul grants do not transfer.

The root [AI Teammate workflow](../.github/workflows/ai-teammate-ci.yml) validates the source-safe
contract and SDK pin and rejects recursively tracked operational state and foreign source. The
[cross-project contract workflow](../.github/workflows/contract-alignment-ci.yml) compares this lock
with the canonical backend contract.

## M8 status

The source-safe package boundary carries Japan Tourist Assistant branding and Japanese-flag icons. The clean
Agent 365 run reused the single shared `Japan Tourist Assistant Blueprint` without reading or reusing Seoul
endpoint, identity, permission, package, instance, or installation state, and no second blueprint was
created.

`a365 publish --aiteammate` produced the package. The CLI ships placeholder branding and its own
default icons, so the generated package was completed with Japan Tourist Assistant naming, the Japanese red
accent, and the source-owned icons. The Admin Center lists an uploaded agent by `name.short`, which is
`Japan Tourist Assistant (Teammate)` so administrators can distinguish it from the `Japan Tourist Assistant` Teams app.

Microsoft 365 licensing, Admin Center upload, instance creation, and installation are still
outstanding and require separate approval. Each effective child identity created at installation also
needs the documented `Cognitive Services User` role on the existing Foundry account. **No live AI
Teammate turn has run, so AI Teammate acceptance remains open.**

See the project [instructions](AGENTS.md), [configuration](docs/configuration.md),
[milestone protocol](docs/milestones/README.md),
[M8 AI Teammate record](docs/milestones/M8-japan-expert-ai-teammate.md), and
[M8 shared backend record](../a365-tourist-backend/docs/milestones/M8-japan-expert-migration.md).
The [M7 record](docs/milestones/M7-ai-teammate-alignment.md) is historical only.
