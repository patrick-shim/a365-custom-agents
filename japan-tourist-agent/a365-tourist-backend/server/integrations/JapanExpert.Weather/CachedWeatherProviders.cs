using System.Globalization;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather;

/// <summary>
/// Dedicated bounded <see cref="MemoryCache"/> for weather responses. A private instance is used
/// instead of the shared container <see cref="IMemoryCache"/> so the size limit enforced here can
/// never make an unrelated component throw for omitting an entry size.
/// </summary>
public sealed class WeatherResponseCache : IDisposable
{
    private readonly MemoryCache _cache;

    public WeatherResponseCache(IOptions<WeatherCacheOptions> options)
    {
        ArgumentNullException.ThrowIfNull(options);
        _cache = new MemoryCache(new MemoryCacheOptions
        {
            SizeLimit = options.Value.SizeLimit
        });
    }

    internal IMemoryCache Cache => _cache;

    public void Dispose() => _cache.Dispose();
}

/// <summary>A cached value with the moment it stops being served.</summary>
internal sealed record CachedWeatherResponse<T>(T Value, DateTimeOffset ExpiresAt);

/// <summary>
/// Shared read-through helper. Only successful results are stored: a provider failure, a schema
/// or freshness rejection, and a cancellation all propagate without writing to the cache, so an
/// outage or a drifted payload is never memoised.
/// </summary>
internal static class WeatherCacheReader
{
    internal static async Task<T> GetOrAddAsync<T>(
        WeatherResponseCache cache,
        TimeProvider timeProvider,
        string key,
        TimeSpan ttl,
        int maximumEntrySize,
        Func<T, int> measure,
        Func<CancellationToken, Task<T>> load,
        CancellationToken cancellationToken)
    {
        if (ttl <= TimeSpan.Zero)
        {
            return await load(cancellationToken);
        }

        var now = timeProvider.GetUtcNow();
        if (cache.Cache.TryGetValue(key, out CachedWeatherResponse<T>? cached)
            && cached is not null
            && now < cached.ExpiresAt)
        {
            return cached.Value;
        }

        var value = await load(cancellationToken);
        var size = measure(value);
        if (size <= maximumEntrySize)
        {
            cache.Cache.Set(
                key,
                new CachedWeatherResponse<T>(value, now + ttl),
                new MemoryCacheEntryOptions
                {
                    Size = size,
                    AbsoluteExpirationRelativeToNow = ttl
                });
        }

        return value;
    }
}

/// <summary>Caches validated Japan Meteorological Agency prefecture forecasts.</summary>
public sealed class CachedWeatherForecastProvider(
    IWeatherForecastProvider inner,
    WeatherResponseCache cache,
    IOptions<WeatherCacheOptions> options,
    TimeProvider timeProvider) : IWeatherForecastProvider
{
    private readonly WeatherCacheOptions _options = options.Value;

    public Task<WeatherForecastResult> GetForecastAsync(
        JapanArea area,
        int days,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(area);
        ArgumentOutOfRangeException.ThrowIfLessThan(days, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, IWeatherForecastProvider.MaximumDays);

        return WeatherCacheReader.GetOrAddAsync(
            cache,
            timeProvider,
            BuildKey(area, days),
            _options.ForecastTtl,
            _options.MaximumEntrySize,
            forecast => forecast.Days.Count + 1,
            token => inner.GetForecastAsync(area, days, token),
            cancellationToken);
    }

    internal static string BuildKey(JapanArea area, int days) =>
        string.Create(CultureInfo.InvariantCulture, $"forecast|{area.OfficeCode}|{days}");
}

/// <summary>Caches Japan Meteorological Agency warning and advisory bulletins for a short window.</summary>
public sealed class CachedWeatherAlertProvider(
    IWeatherAlertProvider inner,
    WeatherResponseCache cache,
    IOptions<WeatherCacheOptions> options,
    TimeProvider timeProvider) : IWeatherAlertProvider
{
    private readonly WeatherCacheOptions _options = options.Value;

    public Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        JapanArea area,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(area);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, IWeatherAlertProvider.MaximumAlerts);

        return WeatherCacheReader.GetOrAddAsync(
            cache,
            timeProvider,
            BuildKey(area, limit),
            _options.AlertTtl,
            _options.MaximumEntrySize,
            alerts => alerts.Count + 1,
            token => inner.GetAlertsAsync(area, limit, token),
            cancellationToken);
    }

    internal static string BuildKey(JapanArea area, int limit) =>
        string.Create(CultureInfo.InvariantCulture, $"alerts|{area.OfficeCode}|{limit}");
}

/// <summary>Caches the labelled third-party current-conditions estimate for a short window.</summary>
public sealed class CachedCurrentWeatherProvider(
    ICurrentWeatherProvider inner,
    WeatherResponseCache cache,
    IOptions<WeatherCacheOptions> options,
    TimeProvider timeProvider) : ICurrentWeatherProvider
{
    /// <summary>
    /// Coordinate precision used in the cache key. It matches the four decimals MET Norway allows
    /// on the wire, and it truncates exactly as the provider does, so an entry can never be shared
    /// by two points that produce different upstream requests. A provider configured with fewer
    /// decimals simply produces extra misses, never a wrong hit.
    /// </summary>
    private const int CoordinateKeyDecimals = 4;

    private readonly WeatherCacheOptions _options = options.Value;

    public Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(location);
        location.EnsureWithinJapan();

        return WeatherCacheReader.GetOrAddAsync(
            cache,
            timeProvider,
            BuildKey(location),
            _options.CurrentTtl,
            _options.MaximumEntrySize,
            _ => 1,
            token => inner.GetCurrentWeatherAsync(location, token),
            cancellationToken);
    }

    internal static string BuildKey(WeatherLocation location)
    {
        var latitude = TruncateCoordinate(location.Latitude);
        var longitude = TruncateCoordinate(location.Longitude);
        return string.Create(CultureInfo.InvariantCulture, $"current|{latitude}|{longitude}");
    }

    private static string TruncateCoordinate(double value)
    {
        var scale = Math.Pow(10, CoordinateKeyDecimals);
        var truncated = Math.Truncate(value * scale) / scale;
        return truncated.ToString("F4", CultureInfo.InvariantCulture);
    }
}
