# Seoul Tourist OBO Teams frontend

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

## Contract and validation

The contract pin fixes:

- route `/api/messages/obo`;
- audience setting `TokenValidation__Audiences__OnBehalfOf`;
- identity binding `configured-obo-child-agent-identity`.

The [root OBO Teams workflow](../.github/workflows/obo-teams-ci.yml) validates that pin and the
committed Teams manifest structure. Live Teams
acceptance is a separate M7 operation and must prove endpoint, audience, authentication, installed
package, governed response, Purview behavior, and sanitized observability.

## M7 checkpoint

The shared host is currently revision `0000028`, digest
`sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`. The last documented OBO
Teams live pass was revision `0000025`; do not claim same-revision alignment until Teams is replayed
and recorded against `0000028`. Package or tenant changes require an approved CLI workflow, fresh dry
run, explicit rollback boundary, and explicit approval.

See [configuration](docs/configuration.md), the [M7 record](docs/milestones/M7-obo-alignment.md), and
the [shared backend checkpoint](../a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md).
