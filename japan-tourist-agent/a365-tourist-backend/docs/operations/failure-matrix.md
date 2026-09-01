# Failure contract matrix

This matrix is the M3 source for ownership and safe behavior. `Retry` means application-owned
automatic retry; user-initiated retry remains possible unless policy blocks it.

| Boundary | Failure | Retry | Channel behavior | Diagnostic owner | Coverage |
| --- | --- | --- | --- | --- | --- |
| Frontend JWT | Malformed token | No | HTTP 401 | ASP.NET auth | Safe issuer parser tests |
| Agent identity/OBO | Authentication/authorization | No | `JEX-AUTH-001` / `JEX-AUTHZ-001` | Host 1101 | Classifier and token tests |
| Any host operation | Caller cancellation | No | No failure reply | None at warning/error | Cancellation tests |
| MCP discovery/model | Timeout/throttle/outage | No | `JEX-DEP-001/002/004` | Host 1101 | Classifier tests |
| Session decode | Invalid serialized state | No | `JEX-DEP-003` | Host 1101 | Boundary implemented; fault injection pending |
| Session save/internal defect | Unexpected failure | No | `JEX-INT-001` | Host 1102 | Boundary implemented; fault injection pending |
| Purview input/output | Block | No | Configured policy block message | Purview activity/DLP | Block tests and production evidence |
| Purview service | Error/malformed decision | No | Fail-closed evaluation message | Host 1004 | Failure test |
| Tool content | Block/evaluation failure | No | Policy block/fail-closed message | Host 1007/1008 | Tool protection tests |
| Activity replay | Duplicate activity ID | No | Suppress before model/tools | Host 1103 | Coordinator tests |
| Concurrent turn | Same conversation/frontend | No | Serialize state mutation | Host scope | Coordinator tests |
| Direct Line client | Client-owned failures | No | See the "Error contract" in the Direct Line frontend's `docs/configuration.md` | Direct Line frontend | Focused protocol tests |
| Weather/currency | Provider outage | Provider fallback only | Tool result or safe MCP error | 3001/4001/4002 | Status, malformed, and fallback tests |
| Provider-backed MCP tool | Auth/timeout/throttle/malformed/outage | No | Sanitized `MCP-*` error | 5001 | MCP boundary tests |
| Prompt admission | Empty/oversized text | No | Guidance / `JEX-INPUT-001` | 1104 | Input guard tests |

No automatic retry is currently enabled. This avoids duplicate non-idempotent tool calls. Add retry
only to an explicitly idempotent GET operation with bounded attempts, total deadline, jitter, and
`Retry-After` tests.

Provider clients buffer at most 1 MiB under their 20-second `HttpClient.Timeout`. Credential-bearing
provider clients suppress framework URI logging. Authentication/authorization failures are not
hidden by provider fallback.
