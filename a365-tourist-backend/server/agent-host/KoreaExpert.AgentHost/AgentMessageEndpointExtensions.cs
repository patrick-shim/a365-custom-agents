using Microsoft.Agents.Builder;
using Microsoft.Agents.Hosting.AspNetCore;

namespace KoreaExpert.AgentHost;

public static class AgentMessageEndpointExtensions
{
    public static RouteHandlerBuilder MapAgentMessageEndpoint(
        this IEndpointRouteBuilder endpoints,
        string pattern,
        AgentFrontendMode mode) =>
        endpoints.MapPost(
            pattern,
            async (
                HttpRequest request,
                HttpResponse response,
                IAgentHttpAdapter adapter,
                IAgent agent,
                AgentTurnFrontendContext frontendContext,
                CancellationToken cancellationToken) =>
            {
                using var frontendScope = frontendContext.Push(mode);
                await adapter.ProcessAsync(request, response, agent, cancellationToken);
            });
}
