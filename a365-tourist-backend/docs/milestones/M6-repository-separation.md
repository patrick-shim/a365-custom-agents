# M6 Repository Separation

> Historical M6 closeout. At M6 closeout, the OBO package still grouped Teams and Direct Line assets.
> M7 later separated Direct Line into `a365-tourist-agent-obo-directline`; this document preserves
> the pre-split extraction evidence and is not current operating guidance.

## Goal

M6 created `a365-tourist-backend` as the canonical shared runtime, seeded only from the latest OBO
implementation. It kept the then-bundled OBO and AI Teammate package ownership separate without
touching tenant state.

## Rules

- Preserve the shared host and its `/api/messages` and `/api/messages/obo` routes.
- Do not copy, move, inspect, or commit Agent 365 CLI state, generated packages, identities, secrets,
  tenant IDs, deployment evidence, or `.azure` state.
- Do not merge backend code from `a365-tourist-agent-teammate`.
- Do not delete either transition frontend until its package and acceptance checks pass against the
  backend contract.

## Acceptance Checklist

- Backend source contains the OBO runtime, integrations, MCP services, infrastructure, tests, Docker
  files, and backend-only validation tooling.
- Direct Line, Teams packages, Toolkit, Agent 365 CLI dependencies, and generated state are absent
  from backend source and CI.
- `contracts/frontend-backend-contract.json` validates and declares both protected routes, health
  endpoints, and the four protected MCP services.
- Backend solution tests, tool self-tests, aggregate offline validation, and Local CI pass.
- At M6 closeout, the then-bundled OBO and AI Teammate transition frontends pinned the same non-secret
  contract version.
- The next M5 deployment test has a reviewed backend-only inventory, acceptance matrix, rollback
  requirements, and explicit activation gate in
  [M6-backend-deployment-test-handoff.md](M6-backend-deployment-test-handoff.md).
