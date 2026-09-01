using System.Net;
using System.Text;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather.Tests;

/// <summary>Deterministic clock for freshness and retrieval assertions.</summary>
internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}

/// <summary>Recording handler that replays a fixed response. No test performs a live call.</summary>
internal sealed class RecordingHandler(
    HttpStatusCode statusCode,
    string body,
    string mediaType = "application/json") : HttpMessageHandler
{
    public Uri? RequestUri { get; private set; }

    public string? UserAgent { get; private set; }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        RequestUri = request.RequestUri;
        UserAgent = request.Headers.UserAgent.ToString();
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(body, Encoding.UTF8, mediaType)
        });
    }
}

internal static class WeatherTestFactory
{
    internal const string TestUserAgent = "JapanExpertTests/1.0 (+https://example.test/contact)";

    internal static readonly DateTimeOffset Now =
        new(2026, 8, 30, 9, 0, 0, TimeSpan.Zero);

    internal static JmaForecastProvider CreateForecastProvider(
        RecordingHandler handler,
        JmaOptions? options = null,
        DateTimeOffset? now = null) =>
        new(
            new HttpClient(handler),
            Options.Create(options ?? new JmaOptions()),
            new FixedTimeProvider(now ?? Now));

    internal static JmaAlertFeedProvider CreateAlertProvider(
        RecordingHandler handler,
        JmaOptions? options = null) =>
        new(
            new HttpClient(handler),
            Options.Create(options ?? new JmaOptions()),
            new FixedTimeProvider(Now));

    internal static MetNorwayCurrentWeatherProvider CreateCurrentProvider(
        RecordingHandler handler,
        MetNorwayOptions? options = null)
    {
        var resolved = options ?? new MetNorwayOptions { UserAgent = TestUserAgent };
        return new MetNorwayCurrentWeatherProvider(
            new HttpClient(handler) { BaseAddress = new Uri(resolved.BaseAddress) },
            Options.Create(resolved),
            new FixedTimeProvider(Now));
    }
}
