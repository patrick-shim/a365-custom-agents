# Japan Tourist Assistant OBO Direct Line frontend

> **LOCKED (2026-08-31).** Frozen at a verified-good baseline: 2/2 projects, 0 warnings, 0 errors, 5
> tests passing, contract pin aligned. Build, test, and read freely; change nothing without explicit
> owner approval. See [../AGENTS.md](../AGENTS.md#change-lock).

This project owns the Direct Line console client, focused tests, and synthetic SIT list for the
canonical shared backend route `/api/messages/obo`. It contains no Teams package, Agent 365 CLI
state, backend runtime, infrastructure, or deployment automation.

The contract pin fixes:

- product `Japan Tourist Assistant`, default time zone `Asia/Tokyo`, and default currency `JPY`;
- route `/api/messages/obo`;
- audience setting `TokenValidation__Audiences__OnBehalfOf`;
- identity binding `configured-obo-child-agent-identity`.

OBO Teams lives in `../a365-tourist-agent-obo`, AI Teammate lives in
`../a365-tourist-agent-teammate`, and shared backend work lives only in
`../a365-tourist-backend`.

## Validate and run

```powershell
dotnet test JapanExpert.OBO.DirectLine.slnx --configuration Release
dotnet run --project direct/JapanExpert.Direct
```

The root [Direct Line workflow](../.github/workflows/direct-line-ci.yml) runs the focused tests,
validates the lock, and rejects recursively tracked credentials, operational state, and foreign
source. The
[cross-project contract workflow](../.github/workflows/contract-alignment-ci.yml) compares this lock
with the canonical backend contract.

Set `JAPAN_EXPERT_DIRECT_LINE_SECRET` only in the current process and remove it afterward. Never put
the secret or a private key in source, arguments, shell history, logs, or configuration files. See
[configuration](docs/configuration.md) and the [client guide](direct/README.md).

## M8 status

The client is renamed to `JapanExpert`, uses a Japan Tourist Assistant process-secret boundary, and owns three
reserved synthetic policy cases: Japan passport, Japanese residence card, and an industry credit-card
test number.

**Direct Line is live and accepted.** The Japan Tourist Assistant Azure Bot, its Direct Line site, and the
`japan-expert-obo` OAuth connection exist, and governed turns return model answers with fail-closed
Purview evaluation and all four MCP services healthy. A first-time user still receives an OAuth
sign-in card, which is correct enforcement rather than a defect. The reserved three-case synthetic
policy run remains a separate operation requiring its own approval, and no Seoul channel secret or
registration is valid M8 input.

The executable uses the source-owned [Japanese-flag icon](direct/assets/README.md).

See the project [instructions](AGENTS.md), [configuration](docs/configuration.md),
[client guide](direct/README.md), [milestone protocol](docs/milestones/README.md),
[M8 Direct Line record](docs/milestones/M8-japan-expert-direct-line.md), and
[M8 shared backend record](../a365-tourist-backend/docs/milestones/M8-japan-expert-migration.md).
The [M7 record](docs/milestones/M7-direct-line-alignment.md) is historical only.
