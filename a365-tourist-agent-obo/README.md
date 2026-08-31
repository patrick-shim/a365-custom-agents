# Korea Expert OBO Teams frontend

This project owns the source OBO Teams package and the non-secret contract pin for the canonical
shared backend route `/api/messages/obo`. It contains no backend runtime or deployment assets.

| Surface | Ownership |
| --- | --- |
| `teams/appPackage/manifest.json`, icons, `teams/m365agents.yml` | Committed Teams package source |
| `backend-contract.lock.json` | Committed backend contract pin |
| `.a365/`, `.config/`, `teams/env/.env.*` | Protected local CLI/tenant state; never committed |
| `teams/appPackage/build/` | Generated historical output; never deployment source |

The Direct Line frontend lives in `../a365-tourist-agent-obo-directline`, AI Teammate lives in
`../a365-tourist-agent-teammate`, and all shared runtime, MCP, infrastructure, Docker, tests, tools,
and Azure deployment automation live in `../a365-tourist-backend`.

### Tracked files

This project tracks 15 files. It contains no `.csproj`, no `global.json`, and no compiled output — it
is a package and contract boundary, not a buildable application, so it has no test suite of its own.

| Path | Kind |
| --- | --- |
| `teams/KoreaExpert.Teams.atkproj` | Teams Toolkit project file |
| `teams/m365agents.yml` | Teams Toolkit lifecycle definition |
| `teams/appPackage/manifest.json` | Teams app manifest source |
| `teams/appPackage/color.png`, `teams/appPackage/outline.png` | Package icons |
| `teams/env/.gitignore` | Keeps tenant-bound `.env.*` files out of Git |
| `backend-contract.lock.json` | Non-secret contract pin |
| `AGENTS.md`, `README.md`, `docs/` | Boundary rules and documentation |

Everything the Agent 365 and Teams Toolkit CLIs generate — `.a365/`, `.config/`,
`teams/env/.env.*`, and `teams/appPackage/build/` — stays on the operator workstation. Preserve it
locally; never copy, hand-edit, fabricate, stage, or delete it.

## Contract and validation

The contract pin fixes:

- route `/api/messages/obo`;
- audience setting `TokenValidation__Audiences__OnBehalfOf`;
- identity binding `configured-obo-child-agent-identity`.

These three values must match
[`../a365-tourist-backend/contracts/frontend-backend-contract.json`](../a365-tourist-backend/contracts/frontend-backend-contract.json)
exactly — `contractId: korea-expert-shared-backend`, `contractVersion: 1.0.0`, frontend
`on-behalf-of`. Unlike the generated Agent 365 state around it, `backend-contract.lock.json` **is**
non-secret source and is expected to be committed.

The [root OBO Teams workflow](../.github/workflows/obo-teams-ci.yml) runs on `windows-latest` with a
10-minute timeout and `permissions: contents: read`. It validates that pin and the committed Teams
manifest structure, failing with `Invalid OBO backend contract pin.` on any drift.
[`contract-alignment-ci.yml`](../.github/workflows/contract-alignment-ci.yml) independently compares
this lock file against the backend contract and the two sibling frontends.

Live Teams acceptance is a separate M7 operation and must prove endpoint, audience, authentication,
installed package, governed response, Purview behavior, and sanitized observability.

## Shared route, separate evidence

This package and the Direct Line client both reach `/api/messages/obo` with the same audience and the
same configured child Agent Identity, so they share the backend's DLP behavior. They do **not** share
acceptance evidence: a Direct Line pass proves nothing about the Teams channel, because the channel,
package installation, and token acquisition path differ. Each frontend records its own replay.

## M7 checkpoint

The shared host is currently revision `0000028`, digest
`sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`. The last documented OBO
Teams live pass was revision `0000025`; do not claim same-revision alignment until Teams is replayed
and recorded against `0000028`. Package or tenant changes require an approved CLI workflow, fresh dry
run, explicit rollback boundary, and explicit approval.

See [configuration](docs/configuration.md), the [M7 record](docs/milestones/M7-obo-alignment.md), and
the [shared backend checkpoint](../a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md).
