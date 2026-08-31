using System.Net;

namespace JapanExpert.Weather.Tests;

[TestClass]
public sealed class MetNorwayCurrentWeatherProviderTests
{
    /// <summary>Recorded shape of the MET Norway Locationforecast 2.0 compact payload.</summary>
    private const string TokyoCompactJson = """
        {
          "type": "Feature",
          "properties": {
            "meta": {
              "updated_at": "2026-08-30T08:31:53Z",
              "units": { "air_temperature": "celsius" }
            },
            "timeseries": [
              {
                "time": "2026-08-30T09:00:00Z",
                "data": {
                  "instant": {
                    "details": {
                      "air_temperature": 28.7,
                      "relative_humidity": 71.4,
                      "wind_speed": 3.5
                    }
                  },
                  "next_1_hours": {
                    "summary": { "symbol_code": "partlycloudy_day" },
                    "details": { "precipitation_amount": 0.4 }
                  }
                }
              }
            ]
          }
        }
        """;

    [TestMethod]
    public async Task MapsCurrentConditionsAndLabelsTheThirdPartySource()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoCompactJson);
        var provider = WeatherTestFactory.CreateCurrentProvider(handler);

        var result = await provider.GetCurrentWeatherAsync(
            WeatherLocation.Default,
            TestContext.CancellationToken);

        Assert.IsNotNull(result);
        Assert.AreEqual(
            new DateTimeOffset(2026, 8, 30, 9, 0, 0, TimeSpan.Zero),
            result.ObservedAt);
        Assert.AreEqual("Partly cloudy (day)", result.Summary);
        Assert.AreEqual("partlycloudy_day", result.SymbolCode);
        Assert.AreEqual(28.7, result.TemperatureCelsius);
        Assert.AreEqual(71, result.RelativeHumidityPercent);
        Assert.AreEqual(0.4, result.PrecipitationMillimeters);
        Assert.AreEqual(12.6, result.WindSpeedKilometersPerHour);

        StringAssert.Contains(result.Source.Name, "MET Norway");
        StringAssert.Contains(result.Source.Name, "third party");
        Assert.AreEqual(MetNorwayCurrentWeatherProvider.AttributionUrl, result.Source.AttributionUrl);
        StringAssert.Contains(
            result.Source.Notice,
            "not a Japan Meteorological Agency observation, forecast, or warning");
    }

    [TestMethod]
    public async Task TruncatesCoordinatesAndSendsAnIdentifyingUserAgent()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoCompactJson);
        var provider = WeatherTestFactory.CreateCurrentProvider(handler);

        await provider.GetCurrentWeatherAsync(
            new WeatherLocation(35.676212345, 139.650312345),
            TestContext.CancellationToken);

        StringAssert.Contains(handler.RequestUri!.Query, "lat=35.6762");
        StringAssert.Contains(handler.RequestUri.Query, "lon=139.6503");
        Assert.DoesNotContain("35.67621", handler.RequestUri.Query, StringComparison.Ordinal);
        StringAssert.Contains(handler.UserAgent!, "JapanExpertTests/1.0");
        StringAssert.Contains(
            handler.RequestUri.AbsolutePath,
            "/weatherapi/locationforecast/2.0/compact");
    }

    [TestMethod]
    public async Task RejectsCoordinatesOutsideJapan()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoCompactJson));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.GetCurrentWeatherAsync(
                new WeatherLocation(37.5665, 126.9780),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RejectsResponsesWithoutTheDocumentedEnvelope()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(
            new RecordingHandler(HttpStatusCode.OK, """{"type":"Feature"}"""));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetCurrentWeatherAsync(
                WeatherLocation.Default,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RejectsResponsesWithoutInstantDetails()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(new RecordingHandler(
            HttpStatusCode.OK,
            """{"properties":{"timeseries":[{"time":"2026-08-30T09:00:00Z","data":{}}]}}"""));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetCurrentWeatherAsync(
                WeatherLocation.Default,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task EmptyTimeSeriesReturnsNoObservation()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(
            new RecordingHandler(HttpStatusCode.OK, """{"properties":{"timeseries":[]}}"""));

        var result = await provider.GetCurrentWeatherAsync(
            WeatherLocation.Default,
            TestContext.CancellationToken);

        Assert.IsNull(result);
    }

    [TestMethod]
    public async Task RateLimitSurfacesTooManyRequests()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(
            new RecordingHandler(HttpStatusCode.TooManyRequests, "slow down", "text/plain"));

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetCurrentWeatherAsync(
                WeatherLocation.Default,
                TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.TooManyRequests, exception.StatusCode);
    }

    [TestMethod]
    public async Task DisabledSourceFailsExplicitly()
    {
        var provider = WeatherTestFactory.CreateCurrentProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoCompactJson),
            new MetNorwayOptions
            {
                Enabled = false,
                UserAgent = WeatherTestFactory.TestUserAgent
            });

        await Assert.ThrowsExactlyAsync<InvalidOperationException>(() =>
            provider.GetCurrentWeatherAsync(
                WeatherLocation.Default,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public void DefaultUserAgentIsSourceSafeAndContactable()
    {
        var userAgent = new MetNorwayOptions().UserAgent;

        Assert.AreEqual(
            "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/a365-custom-agents)",
            userAgent);
        StringAssert.Contains(userAgent, "+https://github.com/patrick-shim/a365-custom-agents");
        Assert.DoesNotContain("@", userAgent, StringComparison.Ordinal);
        Assert.DoesNotContain("TODO", userAgent, StringComparison.OrdinalIgnoreCase);
        Assert.IsTrue(new MetNorwayOptions().IsValid());
    }

    [TestMethod]
    public async Task DefaultUserAgentIsSentOnEveryMetNorwayRequest()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoCompactJson);
        var provider = WeatherTestFactory.CreateCurrentProvider(handler, new MetNorwayOptions());

        await provider.GetCurrentWeatherAsync(
            WeatherLocation.Default,
            TestContext.CancellationToken);

        Assert.AreEqual(
            "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/a365-custom-agents)",
            handler.UserAgent);
    }

    [TestMethod]
    [DataRow("JapanExpertMcp/1.0")]
    [DataRow("curl/8.0")]
    [DataRow("   ")]
    public void UserAgentWithoutAContactReferenceIsRejected(string userAgent) =>
        Assert.IsFalse(new MetNorwayOptions { UserAgent = userAgent }.IsValid());

    [TestMethod]
    [DataRow("JapanExpertMcp/1.0 (+https://contoso.example/japan-expert)")]
    [DataRow("JapanExpertMcp/1.0 (mailto:ops@contoso.example)")]
    public void OperatorSuppliedContactableAgentIsAccepted(string userAgent) =>
        Assert.IsTrue(new MetNorwayOptions { UserAgent = userAgent }.IsValid());

    public TestContext TestContext { get; set; } = null!;
}

[TestClass]
public sealed class JapanAreaCatalogTests
{
    [TestMethod]
    public void DefaultsToTheDocumentedTokyoOfficeCode()
    {
        Assert.AreEqual("130000", JapanAreaCatalog.Resolve(prefecture: null).OfficeCode);
        Assert.AreEqual("130000", JapanAreaCatalog.Resolve("Tokyo").OfficeCode);
        Assert.AreEqual("130000", JapanAreaCatalog.Resolve("東京都").OfficeCode);
    }

    [TestMethod]
    [DataRow("Hokkaido", "016000")]
    [DataRow("Kyoto", "260000")]
    [DataRow("Osaka-fu", "270000")]
    [DataRow("Hiroshima Prefecture", "340000")]
    [DataRow("kanagawa", "140000")]
    [DataRow("Kagoshima", "460100")]
    [DataRow("Okinawa", "471000")]
    [DataRow("沖縄県", "471000")]
    public void ResolvesEveryDocumentedPrefectureForm(string prefecture, string expectedOfficeCode) =>
        Assert.AreEqual(expectedOfficeCode, JapanAreaCatalog.Resolve(prefecture).OfficeCode);

    [TestMethod]
    public void ExplicitOfficeCodeOverridesThePrefectureName() =>
        Assert.AreEqual(
            "014100",
            JapanAreaCatalog.Resolve("Tokyo", "014100").OfficeCode);

    [TestMethod]
    public void CoversAllFortySevenPrefectures()
    {
        string[] prefectures =
        [
            "Hokkaido", "Aomori", "Iwate", "Miyagi", "Akita", "Yamagata", "Fukushima",
            "Ibaraki", "Tochigi", "Gunma", "Saitama", "Chiba", "Tokyo", "Kanagawa",
            "Niigata", "Toyama", "Ishikawa", "Fukui", "Yamanashi", "Nagano",
            "Gifu", "Shizuoka", "Aichi", "Mie", "Shiga", "Kyoto", "Osaka", "Hyogo",
            "Nara", "Wakayama", "Tottori", "Shimane", "Okayama", "Hiroshima", "Yamaguchi",
            "Tokushima", "Kagawa", "Ehime", "Kochi", "Fukuoka", "Saga", "Nagasaki",
            "Kumamoto", "Oita", "Miyazaki", "Kagoshima", "Okinawa"
        ];

        Assert.HasCount(47, prefectures);
        foreach (var prefecture in prefectures)
        {
            Assert.IsNotNull(JapanAreaCatalog.Resolve(prefecture).OfficeCode);
        }
    }

    [TestMethod]
    public void RejectsUnknownPrefectureWithGuidance()
    {
        var exception = Assert.ThrowsExactly<ArgumentException>(() =>
            JapanAreaCatalog.Resolve("Seoul"));

        StringAssert.Contains(exception.Message, "Supported prefectures are");
    }

    [TestMethod]
    public void RejectsUndocumentedOfficeCode()
    {
        var exception = Assert.ThrowsExactly<ArgumentException>(() =>
            JapanAreaCatalog.Resolve("Tokyo", "999999"));

        StringAssert.Contains(exception.Message, "documented JMA forecast office code");
    }
}

[TestClass]
public sealed class JmaWeatherSummaryTests
{
    [TestMethod]
    [DataRow("晴れ　時々　くもり", "101", "Clear at times cloudy")]
    [DataRow("雨　のち　くもり", "313", "Rain later cloudy")]
    [DataRow("くもり", "200", "Cloudy")]
    [DataRow("雪", "400", "Snow")]
    public void TranslatesJapaneseForecastText(string japanese, string code, string expected) =>
        Assert.AreEqual(expected, JmaWeatherSummary.Describe(japanese, code));

    [TestMethod]
    [DataRow("100", "Clear")]
    [DataRow("200", "Cloudy")]
    [DataRow("300", "Rain")]
    [DataRow("400", "Snow")]
    [DataRow(null, "Unknown conditions")]
    public void FallsBackToTheWeatherCodeBand(string? code, string expected) =>
        Assert.AreEqual(expected, JmaWeatherSummary.Describe(japanese: null, code));
}
