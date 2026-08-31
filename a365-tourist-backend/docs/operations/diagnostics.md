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
| `STA-AUTH-001` | Authentication failed | Sign in again. |
| `STA-AUTHZ-001` | Authorization denied | Contact the tenant administrator. |
| `STA-DEP-001` | Dependency timeout | Retry once. |
| `STA-DEP-002` | Dependency throttled | Retry later. |
| `STA-DEP-003` | Invalid dependency response | Retry later; administrator checks provider health. |
| `STA-DEP-004` | Dependency unavailable | Retry later. |
| `STA-INT-001` | Internal defect or state failure | Retry; administrator correlates by trace/hash. |
| `STA-INPUT-001` | Prompt exceeds the configured character limit | Shorten the request. |
| `DL-AUTH-001` / `DL-AUTHZ-001` | Direct Line credential/configuration failure | Refresh channel configuration. |
| `DL-CONV-001` | Direct Line conversation expired | Start a new conversation. |
| `DL-DEP-001` / `DL-DEP-002` / `DL-DEP-004` | Direct Line timeout, throttling, or outage | Retry as directed. |
| `DL-PROTO-001` | Invalid Direct Line response | Check service and client versions. |

Purview block and evaluation-failure messages remain separate from dependency errors so policy
decisions are never misrepresented as outages.
