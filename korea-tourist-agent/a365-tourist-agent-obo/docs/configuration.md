# OBO Teams frontend configuration

The source package binds to `/api/messages/obo` through `backend-contract.lock.json`. The committed
pin names `TokenValidation__Audiences__OnBehalfOf` and `configured-obo-child-agent-identity`; actual
tenant identifiers remain in protected deployment and CLI-owned state.

The current package source is `teams/appPackage/manifest.json` plus its icons and
`teams/m365agents.yml`. `.a365/obo`, `.config/`, `teams/env/.env.*`, and generated package output are
local operational state. Never copy their identities, secrets, or generated values into source.
`.a365/ai-teammate` is a protected historical snapshot and never the AI Teammate publication source.

`teams/appPackage/build/` may predate the current disabled WorkIQ policy and is not deployment source.
Regenerate and validate a candidate only through the approved Teams/Agent 365 CLI workflow. Reject a
dry run that recreates the shared Blueprint, replaces the existing OBO child, or changes the exact
`/api/messages/obo` endpoint or audience outside the reviewed boundary.

Structural source CI is offline. Live channel validation and any package, registration, consent, or
tenant mutation remain separately gated under M7.
