# Seoul Tourist OBO Direct Line frontend

This project owns the Direct Line console client, focused tests, and synthetic SIT list for the
canonical shared backend route `/api/messages/obo`. It contains no Teams package, Agent 365 CLI
state, backend runtime, infrastructure, or deployment automation.

The contract pin fixes:

- route `/api/messages/obo`;
- audience setting `TokenValidation__Audiences__OnBehalfOf`;
- identity binding `configured-obo-child-agent-identity`.

OBO Teams lives in `../a365-tourist-agent-obo`, AI Teammate lives in
`../a365-tourist-agent-teammate`, and shared backend work lives only in
`../a365-tourist-backend`.

## Validate and run

```powershell
dotnet test SeoulTourist.OBO.DirectLine.slnx --configuration Release
dotnet run --project direct/SeoulTourist.Direct
```

Set `SEOUL_TOURIST_DIRECT_LINE_SECRET` only in the current process and remove it afterward. Never put
the secret or a private key in source, arguments, shell history, logs, or configuration files. See
[configuration](docs/configuration.md) and the [client guide](direct/README.md).

## M7 checkpoint

The client passes 5/5 focused tests. Shared host revision `0000028`, digest
`sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`, passed isolated Direct Line
acceptance for one approved synthetic credit card, passport, and South Korean
resident-registration case. Each was blocked before model access and model requests were zero in the
covered interval. Revision `0000027`, digest
`sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`, remains the backend rollback
boundary.

See [the Direct Line M7 record](docs/milestones/M7-direct-line-alignment.md) and
[the shared backend record](../a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md).
