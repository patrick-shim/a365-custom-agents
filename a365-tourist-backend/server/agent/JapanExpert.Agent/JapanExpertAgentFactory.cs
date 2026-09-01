using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

namespace JapanExpert.Agent;

public static class JapanExpertAgentFactory
{
    public static AIAgent Create(
        IChatClient chatClient,
        IEnumerable<AITool> tools,
        string? agentId = null)
    {
        ArgumentNullException.ThrowIfNull(chatClient);
        ArgumentNullException.ThrowIfNull(tools);

        var options = new ChatClientAgentOptions
        {
            Name = "Japan Tourist Assistant",
            ChatOptions = new ChatOptions
            {
                Instructions = JapanExpertAgentInstructions.Create(),
                Tools = [.. tools]
            }
        };

        if (!string.IsNullOrWhiteSpace(agentId))
        {
            options.Id = agentId;
        }

        return new ChatClientAgent(chatClient, options);
    }
}
