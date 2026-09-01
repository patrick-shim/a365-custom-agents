# Japan Tourist Assistant monorepo instructions

- **This repository is LOCKED (2026-08-31).** It is frozen at a verified-good baseline. Do not edit,
  rename, move, refactor, reformat, or tidy any file; do not add, remove, or upgrade packages; do not
  change version pins, `global.json`, `infra/`, `Dockerfile*`, or workflows. Reading, building,
  testing, and running `a365-tourist-backend/tools/` validation are always allowed. A change being
  obviously correct or an improvement is not authorization. Unlock only on an explicit, file-scoped
  instruction from the repository owner. See root `AGENTS.md` → "Change lock".
- Follow the naming rules in root `AGENTS.md`: every user-visible and directory-object name derives from `<Country> Tourist Assistant`, with `(OBO)` and `(Teammate)` channel suffixes. The Teams schema caps `name.short` at 30 characters, so the AI Teammate package uses `(Team)` there and keeps `(Teammate)` in `name.full`. Never delete or recreate a Blueprint, Agent Identity, or channel application in order to rename it.
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
