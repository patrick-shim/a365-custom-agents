# M7 Frontend Backend Cleanup

> Historical M7 cleanup record. The ownership boundaries it established remain current, while active
> M8 owns Japan Tourist Assistant source, deployment, and registration work.

## Authority

`a365-tourist-backend` is the sole source and deployment owner for the shared host, agent,
integrations, MCP services, infrastructure, Docker assets, backend tests, validation tools, and Azure
rollout artifacts.

## OBO Teams Retained Surface

- `teams/` OBO Custom Engine Agent package source.
- `backend-contract.lock.json` and minimal frontend metadata as committed non-secret source.
- `.a365/obo`, `.config/`, tenant environment files, and generated package output as protected local
  operational state excluded from Git.
- `.a365/ai-teammate` protected historical output, which is not an OBO asset or an AI Teammate
  publication source and must not be hand-edited, copied, or deleted.

## OBO Direct Line Retained Surface

- `a365-tourist-agent-obo-directline/direct/` including its focused test project and synthetic prompt
  list.
- `backend-contract.lock.json`, .NET solution/build metadata, and minimal frontend metadata.
- No Teams package, Agent 365 CLI state, generated manifest, or deployment asset.

## AI Teammate Retained Surface

- `backend-contract.lock.json` and minimal frontend metadata as committed non-secret source.
- `a365.config.json`, `a365.generated.config.json`, `.config/`, `manifest/`, and
  `.a365-workspace-detection.local.json` as CLI-owned operational state excluded from Git.

## Removed Mirror Surface

The OBO Teams, OBO Direct Line, and AI Teammate trees must not contain `server/`, `infra/`, shared
`tests/`, `tools/`, backend Dockerfiles, backend solutions, backend package/version props, backend
deployment evidence, or backend Copilot agent instructions. The OBO Teams tree contains no Direct Line
source; the OBO Direct Line tree contains no Teams or Agent 365 operational state. The AI Teammate tree
also removes its unreferenced Teams Toolkit package and is the authoritative AI Teammate package
frontend.

No Azure resource, deployment, Blueprint, child identity, package state, consent, or policy is
changed by this local source cleanup.
