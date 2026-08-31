# Validation tools

These PowerShell 7 scripts are intended for both humans and coding agents. They use the same module,
result schema, milestone rules, and exit-code behavior. Shared logic lives in
`modules/JapanExpert.Validation/JapanExpert.Validation.psm1`; the command scripts are thin wrappers.

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
- Fixed non-secret deployment names may be committed: the target resource group, the existing Foundry
  account and project, its endpoint, and the model deployment name. Subscription GUIDs, tenant or
  directory IDs, principal and object IDs, owner user principal names, and full ARM resource IDs are
  runtime values. `Test-Repository.ps1` fails when one is committed, and reports only the file, line,
  and rule so the finding itself never republishes the value.
- Every validation function is defined, exported, and called under the `Jex` prefix. `Test-Repository.ps1`
  fails on a retired product acronym or a non-`Jex` module function. Matching is case sensitive, so
  English words such as "two-stage" and resource names such as `id-stay-japanexpert` are not flagged,
  and the two self-test harness helpers are allowed because they are not part of the validation API.

## Commands

```powershell
# Local prerequisites and repository policy
./tools/Test-Prerequisites.ps1
./tools/Test-Repository.ps1

# Deployment boundary: resource-group scope, existing Foundry reference, and Japan Expert naming
./tools/Test-Deployment.ps1
./tools/Test-Deployment.ps1 -OutputFormat Json -Strict

# Azure: local configuration only, then optional signed-in read checks
./tools/Test-Azure.ps1
./tools/Test-Azure.ps1 -Online -SubscriptionId '<subscription-id>' -ResourceId '<resource-id>'

# Purview: local implementation evidence and optional read-only tenant policy evidence
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
does not rely on one tenant-localized display name and never changes the policy. The historical M7
checkpoint passed 12/12 checks, including 15/15 categorized behavior tests; M8 requires fresh
Japan Expert acceptance evidence before any equivalent current claim.

The Purview probe token needs Microsoft Graph `Content.Process.User` or `Content.Process.All`. Prefer
least privilege and a dedicated test user/application scope. A direct `-ProbePolicy` call proves a
policy-service outcome only; it is not end-to-end evidence that a channel request was blocked before
model access. Pair channel acceptance with sanitized host policy-block evidence and zero model
requests for the isolated interval.

## Synthetic sensitive-data cases

Acceptance uses exactly three reserved synthetic cases: a Japan passport number shaped as `ZZ` plus
7 digits, a Japanese residence card number shaped as `ZZ` plus 8 digits plus `ZZ`, and the industry
reserved test card number. `ZZ` is never issued for a real document, so the first two shapes cannot
collide with real data. Exact reserved values belong only to the Direct Line frontend's reviewed
three-case prompt list; do not duplicate them into backend source, parameter files, logs, or evidence.

Backend `Test-Repository.ps1` fails when backend source contains a checksum-valid card-shaped number,
or a passport- or residence-card-shaped literal outside the reserved prefix. It also fails when the
active milestone stops declaring the three cases or re-declares a retired Korean case. Findings report
file, rule, and line only, so the result object and JSON output never republish a value. Generated
template hashes are exempt from the card rule because a numeric hash can satisfy the checksum by
coincidence.

## Output and exit codes

The seven validation and local-CI wrappers support `-OutputFormat Text|Json` and `-Strict`.
`tools/tests/Invoke-ToolsSelfTest.ps1` is the dependency-free test runner; it accepts only
`-RepositoryRoot` and emits `PASS`/`FAIL` text.

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

## Deployment boundary checks

`./tools/Test-Deployment.ps1` and the deployment results inside `./tools/Invoke-Validation.ps1` are
offline and read-only. They parse `infra/**` and assert that:

- both entry templates declare `targetScope = 'resourceGroup'` and no template declares a wider scope;
- no template declares `Microsoft.Resources/resourceGroups` or a subscription, management group, or
  tenant scoped deployment, so a resource group can never be created;
- both entry templates pin and guard the approved backend resource group, and reference no other
  resource group than the existing Foundry group;
- the existing Foundry account is referenced across resource groups and never created, with its
  project and model deployment pinned as parameter defaults;
- all 16 resource names default to deterministic Japan Expert values inside their Azure length limits
  and stay identical between the bootstrap and update templates;
- the registry defaults to Basic, all four public-provider MCP apps are capped at one replica, and the
  Key Vault surface equals what first-party source actually reads, so with no secret client in the
  server tree the deployment declares no vault and the rule relaxes automatically if one is added;
- no infrastructure module file is unreferenced by an entry template, so deleted capability cannot
  survive as stale plumbing;
- the deployment and validation guidance in this project states the milestone that
  `docs/milestones/milestones.json` marks current, and every earlier milestone appears only as an
  explicitly historical reference, a milestone range, or a link to that milestone's record;
- no executable deployment file carries a retired Seoul deployment name;
- the checked-in compiled update template still matches its Bicep source;
- deployed MCP provider configuration covers exactly the configuration sections each MCP service
  binds, over HTTPS, with a commit-safe `User-Agent` and no retired provider setting;
- the bootstrap and update templates declare identical provider defaults;
- infrastructure declares no Agent 365 Blueprint, agent identity, or federated identity credential
  resource type, and still publishes `hostManagedIdentityPrincipalId` for the CLI handoff;
- the Azure Bot, Direct Line v3, Teams channel, and Aadv2 OAuth connection are declared once in the
  bootstrap template, bound to `/api/messages/obo` and the OBO channel application, with fail-closed
  inputs, secure secret propagation, and no literal or output secret;
- the deployed host configuration sets exactly the settings the agent host options contract marks
  required, emits no `AgentHost__` key the contract does not declare, derives the Foundry project
  endpoint from the pinned account and project names, and injects no account-root endpoint setting,
  raw `/openai/responses` route, or `api-version`. The retired account-root endpoint and deployment
  keys also fail this check if they reappear in the deployment documentation this project owns, so
  that prohibition is stated by description rather than by repeating the key names;
- the deployed inference token scope equals the scope the host source requests, the runbook grants
  `Cognitive Services User` at the existing Foundry account scope, it excludes the host managed
  identity, and no template or runbook claims a retired Foundry data-plane role.

The approved resource group, Foundry account, and model deployment are cross-checked against the
active milestone in `docs/milestones/milestones.json`, and the required MCP provider configuration
sections are read from each MCP service's own `appsettings.json`, so protocol, source, and validation
cannot drift apart. Package presence, template compilation, and these structural checks are readiness
evidence only; they never prove that a resource, identity, or registration exists in the tenant.

Source paths that carry the product name are discovered structurally through `Get-JexSourceLayout`
rather than hard-coded, so a product rename in progress produces a readable failure instead of a
crash.
