# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately to the repository
owner through GitHub's **Report a vulnerability** flow on the Security tab, and allow time for a
fix before any public disclosure.

## What this repository does and does not contain

This is a reference implementation. It contains no credentials, and it is designed so that a clone
of it cannot be deployed against someone else's tenant by accident.

- No secret is committed. Client secrets, tenant identifiers, subscription identifiers, object
  identifiers, and generated Agent 365 state are produced at deployment time and are excluded by
  `.gitignore`.
- Documentation uses placeholders such as `<tenant-id>` and `<mcp-api-application-id>` rather than
  real values. `tools/Test-Repository.ps1` enforces this, and the build fails if a real
  subscription, tenant, principal, mailbox, or resource identifier is committed.
- The deployment templates refuse to run outside their approved resource group, so a copied
  parameter file cannot silently target unrelated infrastructure.

## Security properties worth understanding before you deploy

- **No API keys for inference.** The agent host authenticates to Microsoft Foundry with a token
  bound to an Agent 365 child identity. There is no model key to leak or rotate.
- **The host managed identity is deliberately weak.** It holds `AcrPull` and nothing else. It has no
  Foundry, Purview, or MCP data permission. Every downstream call is authorized by an Agent 365
  identity resolved per turn, not by the infrastructure identity.
- **Prompt and response content is evaluated fail-closed.** If Microsoft Purview cannot be reached,
  the turn is rejected rather than allowed through unevaluated.
- **Prompt injection is screened fail-closed by Azure AI Content Safety Prompt Shields.** Two
  surfaces are checked: the message the user typed (direct jailbreak) and the text a tool returned
  (indirect injection planted in third-party data). Purview protects prompts and model responses,
  not tool results, so this guard closes that gap. A block, a transport failure, a non-success
  status, or an unparsable response all reject the turn. Prompt Shields authenticates with the same
  per-turn child Agent Identity token, so no Content Safety key exists anywhere in the deployment.
  It is a standalone text classifier that never sees the model, so it keeps working unchanged if
  inference moves to a provider outside Azure. The guard is on by default; see
  `a365-tourist-backend/docs/configuration.md` for the settings and the role it needs.
- **MCP services are internal-ingress only** and validate a delegated `Mcp.Invoke` token. They are
  not reachable from the public internet.
- **WorkIQ tool loading is disabled by an explicit gate.** Purview chat middleware protects textual
  prompts and responses, not MCP tool arguments and results, so generated tools stay off until
  tool-content protection is equivalent.

## Reporting scope

Findings in the deployment templates, the identity and token exchange path, the Purview enforcement
path, or the MCP authorization boundary are in scope. Findings in the third-party public data
sources this sample calls are not.
