using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates.Tests;

[TestClass]
public sealed class ExchangeRateProviderTests
{
    private const string FrankfurterJpyJson = """
        [
          {
            "date": "2026-08-28",
            "base": "USD",
            "quote": "JPY",
            "rate": 159.68
          }
        ]
        """;

    private const string EcbCrossRateCsv = """
        KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
        EXR.D.JPY.EUR.SP00.A,D,JPY,EUR,SP00,A,2026-08-28,171.15
        EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-08-28,1.1620
        """;

    [TestMethod]
    public async Task FrankfurterUsesV2RatesRouteWithEcbProviderQuery()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, FrankfurterJpyJson);
        var provider = CreateFrankfurterProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "usd",
            "jpy",
            cancellationToken: TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual("USD", quote.SourceCurrency);
        Assert.AreEqual("JPY", quote.TargetCurrency);
        Assert.AreEqual(159.68m, quote.Rate);
        Assert.AreEqual(new DateOnly(2026, 8, 28), quote.ObservationDate);
        Assert.AreEqual(
            new DateTimeOffset(2026, 8, 28, 0, 0, 0, TimeSpan.Zero),
            quote.ObservedAt);

        Assert.AreEqual("/v2/rates", handler.RequestUri!.AbsolutePath);
        StringAssert.Contains(handler.RequestUri.Query, "base=USD");
        StringAssert.Contains(handler.RequestUri.Query, "quotes=JPY");
        StringAssert.Contains(handler.RequestUri.Query, "providers=ECB");
        Assert.DoesNotContain(
            "symbols=",
            handler.RequestUri.Query,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            "/latest",
            handler.RequestUri.AbsolutePath,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            "convert",
            handler.RequestUri.AbsoluteUri,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            "amount=",
            handler.RequestUri.Query,
            StringComparison.OrdinalIgnoreCase);
        Assert.IsNull(handler.AuthorizationHeader);

        StringAssert.Contains(quote.Source.Name, "European Central Bank");
        Assert.AreEqual(FrankfurterExchangeRateProvider.AttributionUrl, quote.Source.AttributionUrl);
        StringAssert.Contains(quote.Source.RateType, "ECB");
        StringAssert.Contains(quote.Source.FreshnessNote, "not transaction rates");
    }

    [TestMethod]
    public void DefaultBaseAddressTargetsTheV2Prefix()
    {
        var baseAddress = new FrankfurterOptions().BaseAddress;

        Assert.AreEqual("https://api.frankfurter.dev/v2/", baseAddress);
        Assert.IsTrue(new FrankfurterOptions().IsValid());
    }

    [TestMethod]
    public async Task FrankfurterHistoricalRequestUsesTheDateQueryParameter()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, FrankfurterJpyJson);
        var provider = CreateFrankfurterProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "USD",
            "JPY",
            new DateOnly(2026, 8, 28),
            TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual("/v2/rates", handler.RequestUri!.AbsolutePath);
        StringAssert.Contains(handler.RequestUri.Query, "date=2026-08-28");
        StringAssert.Contains(handler.RequestUri.Query, "providers=ECB");
        StringAssert.Contains(quote.Source.RateType, "Historical");
    }

    [TestMethod]
    public async Task FrankfurterAcceptsAHistoricalRowResolvedToAnEarlierWorkingDay()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """[{"date":"2026-08-28","base":"USD","quote":"JPY","rate":159.68}]"""));

        var quote = await provider.TryGetRateAsync(
            "USD",
            "JPY",
            new DateOnly(2026, 8, 30),
            TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(new DateOnly(2026, 8, 28), quote.ObservationDate);
    }

    [TestMethod]
    public async Task FrankfurterRejectsAnObservationDatedAfterTheRequestedDate()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """[{"date":"2026-08-30","base":"USD","quote":"JPY","rate":159.68}]"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                new DateOnly(2026, 8, 28),
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "dated after the requested date");
    }

    [TestMethod]
    public async Task FrankfurterRejectsTheLegacyV1ObjectEnvelope()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """{"amount":1.0,"base":"USD","date":"2026-08-28","rates":{"JPY":147.32}}"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "JSON array of rate rows");
    }

    [TestMethod]
    public async Task FrankfurterRejectsMultipleRowsForASingleQuoteRequest()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """
            [
              {"date":"2026-08-28","base":"USD","quote":"JPY","rate":159.68},
              {"date":"2026-08-28","base":"USD","quote":"KRW","rate":1381.25}
            ]
            """));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "more than one rate row");
    }

    [TestMethod]
    public async Task FrankfurterRejectsAMismatchedBaseCurrency()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """[{"date":"2026-08-28","base":"EUR","quote":"JPY","rate":171.15}]"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "different base currency");
    }

    [TestMethod]
    public async Task FrankfurterRejectsAMismatchedQuoteCurrency()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """[{"date":"2026-08-28","base":"USD","quote":"KRW","rate":1381.25}]"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "different quote currency");
    }

    [TestMethod]
    [DataRow("""[{"date":"2026-08-28","base":"USD","quote":"JPY","rate":0}]""")]
    [DataRow("""[{"date":"2026-08-28","base":"USD","quote":"JPY","rate":-159.68}]""")]
    [DataRow("""[{"date":"2026-08-28","base":"USD","quote":"JPY","rate":"159.68"}]""")]
    [DataRow("""[{"date":"2026-08-28","base":"USD","quote":"JPY"}]""")]
    public async Task FrankfurterRejectsANonPositiveOrNonNumericRate(string body)
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(HttpStatusCode.OK, body));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "positive numeric rate");
    }

    [TestMethod]
    public async Task FrankfurterRejectsAMissingObservationDate()
    {
        var provider = CreateFrankfurterProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """[{"base":"USD","quote":"JPY","rate":159.68}]"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.TryGetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "valid observation date");
    }

    [TestMethod]
    public async Task FrankfurterReturnsNothingWhenNoRowIsPublished()
    {
        var provider = CreateFrankfurterProvider(
            new RecordingHandler(HttpStatusCode.OK, "[]"));

        Assert.IsNull(await provider.TryGetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task FrankfurterReturnsNothingWhenDisabled()
    {
        var provider = CreateFrankfurterProvider(
            new RecordingHandler(HttpStatusCode.OK, FrankfurterJpyJson),
            new FrankfurterOptions { Enabled = false });

        Assert.IsNull(await provider.TryGetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task EcbSdmxDerivesEuroCrossRatesLocally()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv");
        var provider = CreateEcbProvider(handler);

        var quote = await provider.TryGetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(decimal.Round(171.15m / 1.1620m, 6), decimal.Round(quote.Rate, 6));
        Assert.AreEqual(new DateOnly(2026, 8, 28), quote.ObservationDate);
        StringAssert.Contains(handler.RequestUri!.AbsolutePath, "D.USD+JPY.EUR.SP00.A");
        StringAssert.Contains(handler.RequestUri.Query, "format=csvdata");
        StringAssert.Contains(handler.RequestUri.Query, "lastNObservations=1");
        StringAssert.Contains(quote.Source.Name, "European Central Bank");
        StringAssert.Contains(quote.Source.FreshnessNote, "EUR cross rates");
    }

    [TestMethod]
    public async Task EcbSdmxTreatsEuroAsUnity()
    {
        const string euroCsv = """
            KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
            EXR.D.JPY.EUR.SP00.A,D,JPY,EUR,SP00,A,2026-08-28,171.15
            """;
        var provider = CreateEcbProvider(
            new RecordingHandler(HttpStatusCode.OK, euroCsv, "text/csv"));

        var quote = await provider.TryGetRateAsync(
            "EUR",
            "JPY",
            cancellationToken: TestContext.CancellationToken);

        Assert.IsNotNull(quote);
        Assert.AreEqual(171.15m, quote.Rate);
    }

    [TestMethod]
    public async Task EcbSdmxHistoricalRequestUsesTheLookbackWindow()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv");
        var provider = CreateEcbProvider(handler);

        await provider.TryGetRateAsync(
            "USD",
            "JPY",
            new DateOnly(2026, 8, 28),
            TestContext.CancellationToken);

        StringAssert.Contains(handler.RequestUri!.Query, "startPeriod=2026-08-21");
        StringAssert.Contains(handler.RequestUri.Query, "endPeriod=2026-08-28");
    }

    [TestMethod]
    public void EcbSdmxRejectsObservationsFromDifferentPublicationDates()
    {
        const string mixedCsv = """
            KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
            EXR.D.JPY.EUR.SP00.A,D,JPY,EUR,SP00,A,2026-08-28,171.15
            EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-08-27,1.1610
            """;

        var exception = Assert.ThrowsExactly<InvalidDataException>(() =>
            EcbSdmxExchangeRateProvider.ParseCsv(mixedCsv, ["USD", "JPY"]));

        StringAssert.Contains(exception.Message, "different publication");
    }

    [TestMethod]
    public void EcbSdmxRejectsUnexpectedCsvColumns()
    {
        const string driftedCsv = """
            KEY,FREQ,CCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,PERIOD,VALUE
            EXR.D.JPY.EUR.SP00.A,D,JPY,EUR,SP00,A,2026-08-28,171.15
            """;

        Assert.ThrowsExactly<InvalidDataException>(() =>
            EcbSdmxExchangeRateProvider.ParseCsv(driftedCsv, ["JPY"]));
    }

    [TestMethod]
    public async Task EcbSdmxReturnsNothingWhenTheSeriesIsMissing()
    {
        var provider = CreateEcbProvider(
            new RecordingHandler(HttpStatusCode.NotFound, string.Empty, "text/plain"));

        Assert.IsNull(await provider.TryGetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task FrankfurterOutageFallsBackToTheDirectEcbSource()
    {
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(
                new RecordingHandler(HttpStatusCode.ServiceUnavailable, string.Empty, "text/plain")),
            CreateEcbProvider(new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv")),
            NullLogger<ExchangeRateProvider>.Instance);

        var quote = await provider.GetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(EcbSdmxExchangeRateProvider.ProviderName, quote.Source.Name);
    }

    [TestMethod]
    public async Task FrankfurterSchemaDriftFallsBackToTheDirectEcbSource()
    {
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(new RecordingHandler(
                HttpStatusCode.OK,
                """{"amount":1.0,"base":"USD","date":"2026-08-28","rates":{"JPY":147.32}}""")),
            CreateEcbProvider(new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv")),
            NullLogger<ExchangeRateProvider>.Instance);

        var quote = await provider.GetRateAsync(
            "USD",
            "JPY",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(EcbSdmxExchangeRateProvider.ProviderName, quote.Source.Name);
    }

    [TestMethod]
    public async Task AuthorizationFailureIsNotHiddenBehindTheFallback()
    {
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(
                new RecordingHandler(HttpStatusCode.Unauthorized, string.Empty, "text/plain")),
            CreateEcbProvider(new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv")),
            NullLogger<ExchangeRateProvider>.Instance);

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.Unauthorized, exception.StatusCode);
    }

    [TestMethod]
    public async Task ExhaustedProvidersFailWithoutInventingARate()
    {
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(new RecordingHandler(HttpStatusCode.OK, "[]")),
            CreateEcbProvider(
                new RecordingHandler(HttpStatusCode.NotFound, string.Empty, "text/plain")),
            NullLogger<ExchangeRateProvider>.Instance);

        await Assert.ThrowsExactlyAsync<InvalidOperationException>(() =>
            provider.GetRateAsync(
                "USD",
                "JPY",
                cancellationToken: TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task IdentityConversionShortCircuitsWithoutAProviderCall()
    {
        var frankfurter = new RecordingHandler(HttpStatusCode.OK, FrankfurterJpyJson);
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(frankfurter),
            CreateEcbProvider(new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv")),
            NullLogger<ExchangeRateProvider>.Instance);

        var quote = await provider.GetRateAsync(
            "JPY",
            "jpy",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(1m, quote.Rate);
        Assert.AreEqual("Identity conversion", quote.Source.Name);
        Assert.IsNull(frankfurter.RequestUri);
    }

    [TestMethod]
    public async Task InvalidCurrencyCodesAreRejectedAtTheBoundary()
    {
        var provider = new ExchangeRateProvider(
            CreateFrankfurterProvider(new RecordingHandler(HttpStatusCode.OK, FrankfurterJpyJson)),
            CreateEcbProvider(new RecordingHandler(HttpStatusCode.OK, EcbCrossRateCsv, "text/csv")),
            NullLogger<ExchangeRateProvider>.Instance);

        await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            provider.GetRateAsync(
                "US",
                "JPY",
                cancellationToken: TestContext.CancellationToken));
    }

    public TestContext TestContext { get; set; } = null!;

    private static FrankfurterExchangeRateProvider CreateFrankfurterProvider(
        HttpMessageHandler handler,
        FrankfurterOptions? options = null)
    {
        var resolved = options ?? new FrankfurterOptions();
        return new FrankfurterExchangeRateProvider(
            new HttpClient(handler) { BaseAddress = new Uri(resolved.BaseAddress) },
            Options.Create(resolved));
    }

    private static EcbSdmxExchangeRateProvider CreateEcbProvider(HttpMessageHandler handler)
    {
        var options = new EcbSdmxOptions();
        return new EcbSdmxExchangeRateProvider(
            new HttpClient(handler) { BaseAddress = new Uri(options.BaseAddress) },
            Options.Create(options));
    }

    private sealed class RecordingHandler(
        HttpStatusCode statusCode,
        string body,
        string mediaType = "application/json") : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        public string? AuthorizationHeader { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            AuthorizationHeader = request.Headers.Authorization?.ToString();
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(body, Encoding.UTF8, mediaType)
            });
        }
    }
}

[TestClass]
public sealed class CurrencyCodesTests
{
    [TestMethod]
    public void JapaneseYenIsTheDefaultTravelCurrency()
    {
        Assert.AreEqual(
            "JPY",
            CurrencyCodes.Normalize(CurrencyCodes.DefaultTravelCurrency, "currency"));
        Assert.AreEqual(0, CurrencyCodes.GetDecimalDigits(CurrencyCodes.DefaultTravelCurrency));
    }

    [TestMethod]
    [DataRow("JPY", 0)]
    [DataRow("jpy", 0)]
    [DataRow("USD", 2)]
    [DataRow("EUR", 2)]
    [DataRow("KWD", 3)]
    public void MinorUnitDigitsFollowIso4217(string currency, int expected) =>
        Assert.AreEqual(expected, CurrencyCodes.GetDecimalDigits(currency));

    [TestMethod]
    public void YenAmountsRoundAndFormatWithoutDecimals()
    {
        Assert.AreEqual(1_818m, CurrencyCodes.Round(1_817.9m, "JPY"));
        Assert.AreEqual("1,818 JPY", CurrencyCodes.Format(1_817.9m, "JPY"));
    }

    [TestMethod]
    public void TwoDecimalCurrenciesKeepMinorUnitsWithBankersRounding()
    {
        Assert.AreEqual(12.34m, CurrencyCodes.Round(12.345m, "USD"));
        Assert.AreEqual(12.36m, CurrencyCodes.Round(12.355m, "USD"));
        Assert.AreEqual("1,234.56 USD", CurrencyCodes.Format(1_234.559m, "USD"));
    }

    [TestMethod]
    public void MalformedCodesAreRejected() =>
        Assert.ThrowsExactly<ArgumentException>(() =>
            CurrencyCodes.Normalize("JP1", "currency"));
}
