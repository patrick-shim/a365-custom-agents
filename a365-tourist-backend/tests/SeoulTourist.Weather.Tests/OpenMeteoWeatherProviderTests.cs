using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SeoulTourist.Weather;

namespace SeoulTourist.Weather.Tests;

[TestClass]
public sealed class OpenMeteoWeatherProviderTests
{
    [TestMethod]
    public async Task GetCurrentWeatherAsyncMapsValuesAndLocalOffset()
    {
        const string responseJson = """
            {
              "utc_offset_seconds": 32400,
              "current": {
                "time": "2026-08-08T14:15",
                "temperature_2m": 29.4,
                "apparent_temperature": 32.1,
                "relative_humidity_2m": 71,
                "precipitation": 0.2,
                "weather_code": 61,
                "wind_speed_10m": 8.7
              }
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateProvider(handler);

        var result = await provider.GetCurrentWeatherAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);

        Assert.IsNotNull(result);
        Assert.AreEqual("Rain", result.Summary);
        Assert.AreEqual(29.4, result.TemperatureCelsius);
        Assert.AreEqual(TimeSpan.FromHours(9), result.ObservedAt.Offset);
        Assert.AreEqual("Open-Meteo (CC BY 4.0)", result.Source.Name);
        StringAssert.Contains(handler.RequestUri!.Query, "timezone=Asia%2FSeoul");
        StringAssert.Contains(handler.RequestUri.Query, "current=");
    }

    [TestMethod]
    public async Task GetDailyForecastAsyncMapsParallelArrays()
    {
        const string responseJson = """
            {
              "daily": {
                "time": ["2026-08-08", "2026-08-09"],
                "weather_code": [2, 80],
                "temperature_2m_max": [31.2, 28.4],
                "temperature_2m_min": [23.1, 22.8],
                "precipitation_probability_max": [20, 75]
              }
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateProvider(handler);

        var results = await provider.GetDailyForecastAsync(
            new WeatherLocation(37.5665, 126.9780),
            2,
            TestContext.CancellationToken);

        Assert.HasCount(2, results);
        Assert.AreEqual(new DateOnly(2026, 8, 9), results[1].Date);
        Assert.AreEqual("Rain showers", results[1].Summary);
        Assert.AreEqual(75, results[1].MaximumPrecipitationProbabilityPercent);
        StringAssert.Contains(handler.RequestUri!.Query, "forecast_days=2");
    }

    [TestMethod]
    public async Task GetDailyForecastAsyncRejectsMoreThanSixteenDays()
    {
        var provider = CreateProvider(new RecordingHandler("{}"));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.GetDailyForecastAsync(
                new WeatherLocation(37.5665, 126.9780),
                17,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task OpenWeatherMapsCurrentConditionsAndAlertDetails()
    {
        const string currentJson = """
            {
              "timezone_offset": 32400,
              "data": [{
                "dt": 1786158900,
                "temp": 27.5,
                "feels_like": 30.2,
                "humidity": 74,
                "wind_speed": 2.5,
                "rain": { "1h": 1.4 },
                "weather": [{ "description": "moderate rain" }],
                "alerts": ["alert-1"]
              }]
            }
            """;
        const string alertJson = """
            {
              "id": "alert-1",
              "sender_name": "Korea Meteorological Administration",
              "event": "Heavy Rain Advisory",
              "start": 1786158000,
              "end": 1786172400,
              "description": "Heavy rain is expected."
            }
            """;
        var handler = new RoutingHandler(request =>
            request.RequestUri!.AbsolutePath.Contains("/alert/", StringComparison.Ordinal)
                ? CreateResponse(alertJson)
                : CreateResponse(currentJson));
        var provider = CreateOpenWeatherProvider(handler);

        var current = await provider.GetCurrentWeatherAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);
        var alerts = await provider.GetAlertsAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);

        Assert.IsNotNull(current);
        Assert.AreEqual("moderate rain", current.Summary);
        Assert.AreEqual(9.0, current.WindSpeedKilometersPerHour);
        Assert.HasCount(1, alerts);
        Assert.AreEqual("Heavy Rain Advisory", alerts[0].Event);
    }

    [TestMethod]
    public async Task FallbackProviderUsesOpenWeatherAfterPrimaryHttpFailure()
    {
        var primary = CreateProvider(new RoutingHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)));
        var fallback = CreateOpenWeatherProvider(new RoutingHandler(_ => CreateResponse("""
            {
              "data": [{
                "dt": 1786158900,
                "temp": 26.0,
                "weather": [{ "description": "clear sky" }]
              }]
            }
            """)));
        var options = Options.Create(CreateOpenWeatherOptions());
        var provider = new FallbackWeatherProvider(
            primary,
            fallback,
            options,
            NullLogger<FallbackWeatherProvider>.Instance);

        var result = await provider.GetCurrentWeatherAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);

        Assert.IsNotNull(result);
        Assert.AreEqual("OpenWeather One Call 4.0", result.Source.Name);
    }

    [TestMethod]
    public async Task FallbackProviderDoesNotHidePrimaryAuthenticationFailure()
    {
        var primary = CreateProvider(new RoutingHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.Unauthorized)));
        var fallback = CreateOpenWeatherProvider(new RoutingHandler(_ => CreateResponse(
            """
            {"data":[{"dt":1786158900,"temp":26.0,"weather":[{"description":"clear sky"}]}]}
            """)));
        var provider = new FallbackWeatherProvider(
            primary,
            fallback,
            Options.Create(CreateOpenWeatherOptions()),
            NullLogger<FallbackWeatherProvider>.Instance);

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetCurrentWeatherAsync(
                new WeatherLocation(37.5665, 126.9780),
                TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.Unauthorized, exception.StatusCode);
    }

    [TestMethod]
    public async Task MalformedPrimaryResponseUsesConfiguredFallback()
    {
        var primary = CreateProvider(new RecordingHandler("{}"));
        var fallback = CreateOpenWeatherProvider(new RoutingHandler(_ => CreateResponse(
            """
            {"data":[{"dt":1786158900,"temp":26.0,"weather":[{"description":"clear sky"}]}]}
            """)));
        var provider = new FallbackWeatherProvider(
            primary,
            fallback,
            Options.Create(CreateOpenWeatherOptions()),
            NullLogger<FallbackWeatherProvider>.Instance);

        var result = await provider.GetCurrentWeatherAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);

        Assert.IsNotNull(result);
        Assert.AreEqual("OpenWeather One Call 4.0", result.Source.Name);
    }

    [TestMethod]
    public async Task MissingCurrentObjectIsInvalidWithoutFallback()
    {
        var provider = CreateProvider(new RecordingHandler("{}"));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetCurrentWeatherAsync(
                new WeatherLocation(37.5665, 126.9780),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task UnavailableAlertProviderReturnsEmptyCollection()
    {
        var provider = new UnavailableWeatherAlertProvider();

        var alerts = await provider.GetAlertsAsync(
            new WeatherLocation(37.5665, 126.9780),
            TestContext.CancellationToken);

        Assert.IsEmpty(alerts);
    }

    public TestContext TestContext { get; set; } = null!;

    private static OpenMeteoWeatherProvider CreateProvider(HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.open-meteo.com/v1/")
        };
        return new OpenMeteoWeatherProvider(client, Options.Create(new OpenMeteoOptions()));
    }

    private static OpenWeatherOneCallProvider CreateOpenWeatherProvider(
        HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openweathermap.org/data/4.0/")
        };
        return new OpenWeatherOneCallProvider(
            client,
            Options.Create(CreateOpenWeatherOptions()));
    }

    private static OpenWeatherOptions CreateOpenWeatherOptions() => new()
    {
        Enabled = true,
        ApiKey = "test-api-key"
    };

    private static HttpResponseMessage CreateResponse(string responseJson) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
    };

    private sealed class RecordingHandler(string responseJson) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class RoutingHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responseFactory) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            Task.FromResult(responseFactory(request));
    }
}
