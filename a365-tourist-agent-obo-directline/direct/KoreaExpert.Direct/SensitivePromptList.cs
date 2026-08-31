using System.Text.Json;
using System.Text.Json.Serialization;

namespace KoreaExpert.Direct;

public static class SensitivePromptList
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static async Task<IReadOnlyList<string>> LoadAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (!File.Exists(path))
        {
            throw new SensitivePromptListException($"SIT prompt file was not found: {path}");
        }

        try
        {
            await using var stream = File.OpenRead(path);
            var entries = await JsonSerializer.DeserializeAsync<List<SensitivePromptEntry>>(
                stream,
                JsonOptions,
                cancellationToken)
                ?? throw new SensitivePromptListException("SIT prompt file contains null JSON.");
            if (entries.Count == 0)
            {
                throw new SensitivePromptListException("SIT prompt file contains no prompts.");
            }

            var prompts = new List<string>(entries.Count);
            for (var index = 0; index < entries.Count; index++)
            {
                var prompt = entries[index].Prompt?.Trim();
                if (string.IsNullOrWhiteSpace(prompt))
                {
                    throw new SensitivePromptListException(
                        $"SIT prompt at index {index} is empty.");
                }

                prompts.Add(prompt);
            }

            return prompts;
        }
        catch (JsonException exception)
        {
            throw new SensitivePromptListException(
                $"SIT prompt file is not valid JSON: {exception.Message}",
                exception);
        }
        catch (IOException exception)
        {
            throw new SensitivePromptListException(
                $"SIT prompt file could not be read: {exception.Message}",
                exception);
        }
    }

    private sealed class SensitivePromptEntry
    {
        [JsonPropertyName("prompt")]
        public string? Prompt { get; init; }
    }
}

public sealed class SensitivePromptListException : Exception
{
    public SensitivePromptListException(string message)
        : base(message)
    {
    }

    public SensitivePromptListException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
