using System.Net;

namespace JapanExpert.Weather.Tests;

[TestClass]
public sealed class JmaForecastProviderTests
{
    /// <summary>
    /// Recorded shape of the 2026 JMA bosai prefecture forecast payload for Tokyo (130000),
    /// trimmed to the series this backend consumes.
    /// </summary>
    private const string TokyoForecastJson = """
        [
          {
            "publishingOffice": "気象庁",
            "reportDatetime": "2026-08-30T17:00:00+09:00",
            "timeSeries": [
              {
                "timeDefines": [
                  "2026-08-30T17:00:00+09:00",
                  "2026-08-31T00:00:00+09:00",
                  "2026-09-01T00:00:00+09:00"
                ],
                "areas": [
                  {
                    "area": { "name": "東京地方", "code": "130010" },
                    "weatherCodes": ["101", "200", "313"],
                    "weathers": [
                      "晴れ　時々　くもり",
                      "くもり",
                      "雨　のち　くもり"
                    ]
                  }
                ]
              },
              {
                "timeDefines": [
                  "2026-08-30T18:00:00+09:00",
                  "2026-08-31T00:00:00+09:00",
                  "2026-09-01T00:00:00+09:00"
                ],
                "areas": [
                  {
                    "area": { "name": "東京地方", "code": "130010" },
                    "pops": ["10", "30", "70"]
                  }
                ]
              }
            ]
          },
          {
            "publishingOffice": "気象庁",
            "reportDatetime": "2026-08-30T17:00:00+09:00",
            "timeSeries": [
              {
                "timeDefines": [
                  "2026-08-31T00:00:00+09:00",
                  "2026-09-01T00:00:00+09:00",
                  "2026-09-02T00:00:00+09:00"
                ],
                "areas": [
                  {
                    "area": { "name": "東京地方", "code": "130010" },
                    "weatherCodes": ["200", "313", "100"],
                    "pops": ["30", "70", "10"]
                  }
                ]
              },
              {
                "timeDefines": [
                  "2026-08-31T00:00:00+09:00",
                  "2026-09-01T00:00:00+09:00",
                  "2026-09-02T00:00:00+09:00"
                ],
                "areas": [
                  {
                    "area": { "name": "東京", "code": "44132" },
                    "tempsMin": ["25", "24", "26"],
                    "tempsMax": ["33", "29", "34"]
                  }
                ]
              }
            ]
          }
        ]
        """;

    [TestMethod]
    public async Task MapsTokyoForecastWithJmaAttributionAndPreservedJapaneseText()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson);
        var provider = WeatherTestFactory.CreateForecastProvider(handler);

        var forecast = await provider.GetForecastAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            3,
            TestContext.CancellationToken);

        Assert.AreEqual("130000", forecast.OfficeCode);
        Assert.AreEqual("Tokyo", forecast.PrefectureEnglish);
        Assert.AreEqual("東京都", forecast.PrefectureJapanese);
        Assert.AreEqual("東京地方", forecast.AreaName);
        Assert.AreEqual("気象庁", forecast.PublishingOffice);
        Assert.HasCount(3, forecast.Days);

        Assert.AreEqual(new DateOnly(2026, 8, 30), forecast.Days[0].Date);
        Assert.AreEqual("晴れ 時々 くもり", forecast.Days[0].SummaryJapanese);
        Assert.AreEqual("Clear at times cloudy", forecast.Days[0].Summary);
        Assert.AreEqual("101", forecast.Days[0].WeatherCode);
        Assert.AreEqual(10, forecast.Days[0].MaximumPrecipitationProbabilityPercent);

        Assert.AreEqual(new DateOnly(2026, 9, 1), forecast.Days[2].Date);
        Assert.AreEqual("Rain later cloudy", forecast.Days[2].Summary);
        Assert.AreEqual(70, forecast.Days[2].MaximumPrecipitationProbabilityPercent);
        Assert.AreEqual(24, forecast.Days[2].MinimumTemperatureCelsius);
        Assert.AreEqual(29, forecast.Days[2].MaximumTemperatureCelsius);

        StringAssert.Contains(forecast.Source.Name, "Japan Meteorological Agency");
        Assert.AreEqual(JmaForecastProvider.AttributionUrl, forecast.Source.AttributionUrl);
        StringAssert.Contains(forecast.Source.Notice, "strict schema and freshness guard");
        StringAssert.Contains(forecast.Source.Notice, "Japan Tourist Assistant transformation");
        Assert.AreEqual(WeatherTestFactory.Now, forecast.Source.RetrievedAt);
    }

    [TestMethod]
    public async Task RequestsTheResolvedOfficeCodeForEachPrefecture()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson);
        var provider = WeatherTestFactory.CreateForecastProvider(handler);

        await provider.GetForecastAsync(
            JapanAreaCatalog.Resolve("Kyoto"),
            1,
            TestContext.CancellationToken);

        Assert.AreEqual(
            "https://www.jma.go.jp/bosai/forecast/data/forecast/260000.json",
            handler.RequestUri!.AbsoluteUri);
    }

    [TestMethod]
    public async Task HonorsAConfiguredForecastEndpoint()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson);
        var provider = WeatherTestFactory.CreateForecastProvider(
            handler,
            new JmaOptions { ForecastBaseAddress = "https://mirror.example.test/jma/forecast/" });

        await provider.GetForecastAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            1,
            TestContext.CancellationToken);

        Assert.AreEqual(
            "https://mirror.example.test/jma/forecast/130000.json",
            handler.RequestUri!.AbsoluteUri);
    }

    [TestMethod]
    public async Task RejectsLegacyObjectPayloadExplicitly()
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, """{"publishingOffice":"気象庁"}"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "legacy or unsupported payload");
    }

    [TestMethod]
    public async Task RejectsLegacyContainerMarkers()
    {
        const string legacyJson = """
            [
              {
                "publishingOffice": "気象庁",
                "reportDatetime": "2026-08-30T17:00:00+09:00",
                "srf": { "timeSeries": [] },
                "timeSeries": [
                  {
                    "timeDefines": ["2026-08-30T17:00:00+09:00"],
                    "areas": [{ "area": { "name": "東京地方", "code": "130010" } }]
                  }
                ]
              }
            ]
            """;
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, legacyJson));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "legacy bosai payload");
    }

    [TestMethod]
    public async Task RejectsSeriesThatNoLongerAlignWithTimeDefines()
    {
        const string driftedJson = """
            [
              {
                "publishingOffice": "気象庁",
                "reportDatetime": "2026-08-30T17:00:00+09:00",
                "timeSeries": [
                  {
                    "timeDefines": ["2026-08-30T17:00:00+09:00", "2026-08-31T00:00:00+09:00"],
                    "areas": [
                      {
                        "area": { "name": "東京地方", "code": "130010" },
                        "weathers": ["晴れ"]
                      }
                    ]
                  }
                ]
              }
            ]
            """;
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, driftedJson));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "did not align with timeDefines");
    }

    [TestMethod]
    public async Task RejectsMissingReportTimestamp()
    {
        const string undatedJson = """
            [
              {
                "publishingOffice": "気象庁",
                "timeSeries": [
                  {
                    "timeDefines": ["2026-08-30T17:00:00+09:00"],
                    "areas": [{ "area": { "name": "東京地方", "code": "130010" } }]
                  }
                ]
              }
            ]
            """;
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, undatedJson));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "reportDatetime");
    }

    [TestMethod]
    public async Task RejectsStaleForecastPayload()
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson),
            now: new DateTimeOffset(2026, 9, 3, 9, 0, 0, TimeSpan.Zero));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "stale");
    }

    [TestMethod]
    public async Task RejectsImplausibleFutureReportTimestamp()
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson),
            now: new DateTimeOffset(2026, 8, 25, 9, 0, 0, TimeSpan.Zero));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(8)]
    public async Task RejectsForecastHorizonOutsideContractBounds(int days)
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                days,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RateLimitedForecastEndpointSurfacesTooManyRequests()
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.TooManyRequests, "busy", "text/plain"));

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.TooManyRequests, exception.StatusCode);
    }

    [TestMethod]
    public async Task DisabledForecastSourceFailsExplicitly()
    {
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson),
            new JmaOptions { ForecastEnabled = false });

        await Assert.ThrowsExactlyAsync<InvalidOperationException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CallerCancellationIsPropagated()
    {
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();
        var provider = WeatherTestFactory.CreateForecastProvider(
            new RecordingHandler(HttpStatusCode.OK, TokyoForecastJson));

        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() =>
            provider.GetForecastAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                3,
                cancellation.Token));
    }

    public TestContext TestContext { get; set; } = null!;
}
