using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace KoreaExpert.Weather;

public sealed class OpenMeteoWeatherProvider(
    HttpClient httpClient,
    IOptions<OpenMeteoOptions> options) : IWeatherProvider
{
    private const string ProviderName = "Open-Meteo (CC BY 4.0)";
    private const string AttributionUrl = "https://open-meteo.com/";
    private readonly OpenMeteoOptions _options = options.Value;

    public async Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        ValidateLocation(location);
        var path = BuildPath(
            location,
            new Dictionary<string, string?>
            {
                ["current"] = "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m"
            });

        using var document = await GetJsonAsync(path, cancellationToken);
        if (!document.RootElement.TryGetProperty("current", out var current)
            || current.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Open-Meteo returned an invalid current-weather object.");
        }

        var retrievedAt = DateTimeOffset.UtcNow;
        return new CurrentWeatherResult(
            ReadLocalTimestamp(document.RootElement, current, "time") ?? retrievedAt,
            DescribeWeatherCode(ReadInt32(current, "weather_code")),
            ReadDouble(current, "temperature_2m"),
            ReadDouble(current, "apparent_temperature"),
            ReadInt32(current, "relative_humidity_2m"),
            ReadDouble(current, "precipitation"),
            ReadDouble(current, "wind_speed_10m"),
            CreateSource(retrievedAt));
    }

    public async Task<IReadOnlyList<DailyWeatherResult>> GetDailyForecastAsync(
        WeatherLocation location,
        int days,
        CancellationToken cancellationToken = default)
    {
        ValidateLocation(location);
        ArgumentOutOfRangeException.ThrowIfLessThan(days, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, 16);

        var path = BuildPath(
            location,
            new Dictionary<string, string?>
            {
                ["daily"] = "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
                ["forecast_days"] = days.ToString(CultureInfo.InvariantCulture)
            });

        using var document = await GetJsonAsync(path, cancellationToken);
        if (!document.RootElement.TryGetProperty("daily", out var daily)
            || daily.ValueKind != JsonValueKind.Object
            || !daily.TryGetProperty("time", out var times)
            || times.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("Open-Meteo returned an invalid daily forecast object.");
        }

        var source = CreateSource(DateTimeOffset.UtcNow);
        var results = new List<DailyWeatherResult>(times.GetArrayLength());
        for (var index = 0; index < times.GetArrayLength(); index++)
        {
            var dateText = times[index].GetString();
            if (!DateOnly.TryParseExact(
                    dateText,
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out var date))
            {
                continue;
            }

            results.Add(new DailyWeatherResult(
                date,
                DescribeWeatherCode(ReadArrayInt32(daily, "weather_code", index)),
                ReadArrayDouble(daily, "temperature_2m_min", index),
                ReadArrayDouble(daily, "temperature_2m_max", index),
                ReadArrayInt32(daily, "precipitation_probability_max", index),
                source));
        }

        return results;
    }

    private string BuildPath(
        WeatherLocation location,
        IReadOnlyDictionary<string, string?> providerParameters)
    {
        var parameters = new Dictionary<string, string?>(providerParameters)
        {
            ["latitude"] = location.Latitude.ToString(CultureInfo.InvariantCulture),
            ["longitude"] = location.Longitude.ToString(CultureInfo.InvariantCulture),
            ["timezone"] = "Asia/Seoul"
        };
        if (!string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            parameters["apikey"] = _options.ApiKey;
        }

        return QueryHelpers.AddQueryString("forecast", parameters);
    }

    private async Task<JsonDocument> GetJsonAsync(
        string path,
        CancellationToken cancellationToken)
    {
        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await JsonDocument.ParseAsync(content, cancellationToken: cancellationToken);
    }

    private static void ValidateLocation(WeatherLocation location)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Latitude, -90);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Latitude, 90);
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Longitude, -180);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Longitude, 180);
    }

    private static WeatherSource CreateSource(DateTimeOffset retrievedAt) =>
        new(ProviderName, AttributionUrl, retrievedAt);

    private static DateTimeOffset? ReadLocalTimestamp(
        JsonElement root,
        JsonElement element,
        string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String
            || !DateTime.TryParseExact(
                property.GetString(),
                "yyyy-MM-dd'T'HH:mm",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var localTime))
        {
            return null;
        }

        var offsetSeconds = ReadInt32(root, "utc_offset_seconds") ?? 0;
        return new DateTimeOffset(
            DateTime.SpecifyKind(localTime, DateTimeKind.Unspecified),
            TimeSpan.FromSeconds(offsetSeconds));
    }

    private static double? ReadDouble(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.TryGetDouble(out var value)
            ? value
            : null;

    private static int? ReadInt32(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.TryGetInt32(out var value)
            ? value
            : null;

    private static double? ReadArrayDouble(
        JsonElement element,
        string propertyName,
        int index) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.Array
        && index < property.GetArrayLength()
        && property[index].TryGetDouble(out var value)
            ? value
            : null;

    private static int? ReadArrayInt32(
        JsonElement element,
        string propertyName,
        int index) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.Array
        && index < property.GetArrayLength()
        && property[index].TryGetInt32(out var value)
            ? value
            : null;

    private static string DescribeWeatherCode(int? code) => code switch
    {
        0 => "Clear sky",
        1 => "Mainly clear",
        2 => "Partly cloudy",
        3 => "Overcast",
        45 or 48 => "Fog",
        51 or 53 or 55 => "Drizzle",
        56 or 57 => "Freezing drizzle",
        61 or 63 or 65 => "Rain",
        66 or 67 => "Freezing rain",
        71 or 73 or 75 or 77 => "Snow",
        80 or 81 or 82 => "Rain showers",
        85 or 86 => "Snow showers",
        95 => "Thunderstorm",
        96 or 99 => "Thunderstorm with hail",
        _ => "Unknown conditions"
    };
}
