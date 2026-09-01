# Contributing

Thanks for looking at this. It is a reference implementation, so the most useful contributions are
usually a clearer explanation, a fixed link, or a genuine bug — not a refactor.

## Before you change anything

Reproduce the baseline. If these do not pass on a clean clone, that is the bug to report:

```powershell
cd a365-tourist-backend
./tools/Invoke-LocalCi.ps1 -Strict     # build, tests, local host and MCP health probes
./tools/Test-Repository.ps1 -Strict    # architecture and security boundary checks
```

Everything above runs offline. No Azure subscription, no tenant, no sign-in.

## What the validation suite is actually for

`Test-Repository.ps1` enforces the architecture rather than describing it. If it fails, the design
has been broken, not the test. It checks, among other things:

- the two-stage child Agent Identity exchange and per-resource token binding
- that Purview evaluation stays fail-closed
- the MCP token audience boundary and HTTPS-only endpoints outside local runs
- canonical MCP schema fingerprints
- that no real subscription, tenant, principal, mailbox, or resource identifier is committed

If your change needs one of these relaxed, please open an issue explaining the security reasoning
first. A pull request that edits the guard to make the build pass will be declined.

## Things that commonly surprise people

- **MCP tool descriptions are part of the SHA-256 schema fingerprint.** Editing a description without
  repinning the fingerprint fails the build. That is intentional: the fingerprint is what stops a
  tool contract from drifting silently.
- **Readiness reports `degraded` locally.** The sample uses process-local session storage, so the
  host declares itself unsafe to scale out. This is correct behaviour, not a failure.
- **The `a365-tourist-*` directory names are stable ownership boundaries**, not product branding.
- **Generated packages, `.env` files, and Agent 365 CLI state are deliberately untracked.** They are
  tenant-bound. Do not commit them, and do not add them to a pull request.

## Style

- Match the surrounding code. The backend builds with `TreatWarningsAsErrors`, so a warning is a
  build break.
- Markdown wraps at 100 columns.
- Commit messages explain *why* the change is correct, not what the diff shows.

## Reporting a security issue

Do not open a public issue. See [SECURITY.md](SECURITY.md).
