# Direct Line Console Client

The .NET 10 console app in `KoreaExpert.Direct` talks to the OBO Azure Bot through Direct Line v3.
It does not use Teams or Microsoft 365 Copilot. It starts a Direct Line conversation, sends user
messages, renders agent replies, renews expiring conversation tokens, and completes Bot Token
Service authentication through the OAuth card and standard message-based magic-code flow.

## Prerequisites

- The OBO Azure Bot has an enabled Direct Line site.
- The bot endpoint targets `/api/messages/obo`.
- The Bot Token Service connection is named `korea-expert-obo`.
- You have one Direct Line site secret. Keep it in an environment variable; do not put it in source,
  arguments, shell history, or logs.

During M7, obtain `KOREA_EXPERT_DIRECT_LINE_SECRET` only through an approved channel-operations
workflow and set it only in the current process without printing it. Tenant or Purview operations
require the M7 milestone permission, a reviewed dry run and rollback boundary, and explicit approval.
Direct Line acceptance must prove zero unexplained route, audience, OAuth, token-renewal, policy, or
response drift from the canonical deployed backend.

## Run

Interactive conversation:

```powershell
dotnet run --project direct/KoreaExpert.Direct
```

Send one prompt and exit after the response:

```powershell
dotnet run --project direct/KoreaExpert.Direct -- `
  --message 'Plan a one-day Seoul itinerary for tomorrow.'
```

The first protected turn can return an OAuth card. The client opens its URL in the default browser.
Sign in with the Microsoft 365 user, then enter the displayed verification code in the console. If
the browser reports that sign-in completed automatically, press Enter without a code and the client
continues polling.

Use `--no-browser` on a remote shell and open the printed URL yourself. Use `--help` for endpoint,
identity, polling, and timeout options. A regional Direct Line base URL can also be supplied through
`KOREA_EXPERT_DIRECT_LINE_ENDPOINT` or `--endpoint`.

Remove the process-scoped secret when finished:

```powershell
Remove-Item Env:KOREA_EXPERT_DIRECT_LINE_SECRET
```

For isolated M7 acceptance, use a reviewed file containing exactly the approved credit-card,
passport, and South Korean resident-registration cases, with three-minute separation:

```powershell
dotnet run --project direct/KoreaExpert.Direct -- `
  --sit-file '<approved-three-case-file>' `
  --interval 180
```

Correlate each isolated interval with sanitized host policy-block evidence and zero Azure OpenAI
model requests. Refusal wording by itself is not proof that Purview blocked before model access.

For broad exploratory coverage, `--sit-list` sends the default
`direct/sensitive-information-type-test.json`; `--interval` controls spacing. A 120-case run at a
short interval is not accepted as isolated M7 evidence. Use `--sit-file <path>` to select another
list. SIT mode prints only record numbers and agent responses; it does not echo synthetic identifiers
to the terminal. `--sit-list` and `--message` are mutually exclusive.

## Command-line reference

Every option is parsed and validated by `DirectClientOptions`. An unrecognized token fails fast with
`Unknown option '<token>'. Use --help for usage.`

| Option | Default | Notes |
| --- | --- | --- |
| `--endpoint <url>` | `KOREA_EXPERT_DIRECT_LINE_ENDPOINT`, else the global Direct Line base URL | Use for a regional Direct Line endpoint |
| `--secret-env <name>` | `KOREA_EXPERT_DIRECT_LINE_SECRET` | Names the variable holding the site secret; the secret itself is never an argument |
| `--user-id <id>` | `dl_korea_expert_cli` | Direct Line user id |
| `--user-name <name>` | `Korea Tourist Assistant CLI` | Display name sent with activities |
| `--message <text>` | — | Sends one prompt, waits for the response, exits |
| `--sit-list` | off | Runs the default list `direct/sensitive-information-type-test.json` |
| `--sit-file <path>` | — | Runs an alternate synthetic list; implies list mode |
| `--interval <seconds>` | `5` | Spacing between SIT cases; range 1–86 400 |
| `--poll-ms <milliseconds>` | `1000` | Activity poll interval; range 1–30 000 |
| `--timeout-seconds <seconds>` | `90` | Per-turn response timeout; range 1–3 600 |
| `--no-browser` | browser launch on | Prints the OAuth URL instead of opening it |
| `--help` | — | Prints usage and exits |

Constraints the parser enforces:

- `--sit-list` and `--message` cannot be combined.
- `--sit-file` and `--interval` apply only to list mode.
- Numeric options are range-checked at parse time, so an out-of-range value fails before any network
  call.

## Safety rules

- The secret lives in a process environment variable only — never in source, arguments, shell
  history, logs, or a configuration file.
- The SIT lists contain synthetic data only. Never use real personal, financial, passport, or
  resident-registration data.
- This client never runs `a365` or `atk` commands, never signs in on the operator's behalf, and never
  creates, updates, consents to, deploys, or deletes a policy.
- Never disable fail-closed Purview enforcement to make a run pass.
