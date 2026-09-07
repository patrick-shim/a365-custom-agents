# Japan Tourist Expert OBO Direct Line frontend configuration

The client binds to `/api/messages/obo` through `backend-contract.lock.json`. The committed pin names
Japan Tourist Expert, `Asia/Tokyo`, `JPY`, `TokenValidation__Audiences__OnBehalfOf`, and
`configured-obo-child-agent-identity`; actual tenant, channel, child, and secret values remain
outside source.

Set the Direct Line site secret only for the current process:

```powershell
$env:JAPAN_EXPERT_DIRECT_LINE_SECRET = '<retrieve-through-approved-secret-workflow>'
dotnet run --project direct/JapanExpert.Direct
Remove-Item Env:JAPAN_EXPERT_DIRECT_LINE_SECRET
```

Do not place the value in source, command arguments, shell history, logs, appsettings, `.env` files,
or key files. `JAPAN_EXPERT_DIRECT_LINE_ENDPOINT` may override the regional Direct Line base URL;
the default is the standard Direct Line v3 service.

The OBO Teams package and protected OBO state belong only in `../a365-tourist-agent-obo`; AI Teammate
package state belongs only in `../a365-tourist-agent-teammate`. Shared route, identity, Purview, or
deployment changes belong only in `../a365-tourist-backend`.

The root [`direct-line-ci.yml`](../../.github/workflows/direct-line-ci.yml) workflow runs the focused
tests, validates the contract pin, and rejects recursively tracked credentials, operational state,
and foreign source. The root
[`contract-alignment-ci.yml`](../../.github/workflows/contract-alignment-ci.yml) workflow compares
the committed pin with the canonical backend contract and the other frontend pins.

## Error contract

The client maps Direct Line transport failures to stable, non-sensitive codes implemented in
[`DirectLineClient.cs`](../direct/JapanExpert.Direct/DirectLineClient.cs):

| Code | Condition | Operator or user action |
| --- | --- | --- |
| `DL-AUTH-001` | Direct Line rejected the site secret. | Refresh the approved channel secret. |
| `DL-AUTHZ-001` | Direct Line denied the client. | Verify the bot channel configuration. |
| `DL-CONV-001` | The conversation expired. | Start a new conversation. |
| `DL-DEP-001` | Direct Line timed out. | Retry once. |
| `DL-DEP-002` | Direct Line throttled the request. | Retry after a delay. |
| `DL-DEP-004` | Direct Line or its transport was unavailable. | Retry later and check service health. |
| `DL-PROTO-001` | Direct Line returned malformed JSON or an invalid response. | Check service and client compatibility. |
