using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace SeoulTourist.AgentHost;

public sealed partial class PurviewGraphProxy(
    IHttpClientFactory httpClientFactory,
    IOptions<PurviewDlpOptions> options,
    ILogger<PurviewGraphProxy> logger)
{
    private static readonly byte[] EmptyTextSuccessResponse =
        "{\"protectionScopeState\":\"notModified\",\"policyActions\":[],\"processingErrors\":[]}"u8.ToArray();

    private static readonly string[] SafeDiagnosticKeywords =
    [
        "already",
        "correlation",
        "duplicate",
        "empty",
        "exists",
        "format",
        "guid",
        "invalid",
        "length",
        "mismatch",
        "missing",
        "required",
        "sequence",
        "unique"
    ];

    private readonly PurviewDlpOptions _options = options.Value;

    public async Task ForwardAsync(
        HttpContext context,
        string? path,
        CancellationToken cancellationToken)
    {
        if (!_options.UseCompatibilityProxy
            || context.Connection.RemoteIpAddress is not { } remoteAddress
            || !IPAddress.IsLoopback(remoteAddress)
            || !TryValidatePath(path, out var normalizedPath, out var operation))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        var targetUri = new Uri(_options.GraphBaseUri, normalizedPath);
        if (!string.Equals(targetUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Purview Graph forwarding requires HTTPS.");
        }

        using var requestBuffer = new MemoryStream();
        await context.Request.Body.CopyToAsync(requestBuffer, cancellationToken);
        var requestBody = requestBuffer.ToArray();
        var requestShape = InspectRequest(requestBody);
        if (string.Equals(operation, "processContent", StringComparison.Ordinal)
            && requestShape.HasOnlyEmptyTextContent)
        {
            context.Response.StatusCode = StatusCodes.Status200OK;
            context.Response.ContentType = "application/json";
            await context.Response.Body.WriteAsync(EmptyTextSuccessResponse, cancellationToken);
            return;
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, targetUri)
        {
            Content = new ByteArrayContent(requestBody)
        };
        CopyRequestHeader(context, request, "Authorization");
        CopyRequestHeader(context, request, "If-None-Match");
        CopyRequestHeader(context, request, "Client-Request-Id");
        CopyRequestHeader(context, request, "User-Agent");
        if (!request.Headers.Contains("Client-Request-Id"))
        {
            request.Headers.TryAddWithoutValidation(
                "Client-Request-Id",
                Guid.NewGuid().ToString("D"));
        }

        if (!string.IsNullOrWhiteSpace(context.Request.ContentType))
        {
            request.Content.Headers.TryAddWithoutValidation("Content-Type", context.Request.ContentType);
        }

        using var response = await httpClientFactory
            .CreateClient("PurviewGraphProxy")
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var responseBody = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        context.Response.StatusCode = (int)response.StatusCode;
        CopyResponseHeaders(response, context.Response);

        if (!response.IsSuccessStatusCode)
        {
            var error = ClassifyError(responseBody);
            LogPurviewGraphFailure(
                logger,
                operation,
                (int)response.StatusCode,
                error.Code,
                error.Category,
                error.Keywords,
                requestShape.EntryCount,
                requestShape.EmptyCorrelationCount,
                requestShape.InvalidCorrelationCount,
                requestShape.DistinctCorrelationCount,
                requestShape.EmptyContentCount,
                GetResponseHeader(response, "request-id"));
        }

        await context.Response.Body.WriteAsync(responseBody, cancellationToken);
    }

    private static void CopyRequestHeader(
        HttpContext context,
        HttpRequestMessage request,
        string headerName)
    {
        if (context.Request.Headers.TryGetValue(headerName, out var values))
        {
            request.Headers.TryAddWithoutValidation(headerName, values.ToArray());
        }
    }

    private static void CopyResponseHeaders(HttpResponseMessage source, HttpResponse target)
    {
        foreach (var header in source.Headers)
        {
            target.Headers[header.Key] = header.Value.ToArray();
        }

        foreach (var header in source.Content.Headers)
        {
            target.Headers[header.Key] = header.Value.ToArray();
        }

        target.Headers.Remove("transfer-encoding");
    }

    private static string? GetResponseHeader(HttpResponseMessage response, string name) =>
        response.Headers.TryGetValues(name, out var values)
            ? values.FirstOrDefault()
            : null;

    private static bool TryValidatePath(
        string? path,
        out string normalizedPath,
        out string operation)
    {
        normalizedPath = string.Empty;
        operation = string.Empty;
        var segments = path?.Split('/', StringSplitOptions.RemoveEmptyEntries) ?? [];
        if (segments.Length is < 4 or > 5
            || !string.Equals(segments[0], "users", StringComparison.Ordinal)
            || !Guid.TryParse(segments[1], out _)
            || !string.Equals(segments[2], "dataSecurityAndGovernance", StringComparison.Ordinal))
        {
            return false;
        }

        operation = string.Join('/', segments[3..]);
        if (operation is not ("processContent"
            or "protectionScopes/compute"
            or "activities/contentActivities"))
        {
            return false;
        }

        normalizedPath = string.Join('/', segments);
        return true;
    }

    private static PurviewGraphError ClassifyError(ReadOnlySpan<byte> responseBody)
    {
        try
        {
            using var document = JsonDocument.Parse(responseBody.ToArray());
            var error = document.RootElement.GetProperty("error");
            var code = error.TryGetProperty("code", out var codeValue)
                ? codeValue.GetString() ?? "unknown"
                : "unknown";
            var message = error.TryGetProperty("message", out var messageValue)
                ? messageValue.GetString() ?? string.Empty
                : string.Empty;
            return new PurviewGraphError(
                code,
                ClassifyMessage(message),
                string.Join(
                    ',',
                    SafeDiagnosticKeywords.Where(
                        keyword => message.Contains(keyword, StringComparison.OrdinalIgnoreCase))));
        }
        catch (JsonException)
        {
            return new PurviewGraphError("invalid-json", "unclassified", string.Empty);
        }
    }

    private static PurviewRequestShape InspectRequest(ReadOnlySpan<byte> requestBody)
    {
        try
        {
            using var document = JsonDocument.Parse(requestBody.ToArray());
            if (!document.RootElement.TryGetProperty("contentToProcess", out var contentToProcess)
                || !contentToProcess.TryGetProperty("contentEntries", out var entries)
                || entries.ValueKind != JsonValueKind.Array)
            {
                return PurviewRequestShape.Empty;
            }

            var correlations = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var entryCount = 0;
            var emptyCorrelationCount = 0;
            var invalidCorrelationCount = 0;
            var emptyContentCount = 0;
            var nonTextContentCount = 0;
            foreach (var entry in entries.EnumerateArray())
            {
                entryCount++;
                var correlation = entry.TryGetProperty("correlationId", out var correlationValue)
                    ? correlationValue.GetString()
                    : null;
                if (string.IsNullOrWhiteSpace(correlation))
                {
                    emptyCorrelationCount++;
                }
                else
                {
                    correlations.Add(correlation);
                    if (!Guid.TryParse(correlation, out _))
                    {
                        invalidCorrelationCount++;
                    }
                }

                if (!entry.TryGetProperty("content", out var content)
                    || !content.TryGetProperty("@odata.type", out var contentType)
                    || !string.Equals(
                        contentType.GetString(),
                        "microsoft.graph.textContent",
                        StringComparison.Ordinal))
                {
                    nonTextContentCount++;
                }
                else if (!content.TryGetProperty("data", out var data)
                    || data.ValueKind != JsonValueKind.String
                    || string.IsNullOrWhiteSpace(data.GetString()))
                {
                    emptyContentCount++;
                }
            }

            return new PurviewRequestShape(
                entryCount,
                emptyCorrelationCount,
                invalidCorrelationCount,
                correlations.Count,
                emptyContentCount,
                nonTextContentCount);
        }
        catch (JsonException)
        {
            return PurviewRequestShape.Empty;
        }
    }

    private static string ClassifyMessage(string message)
    {
        if (message.Contains("correlation", StringComparison.OrdinalIgnoreCase))
        {
            if (message.Contains("duplicate", StringComparison.OrdinalIgnoreCase)
                || message.Contains("already", StringComparison.OrdinalIgnoreCase)
                || message.Contains("exists", StringComparison.OrdinalIgnoreCase))
            {
                return "correlation-duplicate";
            }

            if (message.Contains("sequence", StringComparison.OrdinalIgnoreCase))
            {
                return "correlation-sequence";
            }

            if (message.Contains("format", StringComparison.OrdinalIgnoreCase)
                || message.Contains("guid", StringComparison.OrdinalIgnoreCase)
                || message.Contains("invalid", StringComparison.OrdinalIgnoreCase))
            {
                return "correlation-format";
            }

            if (message.Contains("missing", StringComparison.OrdinalIgnoreCase)
                || message.Contains("required", StringComparison.OrdinalIgnoreCase)
                || message.Contains("empty", StringComparison.OrdinalIgnoreCase))
            {
                return "correlation-missing";
            }

            return "correlation";
        }

        if (message.Contains("agent", StringComparison.OrdinalIgnoreCase)
            || message.Contains("blueprint", StringComparison.OrdinalIgnoreCase))
        {
            return "agent-metadata";
        }

        if (message.Contains("application", StringComparison.OrdinalIgnoreCase)
            || message.Contains("location", StringComparison.OrdinalIgnoreCase))
        {
            return "application-location";
        }

        if (message.Contains("policy", StringComparison.OrdinalIgnoreCase))
        {
            return "policy";
        }

        if (message.Contains("payment", StringComparison.OrdinalIgnoreCase)
            || message.Contains("billing", StringComparison.OrdinalIgnoreCase))
        {
            return "billing";
        }

        if (message.Contains("activity", StringComparison.OrdinalIgnoreCase))
        {
            return "activity";
        }

        return "unclassified";
    }

    private sealed record PurviewGraphError(string Code, string Category, string Keywords);

    private sealed record PurviewRequestShape(
        int EntryCount,
        int EmptyCorrelationCount,
        int InvalidCorrelationCount,
        int DistinctCorrelationCount,
        int EmptyContentCount,
        int NonTextContentCount)
    {
        public bool HasOnlyEmptyTextContent =>
            EntryCount > 0
            && EmptyContentCount == EntryCount
            && NonTextContentCount == 0;

        public static PurviewRequestShape Empty { get; } = new(0, 0, 0, 0, 0, 0);
    }

    [LoggerMessage(
        EventId = 1020,
        Level = LogLevel.Warning,
        Message = "Purview Graph {Operation} failed with status {StatusCode}, code {ErrorCode}, category {Category}, keywords {Keywords}, entries {EntryCount}, empty correlations {EmptyCorrelationCount}, invalid correlations {InvalidCorrelationCount}, distinct correlations {DistinctCorrelationCount}, empty contents {EmptyContentCount}, request {RequestId}.")]
    private static partial void LogPurviewGraphFailure(
        ILogger logger,
        string operation,
        int statusCode,
        string errorCode,
        string category,
        string keywords,
        int entryCount,
        int emptyCorrelationCount,
        int invalidCorrelationCount,
        int distinctCorrelationCount,
        int emptyContentCount,
        string? requestId);
}
