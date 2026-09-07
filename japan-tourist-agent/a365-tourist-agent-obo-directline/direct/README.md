# Japan Tourist Expert Direct Line Console Client

The .NET 10 console app in `JapanExpert.Direct` talks to the Japan Tourist Expert OBO Azure Bot through
Direct Line v3.
It does not use Teams or Microsoft 365 Copilot. It starts a Direct Line conversation, sends user
messages, renders agent replies, renews expiring conversation tokens, and completes Bot Token
Service authentication through the OAuth card and standard message-based magic-code flow.

## Prerequisites

- The OBO Azure Bot has an enabled Direct Line site.
- The bot endpoint targets `/api/messages/obo`.
- The Bot Token Service connection is named `japan-tourist-assistant-obo`.
- You have one Direct Line site secret. Keep it in an environment variable; do not put it in source,
  arguments, shell history, or logs.

Read `JAPAN_EXPERT_DIRECT_LINE_SECRET` from the Azure Bot's Direct Line channel keys and set it only
in the current process, without printing it. Direct Line acceptance should prove zero unexplained
route, audience, OAuth, token-renewal, policy, or response drift from the deployed backend.

## Run

Interactive conversation:

```powershell
dotnet run --project direct/JapanExpert.Direct
```

Send one prompt and exit after the response:

```powershell
dotnet run --project direct/JapanExpert.Direct -- `
  --message 'Plan a one-day Tokyo itinerary for tomorrow.'
```

The first protected turn can return an OAuth card. The client opens its URL in the default browser.
Sign in with the Microsoft 365 user, then enter the displayed verification code in the console. If
the browser reports that sign-in completed automatically, press Enter without a code and the client
continues polling.

Use `--no-browser` on a remote shell and open the printed URL yourself. Use `--help` for endpoint,
identity, polling, and timeout options. A regional Direct Line base URL can also be supplied through
`JAPAN_EXPERT_DIRECT_LINE_ENDPOINT` or `--endpoint`.

Remove the process-scoped secret when finished:

```powershell
Remove-Item Env:JAPAN_EXPERT_DIRECT_LINE_SECRET
```

For isolated M8 acceptance, use the reviewed three-case file containing reserved synthetic Japan
passport, Japanese residence-card, and credit-card test values, with three-minute separation:

```powershell
dotnet run --project direct/JapanExpert.Direct -- `
  --sit-list `
  --sit-file '<approved-three-case-file>' `
  --interval 180
```

Correlate each isolated interval with sanitized host policy-block evidence and zero Microsoft
Foundry model requests. Refusal wording by itself is not proof that Purview blocked before model
access.

The Japan formats follow the Microsoft Purview definitions for
[Japan passport numbers](https://learn.microsoft.com/purview/sit-defn-japan-passport-number) and
[Japanese residence card numbers](https://learn.microsoft.com/purview/sit-defn-japan-residence-card-number).
The `ZZ`-prefixed values are reserved synthetic fixtures, never real identifiers.

`--sit-list` sends `direct/sensitive-information-type-test.json`; `--interval` controls spacing.
Use `--sit-list --sit-file <path>` only with another reviewed synthetic list. SIT mode prints record
numbers and agent responses but never echoes the submitted identifiers. `--sit-list` and `--message`
are mutually exclusive.
