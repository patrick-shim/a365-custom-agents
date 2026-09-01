using JapanExpert.ExchangeRates;
using JapanExpert.Mcp.Currency;
using JapanExpert.Mcp.Weather;
using Microsoft.Extensions.Logging.Abstractions;

namespace JapanExpert.Mcp.Tools.Tests;

[TestClass]
public sealed class CurrencyToolsTests
{
    [TestMethod]
    public void ConvertCurrencyWithRateDefaultsToYenAndDropsDecimals()
    {
        var result = new CurrencyTools().ConvertCurrency(
            120.50m,
            " usd ",
            147.32m,
            rateObservedAt: new DateTimeOffset(2026, 8, 28, 0, 0, 0, TimeSpan.Zero));

        Assert.AreEqual("USD", result.SourceCurrency);
        Assert.AreEqual("JPY", result.TargetCurrency);
        Assert.AreEqual(17_752m, result.TargetAmount);
        Assert.AreEqual("17,752 JPY", result.FormattedTargetAmount);
        Assert.AreEqual(0, result.TargetCurrencyDecimalDigits);
    }

    [TestMethod]
    public void ConvertCurrencyWithRateKeepsMinorUnitsForTwoDecimalTargets()
    {
        var result = new CurrencyTools().ConvertCurrency(10_000m, "JPY", 0.006787m, "USD");

        Assert.AreEqual(67.87m, result.TargetAmount);
        Assert.AreEqual("67.87 USD", result.FormattedTargetAmount);
        Assert.AreEqual(2, result.TargetCurrencyDecimalDigits);
    }

    [TestMethod]
    public void ConvertCurrencyWithRateRejectsInvalidCurrencyCode() =>
        Assert.ThrowsExactly<ArgumentException>(() =>
            new CurrencyTools().ConvertCurrency(10m, "US", 150m));

    [TestMethod]
    public void ConvertCurrencyWithRateRejectsNonPositiveRate() =>
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() =>
            new CurrencyTools().ConvertCurrency(10m, "USD", 0m));

    [TestMethod]
    public void ConvertCurrencyWithRateRejectsNegativeAmount() =>
        Assert.ThrowsExactly<ArgumentOutOfRangeException>(() =>
            new CurrencyTools().ConvertCurrency(-1m, "USD", 147.32m));

    [TestMethod]
    public async Task ConvertCurrencyAsyncDefaultsToYenAndReturnsProvenance()
    {
        var provider = new ToolStubs.StubExchangeRateProvider();
        var tools = new ExchangeRateTools(provider, NullLogger<ExchangeRateTools>.Instance);

        var result = await tools.ConvertCurrencyAsync(
            120.50m,
            "USD",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual("JPY", provider.LastTargetCurrency);
        Assert.AreEqual(17_752m, result.TargetAmount);
        Assert.AreEqual("17,752 JPY", result.FormattedTargetAmount);
        Assert.AreEqual(0, result.TargetCurrencyDecimalDigits);
        Assert.AreEqual(new DateOnly(2026, 8, 28), result.Quote.ObservationDate);
        StringAssert.Contains(result.Quote.Source.Name, "European Central Bank");
        StringAssert.Contains(result.Quote.Source.AttributionUrl, "frankfurter.dev");
    }

    [TestMethod]
    public async Task GetExchangeRateAsyncRejectsMalformedDates()
    {
        var tools = new ExchangeRateTools(
            new ToolStubs.StubExchangeRateProvider(),
            NullLogger<ExchangeRateTools>.Instance);

        await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            tools.GetExchangeRateAsync(
                "USD",
                date: "28-08-2026",
                cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task GetExchangeRateAsyncPassesHistoricalDatesThrough()
    {
        var tools = new ExchangeRateTools(
            new ToolStubs.StubExchangeRateProvider(),
            NullLogger<ExchangeRateTools>.Instance);

        var quote = await tools.GetExchangeRateAsync(
            "USD",
            date: "2026-08-27",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(new DateOnly(2026, 8, 27), quote.ObservationDate);
        Assert.AreEqual("JPY", quote.TargetCurrency);
    }

    public TestContext TestContext { get; set; } = null!;
}

[TestClass]
public sealed class WeatherToolsBoundaryTests
{
    [TestMethod]
    public async Task ForecastToolResolvesThePrefectureToAJmaOfficeCode()
    {
        var forecastProvider = new ToolStubs.StubForecastProvider();
        var tools = CreateTools(forecastProvider: forecastProvider);

        var result = await tools.GetJapanWeatherForecastAsync(
            "Kyoto",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual("260000", forecastProvider.LastArea!.OfficeCode);
        Assert.AreEqual(5, forecastProvider.LastDays);
        Assert.AreEqual("260000", result.OfficeCode);
    }

    [TestMethod]
    public async Task ForecastToolHonorsAnExplicitOfficeCode()
    {
        var forecastProvider = new ToolStubs.StubForecastProvider();
        var tools = CreateTools(forecastProvider: forecastProvider);

        await tools.GetJapanWeatherForecastAsync(
            "Tokyo",
            "016000",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual("016000", forecastProvider.LastArea!.OfficeCode);
    }

    [TestMethod]
    public async Task ForecastToolRejectsUnknownPrefectures()
    {
        var tools = CreateTools();

        await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            tools.GetJapanWeatherForecastAsync(
                "Seoul",
                cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(8)]
    public async Task ForecastToolRejectsHorizonsOutsideBounds(int days)
    {
        var tools = CreateTools();

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            tools.GetJapanWeatherForecastAsync(
                days: days,
                cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(26)]
    public async Task AlertToolRejectsLimitsOutsideBounds(int limit)
    {
        var tools = CreateTools();

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            tools.GetJapanWeatherAlertsAsync(
                limit: limit,
                cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task AlertToolDefaultsToTokyo()
    {
        var alertProvider = new ToolStubs.StubAlertProvider();
        var tools = CreateTools(alertProvider: alertProvider);

        await tools.GetJapanWeatherAlertsAsync(cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual("130000", alertProvider.LastArea!.OfficeCode);
        Assert.AreEqual(10, alertProvider.LastLimit);
    }

    [TestMethod]
    public async Task CurrentWeatherToolRejectsCoordinatesOutsideJapan()
    {
        var tools = CreateTools();

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            tools.GetJapanCurrentWeatherAsync(
                37.5665,
                126.9780,
                TestContext.CancellationToken));
    }

    public TestContext TestContext { get; set; } = null!;

    private static WeatherTools CreateTools(
        ToolStubs.StubForecastProvider? forecastProvider = null,
        ToolStubs.StubAlertProvider? alertProvider = null) =>
        new(
            new ToolStubs.StubCurrentWeatherProvider(),
            forecastProvider ?? new ToolStubs.StubForecastProvider(),
            alertProvider ?? new ToolStubs.StubAlertProvider(),
            NullLogger<WeatherTools>.Instance);
}
