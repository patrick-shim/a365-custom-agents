using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using KoreaExpert.ExchangeRates;

namespace KoreaExpert.ExchangeRates.Tests;

[TestClass]
public sealed class ExchangeRateProviderTests
{
    [TestMethod]
    public async Task KoreaEximbankNormalizesPerHundredCurrencyUnits()
    {
        const string responseJson = """
            [
              { "result": 1, "cur_unit": "KRW", "deal_bas_r": "1" },
              { "result": 1, "cur_unit": "USD", "deal_bas_r": "1,380.00" },
              { "result": 1, "cur_unit": "JPY(100)", "deal_bas_r": "920.00" }
            ]
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateKoreaEximbankProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "USD",
            "JPY",
            new DateOnly(2026, 8, 7),
            TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(150m, quote.Rate);
        Assert.AreEqual(TimeSpan.FromHours(9), quote.ObservedAt.Offset);
        Assert.AreEqual("Daily official reference rate", quote.Source.RateType);
        StringAssert.Contains(handler.RequestUri!.Query, "searchdate=20260807");
    }

    [TestMethod]
    public async Task ForexRateApiUsesHeaderAuthenticationAndMapsTimestamp()
    {
        const string responseJson = """
            {
              "success": true,
              "base": "USD",
              "timestamp": 1786169595,
              "rates": { "KRW": 1381.25 }
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateForexRateApiProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "usd",
            "krw",
            cancellationToken: TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(1381.25m, quote.Rate);
        Assert.AreEqual("test-api-key", handler.ApiKey);
        Assert.IsFalse(handler.RequestUri!.Query.Contains("api_key", StringComparison.OrdinalIgnoreCase));
        Assert.AreEqual(DateTimeOffset.FromUnixTimeSeconds(1786169595), quote.ObservedAt);
    }

    [TestMethod]
    public async Task FrankfurterMapsEcbReferenceRateWithoutCredentials()
    {
        const string responseJson = """
            {
              "amount": 1.0,
              "base": "USD",
              "date": "2026-08-07",
              "rates": { "KRW": 1382.42 }
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateFrankfurterProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "usd",
            "krw",
            cancellationToken: TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(1382.42m, quote.Rate);
        Assert.AreEqual(
            new DateTimeOffset(2026, 8, 7, 0, 0, 0, TimeSpan.Zero),
            quote.ObservedAt);
        Assert.IsNull(handler.ApiKey);
        StringAssert.Contains(handler.RequestUri!.Query, "base=USD");
        StringAssert.Contains(handler.RequestUri.Query, "symbols=KRW");
        StringAssert.Contains(quote.Source.Name, "European Central Bank");
    }

    [TestMethod]
    public async Task ForexOutageFallsBackToFrankfurter()
    {
        var korea = CreateKoreaEximbankProvider(new RecordingHandler("[]"), enabled: false);
        var forex = CreateForexRateApiProvider(new StatusHandler(HttpStatusCode.ServiceUnavailable));
        var frankfurter = CreateFrankfurterProvider(new RecordingHandler(
            """
            {"base":"USD","date":"2026-08-07","rates":{"KRW":1382.42}}
            """));
        var provider = new ExchangeRateProvider(
            korea,
            forex,
            frankfurter,
            NullLogger<ExchangeRateProvider>.Instance);

        var quote = await provider.GetRateAsync(
            "USD",
            "KRW",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(1382.42m, quote.Rate);
        StringAssert.Contains(quote.Source.Name, "European Central Bank");
    }

    [TestMethod]
    public async Task ForexAuthenticationFailureDoesNotHideBehindFallback()
    {
        var provider = new ExchangeRateProvider(
            CreateKoreaEximbankProvider(new RecordingHandler("[]"), enabled: false),
            CreateForexRateApiProvider(new StatusHandler(HttpStatusCode.Unauthorized)),
            CreateFrankfurterProvider(new RecordingHandler(
                """
                {"base":"USD","date":"2026-08-07","rates":{"KRW":1382.42}}
                """)),
            NullLogger<ExchangeRateProvider>.Instance);

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetRateAsync(
                "USD",
                "KRW",
                cancellationToken: TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.Unauthorized, exception.StatusCode);
    }

    [TestMethod]
    public async Task ForexMissingTimestampIsInvalidData()
    {
        var provider = CreateForexRateApiProvider(new RecordingHandler(
            """
            {"success":true,"base":"USD","rates":{"KRW":1381.25}}
            """));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "KRW",
                cancellationToken: TestContext.CancellationToken));
    }

    public TestContext TestContext { get; set; } = null!;

    private static KoreaEximbankExchangeRateProvider CreateKoreaEximbankProvider(
        HttpMessageHandler handler,
        bool enabled = true)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://oapi.koreaexim.go.kr/")
        };
        return new KoreaEximbankExchangeRateProvider(
            client,
            Options.Create(new KoreaEximbankOptions
            {
                Enabled = enabled,
                AuthKey = "test-auth-key"
            }));
    }

    private static ForexRateApiExchangeRateProvider CreateForexRateApiProvider(
        HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.forexrateapi.com/v1/")
        };
        return new ForexRateApiExchangeRateProvider(
            client,
            Options.Create(new ForexRateApiOptions
            {
                Enabled = true,
                ApiKey = "test-api-key"
            }));
    }

    private static FrankfurterExchangeRateProvider CreateFrankfurterProvider(
        HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.frankfurter.dev/v1/")
        };
        return new FrankfurterExchangeRateProvider(
            client,
            Options.Create(new FrankfurterOptions { Enabled = true }));
    }

    private sealed class RecordingHandler(string responseJson) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        public string? ApiKey { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            ApiKey = request.Headers.TryGetValues("X-API-KEY", out var values)
                ? values.Single()
                : null;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class StatusHandler(HttpStatusCode statusCode) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(statusCode));
    }
}
