using System.Net;
using Microsoft.Extensions.Options;

namespace JapanExpert.Tourism.Tests;

/// <summary>Advanceable clock so cache expiry is deterministic instead of time dependent.</summary>
internal sealed class AdvanceableTimeProvider(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan amount) => _now += amount;
}

/// <summary>Counts calls and can be told to fail, so cache behaviour is observable.</summary>
internal sealed class CountingTourismProvider(
    IReadOnlyList<TourismPlace>? result = null,
    Exception? failure = null) : ITourismProvider
{
    public int AttractionCalls { get; private set; }

    public int AccommodationCalls { get; private set; }

    public Task<IReadOnlyList<TourismPlace>> SearchAttractionsAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        AttractionCalls++;
        return Respond(cancellationToken);
    }

    public Task<IReadOnlyList<TourismPlace>> SearchAccommodationAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        AccommodationCalls++;
        return Respond(cancellationToken);
    }

    private Task<IReadOnlyList<TourismPlace>> Respond(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return failure is not null
            ? Task.FromException<IReadOnlyList<TourismPlace>>(failure)
            : Task.FromResult(result ?? []);
    }
}

[TestClass]
public sealed class CachedTourismProviderTests
{
    private static readonly DateTimeOffset Start = new(2026, 8, 30, 9, 0, 0, TimeSpan.Zero);

    [TestMethod]
    public async Task RepeatedIdenticalSearchIsServedFromCache()
    {
        var inner = new CountingTourismProvider(CreatePlaces(2));
        var (provider, _) = Create(inner);

        var first = await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);
        var second = await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual(1, inner.AttractionCalls);
        Assert.AreSame(first, second);
        Assert.HasCount(2, second);
    }

    [TestMethod]
    public async Task CacheExpiresAfterTheConfiguredTimeToLive()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, clock) = Create(inner, ttlSeconds: 86_400);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);
        clock.Advance(TimeSpan.FromHours(23));
        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);
        Assert.AreEqual(1, inner.AttractionCalls);

        clock.Advance(TimeSpan.FromHours(2));
        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual(2, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task AttractionAndAccommodationSearchesDoNotShareEntries()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);
        await provider.SearchAccommodationAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual(1, inner.AttractionCalls);
        Assert.AreEqual(1, inner.AccommodationCalls);
    }

    [TestMethod]
    public async Task EveryRequestFieldParticipatesInTheCacheKey()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner);

        TourismSearchRequest[] distinctRequests =
        [
            OverpassTestFactory.TokyoRequest(),
            OverpassTestFactory.TokyoRequest(category: "museum"),
            OverpassTestFactory.TokyoRequest(nameContains: "sensoji"),
            OverpassTestFactory.TokyoRequest(radiusMeters: 6_000),
            OverpassTestFactory.TokyoRequest(limit: 9),
            new TourismSearchRequest(
                TourismCategories.All,
                NameContains: null,
                new TourismLocation(34.6937, 135.5023),
                5_000,
                8)
        ];

        foreach (var request in distinctRequests)
        {
            await provider.SearchAttractionsAsync(request, TestContext.CancellationToken);
        }

        Assert.AreEqual(distinctRequests.Length, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task CategoryAndNameFilterKeysAreCaseInsensitive()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(category: "museum", nameContains: "Edo"),
            TestContext.CancellationToken);
        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(category: "MUSEUM", nameContains: "edo"),
            TestContext.CancellationToken);

        Assert.AreEqual(1, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task ProviderFailuresAreNeverCached()
    {
        var failing = new CountingTourismProvider(
            failure: new HttpRequestException(
                "unavailable",
                inner: null,
                HttpStatusCode.ServiceUnavailable));
        var (provider, _) = Create(failing);

        await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));
        await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));

        Assert.AreEqual(2, failing.AttractionCalls);
    }

    [TestMethod]
    public async Task CancellationIsNeverCached()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner);
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        await Assert.ThrowsExactlyAsync<OperationCanceledException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                cancellation.Token));

        var result = await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.HasCount(1, result);
        Assert.AreEqual(2, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task InvalidRequestsFailBeforeTheCacheIsConsulted()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner);

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(radiusMeters: 50_001),
                TestContext.CancellationToken));

        Assert.AreEqual(0, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task OversizedResultsAreNotCached()
    {
        var inner = new CountingTourismProvider(CreatePlaces(20));
        var (provider, _) = Create(inner, maximumEntrySize: 4);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(limit: 20),
            TestContext.CancellationToken);
        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(limit: 20),
            TestContext.CancellationToken);

        Assert.AreEqual(2, inner.AttractionCalls);
    }

    [TestMethod]
    public async Task ZeroTimeToLiveDisablesCaching()
    {
        var inner = new CountingTourismProvider(CreatePlaces(1));
        var (provider, _) = Create(inner, ttlSeconds: 0);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);
        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual(2, inner.AttractionCalls);
    }

    [TestMethod]
    public void DefaultTimeToLiveIsOneDay()
    {
        var options = new TourismCacheOptions();

        Assert.AreEqual(TimeSpan.FromHours(24), options.Ttl);
        Assert.IsTrue(options.IsEnabled);
    }

    public TestContext TestContext { get; set; } = null!;

    private static (CachedTourismProvider Provider, AdvanceableTimeProvider Clock) Create(
        ITourismProvider inner,
        int ttlSeconds = 86_400,
        int maximumEntrySize = 64)
    {
        var options = Options.Create(new TourismCacheOptions
        {
            TtlSeconds = ttlSeconds,
            SizeLimit = 512,
            MaximumEntrySize = maximumEntrySize
        });
        var clock = new AdvanceableTimeProvider(Start);
        var cache = new TourismResponseCache(options);
        return (new CachedTourismProvider(inner, cache, options, clock), clock);
    }

    private static IReadOnlyList<TourismPlace> CreatePlaces(int count) =>
    [
        .. Enumerable.Range(0, count).Select(index => new TourismPlace(
            $"node/{index}",
            $"Place {index}",
            LocalName: null,
            TourismPlaceKind.Attraction,
            "tourism=attraction",
            Address: null,
            new TourismLocation(35.6762, 139.6503),
            0,
            Website: null,
            Telephone: null,
            OpeningHours: null,
            new TourismSource(
                OverpassTourismProvider.ProviderName,
                OverpassTourismProvider.AttributionUrl,
                OverpassTourismProvider.License,
                "test notice",
                Start)))
    ];
}
