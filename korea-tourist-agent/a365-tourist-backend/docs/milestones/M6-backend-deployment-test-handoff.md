# M6 Backend Deployment-Test Handoff

> Historical M6 handoff. The M5 rollout described here completed on 2026-08-16. Active M7 now owns
> fresh deployment and tenant-operation work under its reviewed dry-run, rollback, and
> explicit-approval gates; this handoff remains evidence only.

## Historical State at M6 Closeout

`a365-tourist-backend` is locally validated and is the only source for a future shared-backend
deployment. M6 permits no Azure, Entra, Agent 365, Microsoft 365, or Purview read or mutation.
It must not be used to create a deployment plan, build images in ACR, deploy revisions, or run live
channel tests.

The historical OBO deployment plan and M5 wrapper are evidence only. They must not be copied into
this backend or treated as validation for the extracted source.

## Historical Required Authorization

Before the completed M5 rollout, a user had to explicitly activate M5 with the exact phrase:

`Start milestone M5`

M5 resumption requires a separate reviewed milestone change. It must not be combined with tenant
mutation. After activation, use the Azure preparation, validation, and deployment workflows in this
order:

1. Create a fresh backend deployment plan from the current backend source.
2. Complete Azure validation and let that workflow set the plan status to `Validated`.
3. Review the plan, structured what-if, candidate digests, rollback digests, and test boundary.
4. Obtain explicit approval for the resulting deployment mutation.
5. Execute deployment through the approved deployment workflow.

## Backend Deployment Boundary

The candidate deployment may update only these five existing Container Apps:

- Shared agent host built from `Dockerfile`.
- Attractions MCP built from the `attractions` `Dockerfile.mcp` target.
- Weather MCP built from the `weather` `Dockerfile.mcp` target.
- Accommodation MCP built from the `accommodation` `Dockerfile.mcp` target.
- Currency MCP built from the `currency` `Dockerfile.mcp` target.

The plan must retain both host routes, `/api/messages` and `/api/messages/obo`, the shared Blueprint,
both child-identity bindings, existing ingress, scale, resource identities, RBAC, and protected
configuration. It must not create or delete resources, change identity or consent, publish packages,
or mutate Purview or Insider Risk Management policy.

## Fresh Validation Requirements

Validate the current selected subscription and target resource group before any image build. Record
only sanitized evidence for:

- Current revision, traffic, health, configuration, and immutable rollback digest for all five apps.
- Container Apps environment capacity, ACR capacity, policy constraints, and permitted region.
- Existing managed identities and `AcrPull`/Foundry role assignments.
- Current backend Bicep compilation and a fresh existing-resource-only rollout wrapper generated from
  this backend source.
- ARM validation and structured what-if showing exactly five `Modify` operations, zero `Create`, and
  zero `Delete`, with no unrelated identity, RBAC, SKU, location, scale, ingress, secret, or route
  drift.
- Immutable candidate image digests for all five images and their registry provenance.

## Acceptance Matrix

After deployment, verify in order:

1. All five revisions are provisioned, ready, and receive intended traffic.
2. Host `/api/health` and `/api/health/live` return healthy; `/api/health/ready` returns the expected
   degraded status while process-local storage remains active.
3. Each anonymous protected route rejects requests without leaking configuration or identity details.
4. Each MCP service returns an attributed result or stable sanitized error through the deployed host.
5. OBO and AI Teammate package owners run their respective authenticated route acceptance checks
   against the same backend contract version.
6. The OBO owner runs Direct Line acceptance using its approved frontend workflow; do not bring Direct
   Line secrets or generated state into backend source or logs.
7. A synthetic non-sensitive Purview blocked case does not reach the model. Agent 365 observability
   remains content-free and carries no skipped identity group.
8. Logs, traces, deployment output, and evidence contain no prompts, responses, tool values, matched
   sensitive values, tokens, secrets, raw IDs, or tenant-bound configuration.

## Rollback

Capture five pre-deployment immutable rollback digests before changing traffic. Verify the rollback
wrapper against the same narrow existing-resource change boundary. Do not execute rollback unless the
deployment or acceptance criteria fail, and record the decision and sanitized revision evidence.

## Historical Local Prerequisite Status

Backend solution tests, backend validation, and backend Local CI are green. Docker CLI is installed,
but the local Docker Linux engine was unavailable during M6 validation; start Docker Desktop before
attempting any local container image run. This is not evidence of Azure readiness.
