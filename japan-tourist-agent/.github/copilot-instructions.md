# Japan Tourist Expert monorepo instructions

- **Preserve the enforced invariants.** The agent identity is never the host managed identity;
  Foundry, Graph, and MCP tokens are acquired per resource, per turn, bound to the child identity;
  Purview evaluation is fail-closed; Prompt Shields injection screening is fail-closed across both
  the user prompt and tool results; MCP services stay on internal ingress behind a delegated
  `Mcp.Invoke` token; deployments reference image digests, never mutable tags. See root `AGENTS.md`
  → "Verified baseline". Reproduce `Invoke-LocalCi.ps1 -Strict` and `Test-Repository.ps1 -Strict`
  before and after any change.
- **When working on the upstream copy**, treat it as change-controlled: no file, dependency, pin, or
  Azure resource changes without an explicit, file-scoped instruction from the repository owner.
  Reading, building, testing, and running `a365-tourist-backend/tools/` validation are always
  allowed. A change being obviously correct or an improvement is not authorization.
- Follow the naming rules in root `AGENTS.md`: every user-visible and directory-object name derives from `<Country> Tourist Expert`, with `(OBO)` and `(Teammate)` channel suffixes. The Teams schema caps `name.short` at 30 characters, so the AI Teammate package uses `(Team)` there and keeps `(Teammate)` in `name.full`. Never delete or recreate a Blueprint, Agent Identity, or channel application in order to rename it.
- Read root `AGENTS.md`, then the owning child `AGENTS.md` and milestone manifest before work.
- `a365-tourist-backend` is the sole shared runtime, MCP, infrastructure, tests, tools, Docker, and
  Azure deployment authority.
- OBO Teams and Direct Line use `/api/messages/obo`; AI Teammate uses `/api/messages`. Preserve their
  distinct audiences, the shared Blueprint, and the two-child identity model.
- Never copy backend code into a frontend or generated frontend state into the backend.
- Never inspect, edit, stage, commit, or delete `.a365`, `.azure`, `.config`, tenant environment
  files, generated manifests/ZIPs, keys, secrets, or tenant-bound evidence.
- `a365-tourist-agent-obo-teammate/` is a separate excluded project. Do not inspect or change it
  without specific human approval.
- M8 deployment and tenant mutations require a reviewed dry run, explicit rollback boundary, and
  explicit approval. Historical evidence is never current authorization.
- Run the owning root workflow or equivalent local validation before finishing. Review ignored and
  staged files before every commit.
