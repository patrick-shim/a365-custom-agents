# WorkIQ status

WorkIQ is disabled in the current shared backend. `Agent365:EnableWorkIq` must remain `false` because
Agent 365 Tooling targets an MCP preview API that is incompatible with the custom MCP 2.1 client, and
its generated tools have not passed the equivalent tool-content protection boundary.

This directory intentionally contains no local MCP server or Microsoft Graph wrapper. Do not run
`a365 develop`, create `ToolingManifest.json`, or add WorkIQ tooling to this backend. Agent 365 CLI
state belongs only to the owning frontend projects.

WorkIQ can be reconsidered only in a separately authorized future milestone after tooling
compatibility and generated-tool protection have been proven with focused tests.
