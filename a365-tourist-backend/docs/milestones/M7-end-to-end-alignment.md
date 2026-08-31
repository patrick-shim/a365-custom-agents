# M7 End-to-End Cross-Channel Production Alignment

M7 preserves the completed four-project ownership separation and has one overriding goal: bring 100%
of in-scope code, configuration contracts, infrastructure, and channel integrations into alignment
with the canonical shared backend, then make OBO Teams, OBO Direct Line, and AI Teammate work together
in production as one governed system against the same deployed revision.

"100% alignment" means zero unexplained drift in routes, audiences, authentication, child-identity
selection, Purview enforcement, MCP contracts, observability, configuration, package endpoints,
deployment inputs, or active revision provenance. It never means copying backend code into a
frontend or moving frontend package state into the backend.

## Ownership

- `a365-tourist-backend` exclusively owns shared runtime code, infrastructure, Docker assets,
  backend tests, validation tools, and Azure deployment.
- `a365-tourist-agent-obo` exclusively owns the OBO Teams package and protected OBO operational state.
- `a365-tourist-agent-obo-directline` exclusively owns the Direct Line client and synthetic SIT tests.
- `a365-tourist-agent-teammate` exclusively owns authoritative AI Teammate CLI package state.

## Required workflow

1. Establish fresh local, Azure, identity, route/audience, Purview, and package baselines.
2. Diagnose each failure at its owning boundary and make source changes only in that project.
3. Run a documented dry run with an exact mutation boundary, rollback target, and sanitized evidence.
4. Obtain explicit approval separately for backend deployment, frontend publication/installation,
   consent, identity/audience, Purview, or Insider Risk Management mutations.
5. Validate OBO Teams and Direct Line through `/api/messages/obo`, and AI Teammate through
   `/api/messages`, against the same deployed backend revision.
6. Record only sanitized status, timing, revision, digest, and aggregate evidence; never prompts,
   responses, matched SIT values, tokens, credentials, secrets, or tenant-bound generated files.

## Definition of done

- Canonical backend source and freshly validated deployment inputs produce the active backend
  revision with no unexplained drift.
- OBO Teams and Direct Line both pass `/api/messages/obo` using the same OBO audience and child
  identity, with expected Purview behavior.
- AI Teammate passes `/api/messages` using the shared Blueprint audience and dynamic child identity,
  with expected Purview behavior.
- All three frontends pass against the same backend revision, and each package/client remains within
  its project ownership boundary.
- No acceptance item is inferred from local tests, package structure, or historical evidence; live
  sanitized evidence exists for every channel.

## Current checkpoint

- Canonical source passes 28/28 strict repository checks, 15/15 categorized Purview behavior tests,
  75/75 tool self-tests, 11/11 Release local-CI gates, and 130/130 solution tests. The Direct Line
  frontend passes 5/5 focused tests, and the online Purview tenant read passes 12/12.
- Production host revision `0000028` is healthy, latest-ready, and receiving 100% traffic at digest
  `sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`.
  Revision `0000027`, digest
  `sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`,
  is the verified rollback boundary. The four MCP services remain healthy on revision `0000005` and
  their approved immutable digests.
- Live host configuration has distinct Blueprint and OBO audiences, aligned Purview and token tenant
  values, fail-closed compatibility processing, all three delegated Purview scopes, and authenticated
  HTTPS internal MCP endpoints. Each protected turn receives a distinct Purview wrapper; wrapper
  disposal is deferred to host shutdown for background content-activity completion.
- The named Direct Line DLP policy is enabled, distributed successfully, scoped to the Blueprint and
  OBO Channel application locations, and has three enforced `UploadText=Block` rules. Exactly three
  isolated Direct Line cases on revision `0000028`—one synthetic credit card, one South Korean
  passport, and one South Korean resident-registration number—were blocked before model access.
  Model requests were zero throughout the covered interval, prompt values were not echoed, and no
  closed-channel warning appeared during observation.
- AI Teammate endpoint/inheritance reconciliation, the missing delegated Graph grants and admin
  consent, and Foundry User RBAC have been completed through separately approved workflows. They are
  prerequisites, not substitutes for live same-revision acceptance evidence.
- M7 remains active. OBO Teams was last documented live on revision `0000025`; the authoritative AI
  Teammate also lacks a sanitized acceptance record tied to `0000028`. Re-run both channels against
  `0000028` before claiming the three-frontends/one-revision definition of done.

### 2026-08-17 - Live OBO Teams pass and AI Teammate wiring diagnosis

- Live OBO Teams acceptance passed against production host revision `0000025`: a normal turn
  returned a current weather-grounded walking recommendation, proving the `/api/messages/obo`
  channel and weather MCP path. A bounded synthetic sensitive-data turn was blocked by the Teams
  client with no bot reply; the corresponding sanitized host interval contained zero model requests.
- Microsoft 365 Admin Center identifies `KoreaExpert Blueprint` version `1.1.5` with three active
  instances. The authoritative `Korea Expert Assistant` instance is available, but its Activity
  view contains no usage for the last 30 days. A live Teams message remained delivered without a
  response, and the matching host interval contained health probes only, with no inbound agent turn.
- The authoritative AI Teammate source still pins the correct production `/api/messages` endpoint,
  Blueprint, and package contract. Supported Agent 365 CLI dry runs found that the tenant endpoint
  registration must be reconciled through the M365 setup path; the reviewed operation reuses the
  existing Blueprint and registers only the exact production `/api/messages` endpoint through Teams
  Graph.
- Read-only Blueprint inheritance verification found five of seven resource contracts effective.
  Microsoft Cognitive Services `user_impersonation` and the backend MCP API `Mcp.Invoke` grants are
  present on the Blueprint but their app-role inheritance kind is not `allAllowed`. Separate
  supported CLI dry runs were completed for exactly those two existing resource/scope pairs.
- The rollback boundary is explicit: remove only the M365 messaging-endpoint registration with the
  supported endpoint-only cleanup command, and restore only those two inheritance entries to their
  captured pre-change state (`inheritableScopes=allAllowed`, `inheritableRoles=none`). The Blueprint,
  package, three instances, grants, and all other resource entries remain untouched.
- No AI Teammate endpoint, permission, package, instance, license, or tenant mutation was made.
  Live AI Teammate acceptance remains gated on explicit approval of the reviewed endpoint and two
  inheritance reconciliations, followed by normal-turn, MCP, Purview-block, and sanitized
  observability validation against revision `0000025`.

### 2026-08-17 - AI Teammate endpoint and inheritance reconciliation

- The explicitly approved endpoint-only Agent 365 CLI workflow registered the exact production
  `/api/messages` URL against the existing Blueprint. It did not recreate the Blueprint or publish,
  install, or hand-edit the AI Teammate package.
- The two approved existing inheritance entries were reconciled in place. Microsoft Cognitive
  Services and the backend MCP API now both have `inheritableScopes=allAllowed` and
  `inheritableRoles=allAllowed`; `a365 query-entra inheritance` reports all seven resource entries
  effective.
- A live normal AI Teammate turn now reaches host revision `0000025`, proving the endpoint repair.
  Foundry, Graph process-content, internal MCP, and observability exchanges succeed, and all four
  MCP discovery calls return HTTP 200. The turn then fails closed before model access because
  Microsoft Graph `protectionScopes/compute` returns HTTP 403. The same result was reproduced after
  a propagation wait, with zero Azure OpenAI model requests in both intervals.
- Read-back found that the Blueprint and host request only `Content.Process.User`. Microsoft Graph
  documents `ProtectionScopes.Compute.User` for protection-scope computation and
  `ContentActivity.Write` for the Purview audit activity used by this host. The canonical backend
  now has a local, undeployed correction that requests all three delegated Graph scopes and injects
  the two missing production handler settings.
- Local evidence passes: 128/128 solution tests, 91/91 host tests, 28/28 strict repository checks,
  11/11 Purview readiness checks, 43 aggregate validation passes with five expected offline skips,
  73/73 tool self-tests, and a clean Bicep compile. ARM validation succeeds, and the rollback-pinned
  what-if contains exactly five existing Container App modifications, 15 ignored dependencies, and
  zero creates or deletes; only the host's two added Purview scope settings are intentional.
- No new Graph permission, OAuth consent, candidate registry image, Container App revision, Purview
  policy, package, identity, route, audience, or secret mutation was made. The next mutation gate is
  a separately approved least-privilege Graph permission addition plus candidate host build and
  backend deployment. The exact rollback restores the captured Graph required-resource-access list
  and OAuth grant scope string, then redeploys host revision `0000025` digest
  `sha256:ba253ddaf819b69e84034252fe21a0ad12c9c7acdb85b527420934e5ef025fb9`.

### 2026-08-17 - Purview scope backend deployment and Direct Line acceptance

- User approval authorized the previously reviewed M7 backend rollout. A fresh immutable host image
  was built in ACR as digest
  `sha256:df173e8bc0324c803acdc82402defe2484d3ee77dc049f2e08a7a81e0ce093ff`.
- Candidate ARM validation succeeded. Structured what-if contained exactly five existing Container
  App modifications, 15 ignored dependencies, and zero creates or deletes. The four MCP images were
  pinned to their existing revision `0000005` digests; the only intentional runtime change was the
  host image plus the two missing Purview handler scope settings.
- Deployment `koreaexpert-m7-purview-scopes-20260817-01` succeeded. Host revision `0000026` is healthy,
  active, running at 100% traffic, and both health endpoints return HTTP 200. Live environment
  read-back contains all three delegated Purview scopes.
- Live Direct Line acceptance against revision `0000026` passed. A normal weather turn returned a
  current attributed response through the weather MCP. One synthetic passport, South Korean RRN,
  and credit-card case each returned the configured organization DLP block message; prompt values
  were not echoed. Revision logs record policy blocking before model execution and retain the known
  non-blocking RC1 background audit-channel warning.
- Protected deployment parameters pinned the exact active host and MCP digests; the checked-in Bicep
  and compiled ARM wrapper remain parameterized. Revision `0000025` and host digest
  `sha256:ba253ddaf819b69e84034252fe21a0ad12c9c7acdb85b527420934e5ef025fb9`
  remain the rollback boundary.
- The AI Teammate Blueprint still lacks the separately gated Graph delegated permissions
  `ProtectionScopes.Compute.User` and `ContentActivity.Write`; backend deployment does not grant
  tenant consent. AI Teammate live acceptance therefore remains open even though the corrected code
  is now deployed.

### 2026-08-17 - AI Teammate permission and Foundry reconciliation

- The two missing Microsoft Graph delegated permissions, `ProtectionScopes.Compute.User` and
  `ContentActivity.Write`, were added to the existing Blueprint and received tenant admin consent.
  `Content.Process.User` was already present; no unrelated Graph permissions were added.
- The approved Foundry User data-plane role was assigned to the effective AI Teammate runtime
  identity rather than the host UAMI. The existing Blueprint, child identity, endpoint, package,
  audiences, and backend routes were preserved.
- These operations clear the previously recorded protection-scope 403 and Foundry authorization
  prerequisites. A normal channel observation indicated the teammate was operating, but M7 still
  requires a sanitized replay explicitly tied to the final shared revision before same-revision
  acceptance can be closed.

### 2026-08-17 - Per-turn Purview lifecycle deployment and isolated Direct Line proof

- Canonical source now creates a distinct Purview-wrapped chat client for every protected turn so
  protection-scope and ETag state cannot be shared across requests. Created clients remain alive for
  background content-activity work and are disposed exactly once at host shutdown.
- Local gates pass: 28/28 strict repository checks, 15/15 categorized Purview behavior tests, 75/75
  tool self-tests, 11/11 Release local-CI checks, 130/130 solution tests, and 5/5 Direct Line tests.
  The online tenant read passes 12/12 and confirms an enabled Application-plane collection policy.
  The named DLP policy is enabled with successful distribution, both frontend locations, and three
  enforced `UploadText=Block` rules.
- A new immutable host candidate was published at digest
  `sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`.
  Candidate and rollback ARM validation succeeded. Both structured what-ifs contained exactly five
  existing Container App modifications, 15 ignored dependencies, and zero creates or deletes; the
  only concrete runtime value change was the host image. Revision `0000027` at digest
  `sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`
  remains the verified rollback boundary.
- Deployment `m7-purview-per-turn-20260817-01` succeeded. Host revision `0000028` is healthy,
  latest-ready, active at 100% traffic, and reports HTTP 200 for liveness and the expected degraded
  process-local-storage readiness state. All four MCP services remain pinned to revision `0000005`
  digests.
- Direct Line sent exactly three approved synthetic cases with three-minute isolation gaps: one
  passport, one South Korean resident-registration number, and one credit card. Each returned the
  organization DLP block message, and revision logs recorded a policy block before model access.
  Azure OpenAI `ModelRequests` was zero in every one-minute bucket from 17:33Z through 17:39Z,
  covering all three turns. No background closed-channel error appeared in the observed interval.
