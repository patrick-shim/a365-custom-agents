using System.ComponentModel.DataAnnotations;
using System.Globalization;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Bounded in-process response cache settings for published reference rates. European Central
/// Bank rates are issued once per working day, so a multi-hour time to live keeps the public
/// endpoints from being called once per user turn without ever serving a different day's rate.
/// </summary>
public sealed class ExchangeRateCacheOptions
{
    public const string SectionName = "Cache";

    /// <summary>Time to live in seconds. Zero disables caching entirely.</summary>
    [Range(0, 604_800)]
    public int TtlSeconds { get; init; } = 21_600;

    /// <summary>Total cache size budget, counted in cached quotes.</summary>
    [Range(16, 100_000)]
    public int SizeLimit { get; init; } = 256;

    /// <summary>Largest single entry that may be cached, counted in cached quotes.</summary>
    [Range(1, 1_000)]
    public int MaximumEntrySize { get; init; } = 8;

    public TimeSpan Ttl => TimeSpan.FromSeconds(TtlSeconds);

    public bool IsEnabled => TtlSeconds > 0;
}

/// <summary>
/// Dedicated bounded <see cref="MemoryCache"/> for exchange-rate responses. A private instance is
/// used instead of the shared container <see cref="IMemoryCache"/> so the size limit enforced here
/// can never make an unrelated component throw for omitting an entry size.
/// </summary>
public sealed class ExchangeRateResponseCache : IDisposable
{
    private readonly MemoryCache _cache;

    public ExchangeRateResponseCache(IOptions<ExchangeRateCacheOptions> options)
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

/// <summary>A cached quote with the moment it stops being served.</summary>
internal sealed record CachedExchangeRateResponse(
    ExchangeRateQuote Quote,
    DateTimeOffset ExpiresAt);

/// <summary>
/// Caches successful, attributed exchange-rate quotes.
/// <para>
/// Only successful results are stored, so a provider outage, a rejected payload, or a cancellation
/// is never memoised. Identity conversions are not cached because they are computed locally and
/// embed their own retrieval timestamp.
/// </para>
/// </summary>
public sealed class CachedExchangeRateProvider(
    IExchangeRateProvider inner,
    ExchangeRateResponseCache cache,
    IOptions<ExchangeRateCacheOptions> options,
    TimeProvider timeProvider) : IExchangeRateProvider
{
    private readonly ExchangeRateCacheOptions _options = options.Value;

    public async Task<ExchangeRateQuote> GetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default)
    {
        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        if (!_options.IsEnabled || string.Equals(source, target, StringComparison.Ordinal))
        {
            return await inner.GetRateAsync(source, target, asOfDate, cancellationToken);
        }

        var key = BuildKey(source, target, asOfDate);
        var now = timeProvider.GetUtcNow();
        if (cache.Cache.TryGetValue(key, out CachedExchangeRateResponse? cached)
            && cached is not null
            && now < cached.ExpiresAt)
        {
            return cached.Quote;
        }

        var quote = await inner.GetRateAsync(source, target, asOfDate, cancellationToken);
        cache.Cache.Set(
            key,
            new CachedExchangeRateResponse(quote, now + _options.Ttl),
            new MemoryCacheEntryOptions
            {
                Size = 1,
                AbsoluteExpirationRelativeToNow = _options.Ttl
            });
        return quote;
    }

    /// <summary>Builds a normalized key. A historical date is part of the identity of the quote.</summary>
    internal static string BuildKey(string source, string target, DateOnly? asOfDate)
    {
        var date = asOfDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "latest";
        return string.Create(CultureInfo.InvariantCulture, $"rate|{source}|{target}|{date}");
    }
}
