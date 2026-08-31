using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace JapanExpert.Tourism;

/// <summary>A single Overpass element reduced to the fields the tourism contract needs.</summary>
public sealed record OverpassElement(
    string Type,
    long Id,
    double Latitude,
    double Longitude,
    IReadOnlyDictionary<string, string> Tags);

/// <summary>
/// Minimal Overpass API transport. It owns HTTP concerns only: endpoint, user agent, caps,
/// status-code translation, and a strict response-shape guard. It never accepts caller text.
/// </summary>
public sealed class OverpassClient(HttpClient httpClient, IOptions<OverpassOptions> options)
{
    private const int MaximumTagLength = 200;
    private readonly OverpassOptions _options = options.Value;

    /// <summary>Overpass QL timeout budget applied to generated queries.</summary>
    public int QueryTimeoutSeconds => _options.QueryTimeoutSeconds;

    /// <summary>Hard element cap Overpass is allowed to return.</summary>
    public int MaximumFetchElements => _options.MaximumFetchElements;

    /// <summary>Multiplier used to derive a fetch cap from the caller limit.</summary>
    public int FetchMultiplier => _options.FetchMultiplier;

    /// <summary>Posts a generated Overpass QL program and returns validated elements.</summary>
    public async Task<IReadOnlyList<OverpassElement>> QueryAsync(
        string overpassQl,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(overpassQl);
        if (!Uri.TryCreate(_options.Endpoint, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "Overpass:Endpoint must be an absolute HTTPS URI.");
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new FormUrlEncodedContent(
                new Dictionary<string, string> { ["data"] = overpassQl })
        };
        request.Headers.UserAgent.ParseAdd(_options.UserAgent);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var response = await httpClient.SendAsync(request, cancellationToken);
        EnsureUsableResponse(response.StatusCode);

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);
        return ReadElements(document.RootElement);
    }

    /// <summary>
    /// Translates the Overpass status codes that matter operationally into exception types the
    /// shared MCP failure classifier already maps to stable, sanitized tool errors.
    /// </summary>
    private static void EnsureUsableResponse(HttpStatusCode statusCode)
    {
        switch (statusCode)
        {
            case HttpStatusCode.TooManyRequests:
                throw new HttpRequestException(
                    "The Overpass endpoint rate-limited this request.",
                    inner: null,
                    HttpStatusCode.TooManyRequests);
            case HttpStatusCode.NotAcceptable:
                throw new InvalidDataException(
                    "The Overpass endpoint rejected the requested response format.");
            case HttpStatusCode.BadRequest:
                throw new InvalidDataException(
                    "The Overpass endpoint rejected the generated query.");
            case HttpStatusCode.Forbidden:
                throw new HttpRequestException(
                    "The Overpass endpoint refused this request.",
                    inner: null,
                    HttpStatusCode.Forbidden);
        }

        if ((int)statusCode >= 500)
        {
            throw new HttpRequestException(
                "The Overpass endpoint is temporarily unavailable.",
                inner: null,
                statusCode);
        }

        if ((int)statusCode >= 400)
        {
            throw new HttpRequestException(
                "The Overpass endpoint could not serve this request.",
                inner: null,
                statusCode);
        }
    }

    /// <summary>Strict response guard: an unexpected shape is treated as provider schema drift.</summary>
    private static List<OverpassElement> ReadElements(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException(
                "The Overpass response did not use the documented JSON object envelope.");
        }

        if (root.TryGetProperty("remark", out var remark)
            && remark.ValueKind == JsonValueKind.String
            && IsFailureRemark(remark.GetString()))
        {
            throw new InvalidDataException("The Overpass endpoint reported a query failure.");
        }

        if (!root.TryGetProperty("elements", out var elements)
            || elements.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "The Overpass response did not contain the expected elements array.");
        }

        var results = new List<OverpassElement>(elements.GetArrayLength());
        foreach (var element in elements.EnumerateArray())
        {
            if (TryReadElement(element) is { } parsed)
            {
                results.Add(parsed);
            }
        }

        return results;
    }

    private static bool IsFailureRemark(string? remark) =>
        !string.IsNullOrWhiteSpace(remark)
        && (remark.Contains("error", StringComparison.OrdinalIgnoreCase)
            || remark.Contains("timed out", StringComparison.OrdinalIgnoreCase));

    private static OverpassElement? TryReadElement(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object
            || element.TryGetProperty("type", out var typeElement) is false
            || typeElement.ValueKind != JsonValueKind.String
            || !element.TryGetProperty("id", out var idElement)
            || !idElement.TryGetInt64(out var id)
            || !element.TryGetProperty("tags", out var tags)
            || tags.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (!TryReadPosition(element, out var latitude, out var longitude))
        {
            return null;
        }

        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var tag in tags.EnumerateObject())
        {
            if (tag.Value.ValueKind != JsonValueKind.String)
            {
                continue;
            }

            var value = tag.Value.GetString();
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            map[tag.Name] = value.Length > MaximumTagLength
                ? value[..MaximumTagLength]
                : value;
        }

        return new OverpassElement(
            typeElement.GetString()!,
            id,
            latitude,
            longitude,
            map);
    }

    private static bool TryReadPosition(
        JsonElement element,
        out double latitude,
        out double longitude)
    {
        if (TryReadDouble(element, "lat", out latitude)
            && TryReadDouble(element, "lon", out longitude))
        {
            return true;
        }

        if (element.TryGetProperty("center", out var center)
            && center.ValueKind == JsonValueKind.Object
            && TryReadDouble(center, "lat", out latitude)
            && TryReadDouble(center, "lon", out longitude))
        {
            return true;
        }

        latitude = 0;
        longitude = 0;
        return false;
    }

    private static bool TryReadDouble(JsonElement element, string propertyName, out double value)
    {
        if (element.TryGetProperty(propertyName, out var property)
            && property.ValueKind == JsonValueKind.Number
            && property.TryGetDouble(out value))
        {
            return true;
        }

        value = 0;
        return false;
    }

    /// <summary>Formats a coordinate for Overpass QL without culture drift.</summary>
    internal static string FormatCoordinate(double value) =>
        value.ToString("0.######", CultureInfo.InvariantCulture);
}
