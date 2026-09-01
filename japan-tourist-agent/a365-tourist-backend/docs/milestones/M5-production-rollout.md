# M5 validated hardening rollout and live acceptance

> Historical M5 execution record. The canonical backend rollout succeeded on 2026-08-16. M5 remains
> blocked on external M365 channel acceptance and the deferred synthetic-content, cross-channel MCP,
> content-free Agent 365 observability, and rollback acceptance checks recorded in the deployment
> plan. M7 subsequently owned Seoul cross-channel alignment; it is now historical. Active M8 owns any
> fresh Japan Expert deployment, package, consent, policy, and live-acceptance work under its reviewed
> dry-run, rollback, and explicit-approval gates; this historical M5 record grants no authority.

M5 was explicitly activated on 2026-08-11 with `Start milestone M5`. M4 remains reserved and
untouched. This milestone deployed the validated M3 hardening; it did not add features, restructure
repositories, or mutate Agent 365/Purview governance.

## Historical required workflow

1. Archive the deployed M2 plan and create a new `.azure/deployment-plan.md` for M5.
2. Build immutable host and changed MCP images from the validated source.
3. Run the complete Azure validation workflow. Only that workflow may mark the plan `Validated`.
4. Present structured what-if, semantic delta, image digests, rollback targets, and cost/scale impact.
5. Execute deployment only within the reviewed change boundary.
6. Verify revisions, traffic, health, RBAC, OBO, AI Teammate, Direct Line, MCP tools, Purview, and
   Agent 365 observability.
7. Record sanitized evidence and leave M2's IRM indexing checklist intact for resumption.

## Intended change boundary

- Existing shared agent-host Container App: immutable M3 image and no identity/config drift except
  settings required by the reviewed source.
- Existing attractions, weather, accommodation, and currency MCP Container Apps: immutable images
  only where source changed.
- No new Azure resources, no deletes, no Blueprint/child identity changes, no unreviewed package
  publication, no consent changes, no policy changes, and no M4 work. The separately authorized
  frontend-owned AI Teammate version `1.1.5` publication recorded below is a historical exception
  outside the five-app backend change boundary.

## Current status

- The user explicitly authorized the full live deployment on 2026-08-16 after M6 extracted the
  canonical backend.
- Deployment `seoultour-m5-backend-20260816-01` succeeded after fresh backend-specific validation.
- The host and four MCP revisions are healthy at the intended traffic. Remaining M5 closure work is
  the externally blocked M365 OBO and AI Teammate acceptance plus the deferred synthetic-content,
  cross-channel MCP, content-free Agent 365 observability, and rollback acceptance checks listed in
  the deployment plan.
- The AI Teammate version `1.1.5` publication recorded below was a separately user-authorized,
  frontend-owned historical exception. It did not change the five-app backend deployment boundary and
  does not authorize future package operations; active M8 requires a fresh dry run and approval.

## Checkpoint log

### 2026-08-11 - Activation

- M5 became the sole active current milestone after the exact activation phrase.
- M3 was blocked with its unfinished checklist preserved; M2 remains blocked only on IRM indexing.
- No M4 work, image build, deployment, publication, consent, policy, or tenant mutation occurred.

### 2026-08-11 - Plan prepared; Azure authentication blocked

- Archived the completed M2 plan and created an approved M5 plan for one host plus four MCP image
  updates with no creates, deletes, RBAC, identity, package, consent, policy, or M4 changes.
- Added and compiled the existing-resource wrapper now tracked as
  [`infra/live-backend-container-apps-update.bicep`](../../infra/live-backend-container-apps-update.bicep)
  and its typed parameter file. The wrapper references all dependencies as existing and deploys only
  the five Container App modules.
- Resource Graph refreshed the live revisions, images, identities, environment, and non-secret
  application IDs. Generic Azure MCP commands used a different principal without subscription
  read access and were not used as evidence.
- Azure CLI is configured for the correct subscription and tenant, but its management token expired
  and `az login` required browser account selection. The confirmation prompt returned user
  unavailable, so the waiting login was terminated safely.
- No ACR build, Azure validation, what-if, deployment, publication, consent, policy, or tenant
  mutation occurred. Resume by authenticating Azure CLI, then refresh capacity/RBAC/policy and
  rollback digests before any candidate image build.

### 2026-08-11 - Paused after Azure login

- The user completed Azure CLI authentication. Read-back confirmed the expected subscription,
  tenant, and deployment account.
- The user paused M5 for later resumption. No refreshed capacity/RBAC/policy reads, candidate image
  build, Azure validation, what-if, deployment, publication, consent, policy, identity, or M4
  mutation followed the login.
- Resume from the ordered checkpoint in repository memory: refresh capacity/RBAC/policy and all
  five rollback digests before any ACR build.

### 2026-08-12 - Validated deployment verified

- Built five immutable `m5-hardening-20260811-01` images and recorded their platform-specific
  digests in `.azure/deployment-plan.md`.
- Completed the official Azure validation workflow. ARM validation and structured what-if showed
  exactly five existing Container App modifications, zero creates, and zero deletes.
- Deployment `seoultour-m5-hardening-20260811-01` succeeded. The host and four MCP apps run healthy,
  active M5 revisions at 100% traffic with the validated candidate digests.
- Verified legacy health and liveness as healthy, readiness as intentionally degraded, and one
  direct `AcrPull` assignment for each app identity.
- Regenerated and validated `teams/appPackage/build/appPackage.obo.zip` as Teams/OBO version
  `1.0.1` after Developer Portal rejected the unchanged `1.0.0` version. Its SHA-256 is
  `9EA574607BC47634741146114DF3D46D911A96BB8EF11EACC6CA79E1FDF1DECF`; all ZIP entries exactly
  match the current rendered manifest and icons. Do not use the stale `appPackage.dev.zip`. The AI
  Teammate package remains separately intact at `.a365/ai-teammate/manifest/manifest.zip`; no
  package was published.
- No consent, policy, RBAC, identity, Blueprint, child-agent, Purview/IRM, or M4 mutation occurred.
  Bounded live channel and governance acceptance remains before M5 closure.

### 2026-08-16 - Canonical backend rollout and frontend acceptance

- Rebuilt the extracted canonical backend, passed its 127 Release tests, and built five immutable
  Linux/AMD64 images from the backend source.
- Fresh Bicep validation and structured what-if against the existing resource group showed five
  Container App modifications, 15 ignored existing dependencies, and no creates or deletes.
- Deployment `seoultour-m5-backend-20260816-01` succeeded. The shared host and four MCP apps run
  healthy candidate-digest revisions at 100% latest-revision traffic. Host health and liveness are
  healthy; readiness remains intentionally degraded because storage is process-local.
- Both anonymous protected routes return 401. The OBO Direct Line client completed an authenticated,
  non-sensitive weather/tool turn through `/api/messages/obo`.
- The `SeoulTourist Blueprint` AI Teammate package was generated by the supported CLI at version
  1.1.5, uploaded through the Microsoft 365 Admin Center, published, and activated for all users.
- M365 Copilot OBO chat currently remains in the platform processing state without a delivered
  response, despite the healthy host revision and no matching sanitized host auth, Purview, delivery,
  or unhandled-error signal. AI Teammate instance creation remains disabled because the tenant
  reports no available Agent 365 licenses, even after the template license assignment was updated.
  These are outstanding channel/tenant acceptance blockers, not a reason to roll back the healthy
  five-app backend revision.
