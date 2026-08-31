using System.Net;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather.Tests;

/// <summary>Advanceable clock so cache expiry is deterministic instead of time dependent.</summary>
internal sealed class AdvanceableTimeProvider(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan amount) => _now += amount;
}

internal sealed class CountingForecastProvider(Exception? failure = null) : IWeatherForecastProvider
{
    public int Calls { get; private set; }

    public Task<WeatherForecastResult> GetForecastAsync(
        JapanArea area,
        int days,
        CancellationToken cancellationToken = default)
    {
        Calls++;
        cancellationToken.ThrowIfCancellationRequested();
        if (failure is not null)
        {
            return Task.FromException<WeatherForecastResult>(failure);
        }

        return Task.FromResult(new WeatherForecastResult(
            area.OfficeCode,
            area.PrefectureEnglish,
            area.PrefectureJapanese,
            "東京地方",
            "気象庁",
            new DateTimeOffset(2026, 8, 30, 8, 0, 0, TimeSpan.Zero),
            [],
            new WeatherSource("JMA", "https://www.jma.go.jp/", "terms", "notice", WeatherTestFactory.Now)));
    }
}

internal sealed class CountingAlertProvider : IWeatherAlertProvider
{
    public int Calls { get; private set; }

    public Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        JapanArea area,
        int limit,
        CancellationToken cancellationToken = default)
    {
        Calls++;
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult<IReadOnlyList<WeatherAlert>>([]);
    }
}

internal sealed class CountingCurrentProvider : ICurrentWeatherProvider
{
    public int Calls { get; private set; }

    public Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        Calls++;
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult<CurrentWeatherResult?>(new CurrentWeatherResult(
            WeatherTestFactory.Now,
            "Partly cloudy (day)",
            "partlycloudy_day",
            28.7,
            71,
            0.4,
            12.6,
            new WeatherSource("MET Norway", "https://api.met.no/", "NLOD", "notice", WeatherTestFactory.Now)));
    }
}

[TestClass]
public sealed class CachedWeatherProviderTests
{
    private static readonly DateTimeOffset Start = new(2026, 8, 30, 9, 0, 0, TimeSpan.Zero);

    [TestMethod]
    public async Task ForecastIsServedFromCacheWithinTheHalfHourWindow()
    {
        var inner = new CountingForecastProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherForecastProvider(inner, cache, options, clock);

        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);
        clock.Advance(TimeSpan.FromMinutes(29));
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);
        Assert.AreEqual(1, inner.Calls);

        clock.Advance(TimeSpan.FromMinutes(2));
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task ForecastKeysIsolatePrefectureAndHorizon()
    {
        var inner = new CountingForecastProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherForecastProvider(inner, cache, options, clock);

        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Kyoto"), 5, TestContext.CancellationToken);
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 3, TestContext.CancellationToken);
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);

        Assert.AreEqual(3, inner.Calls);
    }

    [TestMethod]
    public async Task AlertsUseAShortWindowSoWarningsAreNotWithheld()
    {
        var inner = new CountingAlertProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherAlertProvider(inner, cache, options, clock);

        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, TestContext.CancellationToken);
        clock.Advance(TimeSpan.FromSeconds(59));
        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, TestContext.CancellationToken);
        Assert.AreEqual(1, inner.Calls);

        clock.Advance(TimeSpan.FromSeconds(2));
        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task AlertKeysIsolatePrefectureAndLimit()
    {
        var inner = new CountingAlertProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherAlertProvider(inner, cache, options, clock);

        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, TestContext.CancellationToken);
        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Osaka"), 10, TestContext.CancellationToken);
        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);
        await provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, TestContext.CancellationToken);

        Assert.AreEqual(3, inner.Calls);
    }

    [TestMethod]
    public async Task CurrentConditionsAreCachedForTenMinutes()
    {
        var inner = new CountingCurrentProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedCurrentWeatherProvider(inner, cache, options, clock);

        await provider.GetCurrentWeatherAsync(WeatherLocation.Default, TestContext.CancellationToken);
        clock.Advance(TimeSpan.FromMinutes(9));
        await provider.GetCurrentWeatherAsync(WeatherLocation.Default, TestContext.CancellationToken);
        Assert.AreEqual(1, inner.Calls);

        clock.Advance(TimeSpan.FromMinutes(2));
        await provider.GetCurrentWeatherAsync(WeatherLocation.Default, TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task CurrentConditionKeysTruncateToTheFourDecimalWireCoordinates()
    {
        var inner = new CountingCurrentProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedCurrentWeatherProvider(inner, cache, options, clock);

        // Both truncate to 35.6762 / 139.6503, which is exactly what the provider puts on the wire.
        await provider.GetCurrentWeatherAsync(
            new WeatherLocation(35.676212345, 139.650312345),
            TestContext.CancellationToken);
        await provider.GetCurrentWeatherAsync(
            new WeatherLocation(35.676298765, 139.650398765),
            TestContext.CancellationToken);
        Assert.AreEqual(1, inner.Calls);

        // A point that truncates differently must never be served from the entry above.
        await provider.GetCurrentWeatherAsync(
            new WeatherLocation(35.676312345, 139.650312345),
            TestContext.CancellationToken);
        Assert.AreEqual(2, inner.Calls);

        await provider.GetCurrentWeatherAsync(
            new WeatherLocation(34.6937, 135.5023),
            TestContext.CancellationToken);

        Assert.AreEqual(3, inner.Calls);
    }

    [TestMethod]
    public async Task ForecastFailuresAreNeverCached()
    {
        var inner = new CountingForecastProvider(new InvalidDataException("stale"));
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherForecastProvider(inner, cache, options, clock);

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken));
        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken));

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task CancellationIsNeverCached()
    {
        var inner = new CountingAlertProvider();
        var (cache, options, clock) = Create();
        var provider = new CachedWeatherAlertProvider(inner, cache, options, clock);
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsExactlyAsync<OperationCanceledException>(() =>
            provider.GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 10, cancellation.Token));
        await provider.GetAlertsAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            10,
            TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task OutOfBoundsRequestsFailBeforeTheCacheIsConsulted()
    {
        var forecast = new CountingForecastProvider();
        var current = new CountingCurrentProvider();
        var (cache, options, clock) = Create();

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            new CachedWeatherForecastProvider(forecast, cache, options, clock)
                .GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 8, TestContext.CancellationToken));
        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            new CachedCurrentWeatherProvider(current, cache, options, clock)
                .GetCurrentWeatherAsync(
                    new WeatherLocation(37.5665, 126.9780),
                    TestContext.CancellationToken));

        Assert.AreEqual(0, forecast.Calls);
        Assert.AreEqual(0, current.Calls);
    }

    [TestMethod]
    public async Task ZeroTimeToLiveDisablesCaching()
    {
        var inner = new CountingForecastProvider();
        var (cache, options, clock) = Create(forecastTtlSeconds: 0);
        var provider = new CachedWeatherForecastProvider(inner, cache, options, clock);

        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);
        await provider.GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public void DefaultTimeToLivesMatchEachSourceCadence()
    {
        var options = new WeatherCacheOptions();

        Assert.AreEqual(TimeSpan.FromMinutes(30), options.ForecastTtl);
        Assert.AreEqual(TimeSpan.FromSeconds(60), options.AlertTtl);
        Assert.AreEqual(TimeSpan.FromMinutes(10), options.CurrentTtl);
    }

    [TestMethod]
    public async Task ForecastAndAlertEntriesDoNotCollide()
    {
        var forecast = new CountingForecastProvider();
        var alerts = new CountingAlertProvider();
        var (cache, options, clock) = Create();

        await new CachedWeatherForecastProvider(forecast, cache, options, clock)
            .GetForecastAsync(JapanAreaCatalog.Resolve("Tokyo"), 10 - 5, TestContext.CancellationToken);
        await new CachedWeatherAlertProvider(alerts, cache, options, clock)
            .GetAlertsAsync(JapanAreaCatalog.Resolve("Tokyo"), 5, TestContext.CancellationToken);

        Assert.AreEqual(1, forecast.Calls);
        Assert.AreEqual(1, alerts.Calls);
    }

    public TestContext TestContext { get; set; } = null!;

    private static (WeatherResponseCache Cache, IOptions<WeatherCacheOptions> Options, AdvanceableTimeProvider Clock)
        Create(int forecastTtlSeconds = 1_800)
    {
        var options = Options.Create(new WeatherCacheOptions
        {
            ForecastTtlSeconds = forecastTtlSeconds
        });
        return (new WeatherResponseCache(options), options, new AdvanceableTimeProvider(Start));
    }
}
