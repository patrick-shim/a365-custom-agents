using System.ComponentModel.DataAnnotations;

namespace KoreaExpert.AgentHost;

public sealed class AgentHostOptions
{
    public const string SectionName = "AgentHost";

    [Required]
    public string AzureOpenAIEndpoint { get; init; } = string.Empty;

    [Required]
    public string AzureOpenAIDeployment { get; init; } = string.Empty;

    [Required]
    public string AzureOpenAIModel { get; init; } = string.Empty;

    [Range(1, 100_000)]
    public int MaximumPromptCharacters { get; init; } = 32_768;
}
