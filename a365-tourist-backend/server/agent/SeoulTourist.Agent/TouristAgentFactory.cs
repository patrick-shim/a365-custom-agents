using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

namespace SeoulTourist.Agent;

public static class TouristAgentFactory
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
            Name = "Seoul Tourist Assistant",
            ChatOptions = new ChatOptions
            {
                Instructions = TouristAgentInstructions.Create(),
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
