using System.Globalization;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace JapanExpert.Tourism;

/// <summary>
/// Dedicated bounded <see cref="MemoryCache"/> for tourism responses. A private instance is used
/// instead of the shared container <see cref="IMemoryCache"/> so the size limit enforced here can
/// never make an unrelated component throw for omitting an entry size.
/// </summary>
public sealed class TourismResponseCache : IDisposable
{
    private readonly MemoryCache _cache;

    public TourismResponseCache(IOptions<TourismCacheOptions> options)
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
internal sealed record CachedTourismResponse(
    IReadOnlyList<TourismPlace> Places,
    DateTimeOffset ExpiresAt);

/// <summary>
/// Caches successful, already validated Overpass responses so a public community endpoint is not
/// called once per user turn.
/// <para>
/// Only successful results are stored. A provider failure or a cancellation propagates without
/// writing to the cache, so an outage is never memoised. Requests are validated before the cache
/// is consulted, so an out-of-bounds request can never be answered from a cached entry.
/// </para>
/// </summary>
public sealed class CachedTourismProvider(
    ITourismProvider inner,
    TourismResponseCache cache,
    IOptions<TourismCacheOptions> options,
    TimeProvider timeProvider) : ITourismProvider
{
    /// <summary>
    /// Coordinate precision used in the cache key. Five decimals is about one metre, so a cache
    /// hit never shifts a reported distance by a meaningful amount. Truncation is used rather than
    /// rounding so the quantization is monotonic and matches the weather cache key convention.
    /// </summary>
    private const int CoordinateKeyDecimals = 5;

    private readonly TourismCacheOptions _options = options.Value;

    public Task<IReadOnlyList<TourismPlace>> SearchAttractionsAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var validated = request.Validate();
        return GetOrAddAsync(
            "attractions",
            validated,
            token => inner.SearchAttractionsAsync(validated, token),
            cancellationToken);
    }

    public Task<IReadOnlyList<TourismPlace>> SearchAccommodationAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var validated = request.Validate();
        return GetOrAddAsync(
            "accommodation",
            validated,
            token => inner.SearchAccommodationAsync(validated, token),
            cancellationToken);
    }

    private async Task<IReadOnlyList<TourismPlace>> GetOrAddAsync(
        string operation,
        TourismSearchRequest request,
        Func<CancellationToken, Task<IReadOnlyList<TourismPlace>>> load,
        CancellationToken cancellationToken)
    {
        if (!_options.IsEnabled)
        {
            return await load(cancellationToken);
        }

        var key = BuildKey(operation, request);
        var now = timeProvider.GetUtcNow();
        if (cache.Cache.TryGetValue(key, out CachedTourismResponse? cached)
            && cached is not null
            && now < cached.ExpiresAt)
        {
            return cached.Places;
        }

        var places = await load(cancellationToken);
        var size = places.Count + 1;
        if (size <= _options.MaximumEntrySize)
        {
            cache.Cache.Set(
                key,
                new CachedTourismResponse(places, now + _options.Ttl),
                new MemoryCacheEntryOptions
                {
                    Size = size,
                    AbsoluteExpirationRelativeToNow = _options.Ttl
                });
        }

        return places;
    }

    /// <summary>Builds a normalized, collision-free key from every field that shapes the result.</summary>
    internal static string BuildKey(string operation, TourismSearchRequest request)
    {
        var category = request.Category.Trim().ToUpperInvariant();
        var nameFilter = request.NameContains?.Trim().ToUpperInvariant() ?? string.Empty;
        var latitude = TruncateCoordinate(request.Center.Latitude);
        var longitude = TruncateCoordinate(request.Center.Longitude);
        return string.Create(
            CultureInfo.InvariantCulture,
            $"{operation}|{category}|{nameFilter}|{latitude}|{longitude}|{request.RadiusMeters}|{request.Limit}");
    }

    private static string TruncateCoordinate(double value)
    {
        var scale = Math.Pow(10, CoordinateKeyDecimals);
        var truncated = Math.Truncate(value * scale) / scale;
        return truncated.ToString("F5", CultureInfo.InvariantCulture);
    }
}
