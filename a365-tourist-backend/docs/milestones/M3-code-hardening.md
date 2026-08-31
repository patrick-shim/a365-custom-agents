# M3 runtime resilience and diagnostics hardening

> Historical M3 hardening record. M3 was explicitly activated on 2026-08-10 with `Start milestone
> M3`. M3 remains blocked while M7 owns end-to-end production alignment and live cross-channel
> acceptance. Its remaining checklist is preserved for later resumption. Production deployment and
> tenant mutation remain outside M3.

## Objectives

1. Fail predictably at every external and asynchronous boundary.
2. Preserve cancellation and authorization semantics.
3. Give users actionable errors without leaking internal or sensitive details.
4. Make one failed turn diagnosable from correlated, structured, non-sensitive evidence.
5. Turn known edge cases into deterministic regression tests.

## Work plan

### Failure inventory

- [x] Inventory exception boundaries in agent orchestration, host transport, identity/OBO exchange,
      Purview, internal MCP, provider integrations, Direct Line, storage, and validation scripts.
- [x] Map each failure class to owner, retryability, channel response, log level, event ID, metric,
      and test location.
- [x] Identify catch-all handlers, lost exception context, duplicated messages, and cancellation
      paths currently logged as errors.

### Exception and cancellation contracts

- [ ] Introduce narrow domain exceptions only where they improve stable classification.
- [ ] Preserve `OperationCanceledException` and request-abort behavior through every async layer.
- [x] Distinguish timeout, throttling, authentication, authorization, policy block, malformed
      response, dependency unavailability, and internal defect.
- [x] Apply bounded retry with jitter only to proven idempotent operations and honor server retry
      guidance.
- [x] Ensure partial streaming failures do not persist incomplete or policy-unsafe session state.

### Edge-case matrix

- [ ] Empty, oversized, malformed, duplicate, delayed, and unsupported activities.
- [ ] Missing tenant/user/agent identity, stale OAuth context, expired tokens, and invalid claims.
- [ ] Provider timeout, throttling, non-JSON response, schema drift, empty result, and partial result.
- [ ] MCP discovery failure, tool timeout, invalid arguments, blocked arguments/results, and
      disconnect during execution.
- [ ] Purview allow, audit, warn, block, service failure, malformed decision, and cancellation.
- [ ] Direct Line token refresh, watermark replay, duplicate reply, OAuth timeout, and conversation
      expiry.
- [ ] Storage corruption, serialization incompatibility, concurrent turn, and save failure.

### User-facing errors

- [x] Define stable error codes and concise messages per operation and channel.
- [x] Separate user recovery guidance from administrator diagnostics.
- [x] Preserve policy-specific messages for block versus evaluation failure.
- [x] Verify no stack trace, resource identifier, token, claim, endpoint secret, or matched value can
      reach a channel response.

### Structured diagnostics

- [x] Allocate stable event-ID ranges by component and document them.
- [ ] Include trace ID, correlation ID, conversation hash, frontend mode, dependency, operation,
      attempt, duration, and sanitized outcome where applicable.
- [ ] Correlate Agent 365, Application Insights, Purview, MCP, and provider spans without recording
      prompt or tool content.
- [ ] Define production log levels and sampling so expected cancellations and policy blocks do not
      become noisy failures.
- [ ] Add startup diagnostics that report configuration presence and feature state without values.

### Health and troubleshooting

- [x] Separate liveness from readiness and define which dependencies are critical.
- [x] Add bounded readiness probes only where they cannot mutate state or amplify outages.
- [x] Create symptom-to-evidence troubleshooting decision trees.
- [x] Document safe diagnostic commands, expected events, rollback boundaries, and escalation data.

### Verification

- [ ] Add deterministic fault injection at HTTP, token, Purview, MCP, storage, and streaming seams.
- [ ] Add concurrency, cancellation, retry, and malformed-payload tests.
- [x] Run analyzers, full solution tests, local CI, and tools self-tests with no new warnings.
- [x] Review logs and test output for accidental sensitive-data disclosure.

## Definition of done

M3 is complete only when every supported failure class has a tested contract, every user-visible
error is safe and actionable, cancellation remains cancellation, structured evidence can diagnose a
failed turn end to end, and all repository validation passes.

## Checkpoint log

### 2026-08-10 - Planning

- Added M3 as a planned, non-deployment milestone.
- No runtime code, package, deployment, or tenant state changed.

### 2026-08-10 - Activation

- The user provided the exact activation phrase `Start milestone M3` and explicitly directed that
      M2 be blocked only on external IRM indexing with its checklist preserved.
- M3 is now the single active current milestone. M2 governance validation will resume after its
      external 24-72 hour indexing window.
- The transition changed documentation and milestone state only; it performed no deployment or
      tenant mutation.

### 2026-08-11 - First hardening wave

- Added request-cancellation catch filters at identity, MCP discovery, and observability boundaries;
      the non-cancellable Agent 365 user-token helper is now awaited with the request token.
- Added stable host and Direct Line failure kinds/codes, safe user recovery messages, and sanitized
      exception-type diagnostics. Malformed bearer tokens now fail authentication instead of
      escaping as HTTP 500.
- Direct Line now requires HTTPS except loopback development, trusts only Microsoft Bot OAuth
      origins, classifies dependency timeouts separately from caller cancellation, and never emits
      provider response bodies.
- Added a sanitized host turn scope with trace ID, frontend mode, and hashed conversation/activity
      identifiers. Provider clients with credential-bearing query strings suppress framework URI
      logging and require HTTPS outside loopback development.
- Added bounded in-process duplicate suppression and per-frontend/per-conversation serialization.
      This protects the current single-replica `MemoryStorage` flow but is not a durable scale-out
      idempotency mechanism.
- Preserved `/api/health` and added passive `/api/health/live` and `/api/health/ready` endpoints.
      Added diagnostics, failure-matrix, troubleshooting, contribution, security, and public-release
      documentation. The Direct Line helper now restores/removes its process secret in `finally`.
- Fixed the repository secret scanner so valid JSON objects with secret-like property names are not
      treated as credential values; structured JSON string scanning remains enforced.
- Validation: Release build passed; 132 solution tests passed; 114 tools self-tests passed; Local CI
      passed 10/10 including five health checks and process cleanup; repository validation passed
      27/27; VS Code reported no diagnostics.
- Added status-aware provider fallback, schema/provenance validation, 1 MiB response caps under
      total `HttpClient` timeouts, sanitized MCP error mapping, and oversized prompt admission.
- Validation wrappers now convert unexpected local failures to sanitized JSON and fail closed on an
      empty result set. Local CI verifies legacy health, liveness, and readiness from one host
      process.
- Final validation: Release build passed; 145 solution tests passed; 115 tools self-tests passed;
      Local CI passed 12/12 with readiness intentionally `degraded` for process-local storage;
      process cleanup passed; VS Code reported no diagnostics.
- Remaining M3 gates are durable production storage and cross-replica idempotency, deeper injected
      session serialization/save/delivery failures, passive critical-dependency readiness state,
      and public-release Git provenance/license/SBOM decisions. No deployment or tenant mutation
      occurred.

### 2026-08-11 - Deployment intent deferred to M5

- The user approved deployment and live testing of the validated hardening wave.
- M3 still explicitly prohibits production deployment, and the existing Azure deployment plan is
      the completed M2 plan for revision `0000020`, not a validated M3 rollout plan.
- Added planned M5 with exact activation phrase `Start milestone M5`. M5 owns immutable image
      preparation, Azure validation, deployment, and live acceptance. M4 remains untouched.
- No image build, Azure deployment, publication, consent, policy, or tenant mutation occurred.

### 2026-08-11 - Blocked for M5 rollout

- The user provided the exact phrase `Start milestone M5`.
- M3 is blocked with its remaining durable-storage, fault-injection, dependency-readiness, and
      public-release gates preserved. M5 is the sole active milestone and owns rollout/live testing.
- No image build, deployment, publication, consent, policy, or tenant mutation occurred in this
      transition.
