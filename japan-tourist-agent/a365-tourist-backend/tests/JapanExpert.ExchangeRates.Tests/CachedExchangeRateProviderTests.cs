using System.Net;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates.Tests;

/// <summary>Advanceable clock so cache expiry is deterministic instead of time dependent.</summary>
internal sealed class AdvanceableTimeProvider(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan amount) => _now += amount;
}

internal sealed class CountingExchangeRateProvider(Exception? failure = null) : IExchangeRateProvider
{
    public int Calls { get; private set; }

    public Task<ExchangeRateQuote> GetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default)
    {
        Calls++;
        cancellationToken.ThrowIfCancellationRequested();
        if (failure is not null)
        {
            return Task.FromException<ExchangeRateQuote>(failure);
        }

        var observationDate = asOfDate ?? new DateOnly(2026, 8, 28);
        var observedAt = new DateTimeOffset(
            observationDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc));
        return Task.FromResult(new ExchangeRateQuote(
            sourceCurrency,
            targetCurrency,
            159.68m,
            observationDate,
            observedAt,
            new ExchangeRateSource(
                FrankfurterExchangeRateProvider.ProviderName,
                FrankfurterExchangeRateProvider.AttributionUrl,
                "Latest ECB reference rate",
                "test freshness",
                observedAt)));
    }
}

[TestClass]
public sealed class CachedExchangeRateProviderTests
{
    private static readonly DateTimeOffset Start = new(2026, 8, 30, 9, 0, 0, TimeSpan.Zero);

    [TestMethod]
    public async Task RepeatedPairLookupIsServedFromCache()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);

        var first = await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        var second = await provider.GetRateAsync("usd", "jpy", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(1, inner.Calls);
        Assert.AreSame(first, second);
        Assert.AreEqual(159.68m, second.Rate);
    }

    [TestMethod]
    public async Task CacheExpiresAfterSixHours()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, clock) = Create(inner);

        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        clock.Advance(TimeSpan.FromHours(5));
        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(1, inner.Calls);

        clock.Advance(TimeSpan.FromHours(2));
        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task CurrencyPairAndDateIsolateCacheEntries()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);

        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync("EUR", "JPY", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync("USD", "EUR", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync(
            "USD",
            "JPY",
            new DateOnly(2026, 8, 27),
            TestContext.CancellationToken);
        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(4, inner.Calls);
    }

    [TestMethod]
    public async Task ReversedPairIsNotServedFromTheForwardEntry()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);

        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync("JPY", "USD", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task IdentityConversionsAreNotCached()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);

        await provider.GetRateAsync("JPY", "JPY", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync("JPY", "JPY", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task ProviderFailuresAreNeverCached()
    {
        var inner = new CountingExchangeRateProvider(new HttpRequestException(
            "unavailable",
            inner: null,
            HttpStatusCode.ServiceUnavailable));
        var (provider, _) = Create(inner);

        await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken));
        await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken));

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task CancellationIsNeverCached()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsExactlyAsync<OperationCanceledException>(() =>
            provider.GetRateAsync("USD", "JPY", cancellationToken: cancellation.Token));
        var quote = await provider.GetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(159.68m, quote.Rate);
        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public async Task MalformedCurrencyCodesFailBeforeTheCacheIsConsulted()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner);

        await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            provider.GetRateAsync("US", "JPY", cancellationToken: TestContext.CancellationToken));

        Assert.AreEqual(0, inner.Calls);
    }

    [TestMethod]
    public async Task ZeroTimeToLiveDisablesCaching()
    {
        var inner = new CountingExchangeRateProvider();
        var (provider, _) = Create(inner, ttlSeconds: 0);

        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);
        await provider.GetRateAsync("USD", "JPY", cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(2, inner.Calls);
    }

    [TestMethod]
    public void DefaultTimeToLiveIsSixHours()
    {
        var options = new ExchangeRateCacheOptions();

        Assert.AreEqual(TimeSpan.FromHours(6), options.Ttl);
        Assert.IsTrue(options.IsEnabled);
    }

    public TestContext TestContext { get; set; } = null!;

    private static (CachedExchangeRateProvider Provider, AdvanceableTimeProvider Clock) Create(
        IExchangeRateProvider inner,
        int ttlSeconds = 21_600)
    {
        var options = Options.Create(new ExchangeRateCacheOptions { TtlSeconds = ttlSeconds });
        var clock = new AdvanceableTimeProvider(Start);
        var cache = new ExchangeRateResponseCache(options);
        return (new CachedExchangeRateProvider(inner, cache, options, clock), clock);
    }
}
