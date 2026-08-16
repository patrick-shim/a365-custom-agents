# Seoul Tourist AI Teammate frontend

This project owns the authoritative Microsoft 365 AI Teammate package boundary and the non-secret
contract pin for the canonical shared backend route `/api/messages`. Shared runtime, MCP,
infrastructure, Docker, tests, tools, and Azure deployment live only in
`../a365-tourist-backend`.

| Surface | Ownership |
| --- | --- |
| `backend-contract.lock.json` | Committed, non-secret source contract |
| `global.json` | Committed .NET SDK pin for approved Agent 365 CLI tooling |
| `a365.config.json`, `a365.generated.config.json`, `.config/` | Protected local Agent 365 state |
| `manifest/`, package ZIP, workspace detection file | Protected generated operational state |

Protected state remains on the operator workstation but is intentionally excluded from Git. The
local CLI-owned manifest snapshot is version `1.1.4`, while the published package record is version
`1.1.5`; reconcile only through the approved Agent 365 rehydration/publication workflow. The
historical `.a365/ai-teammate` snapshot in `../a365-tourist-agent-obo` is never publication authority.

## Contract and runtime identity

The contract pin fixes:

- route `/api/messages`;
- audience setting `TokenValidation__Audiences__AgenticUser`;
- identity binding `dynamic-child-agent-identity`.

The shared Blueprint has the three required delegated Purview scopes: `Content.Process.User`,
`ProtectionScopes.Compute.User`, and `ContentActivity.Write`. Endpoint and inheritance reconciliation,
tenant consent, and Foundry User RBAC were completed through separately approved M7 operations.

## M7 checkpoint

The shared host is revision `0000028`, digest
`sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`; revision `0000027`, digest
`sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`, is the verified host rollback.
The prerequisites above are reconciled, but a sanitized AI Teammate normal-turn, MCP, Purview, and
observability replay explicitly tied to `0000028` is still required before same-revision M7 closure.

See [configuration](docs/configuration.md), the [AI Teammate M7 record](docs/milestones/M7-ai-teammate-alignment.md),
and the [shared backend record](../a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md).
