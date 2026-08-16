# Validation tools

These PowerShell 7 scripts are intended for both humans and coding agents. They use the same module,
result schema, milestone rules, and exit-code behavior.

The backend validation path depends on PowerShell, .NET, Git, and optionally Azure CLI for explicit
online reads. Agent 365 CLI, Microsoft 365 Agents Toolkit, and npm package validation belong to the
owning frontend projects.

## Safety model

- Default execution is local/offline and read-only.
- `-Online` enables tenant or subscription reads only. Scripts never log in for the user.
- The tools reject every `a365` and `atk` command, as well as policy creation, policy update, consent,
  deployment, and deletion commands. Agent 365 and Teams validation belongs to the owning frontend.
- Purview `processContent` is a POST because policy evaluation requires it. It runs only with
  `-Online -ProbePolicy`, sends synthetic caller-supplied text, may be retained if tenant ingestion is
  enabled, and never prints the access token or submitted text.
- Real access tokens must be placed in a process environment variable, never passed on the command
  line or committed.
- Protected `.azure`, `.a365`, and `.copilot-azure` operational trees are excluded from repository
  content scans. They are preserved locally and never treated as source or current evidence.

## Commands

```powershell
# Local prerequisites and repository policy
./tools/Test-Prerequisites.ps1
./tools/Test-Repository.ps1

# Azure: local configuration only, then optional signed-in read checks
./tools/Test-Azure.ps1
./tools/Test-Azure.ps1 -Online -SubscriptionId '<subscription-id>' -ResourceId '<resource-id>'

# Purview: local M7 implementation evidence and optional read-only tenant policy evidence
./tools/Test-Purview.ps1
./tools/Test-Purview.ps1 -RequireImplemented
./tools/Test-Purview.ps1 -RequireImplemented -Online -CheckTenantPolicy

# Explicit synthetic processContent probe. Set the token in your own shell first.
$env:PURVIEW_GRAPH_ACCESS_TOKEN = '<delegated-or-application-token>'
./tools/Test-Purview.ps1 -Online -ProbePolicy `
  -UserId '<user-object-id-or-upn>' `
  -ApplicationId '<application-id>' `
  -ExpectBlock

# Aggregate local validation
./tools/Invoke-Validation.ps1 -OutputFormat Json

# Full local CI: tool tests, build, tests, seven health probes, and process cleanup
./tools/Invoke-LocalCi.ps1
./tools/Invoke-LocalCi.ps1 -OutputFormat Json

# Dependency-free tool tests
./tools/tests/Invoke-ToolsSelfTest.ps1
```

The versioned non-secret frontend boundary is defined in
`contracts/frontend-backend-contract.json`. OBO Teams package registration and CLI state, OBO Direct
Line validation, and AI Teammate package registration belong to their respective frontend projects.

For `-CheckTenantPolicy`, install `ExchangeOnlineManagement` and establish your own Security &
Compliance PowerShell session first; the validation script never signs in for you:

```powershell
Import-Module ExchangeOnlineManagement
Connect-IPPSSession
./tools/Test-Purview.ps1 -RequireImplemented -Online -CheckTenantPolicy -OutputFormat Json
```

The script calls `Get-FeatureConfiguration -FeatureScenario KnowYourData` and accepts an enabled
semantic match that includes the Application enforcement plane with upload and download text. It
does not rely on one tenant-localized display name and never changes the policy. The current M7
checkpoint passes 12/12 checks, including 15/15 categorized behavior tests.

The Purview probe token needs Microsoft Graph `Content.Process.User` or `Content.Process.All`. Prefer
least privilege and a dedicated test user/application scope. A direct `-ProbePolicy` call proves a
policy-service outcome only; it is not end-to-end evidence that a channel request was blocked before
model access. Pair channel acceptance with sanitized host policy-block evidence and zero model
requests for the isolated interval.

## Output and exit codes

Every command supports `-OutputFormat Text|Json` and `-Strict`.

- Exit `0`: no failed checks. Warnings are allowed unless `-Strict` is used.
- Exit `1`: one or more checks failed, no checks were produced, or a warning exists under `-Strict`.
- `Pass`: evidence is present.
- `Skip`: the check was not requested or is correctly deferred by the milestone.
- `Warn`: useful evidence is incomplete but not required by the selected mode.
- `Fail`: a required invariant or requested online check failed.

JSON output contains `Summary` and `Results`; each result includes `Area`, `Check`, `Status`,
`Message`, `Remediation`, and optional non-secret `Data`.

`Invoke-LocalCi.ps1` produces 11 gates: tool self-test, build, solution tests, three host health
endpoints, four MCP health endpoints, and process cleanup. It uses random loopback ports, captures
service logs only for failures, and treats cleanup as required. The matching GitHub workflow runs on
Windows without cloud login or online validation switches.
