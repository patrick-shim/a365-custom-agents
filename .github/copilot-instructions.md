# Korea Expert monorepo instructions

- Follow the naming rules in root `AGENTS.md`: every user-visible and directory-object name derives from `<Country> Tourist Agent`, with `(OBO)` and `(TEAMMATE)` channel suffixes. Never delete or recreate a Blueprint, Agent Identity, or channel application in order to rename it.
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
- M7 deployment and tenant mutations require a reviewed dry run, explicit rollback boundary, and
  explicit approval. Historical evidence is never current authorization.
- Run the owning root workflow or equivalent local validation before finishing. Review ignored and
  staged files before every commit.
