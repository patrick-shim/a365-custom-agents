# Diagnostics contract

Diagnostics must explain an outcome without recording prompts, responses, tool values, matched
SIT values, tokens, credentials, tenant/user/client IDs, endpoints, or raw dependency bodies.

## Turn scope

Host turn logs include these sanitized scope fields:

| Field | Meaning |
| --- | --- |
| `TraceId` | Current distributed trace ID, when available. |
| `FrontendMode` | `AgenticUser` or `OnBehalfOf`. |
| `ConversationHash` | First 96 bits of SHA-256 over the conversation ID. |
| `ActivityHash` | First 96 bits of SHA-256 over the activity ID. |

Hashes are correlation aids, not authentication or durable business identifiers.

## Event IDs

| Range | Owner | Current events |
| --- | --- | --- |
| 1000-1099 | Agent identity, Purview, MCP setup | 1001, 1003-1008, 1010-1011, 1020 |
| 1100-1199 | Turn outcomes and state safety | 1101 recoverable, 1102 internal, 1103 duplicate, 1104 input limit |
| 3000-3099 | Weather providers | 3001 fallback |
| 4000-4099 | Exchange-rate providers | 4001 official fallback, 4002 market fallback |
| 5000-5099 | MCP tool boundaries | 5001 safe provider failure |

Do not reuse an EventId for a different semantic outcome.

## User error codes

| Code | Meaning | User action |
| --- | --- | --- |
| `JEX-AUTH-001` | Authentication failed | Sign in again. |
| `JEX-AUTHZ-001` | Authorization denied | Contact the tenant administrator. |
| `JEX-DEP-001` | Dependency timeout | Retry once. |
| `JEX-DEP-002` | Dependency throttled | Retry later. |
| `JEX-DEP-003` | Invalid dependency response | Retry later; administrator checks provider health. |
| `JEX-DEP-004` | Dependency unavailable | Retry later. |
| `JEX-INT-001` | Internal defect or state failure | Retry; administrator correlates by trace/hash. |
| `JEX-INPUT-001` | Prompt exceeds the configured character limit | Shorten the request. |

Purview block and evaluation-failure messages remain separate from dependency errors so policy
decisions are never misrepresented as outages.

## Dependency status in turn-failure logs

Turn-failure events 1101 and 1102 record `dependencyStatus`, the transport status the failing
dependency reported, or `0` when the failure carries none. The status is the only detail logged,
because a dependency exception message can contain service payload content.

The classifier maps `RequestFailedException`, `ClientResultException`, `MsalServiceException`, and
`HttpRequestException` through one status table. `ClientResultException` matters specifically because
the Foundry Responses client reports transport failures with it; without that mapping a throttled or
unauthorized model call is misreported as `JEX-INT-001` with no status. When triaging a model failure,
read `dependencyStatus` first: a `429` is throttling and should surface as `JEX-DEP-002`, a `401` or
`403` is an identity or role problem, and `0` means the fault was not a dependency transport failure.

The Direct Line client and its `DL-*` error contract are owned by the
`a365-tourist-agent-obo-directline` frontend; see the "Error contract" section in that project's
`docs/configuration.md`.
