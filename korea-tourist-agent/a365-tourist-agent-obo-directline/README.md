# Korea Tourist Assistant OBO Direct Line frontend

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

`backend-contract.lock.json` must match
[`../a365-tourist-backend/contracts/frontend-backend-contract.json`](../a365-tourist-backend/contracts/frontend-backend-contract.json)
exactly — `contractId: korea-expert-shared-backend`, `contractVersion: 1.0.0`, frontend
`on-behalf-of`. It is non-secret source and is expected to be committed. This project and the OBO
Teams package share that route, that audience, and that child Agent Identity, so they share backend
DLP behavior — but not acceptance evidence, because the channel and token path differ.

## Repository layout

The project tracks 28 files: one solution, one application, one test project, its own SDK and package
pins, and documentation.

| Path | Purpose |
| --- | --- |
| `KoreaExpert.OBO.DirectLine.slnx` | XML-format solution covering the client and its tests |
| `global.json` | .NET SDK pin |
| `Directory.Build.props`, `Directory.Packages.props` | Shared build settings and central package versions |
| `direct/KoreaExpert.Direct/Program.cs` | Entry point and argument dispatch |
| `direct/KoreaExpert.Direct/DirectClientOptions.cs` | Command-line and environment option parsing/validation |
| `direct/KoreaExpert.Direct/DirectLineClient.cs` | Direct Line v3 transport, token renewal, activity polling |
| `direct/KoreaExpert.Direct/DirectLineModels.cs` | Wire models for conversations, activities, and OAuth cards |
| `direct/KoreaExpert.Direct/ConsoleConversation.cs` | Interactive loop, OAuth card handling, SIT sequencing |
| `direct/KoreaExpert.Direct/SensitivePromptList.cs` | Loading and validation of the synthetic SIT list |
| `direct/sensitive-information-type-test.json` | Default synthetic SIT list — synthetic data only |
| `direct/tests/KoreaExpert.Direct.Tests/` | Three test classes: conversation, client, prompt list |
| `docs/configuration.md`, `docs/milestones/` | Configuration guide, milestone JSON, schema, M7 record |

The local `client_key.key` is covered by `.gitignore` and must never be staged. Credential patterns
(`*.key`, `*.pem`, `*.pfx`, `*.p12`, `.env`) are excluded by design.

## Continuous integration

[`direct-line-ci.yml`](../.github/workflows/direct-line-ci.yml) runs on `windows-latest` with a
10-minute timeout and `permissions: contents: read`. It restores, builds, and tests the solution in
Release, validates the contract pin, and runs a credential scan over the tree.
[`contract-alignment-ci.yml`](../.github/workflows/contract-alignment-ci.yml) separately compares this
lock file against the backend contract and both sibling frontends.

## Validate and run

```powershell
dotnet test KoreaExpert.OBO.DirectLine.slnx --configuration Release
dotnet run --project direct/KoreaExpert.Direct
```

Set `KOREA_EXPERT_DIRECT_LINE_SECRET` only in the current process and remove it afterward. Never put
the secret or a private key in source, arguments, shell history, logs, or configuration files. See
[configuration](docs/configuration.md) and the [client guide](direct/README.md).

The solution builds with `TreatWarningsAsErrors=true`, so a warning fails the build. The test project
holds three classes — `ConsoleConversationTests`, `DirectLineClientTests`, and
`SensitivePromptListTests` — totaling five tests. They are offline: no test contacts Direct Line, the
backend, or a tenant.

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
