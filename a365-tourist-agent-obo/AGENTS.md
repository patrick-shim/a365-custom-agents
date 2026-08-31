# Korea Expert OBO Teams Frontend Guide

Read `docs/milestones/milestones.json` before work. This project contains only the OBO Teams channel
boundary for the shared backend.

## Ownership

- `teams/appPackage/manifest.json`, its source icons, `teams/m365agents.yml`, and the Teams project
  file are the source package boundary.
- `backend-contract.lock.json` is a committed, non-secret source pin for `/api/messages/obo`, its OBO
  audience configuration, and the configured OBO child identity binding.
- `.a365/`, `.config/`, `teams/env/.env.*`, and `teams/appPackage/build/` are protected local or
  generated operational state. Never inspect for source recovery, hand-edit, stage, commit, or
  delete them during cleanup.
- `.a365/ai-teammate` is protected historical output, never AI Teammate publication authority.
- `../a365-tourist-agent-obo-directline` owns the Direct Line client and synthetic acceptance.
- `../a365-tourist-agent-teammate` owns the authoritative AI Teammate package boundary.
- `../a365-tourist-backend` exclusively owns runtime code, Azure resources, MCP services, provider
  integrations, tests, infrastructure, and deployment.

## Validation

The root workflow in `../.github/workflows/obo-teams-ci.yml` validates the non-secret contract pin and Teams
manifest structure. That structural check is not live evidence for endpoint registration, audience,
authentication, installed-channel state, or Purview enforcement.

M7 package generation, publication, installation, and tenant reconciliation must use the supported
Teams/Agent 365 CLI workflow after a reviewed dry run, rollback boundary, and explicit approval.
Never deploy generated historical output from `teams/appPackage/build/`.

## Active M7 status

The current backend checkpoint is revision `0000028`. OBO Teams was last documented live on revision
`0000025`, so it must be replayed and recorded against `0000028` before claiming same-revision M7
alignment. Preserve `/api/messages/obo`, `TokenValidation__Audiences__OnBehalfOf`, the existing OBO
child identity, and the shared Blueprint. Fix any shared behavior only in
`../a365-tourist-backend`; fix this project only through its source package or an approved CLI-owned
channel workflow.

Do not recreate backend directories, copy Direct Line code, or mutate routes, audiences, identities,
consent, Purview, or package registration without the milestone gate and explicit approval.
