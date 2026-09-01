using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace KoreaExpert.Weather;

public sealed class OpenWeatherOneCallProvider(
    HttpClient httpClient,
    IOptions<OpenWeatherOptions> options) : IWeatherProvider, IWeatherAlertProvider
{
    private const string ProviderName = "OpenWeather One Call 4.0";
    private const string AttributionUrl = "https://openweathermap.org/";
    private readonly OpenWeatherOptions _options = options.Value;

    public async Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        EnsureEnabled();
        using var document = await GetJsonAsync(
            BuildPath("onecall/current", location),
            cancellationToken);
        if (!TryGetFirstDataItem(document.RootElement, out var current))
        {
            return null;
        }

        var retrievedAt = DateTimeOffset.UtcNow;
        var offset = ReadOffset(document.RootElement);
        var rain = ReadNestedDouble(current, "rain", "1h") ?? 0;
        var snow = ReadNestedDouble(current, "snow", "1h") ?? 0;
        return new CurrentWeatherResult(
            ReadUnixTimestamp(current, "dt")?.ToOffset(offset) ?? retrievedAt,
            ReadWeatherDescription(current),
            ReadDouble(current, "temp"),
            ReadDouble(current, "feels_like"),
            ReadInt32(current, "humidity"),
            rain + snow,
            ReadDouble(current, "wind_speed") is { } windMetersPerSecond
                ? windMetersPerSecond * 3.6
                : null,
            CreateSource(retrievedAt));
    }

    public async Task<IReadOnlyList<DailyWeatherResult>> GetDailyForecastAsync(
        WeatherLocation location,
        int days,
        CancellationToken cancellationToken = default)
    {
        EnsureEnabled();
        ArgumentOutOfRangeException.ThrowIfLessThan(days, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, 16);

        var path = BuildPath(
            "onecall/timeline/1day",
            location,
            new Dictionary<string, string?>
            {
                ["cnt"] = Math.Min(days, 10).ToString(CultureInfo.InvariantCulture)
            });
        var results = new List<DailyWeatherResult>(days);
        var pagesRemaining = 2;

        while (results.Count < days && path is not null && pagesRemaining-- > 0)
        {
            using var document = await GetJsonAsync(path, cancellationToken);
            AppendDailyResults(document.RootElement, results, days);
            path = ReadValidatedNextPath(document.RootElement);
        }

        return results;
    }

    public async Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        if (!_options.Enabled)
        {
            return [];
        }

        using var currentDocument = await GetJsonAsync(
            BuildPath("onecall/current", location),
            cancellationToken);
        if (!TryGetFirstDataItem(currentDocument.RootElement, out var current)
            || !current.TryGetProperty("alerts", out var alertIds)
            || alertIds.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        var results = new List<WeatherAlert>();
        foreach (var alertIdElement in alertIds.EnumerateArray())
        {
            var alertId = alertIdElement.GetString();
            if (string.IsNullOrWhiteSpace(alertId)
                || results.Count >= _options.MaximumAlerts)
            {
                continue;
            }

            var path = QueryHelpers.AddQueryString(
                $"onecall/alert/{Uri.EscapeDataString(alertId)}",
                "appid",
                _options.ApiKey);
            using var alertDocument = await GetJsonAsync(path, cancellationToken);
            var alert = ParseAlert(alertDocument.RootElement, alertId);
            if (alert is not null)
            {
                results.Add(alert);
            }
        }

        return results;
    }

    private string BuildPath(
        string endpoint,
        WeatherLocation location,
        IReadOnlyDictionary<string, string?>? extraParameters = null)
    {
        ValidateLocation(location);
        var parameters = extraParameters is null
            ? new Dictionary<string, string?>()
            : new Dictionary<string, string?>(extraParameters);
        parameters["lat"] = location.Latitude.ToString(CultureInfo.InvariantCulture);
        parameters["lon"] = location.Longitude.ToString(CultureInfo.InvariantCulture);
        parameters["units"] = "metric";
        parameters["lang"] = "en";
        parameters["appid"] = _options.ApiKey;
        return QueryHelpers.AddQueryString(endpoint, parameters);
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

    private void EnsureEnabled()
    {
        if (!_options.Enabled || string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            throw new InvalidOperationException(
                "OpenWeather must be enabled with a One Call 4.0 API key before use.");
        }
    }

    private string? ReadValidatedNextPath(JsonElement root)
    {
        if (!root.TryGetProperty("next", out var property)
            || property.ValueKind != JsonValueKind.String
            || !Uri.TryCreate(property.GetString(), UriKind.Absolute, out var nextUri)
            || httpClient.BaseAddress is not { } baseAddress
            || !string.Equals(nextUri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(nextUri.Host, baseAddress.Host, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return nextUri.PathAndQuery;
    }

    private static void AppendDailyResults(
        JsonElement root,
        List<DailyWeatherResult> results,
        int limit)
    {
        if (!root.TryGetProperty("data", out var data)
            || data.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        var source = CreateSource(DateTimeOffset.UtcNow);
        var offset = ReadOffset(root);
        foreach (var daily in data.EnumerateArray())
        {
            if (results.Count >= limit || ReadUnixTimestamp(daily, "dt") is not { } timestamp)
            {
                break;
            }

            var probability = ReadDouble(daily, "pop");
            results.Add(new DailyWeatherResult(
                DateOnly.FromDateTime(timestamp.ToOffset(offset).Date),
                ReadWeatherDescription(daily),
                ReadNestedDouble(daily, "temp", "min"),
                ReadNestedDouble(daily, "temp", "max"),
                probability is null
                    ? null
                    : (int)Math.Round(
                        Math.Clamp(probability.Value, 0, 1) * 100,
                        MidpointRounding.AwayFromZero),
                source));
        }
    }

    private static WeatherAlert? ParseAlert(JsonElement alert, string fallbackId)
    {
        var sender = ReadString(alert, "sender_name");
        var eventName = ReadString(alert, "event");
        var description = ReadString(alert, "description");
        var startsAt = ReadUnixTimestamp(alert, "start");
        var endsAt = ReadUnixTimestamp(alert, "end");
        if (string.IsNullOrWhiteSpace(sender)
            || string.IsNullOrWhiteSpace(eventName)
            || string.IsNullOrWhiteSpace(description)
            || startsAt is null
            || endsAt is null)
        {
            return null;
        }

        return new WeatherAlert(
            ReadString(alert, "id") ?? fallbackId,
            sender,
            eventName,
            startsAt.Value,
            endsAt.Value,
            description,
            CreateSource(DateTimeOffset.UtcNow));
    }

    private static bool TryGetFirstDataItem(JsonElement root, out JsonElement item)
    {
        if (root.TryGetProperty("data", out var data))
        {
            if (data.ValueKind == JsonValueKind.Object)
            {
                item = data;
                return true;
            }

            if (data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0)
            {
                item = data[0];
                return true;
            }
        }

        item = default;
        return false;
    }

    private static string ReadWeatherDescription(JsonElement element)
    {
        if (element.TryGetProperty("weather", out var weather)
            && weather.ValueKind == JsonValueKind.Array
            && weather.GetArrayLength() > 0)
        {
            return ReadString(weather[0], "description") ?? "Unknown conditions";
        }

        return "Unknown conditions";
    }

    private static WeatherSource CreateSource(DateTimeOffset retrievedAt) =>
        new(ProviderName, AttributionUrl, retrievedAt);

    private static TimeSpan ReadOffset(JsonElement root) =>
        TimeSpan.FromSeconds(ReadInt32(root, "timezone_offset") ?? 0);

    private static string? ReadString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

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

    private static double? ReadNestedDouble(
        JsonElement element,
        string parentName,
        string propertyName) =>
        element.TryGetProperty(parentName, out var parent)
        && parent.TryGetProperty(propertyName, out var property)
        && property.TryGetDouble(out var value)
            ? value
            : null;

    private static DateTimeOffset? ReadUnixTimestamp(
        JsonElement element,
        string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.TryGetInt64(out var value)
            ? DateTimeOffset.FromUnixTimeSeconds(value)
            : null;

    private static void ValidateLocation(WeatherLocation location)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Latitude, -90);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Latitude, 90);
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Longitude, -180);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Longitude, 180);
    }
}
