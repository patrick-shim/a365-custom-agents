# Japan Expert OBO Teams Frontend Guide

Read `docs/milestones/milestones.json` before work. This project contains only the OBO Teams channel
boundary for the shared backend.

## Ownership

- `teams/appPackage/manifest.json`, its Japanese-flag source icons, `teams/m365agents.yml`, and
  `teams/JapanExpert.Teams.atkproj` are the source package boundary.
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

The root workflow in `../.github/workflows/obo-teams-ci.yml` validates the non-secret contract pin,
Teams manifest structure, and tracked ownership boundary. The cross-project
`../.github/workflows/contract-alignment-ci.yml` workflow compares this pin and both other frontend
pins with the canonical backend contract. Those structural checks are not live evidence for endpoint
registration, audience, authentication, installed-channel state, or Purview enforcement.

M8 package generation, publication, installation, and tenant reconciliation must use the supported
Teams/Agent 365 CLI workflow after a reviewed dry run, rollback boundary, and explicit approval.
Never deploy generated historical output from `teams/appPackage/build/`.

## Active M8 status

Rename this source package and icons to Japan Expert, preserve `/api/messages/obo`, and use only the
new OBO audience and child proposed by the clean M8 Agent 365 workflow. Existing Seoul Blueprint,
child, channel, package, generated state, and installation records are historical and must not be
used as Japan Expert authority. Fix shared behavior only in `../a365-tourist-backend`.

Do not recreate backend directories, copy Direct Line code, or mutate routes, audiences, identities,
consent, Purview, or package registration without the milestone gate and explicit approval.
