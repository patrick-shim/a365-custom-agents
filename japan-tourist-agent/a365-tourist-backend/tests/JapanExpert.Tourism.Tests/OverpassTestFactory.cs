using System.Net;
using System.Text;
using Microsoft.Extensions.Options;

namespace JapanExpert.Tourism.Tests;

/// <summary>
/// Recording handler that captures the Overpass request and replays a fixed response. No test in
/// this project performs a live call.
/// </summary>
internal sealed class OverpassHandler(
    HttpStatusCode statusCode,
    string body,
    string mediaType = "application/json") : HttpMessageHandler
{
    public Uri? RequestUri { get; private set; }

    public string? UserAgent { get; private set; }

    public string? RequestBody { get; private set; }

    public int RequestCount { get; private set; }

    /// <summary>The decoded Overpass QL program posted in the <c>data</c> form field.</summary>
    public string? OverpassQuery =>
        RequestBody is null
            ? null
            : WebUtility.UrlDecode(
                RequestBody.StartsWith("data=", StringComparison.Ordinal)
                    ? RequestBody["data=".Length..]
                    : RequestBody);

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        RequestCount++;
        RequestUri = request.RequestUri;
        UserAgent = request.Headers.UserAgent.ToString();
        RequestBody = request.Content is null
            ? null
            : await request.Content.ReadAsStringAsync(cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        return new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(body, Encoding.UTF8, mediaType)
        };
    }
}

internal static class OverpassTestFactory
{
    internal const string TestUserAgent = "JapanExpertTests/1.0 (+https://example.test/contact)";

    internal static OverpassTourismProvider CreateProvider(
        OverpassHandler handler,
        OverpassOptions? options = null) =>
        new(CreateClient(handler, options));

    internal static OverpassClient CreateClient(
        OverpassHandler handler,
        OverpassOptions? options = null) =>
        new(
            new HttpClient(handler),
            Options.Create(options ?? new OverpassOptions { UserAgent = TestUserAgent }));

    internal static TourismSearchRequest TokyoRequest(
        string category = TourismCategories.All,
        string? nameContains = null,
        int radiusMeters = 5_000,
        int limit = 8) =>
        new(
            category,
            nameContains,
            new TourismLocation(
                JapanGeography.DefaultLatitude,
                JapanGeography.DefaultLongitude),
            radiusMeters,
            limit);
}
