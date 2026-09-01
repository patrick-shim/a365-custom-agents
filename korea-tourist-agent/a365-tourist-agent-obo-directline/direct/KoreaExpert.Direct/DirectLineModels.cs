using System.Text.Json;
using System.Text.Json.Serialization;

namespace KoreaExpert.Direct;

public sealed class DirectLineSession
{
    internal DirectLineSession(
        string conversationId,
        string token,
        DateTimeOffset expiresAtUtc,
        string userId,
        string userName)
    {
        ConversationId = conversationId;
        Token = token;
        ExpiresAtUtc = expiresAtUtc;
        UserId = userId;
        UserName = userName;
    }

    public string ConversationId { get; }

    public string UserId { get; }

    public string UserName { get; }

    public string? Watermark { get; internal set; }

    internal string Token { get; set; }

    internal DateTimeOffset ExpiresAtUtc { get; set; }
}

public sealed class DirectLineActivity
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("type")]
    public string? Type { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("text")]
    public string? Text { get; init; }

    [JsonPropertyName("replyToId")]
    public string? ReplyToId { get; init; }

    [JsonPropertyName("from")]
    public DirectLineChannelAccount? From { get; init; }

    [JsonPropertyName("attachments")]
    public IReadOnlyList<DirectLineAttachment> Attachments { get; init; } = [];
}

public sealed class DirectLineChannelAccount
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("name")]
    public string? Name { get; init; }
}

public sealed class DirectLineAttachment
{
    [JsonPropertyName("contentType")]
    public string? ContentType { get; init; }

    [JsonPropertyName("content")]
    public JsonElement Content { get; init; }
}

public sealed record DirectLineOAuthCard(
    string ConnectionName,
    string? Text,
    Uri SignInUri);

public static class DirectLineOAuthCardParser
{
    public const string ContentType = "application/vnd.microsoft.card.oauth";
    private static readonly HashSet<string> TrustedSignInHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "token.botframework.com",
        "token.botframework.azure.cn",
        "token.botframework.azure.us"
    };

    public static bool TryParse(
        DirectLineAttachment attachment,
        out DirectLineOAuthCard? card)
    {
        card = null;
        if (!string.Equals(attachment.ContentType, ContentType, StringComparison.OrdinalIgnoreCase)
            || attachment.Content.ValueKind is not JsonValueKind.Object)
        {
            return false;
        }

        var content = attachment.Content;
        var connectionName = content.TryGetProperty("connectionName", out var connectionElement)
            ? connectionElement.GetString() ?? string.Empty
            : string.Empty;
        var text = content.TryGetProperty("text", out var textElement)
            ? textElement.GetString()
            : null;

        if (!content.TryGetProperty("buttons", out var buttons)
            || buttons.ValueKind is not JsonValueKind.Array)
        {
            return false;
        }

        foreach (var button in buttons.EnumerateArray())
        {
            if (button.ValueKind is not JsonValueKind.Object
                || !button.TryGetProperty("type", out var type)
                || !string.Equals(type.GetString(), "signin", StringComparison.OrdinalIgnoreCase)
                || !button.TryGetProperty("value", out var value)
                || value.ValueKind is not JsonValueKind.String
                || !Uri.TryCreate(value.GetString(), UriKind.Absolute, out var signInUri)
                || signInUri.Scheme != Uri.UriSchemeHttps
                || !TrustedSignInHosts.Contains(signInUri.Host))
            {
                continue;
            }

            card = new DirectLineOAuthCard(connectionName, text, signInUri);
            return true;
        }

        return false;
    }
}

internal sealed class DirectLineConversationResponse
{
    [JsonPropertyName("conversationId")]
    public string ConversationId { get; init; } = string.Empty;

    [JsonPropertyName("token")]
    public string Token { get; init; } = string.Empty;

    [JsonPropertyName("expires_in")]
    public int ExpiresIn { get; init; }
}

internal sealed class DirectLineActivitySet
{
    [JsonPropertyName("activities")]
    public IReadOnlyList<DirectLineActivity> Activities { get; init; } = [];

    [JsonPropertyName("watermark")]
    public string? Watermark { get; init; }
}

internal sealed class DirectLinePostActivityResponse
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;
}

internal sealed class DirectLineOutboundActivity
{
    [JsonPropertyName("type")]
    public required string Type { get; init; }

    [JsonPropertyName("text")]
    public string? Text { get; init; }

    [JsonPropertyName("locale")]
    public string Locale { get; init; } = "en-US";

    [JsonPropertyName("from")]
    public required DirectLineChannelAccount From { get; init; }

}
