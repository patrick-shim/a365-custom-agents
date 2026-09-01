using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KoreaExpert.Direct;

public sealed class DirectLineClient
{
    public static readonly Uri DefaultEndpoint =
        new("https://directline.botframework.com/v3/directline/");

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
    private static readonly TimeSpan RenewalWindow = TimeSpan.FromMinutes(1);

    private readonly HttpClient _httpClient;
    private readonly Uri _endpoint;
    private readonly TimeProvider _timeProvider;

    public DirectLineClient(
        HttpClient httpClient,
        Uri? endpoint = null,
        TimeProvider? timeProvider = null)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        _httpClient = httpClient;
        _endpoint = NormalizeEndpoint(endpoint ?? DefaultEndpoint);
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<DirectLineSession> StartConversationAsync(
        string secret,
        string userId,
        string userName,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(secret);
        ArgumentException.ThrowIfNullOrWhiteSpace(userId);
        ArgumentException.ThrowIfNullOrWhiteSpace(userName);

        using var request = new HttpRequestMessage(HttpMethod.Post, CreateUri("conversations"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", secret);
        var response = await SendForJsonAsync<DirectLineConversationResponse>(
            request,
            cancellationToken);

        ValidateConversationResponse(response);
        return new DirectLineSession(
            response.ConversationId,
            response.Token,
            GetExpiration(response.ExpiresIn),
            userId,
            userName);
    }

    public Task<string> SendMessageAsync(
        DirectLineSession session,
        string text,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(text);
        return SendActivityAsync(
            session,
            new DirectLineOutboundActivity
            {
                Type = "message",
                Text = text,
                From = CreateAccount(session)
            },
            cancellationToken);
    }

    public Task<string> SendVerificationCodeAsync(
        DirectLineSession session,
        string verificationCode,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(verificationCode);
        return SendActivityAsync(
            session,
            new DirectLineOutboundActivity
            {
                Type = "message",
                Text = verificationCode.Trim(),
                From = CreateAccount(session),
            },
            cancellationToken);
    }

    public async Task<IReadOnlyList<DirectLineActivity>> ReceiveActivitiesAsync(
        DirectLineSession session,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(session);
        await RenewTokenIfNeededAsync(session, cancellationToken);

        var relativeUri = $"conversations/{Uri.EscapeDataString(session.ConversationId)}/activities";
        if (!string.IsNullOrWhiteSpace(session.Watermark))
        {
            relativeUri += $"?watermark={Uri.EscapeDataString(session.Watermark)}";
        }

        using var request = CreateConversationRequest(HttpMethod.Get, relativeUri, session.Token);
        var response = await SendForJsonAsync<DirectLineActivitySet>(request, cancellationToken);
        session.Watermark = response.Watermark ?? session.Watermark;
        return response.Activities;
    }

    private async Task<string> SendActivityAsync(
        DirectLineSession session,
        DirectLineOutboundActivity activity,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        await RenewTokenIfNeededAsync(session, cancellationToken);

        var relativeUri =
            $"conversations/{Uri.EscapeDataString(session.ConversationId)}/activities";
        using var request = CreateConversationRequest(HttpMethod.Post, relativeUri, session.Token);
        request.Content = new StringContent(
            JsonSerializer.Serialize(activity, JsonOptions),
            Encoding.UTF8,
            "application/json");
        var response = await SendForJsonAsync<DirectLinePostActivityResponse>(
            request,
            cancellationToken);
        if (string.IsNullOrWhiteSpace(response.Id))
        {
            throw DirectLineProtocolException.InvalidResponse();
        }

        return response.Id;
    }

    private async Task RenewTokenIfNeededAsync(
        DirectLineSession session,
        CancellationToken cancellationToken)
    {
        if (session.ExpiresAtUtc - _timeProvider.GetUtcNow() > RenewalWindow)
        {
            return;
        }

        const string relativeUri = "tokens/refresh";
        using var request = CreateConversationRequest(HttpMethod.Post, relativeUri, session.Token);
        var response = await SendForJsonAsync<DirectLineConversationResponse>(
            request,
            cancellationToken);
        ValidateConversationResponse(response);
        session.Token = response.Token;
        session.ExpiresAtUtc = GetExpiration(response.ExpiresIn);
    }

    private async Task<T> SendForJsonAsync<T>(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw DirectLineProtocolException.Timeout(exception);
        }
        catch (HttpRequestException exception)
        {
            throw DirectLineProtocolException.Unavailable(exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw DirectLineProtocolException.FromStatus(response.StatusCode);
            }

            try
            {
                return await response.Content.ReadFromJsonAsync<T>(JsonOptions, cancellationToken)
                    ?? throw DirectLineProtocolException.InvalidResponse();
            }
            catch (JsonException exception)
            {
                throw DirectLineProtocolException.InvalidResponse(exception);
            }
            catch (NotSupportedException exception)
            {
                throw DirectLineProtocolException.InvalidResponse(exception);
            }
        }
    }

    private HttpRequestMessage CreateConversationRequest(
        HttpMethod method,
        string relativeUri,
        string token)
    {
        var request = new HttpRequestMessage(method, CreateUri(relativeUri));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }

    private Uri CreateUri(string relativeUri) => new(_endpoint, relativeUri);

    private DateTimeOffset GetExpiration(int expiresInSeconds)
    {
        var lifetime = expiresInSeconds > 0
            ? TimeSpan.FromSeconds(expiresInSeconds)
            : TimeSpan.FromMinutes(30);
        return _timeProvider.GetUtcNow().Add(lifetime);
    }

    private static DirectLineChannelAccount CreateAccount(DirectLineSession session) => new()
    {
        Id = session.UserId,
        Name = session.UserName
    };

    internal static bool IsTrustedEndpoint(Uri endpoint) =>
        endpoint.IsAbsoluteUri
        && (endpoint.Scheme == Uri.UriSchemeHttps
            || (endpoint.Scheme == Uri.UriSchemeHttp && endpoint.IsLoopback));

    private static Uri NormalizeEndpoint(Uri endpoint)
    {
        if (!IsTrustedEndpoint(endpoint))
        {
            throw new ArgumentException(
                "The Direct Line endpoint must use HTTPS, except for loopback development.",
                nameof(endpoint));
        }

        var value = endpoint.AbsoluteUri;
        return value.EndsWith('/')
            ? endpoint
            : new Uri(value + '/', UriKind.Absolute);
    }

    private static void ValidateConversationResponse(DirectLineConversationResponse response)
    {
        if (string.IsNullOrWhiteSpace(response.ConversationId)
            || string.IsNullOrWhiteSpace(response.Token))
        {
            throw DirectLineProtocolException.InvalidResponse();
        }
    }
}

public enum DirectLineFailureKind
{
    Authentication,
    Authorization,
    ConversationExpired,
    Timeout,
    Throttled,
    InvalidResponse,
    Unavailable
}

public sealed class DirectLineProtocolException : Exception
{
    private DirectLineProtocolException(
        DirectLineFailureKind kind,
        string code,
        string message,
        Exception? innerException = null) : base(message, innerException)
    {
        Kind = kind;
        Code = code;
    }

    public DirectLineFailureKind Kind { get; }

    public string Code { get; }

    internal static DirectLineProtocolException FromStatus(HttpStatusCode statusCode) =>
        statusCode switch
        {
            HttpStatusCode.Unauthorized => new(
                DirectLineFailureKind.Authentication,
                "DL-AUTH-001",
                "Direct Line authentication failed. Refresh the channel secret and try again."),
            HttpStatusCode.Forbidden => new(
                DirectLineFailureKind.Authorization,
                "DL-AUTHZ-001",
                "Direct Line rejected this client. Verify the bot channel configuration."),
            HttpStatusCode.Gone => new(
                DirectLineFailureKind.ConversationExpired,
                "DL-CONV-001",
                "The Direct Line conversation expired. Start a new conversation."),
            HttpStatusCode.RequestTimeout or HttpStatusCode.GatewayTimeout => Timeout(),
            HttpStatusCode.TooManyRequests => new(
                DirectLineFailureKind.Throttled,
                "DL-DEP-002",
                "Direct Line is busy. Try again shortly."),
            >= HttpStatusCode.InternalServerError => Unavailable(),
            _ => new(
                DirectLineFailureKind.Unavailable,
                "DL-DEP-004",
                "Direct Line could not complete the request. Try again later.")
        };

    internal static DirectLineProtocolException Timeout(Exception? exception = null) => new(
        DirectLineFailureKind.Timeout,
        "DL-DEP-001",
        "Direct Line timed out. Try again.",
        exception);

    internal static DirectLineProtocolException InvalidResponse(Exception? exception = null) => new(
        DirectLineFailureKind.InvalidResponse,
        "DL-PROTO-001",
        "Direct Line returned an invalid response.",
        exception);

    internal static DirectLineProtocolException Unavailable(Exception? exception = null) => new(
        DirectLineFailureKind.Unavailable,
        "DL-DEP-004",
        "Direct Line is temporarily unavailable. Try again later.",
        exception);
}
