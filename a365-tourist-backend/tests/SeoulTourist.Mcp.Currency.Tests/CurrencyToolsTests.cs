using SeoulTourist.ExchangeRates;
using SeoulTourist.Mcp.Currency;
using Microsoft.Extensions.Logging.Abstractions;

namespace SeoulTourist.Mcp.Currency.Tests;

[TestClass]
public sealed class CurrencyToolsTests
{
    [TestMethod]
    public void ConvertCurrencyNormalizesCodesAndRoundsResult()
    {
        var result = new CurrencyTools().ConvertCurrency(
            12.34m,
            " usd ",
            "krw",
            1_381.275m,
            new DateTimeOffset(2026, 8, 8, 0, 0, 0, TimeSpan.Zero));

        Assert.AreEqual("USD", result.SourceCurrency);
        Assert.AreEqual("KRW", result.TargetCurrency);
        Assert.AreEqual(17_044.93m, result.TargetAmount);
    }

    [TestMethod]
    public void ConvertCurrencyRejectsInvalidCurrencyCode()
    {
        Assert.ThrowsExactly<ArgumentException>(() =>
            new CurrencyTools().ConvertCurrency(10m, "US", "KRW", 1_300m));
    }

    [TestMethod]
    public void ConvertCurrencyRejectsNonPositiveRate()
    {
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() =>
            new CurrencyTools().ConvertCurrency(10m, "USD", "KRW", 0m));
    }

    [TestMethod]
    public async Task ConvertCurrencyAsyncReturnsProviderProvenance()
    {
        var observedAt = new DateTimeOffset(2026, 8, 8, 2, 0, 0, TimeSpan.Zero);
        var tools = new ExchangeRateTools(
            new StubExchangeRateProvider(observedAt),
            NullLogger<ExchangeRateTools>.Instance);

        var result = await tools.ConvertCurrencyAsync(
            12.34m,
            "USD",
            "KRW",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(17_044.93m, result.TargetAmount);
        Assert.AreEqual("Test provider", result.Quote.Source.Name);
        Assert.AreEqual(observedAt, result.Quote.ObservedAt);
    }

    public TestContext TestContext { get; set; } = null!;

    private sealed class StubExchangeRateProvider(DateTimeOffset observedAt) : IExchangeRateProvider
    {
        public Task<ExchangeRateQuote> GetRateAsync(
            string sourceCurrency,
            string targetCurrency,
            DateOnly? asOfDate = null,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(new ExchangeRateQuote(
                sourceCurrency,
                targetCurrency,
                1_381.275m,
                observedAt,
                new ExchangeRateSource(
                    "Test provider",
                    "https://example.test/",
                    "Test rate",
                    "Test freshness",
                    observedAt)));
    }
}
