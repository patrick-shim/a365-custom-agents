using System.ClientModel;
using System.Net;
using System.Text.Json;
using Azure;
using Azure.Identity;
using Microsoft.Identity.Client;
using Microsoft.IdentityModel.Tokens;

namespace JapanExpert.AgentHost;

internal enum AgentFailureKind
{
    Authentication,
    Authorization,
    Timeout,
    Throttled,
    InvalidResponse,
    Unavailable,
    Internal
}

internal sealed record AgentFailureDescriptor(
    AgentFailureKind Kind,
    string Code,
    string UserMessage,
    Microsoft.Extensions.Logging.LogLevel LogLevel);

internal static class AgentFailureClassifier
{
    public static AgentFailureDescriptor Classify(
        Exception exception,
        AgentFailureKind fallback = AgentFailureKind.Internal)
    {
        ArgumentNullException.ThrowIfNull(exception);

        var kind = exception switch
        {
            AuthenticationFailedException or MsalUiRequiredException or SecurityTokenException =>
                AgentFailureKind.Authentication,
            UnauthorizedAccessException => AgentFailureKind.Authorization,
            TimeoutException or OperationCanceledException => AgentFailureKind.Timeout,
            JsonException or InvalidDataException or FormatException => AgentFailureKind.InvalidResponse,
            RequestFailedException requestFailed => FromStatusCode(requestFailed.Status, fallback),
            // The Foundry Responses client reports transport failures as ClientResultException.
            // Without this arm a throttled or unauthorized model call is misreported as internal.
            ClientResultException clientResult => FromStatusCode(clientResult.Status, fallback),
            MsalServiceException msalService => FromStatusCode(msalService.StatusCode, fallback),
            HttpRequestException httpRequest when httpRequest.StatusCode is { } statusCode =>
                FromStatusCode((int)statusCode, fallback),
            HttpRequestException => AgentFailureKind.Unavailable,
            _ => fallback
        };

        return Describe(kind);
    }

    /// <summary>
    /// Returns the transport status a dependency reported, or <c>0</c> when the failure carries
    /// none. Diagnosing a dependency failure requires the status; the exception type alone is not
    /// actionable and the message may contain service payload detail that must not be logged.
    /// </summary>
    public static int GetDependencyStatus(Exception exception)
    {
        ArgumentNullException.ThrowIfNull(exception);

        return exception switch
        {
            RequestFailedException requestFailed => requestFailed.Status,
            ClientResultException clientResult => clientResult.Status,
            MsalServiceException msalService => msalService.StatusCode,
            HttpRequestException { StatusCode: { } statusCode } => (int)statusCode,
            _ => 0
        };
    }

    private static AgentFailureKind FromStatusCode(int statusCode, AgentFailureKind fallback) =>
        statusCode switch
        {
            (int)HttpStatusCode.Unauthorized => AgentFailureKind.Authentication,
            (int)HttpStatusCode.Forbidden => AgentFailureKind.Authorization,
            (int)HttpStatusCode.RequestTimeout or (int)HttpStatusCode.GatewayTimeout =>
                AgentFailureKind.Timeout,
            429 => AgentFailureKind.Throttled,
            >= 500 => AgentFailureKind.Unavailable,
            _ => fallback
        };

    private static AgentFailureDescriptor Describe(AgentFailureKind kind) =>
        kind switch
        {
            AgentFailureKind.Authentication => new(
                kind,
                "JEX-AUTH-001",
                "I could not authenticate this request. Please sign in again and retry.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            AgentFailureKind.Authorization => new(
                kind,
                "JEX-AUTHZ-001",
                "This request is not authorized. Contact your administrator if this continues.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            AgentFailureKind.Timeout => new(
                kind,
                "JEX-DEP-001",
                "A required service timed out. Please try again.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            AgentFailureKind.Throttled => new(
                kind,
                "JEX-DEP-002",
                "A required service is busy. Please try again shortly.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            AgentFailureKind.InvalidResponse => new(
                kind,
                "JEX-DEP-003",
                "A required service returned an invalid response. Please try again later.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            AgentFailureKind.Unavailable => new(
                kind,
                "JEX-DEP-004",
                "A required service is temporarily unavailable. Please try again later.",
                Microsoft.Extensions.Logging.LogLevel.Warning),
            _ => new(
                AgentFailureKind.Internal,
                "JEX-INT-001",
                "I could not complete this request. Please try again.",
                Microsoft.Extensions.Logging.LogLevel.Error)
        };
}
