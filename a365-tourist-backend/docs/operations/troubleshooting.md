# Production troubleshooting

Use sanitized IDs, timestamps, revision names, status codes, EventIds, and aggregate counts only.
Never paste prompt/response text, tool arguments/results, tokens, secrets, or matched values into an
issue, log query, or evidence file.

## First checks

```powershell
Invoke-WebRequest http://127.0.0.1:<port>/api/health/live -UseBasicParsing
Invoke-WebRequest http://127.0.0.1:<port>/api/health/ready -UseBasicParsing
dotnet test KoreaExpertAgent.slnx
./tools/Invoke-Validation.ps1 -OutputFormat Json
```

- Liveness failure: process, listener, or runtime startup problem.
- Readiness failure with liveness success: startup has not completed or validated configuration is
  unavailable. `Degraded` indicates process-local session storage; keep one replica. Readiness is
  passive and never probes cloud dependencies.
- Both healthy: correlate the turn by `TraceId`, `FrontendMode`, `ConversationHash`, and
  `ActivityHash`.

## Symptom map

| Symptom | Evidence | Likely cause | Safe action |
| --- | --- | --- | --- |
| `STA-AUTH-001` | Event 1101, `identity.resolve` | Expired/missing OBO or child token | Sign in again; verify auth handler configuration. |
| `STA-AUTHZ-001` | Event 1101 | Tenant, audience, scope, or role mismatch | Compare configured audiences and inherited scopes without printing tokens. |
| `STA-DEP-001/002/004` | Event 1101 plus dependency span status | Timeout, throttling, outage | Honor service guidance; do not retry non-idempotent tool calls automatically. |
| Purview block text | Purview activity and DLP alert | Expected policy enforcement | Do not bypass; review policy/rule evidence. |
| Purview evaluation failure | Event 1004 | Graph/Purview failure or malformed decision | Treat as fail-closed; inspect status and exception type only. |
| No model call after prompt | Purview activity exists, no inference child | Input was blocked or evaluation failed | Expected fail-closed behavior. |
| Duplicate activity | Event 1103 | Channel replay | No action unless repeated volume is abnormal. |
| Direct Line `DL-PROTO-001` | Client exit 1 | Empty/malformed service response | Start a new conversation and verify endpoint/service health. |
| Liveness healthy after restart but history absent | Process-local storage | Current single-replica `MemoryStorage` limitation | Do not scale out; durable storage is a release gate. |

## Escalation bundle

Provide: UTC window, frontend mode, revision/image digest, EventIds, error code, trace ID, hashed
conversation/activity IDs, dependency name, HTTP status, attempt count, and whether live/ready passed.
Exclude all conversation and credential content.

## Historical M2 resumption

M2 remains blocked with its historical IRM checklist preserved; active M7 owns current deployment,
Purview, and cross-channel alignment. Resume M2 only after the needed external evidence is available
and the milestone is explicitly reactivated. Do not recreate policies or rerun tenant mutations
merely because an alert is delayed.
