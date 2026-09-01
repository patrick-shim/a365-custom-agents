# WorkIQ status

WorkIQ is disabled in the current shared backend. `Agent365:EnableWorkIq` must remain `false` because
Agent 365 Tooling targets an MCP preview API that is incompatible with the custom MCP 2.1 client, and
its generated tools have not passed the equivalent tool-content protection boundary.

This directory intentionally contains no local MCP server or Microsoft Graph wrapper. Do not run
`a365 develop`, create `ToolingManifest.json`, or add WorkIQ tooling to this backend. Agent 365 CLI
state belongs only to the owning frontend projects.

## How the flag is enforced

The prohibition is executable, not advisory. Four independent sites hold it in place:

| Site | Mechanism |
| --- | --- |
| `KoreaExpert.AgentHost/Agent365Options.cs` | `public bool EnableWorkIq { get; init; }` — defaults to `false` |
| `KoreaExpert.AgentHost/Program.cs` | Options `.Validate(options => !options.EnableWorkIq, …)` combined with `.ValidateOnStart()` |
| `KoreaExpert.AgentHost/KoreaExpertApplication.cs` | Runtime guard `if (!_agent365Options.EnableWorkIq)` around the tooling path |
| `KoreaExpert.AgentHost.Tests/PurviewDlpMiddlewareTests.cs` | Two assertions covering tool arguments and tool results |

The startup validation message is the authoritative wording:

```text
Agent365:EnableWorkIq must remain false until Agent 365 Tooling supports MCP 2.1 and tool-content
DLP is validated.
```

Because the check runs under `.ValidateOnStart()`, setting the flag to `true` does not degrade
behavior at request time — the host refuses to start. The two unit tests assert the default
separately, so the guarantee survives a configuration-binding regression:

```csharp
Assert.IsFalse(options.EnableWorkIq, "WorkIQ must default off until tool arguments have DLP coverage.");
Assert.IsFalse(options.EnableWorkIq, "WorkIQ must default off until tool results have DLP coverage.");
```

## The bar WorkIQ tools would have to clear

The four internal MCP services route every call through `ToolContentProtector`, which wraps
`FunctionInvocationContext` and performs four ordered steps: serialize and size-check the arguments,
evaluate them, invoke the function, then serialize, size-check, and evaluate the result.
`IToolContentEvaluator.EvaluateAsync` blocks by throwing; there is no permissive path, and content
over `InternalMcp:MaximumContentCharacters` is rejected rather than truncated.

Agent Framework Purview middleware protects textual model input and output. It does **not**
automatically protect tool arguments, tool results, system instructions, binary content, logs, or
telemetry. WorkIQ-generated tools therefore inherit no protection from the model boundary; they would
need to pass the same fail-closed evaluator, with focused tests proving it, before the flag could
move.

## Reconsideration conditions

WorkIQ can be reconsidered only in a separately authorized future milestone, and only after both
conditions are proven with focused tests:

1. Agent 365 Tooling exposes an MCP surface compatible with the pinned MCP 2.1 client.
2. Generated tools are covered by the same fail-closed tool-content protection boundary as the four
   internal MCP services.

Never disable fail-closed enforcement to make an acceptance test pass. Review and minimize existing
Blueprint Graph grants before any WorkIQ work begins — inherited permissions are shared across both
child identities by design, even while WorkIQ is disabled in code.
