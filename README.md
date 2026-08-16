# Seoul Tourist Agent workspace

This monorepo is the source boundary for one shared Seoul Tourist backend and three channel-only
frontends. The backend is deployed once; each frontend owns only its channel contract, package or
client, and acceptance workflow.

## Projects and routes

| Project | Owner boundary | Backend route |
| --- | --- | --- |
| [`a365-tourist-backend`](a365-tourist-backend) | Shared runtime, MCP, infrastructure, tests, tools, and deployment | `/api/messages`, `/api/messages/obo` |
| [`a365-tourist-agent-obo`](a365-tourist-agent-obo) | OBO Teams package source and protected operational state | `/api/messages/obo` |
| [`a365-tourist-agent-obo-directline`](a365-tourist-agent-obo-directline) | Direct Line console client, focused tests, and synthetic SIT list | `/api/messages/obo` |
| [`a365-tourist-agent-teammate`](a365-tourist-agent-teammate) | AI Teammate package boundary and protected CLI state | `/api/messages` |

`a365-tourist-agent-obo-teammate/`, if present, is a separate excluded project. Do not inspect,
modify, stage, or commit it without specific human approval.

## Current M7 deployment checkpoint

- Shared host: revision `0000028`, healthy and receiving 100% traffic.
- Host image: `sha256:161f9b8fa401012d5d87ccef1c215c23515709850496f585e0aca66f93b1f771`.
- Verified rollback: revision `0000027`, image
  `sha256:9dd1e4d22f824504c375cd112da36b8b25ace68aa4b8e23af12dd0de2a09004c`.
- Attractions, weather, accommodation, and currency MCP services: revision `0000005` on their
  approved immutable digests.
- Direct Line: three isolated synthetic passport, South Korean resident-registration, and credit
  card cases were blocked before model access on revision `0000028`; model requests remained zero in
  the covered interval.

This is a dated operational checkpoint, not deployment authority. The detailed sanitized record is
in [the backend M7 runbook](a365-tourist-backend/docs/milestones/M7-end-to-end-alignment.md). OBO Teams
and AI Teammate must still have same-revision acceptance recorded before M7 is declared complete.

## Validate

Run checks from the owning project root:

```powershell
cd a365-tourist-backend
./tools/Invoke-LocalCi.ps1 -OutputFormat Json
./tools/Test-Repository.ps1 -Strict -OutputFormat Json

cd ../a365-tourist-agent-obo-directline
dotnet test SeoulTourist.OBO.DirectLine.slnx --configuration Release
```

The OBO Teams workflow validates its committed contract and source manifest. The AI Teammate workflow
validates its committed contract and rejects generated Agent 365 state in a clean checkout. Live
channel, package, tenant, and Purview acceptance is separate and requires the active M7 authorization,
a reviewed dry run and rollback boundary, and explicit approval for mutations.

## Git safety

The root repository intentionally excludes build output, local keys, `.env` files, `.azure`, `.a365`,
CLI-owned configuration, generated manifests/ZIPs, and tenant-bound evidence. These files may exist
locally and must be preserved, but they are not source and must never be committed. Review ignored
paths and the staged file list before each commit:

```powershell
git status --short --ignored
git diff --cached --name-only
```

See [AGENTS.md](AGENTS.md) and each child `AGENTS.md` before changing code, deployment state, or
channel assets.
