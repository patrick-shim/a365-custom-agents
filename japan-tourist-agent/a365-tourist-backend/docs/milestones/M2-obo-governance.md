# M2 production OBO governance verification

This document is the durable resume point for M2. Keep it sanitized: record resource names,
revision names, timestamps, status codes, event IDs, and aggregate counts, but never prompts,
responses, matched values, tokens, credentials, or generated secret-bearing files.

> Historical M2 evidence is dated 2026-08-10. M2 was resumed by explicit user instruction on
> 2026-08-16 after the source-separation checkpoint, then returned to blocked when the user revised
> M7 as the cross-channel production-alignment milestone. References below to AI Teammate package version `1.1.4` describe
> the M2 checkpoint; the later CLI-generated package publication record is version `1.1.5`. Do not
> hand-edit generated package state to reconcile the record.

## Activation

- Status: blocked; remaining Seoul cross-channel and Purview verification transferred to M7, which is
  now historical; active M8 requires fresh Japan Expert evidence
- Exact activation phrase: `Start milestone M2`
- Activated by explicit user instruction on 2026-08-10.
- Resumed by explicit user instruction on 2026-08-16.
- Transitioned back to blocked when M7 became the active end-to-end alignment milestone.
- No deployment, publication, consent, or Purview/IRM policy mutation is allowed until its
      corresponding dry run has separate explicit approval.

## Required outcomes

1. Agent 365 Activity is visible for both the OBO child and the shared Blueprint.
2. Purview records governed AI interactions, DLP decisions, SIT matches, and content activity.
3. Insider Risk Management prerequisites and policy scope are valid, with a policy-correct risk
   signal or explicitly documented no-risk outcome from synthetic activity.
4. The supported Agent 365 package is patch-versioned, generated, validated, and installable.
5. Direct Line OBO, Teams, and Microsoft 365 Copilot all pass against the same backend.

## Starting evidence

Captured on 2026-08-10 from read-only production inspection:

- The active Container App revision is healthy and has the Agent 365 exporter enabled.
- Four observability token registrations failed with `Agent Identity token acquisition requires
  resource /.default scopes.`
- Five exporter batches reported `No token obtained. Skipping export for this identity.`
- No outbound Observability API export attempt or successful response was observed.
- The OBO child has valid inherited Observability `OtelWrite` permission evidence.
- The message handler creates identity baggage and pins `ChatClientAgent.Id` correctly.
- The message handler does not create the required `InvokeAgentScope` with `CallerDetails`.
- The current Activity pages being empty is therefore consistent with two independent blockers:
  token acquisition fails before export, and no portal-visible invocation activity is emitted.

## Execution checklist

### Gate and baseline

- [x] Activate M2 with the exact phrase and transition `milestones.json` separately.
- [ ] Capture sanitized CLI, SDK, package, deployment, and tenant baseline versions.
- [ ] Confirm licenses, admin roles, audit ingestion, Purview solution onboarding, and IRM analytics
      prerequisites without mutation.
- [x] Record current Agent 365 package version and supported CLI packaging command.

### Observability repair

- [x] Add tests that reproduce the `/.default` scope-shape failure.
- [x] Normalize observability scopes at the token-exchange ownership boundary.
- [x] Add `InvokeAgentScope` with runtime child/Blueprint attribution and `CallerDetails`.
- [x] Emit invocation occurrence metadata without recording input or output content.
- [ ] Confirm inference and framework tool spans remain non-sensitive children of the invocation.
- [x] Enable sanitized exporter diagnostics needed to prove token registration and service acceptance.

### Build, deploy, and activity proof

- [x] Run focused tests, full build/tests, local CI, and tools self-tests.
- [x] Produce an immutable deployment plan and rollback target; review/approval remains pending.
- [x] Deploy only after explicit approval of the deployment dry run.
- [x] Send uniquely correlated non-sensitive OBO turns without logging their content.
- [x] Prove token registration, export acceptance, and no skipped identity group in runtime logs.
- [ ] After the indexing window, capture sanitized Activity evidence for child and Blueprint views.

### Purview and Insider Risk Management

- [ ] Verify AI interaction and content-activity audit ingestion for the correlated synthetic turn.
- [ ] Run a bounded synthetic SIT matrix for credit card, Korean passport, and Korean resident
      registration categories.
- [ ] Prove expected DLP allow, audit, warn, or block behavior against the actual policy definition.
- [ ] Verify IRM licensing, indicators, policy scope, analytics state, and user inclusion.
- [ ] Review any proposed Purview/IRM policy change as a dry run and obtain explicit approval.
- [ ] Verify the resulting IRM signal/score or document why the configured policy correctly produces
      no risk for the synthetic scenario.

### Package and channel acceptance

- [x] Determine whether package content changed and increment the supported source version only when
      required. At the 2026-08-10 M2 checkpoint, the backend-only repair did not change the package
      and its version was `1.1.4`.
- [x] Validate the Agent 365 package with the supported `a365 publish --dry-run` workflow.
- [ ] Verify update/install semantics without running Blueprint cleanup.
- [ ] Pass Direct Line OBO authentication and governed response acceptance.
- [x] Pass Microsoft 365 Copilot OBO acceptance against revision `0000020`; Teams package validation
      remains passed and the same bot/channel backend is used.

### Closure

- [ ] Re-run all offline and approved online validations.
- [ ] Record final revision/image digest, package version, evidence timestamps, and indexing latency.
- [ ] Remove temporary synthetic fixtures and confirm no sensitive values entered logs or telemetry.
- [ ] Mark M2 complete only when every acceptance-evidence item is proven or explicitly blocked with
      owner and next action.

## Checkpoint log

### 2026-08-16 - M2 resumed and Direct Line DLP scope dry run

- The user explicitly resumed M2 with `Start milestone M2`; M2 is current and active and M7 is
      blocked without waiving its completed source-separation evidence.
- Local validation passed: backend tests, Direct Line focused tests, OBO Teams structure, AI
      Teammate structure, repository validation, and Purview fail-closed behavior are healthy.
- Read-only production inspection found host revision `0000022` ready with liveness/readiness HTTP
      200, populated protected settings, and distinct Blueprint and OBO frontend audiences.
- Read-only Security & Compliance inspection found `a365-custom-obo-agent-direct` enabled on the
      Application enforcement plane with all three expected rules enabled in Enforce mode and
      `UploadText=Block`. The rules use high-confidence, minimum-count-one credit-card, South Korean
      passport, and South Korean resident-registration classifications.
- Root cause: the policy still has only the `SeoulTourist Blueprint` Enterprise application
      location and its distribution status remains Pending. OBO Direct Line identifies the distinct
      `Seoul Tourist OBO Channel` application, so the blocking rules do not apply to those turns.
- Proposed mutation dry run: replace this policy's application-location document with exactly its
      existing Blueprint location plus the existing OBO Channel location, retain Tenant/All,
      Application enforcement, policy mode, and all rule definitions, then read back status. If the
      updated policy reports a distribution error or remains Pending, separately retry distribution
      for this policy only.
- Mutation boundary: no policy/rule creation or deletion, no backend deployment, no package
      publication, no identity/audience/consent change, and no IRM change. Rollback restores the
      current Blueprint-only location document and reads back the policy.
- Awaiting explicit post-dry-run approval; no policy mutation has occurred in this resumed run.

### 2026-08-16 - Direct Line DLP application scope updated

- The user explicitly approved the recorded M2 DLP scope update.
- Updated only `a365-custom-obo-agent-direct`: preserved the existing Blueprint Enterprise
      application and Tenant/All inclusion, added the existing `Seoul Tourist OBO Channel`
      Enterprise application with Tenant/All inclusion, and retained Application enforcement.
- Immediate read-back confirms both locations, policy mode Enable, three rules, and all three
      expected rules enabled in Enforce mode with their existing definitions.
- Distribution remains Pending. A bounded `RetryDistribution` request was attempted for this policy
      only, but Purview ignored it because the content source has not reported a distribution error.
      Microsoft guidance in the returned warning is to wait for a timeout error and contact support
      if the deployment remains stuck beyond the documented window.
- No other policy, rule, identity, audience, consent, IRM state, package, backend deployment, or
      Azure resource changed. Direct Line enforcement testing is waiting on policy distribution and
      a process-scoped Direct Line secret.

### 2026-08-10 - Milestone definition

- Defined M2 as a planned milestone; no tenant mutation performed.
- Root-cause evidence preserved above.

### 2026-08-10 - Activation

- M1 marked complete and M2 made current and active after explicit user instruction.
- M3 planning completed separately before this transition.
- No runtime code, deployment, publication, consent, policy, or other tenant state changed in the
      transition.

### 2026-08-10 - Blocked on external IRM indexing

- The user explicitly activated M3 with `Start milestone M3` and directed that M2 be marked blocked
      only on external IRM indexing.
- M2's checklist and evidence remain intact for later resumption after the 24-72 hour indexing
      window. No unchecked item is waived or treated as complete by this transition.
- No deployment, publication, consent, policy, or other tenant mutation is part of the milestone
      transition.

### 2026-08-10 - Observability repair implemented locally

- Replaced the delegated observability scope at the S2S child-token call site with the Observability
      API resource `/.default` contract.
- Added a content-free `InvokeAgentScope` under existing identity baggage with runtime child ID,
      shared Blueprint ID, tenant ID, channel/session identifiers, and caller identity metadata.
- Kept `IChatClient` sensitive-data capture disabled and added regression assertions that no input
      or output message recording API is called.
- Added sanitized OpenTelemetry and Agent 365 exporter diagnostics to the Container App template.
- Validation: AgentHost tests 65 passed, 0 failed; full Bicep entry point compiled successfully.
- No deployment or tenant mutation performed. Production remains on the prior revision until a
      deployment dry run is reviewed and approved.

### 2026-08-10 - Package and governance baseline

- Agent 365 CLI version: `1.1.214+90c444832f`.
- The shared AI Teammate package is the supported shared-Blueprint package and is version `1.1.4`.
- `a365 publish --dry-run` validated that package without writing files.
- The OBO child is Blueprint-based; its isolated state correctly reports that registration is owned
      by `a365 setup all` and there is no separate package to publish.
- At this M2 checkpoint, only backend observability changed, so package content and version remained
      unchanged.
- Read-only tenant audit confirmed OBO inherited `OtelWrite` and relevant service-plan readiness,
      but DLP policy scope, audit ingestion, and IRM policy state require authenticated Purview and
      Exchange compliance sessions before they can be proven.

### 2026-08-10 - Offline quality gate

- Debug solution build passed with no errors.
- Full solution tests: 104 passed, 0 failed.
- Tools self-tests: 114 passed, 0 failed.
- Release local CI: 10 passed, 0 warnings, 0 failed, including all five health endpoints.
- Local CI and categorized Purview tests now use isolated temporary artifacts, so a running
      developer host cannot lock validation outputs.
- VS Code reports no diagnostics in the touched host and test projects.

### 2026-08-10 - Azure deployment plan prepared

- Created `.azure/deployment-plan.md` for the existing standalone Bicep workflow.
- Confirmed the default subscription and Korea Central target, existing five-app/one-environment
      footprint, and management-group policy constraints.
- Environment usage is 1.5 of 500 consumption cores; rollout peak is bounded at 2.0 cores.
- ACR uses 239,814,546 bytes of 43,980,465,111,040 bytes maximum capacity.
- Reconfirmed rollback revision `0000019` and immutable image digest.
- Local Docker daemon is unavailable; the approved workflow will use the existing Release health
      gate and a bounded ACR build.
- Plan status remains Planning. No candidate image, what-if operation, deployment, or tenant
      mutation was performed; explicit plan approval is the next gate.

### 2026-08-10 - Azure plan approved

- The user explicitly approved `.azure/deployment-plan.md`.
- Approval authorizes candidate ACR image creation and read-only Azure validation/what-if.
- Production Bicep deployment, Purview/IRM mutation, package publication, and consent changes remain
      unapproved and separately gated.

### 2026-08-10 - Candidate image and ACR drift

- Published a minimal 20,287,977-byte host context with no secret-like config, generated Agent 365
      state, or user files.
- ACR build succeeded for `m2-observability-20260810-01`; immutable digest is
      `sha256:6da173056b4c08807d8405d9e89a89f5441cdd15eba4977df325b7c2beb95ebd`.
- Candidate storage delta is 6,787,649 bytes, below the approved 1 GiB bound.
- Azure Resource Changes revealed a separate CLI operation upgraded ACR Basic to Premium four
      minutes before the candidate build. Bicep was reconciled to preserve the live SKU and prevent an
      unapproved downgrade; deployment approval must acknowledge the ongoing Premium cost profile.
- No Container App revision or production traffic changed.

### 2026-08-10 - Ready for Azure validation

- Bicep compiled after Premium ACR reconciliation.
- Release local CI passed 10/10 again after infrastructure source changed.
- Deployment plan status advanced to Ready for Validation.
- Production rollout remains unapproved; validation and what-if are the only next operations.

### 2026-08-10 - Host-only what-if boundary

- Full-stack structured what-if showed no literal creates/deletes but 18 resource modifications due
      API/default drift, so it was rejected under the approved change boundary.
- Added a group-scoped wrapper that references all dependencies as existing and deploys only the
      current host module.
- Official core validation and Bicep linting pass for the wrapper.
- Structured what-if contains one host modification and zero non-host material operations.
- Semantic comparison proves the only intended changes are the candidate image plus two
      observability logging variables; existing dependency values, managed identity, registry,
      CPU/memory, replicas, and ingress are preserved.
- Static RBAC verification passed: the host-only wrapper changes no roles, host AcrPull and OBO
      child Foundry access are least-privilege and resource-scoped, and the host UAMI has no unnecessary
      Foundry or Purview data role.

### 2026-08-10 - Deployed observability and portal activity

- Revision `ca-agent-seoultour-dev-kc-ae23--0000020` is healthy on the M2 image with one replica and
      100% traffic.
- Live `ENABLE_A365_OBSERVABILITY_EXPORTER=true`; production selects `ExportTarget.Agent365` and
      explicitly uses the S2S exporter endpoint.
- Active logs contain accepted Agent 365 exports to OBO child `a27ae7df-...` with HTTP 200 and zero
      no-token, skipped-export, or missing-identity-group failures.
- Microsoft 365 admin center maps `Seoul Tourist Assistant (OBO)` to Entra Agent Identity
      `a27ae7df-...`; its Activity view shows one active user, two successful sessions, zero exceptions,
      two total sessions, and last activity on August 10.
- The `Seoul Tourist Agent` template/Blueprint roll-up shows one active user and one indexed session
      in the registry. `Seoul Tourist OBO` is the Teams/Bot channel app (`f433...`), not the runtime
      Agent Identity, so its 0/0 row is not an exporter failure.

### 2026-08-10 - Purview and Direct Line evidence

- Purview Activity Explorer contains Agent 365 AI Interaction events for Entra Agent Identity
      `a27ae7df-...` and the authenticated user.
- Teams produced a high-severity incident: policy `a365-custom-obo-agent` matched the governed Teams
      conversation with two alerts. This is an actual DLP rule match, not only SIT classification.
- Direct Line reuses stable user `dl_seoul_tourist_cli`; sign-in is cached and not required for each
      message.
- One fresh Direct Line SIT test completed without login. Purview classification/content activity
      and Agent 365 export succeeded, no model endpoint was called, and no synthetic values appeared in
      logs.
- A sustained Direct Line campaign completed 46 of 120 records before cancellation, with 46 replies,
      no repeated sign-in, no timeout, and no command error.
- Direct Line classification alone does not produce a DLP rule-match event under the current tenant
      policy. Existing `a365-custom-obo-agent` covers Teams and other Microsoft 365 locations;
      `a365-custom-obo-agent-copilot` covers Copilot. Neither policy has an Enterprise application
      enforcement plane/location.

### 2026-08-10 - Enterprise AI DLP policy dry run pending approval

- Proposed policy: `a365-custom-obo-agent-direct`.
- Scope: `EnforcementPlanes=Application`, Enterprise application location `SeoulTourist Blueprint`
      (`bb09cd36-...`), all users interacting with this application, mode Enable.
- Proposed High/Enforce rules and `UploadText=Block` action:
      - `a365-custom-obo-agent-direct-card-block-high`
      - `a365-custom-obo-agent-direct-passport-block-high`
      - `a365-custom-obo-agent-direct-rrn-block-high`
- Conditions use Production SITs for Credit Card Number, built-in/custom South Korean passport, and
      built-in/custom South Korean resident-registration number.
- Name collision check passed; no existing policy or rule will be modified.
- Rollback is removal of only the three new rules followed by the one new policy.
- Security & Compliance PowerShell documents that `-WhatIf` is nonfunctional. The object-level dry
      run was presented, but the approval prompt returned user unavailable. No policy mutation occurred;
      explicit post-dry-run approval is required before creation.

### 2026-08-10 - Enterprise AI DLP policy created

- The user explicitly approved the reviewed policy and three blocking rules after the dry run.
- Created `a365-custom-obo-agent-direct` with mode Enable, `EnforcementPlanes=Application`,
      application location `SeoulTourist Blueprint` (`bb09cd36-...`), and Tenant/All inclusion.
- Created three enabled Enforce/High rules using `UploadText=Block`:
      - `a365-custom-obo-agent-direct-card-block-high`
      - `a365-custom-obo-agent-direct-passport-block-high`
      - `a365-custom-obo-agent-direct-rrn-block-high`
- Read-back verified exact Production SIT IDs for card, built-in/custom Korean passport, and
      built-in/custom Korean resident-registration classifications.
- Existing DLP policies were not modified. Rollback remains removal of only these three rules and
      this policy.
- Initial distribution status is Pending. No post-policy validation prompt will be sent until sync
      completes.
- A later DLP portal read shows the policy On at priority 0 with `Sync in progress`; bounded Direct
      Line rule-match tests remain gated until the portal reports `Sync completed`.

### 2026-08-10 - Agent-scoped Insider Risk Management inspection

- Corrected the IRM validation surface from user policies to the **Agent Policies**, **Agents**, and
      agent **Alerts** views.
- The system `Default policy for agents` uses the `Risky Agents (preview)` template, includes all
      agents, and currently reports 8 agents in scope, 0 active alerts, 1 warning, and 1
      recommendation. It cannot be edited.
- Its triggering activities include risky prompts and agent responses containing sensitive data.
      The built-in sensitive-information trigger is 10 activities; low-volume indicator thresholds
      are 50/75/100 activities.
- Three custom Agent policies are healthy but each currently has 0 agents in scope:
      `a365-chat-app-agent-irm-policy`, `a365-chat-app-console`, and `a365-chat-app-hosted`.
- The Agents inventory contains 12 risk records overall, but an exact search for OBO runtime child
      `a27ae7df-...` returns 0 items. An exact search in agent Alerts also returns 0 items.
- Current result is therefore **not yet policy-correct no-risk proof**: the applicable all-agent
      policy exists, but the OBO child has no indexed IRM agent record, policy association, risk
      severity, or alert. Recheck only after the Enterprise application DLP policy is distributed,
      a bounded qualifying test is sent, and the documented analytics indexing window has elapsed.
- No IRM policy, scope, threshold, indicator, alert, or other tenant state was changed.

### 2026-08-10 - OBO Agent Policy dry run pending approval

- Inspected all four policies under **IRM > Policies > Agent Policies**. The three custom policies
      are healthy and configured with the `Risky Agents (preview)` template and all-agent scope;
      their dashboard count of 0 agents in scope reflects no currently triggered agents, not an
      empty configured scope.
- `a365-chat-app-agent-irm-policy` prioritizes sensitivity labels and sensitive information types.
      `a365-chat-app-console` and `a365-chat-app-hosted` prioritize sensitive information types only.
      All three score all activity and use custom trigger and indicator thresholds.
- The reviewed new-policy name is `a365-custom-obo-agent-irm`. The Risky Agents preview currently
      disables **Specific agents**, so the policy cannot be restricted to OBO runtime child
      `a27ae7df-...`; its description explicitly discloses that it applies to all agents.
- The distinct proposed behavior is priority-content-only scoring for `Credit Card Number`,
      `South Korea Passport Number`, and `South Korea Resident Registration Number`; policy
      activation is limited to risky prompts and sensitive agent responses.
- Proposed custom triggering thresholds retain the portal defaults: 10 sensitive-information
      activities per day, 5 priority-content activities per day, and activity above the agent's
      daily baseline. All five available indicators/booster signals remain selected, with Microsoft
      indicator thresholds. The final review page reports no warnings or suggestions.
- The policy would take effect immediately and may take up to 24 hours to generate alerts. Rollback
      is deletion of only `a365-custom-obo-agent-irm` after separate approval.
- The post-dry-run approval prompt returned user unavailable. The unsaved wizard was canceled and
      read-back still shows four Agent Policies; no IRM tenant mutation occurred.

### 2026-08-10 - OBO Agent Policy created manually and threshold dry run

- The user created `a365-custom-obo-agent-irm` manually. Fresh portal read-back shows five Agent
      Policies total; the new policy is Healthy with 0 recommendations, 0 agents currently in scope,
      and no alerts yet.
- The submitted policy uses `Risky Agents (preview)`, all-agent scope, all four triggering activity
      categories, all five indicators/booster signals, all-activity scoring, and custom thresholds.
- Priority content contains seven SITs: built-in South Korea driver's license, passport, resident
      registration, and credit card types, plus the tenant's KT passport, phone, and resident
      registration classifiers.
- All eight numeric triggering-event thresholds are already at the portal minimum of 1 activity per
      day. The above-baseline risk-score booster is already set to High.
- Reviewed production threshold change: lower each of the four indicator boundaries from 1/2/3 to
      the portal-enforced minimum 0/1/2. This makes the first event Low, the second Medium, and the
      third High for risky websites, risky prompts, sensitive responses, and sensitive SharePoint
      access. Scope, content, triggers, and indicators remain unchanged.
- Rollback is restoring each indicator boundary to 1/2/3. The lower thresholds intentionally
      increase production alert sensitivity and expected noise.
- The post-dry-run approval prompt returned user unavailable. The unsaved edit was canceled; the
      minimum trigger thresholds remain live, while the indicator-boundary reduction is not saved.

### 2026-08-10 - Minimum production IRM thresholds applied

- The user explicitly approved `Submit lowest IRM thresholds` and reaffirmed that the production
      update should proceed.
- The first submit attempt failed client-side with `Indicators are required` even though the review
      showed all indicators selected. No partial threshold change persisted from that attempt.
- Reopened the policy in a fresh edit session, traversed every step to hydrate the existing five
      indicator/booster selections, and submitted only the approved threshold reduction.
- Purview reported `Submitted successfully`; live metadata shows the policy was last edited at
      1:04 PM and remains Healthy with no recommendations.
- Fresh read-back verifies all eight triggering-event thresholds remain at their minimum of 1
      activity per day. Each of the four indicator boundaries now persists at the portal-enforced
      minimum 0/1/2, so the first event is Low, the second Medium, and the third High.
- Agent scope, seven prioritized SITs, four triggering activity categories, five
      indicator/booster selections, and the High above-baseline booster were unchanged.
- Purview states that matching alerts may take up to 24 hours to appear.

### 2026-08-10 - Azure validation proof recorded

- Fresh isolated Release build passed.
- Live RBAC read-back confirmed host AcrPull, OBO child Foundry OpenAI User, and no host Foundry role.
- Validation proof table now contains core validation, structured and semantic what-if, policy,
      quota, build, and role evidence.
- User's `Let's push` instruction authorizes the reviewed host-only rollout after the validation
      workflow marks the plan Validated; Purview/IRM policy mutations remain separately gated.

### 2026-08-10 - Azure validation completed

- Official Azure validation workflow authorized and recorded plan status `Validated`.
- No build, Bicep, policy, quota, what-if, identity, or RBAC validation failures remain.
- The next operation is the explicitly approved host-only deployment through `azure-deploy`.

### 2026-08-10 - Host-only rollout started

- Final structured what-if passed with exactly one existing host Deploy operation, zero creates,
  zero deletes, and zero non-host material operations.
- Deployment plan advanced to Executing under the user's explicit `Let's push` approval.

### 2026-08-10 - Host-only rollout verified

- Deployment `seoultour-m2-observability-20260810-01` succeeded with correlation
      `129cd775-b629-4eeb-9791-f525b271737c`.
- Revision `0000020` is healthy, provisioned, one replica, and receives 100% traffic.
- Health returned 200; anonymous OBO returned 401; candidate digest is unchanged.
- Microsoft 365 Copilot OBO returned a basic response and a weather-tool response with source/time.
- Both tested OBO turns exported Agent 365 traces to the OBO child endpoint with HTTP 200.
- Purview evaluations returned 200 and content-activity writes returned 201.
- Revision logs contain no tested prompt/response content, bearer token, Direct Line secret marker,
      no-token event, skipped export, or observability registration failure.
