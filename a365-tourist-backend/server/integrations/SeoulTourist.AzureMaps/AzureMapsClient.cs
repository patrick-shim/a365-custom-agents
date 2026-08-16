using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using Azure.Core;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace SeoulTourist.AzureMaps;

public sealed class AzureMapsClient(
    HttpClient httpClient,
    TokenCredential credential,
    IOptions<AzureMapsOptions> options)
{
    private static readonly string[] TokenScopes = ["https://atlas.microsoft.com/.default"];
    private readonly AzureMapsOptions _options = options.Value;

    public async Task<IReadOnlyList<PlaceResult>> SearchPointsOfInterestAsync(
        string query,
        GeoPoint center,
        int radiusMeters,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(query);
        ArgumentOutOfRangeException.ThrowIfLessThan(radiusMeters, 1);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);

        var path = QueryHelpers.AddQueryString(
            "search/poi/json",
            new Dictionary<string, string?>
            {
                ["api-version"] = "1.0",
                ["query"] = query,
                ["lat"] = center.Latitude.ToString(CultureInfo.InvariantCulture),
                ["lon"] = center.Longitude.ToString(CultureInfo.InvariantCulture),
                ["radius"] = radiusMeters.ToString(CultureInfo.InvariantCulture),
                ["limit"] = limit.ToString(CultureInfo.InvariantCulture),
                ["language"] = "ko-KR"
            });

        using var document = await GetJsonAsync(path, cancellationToken);
        if (!document.RootElement.TryGetProperty("results", out var results))
        {
            return [];
        }

        return results
            .EnumerateArray()
            .Select(ParsePlace)
            .Where(place => place is not null)
            .Cast<PlaceResult>()
            .ToArray();
    }

    public async Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        GeoPoint location,
        CancellationToken cancellationToken = default)
    {
        var query = string.Create(
            CultureInfo.InvariantCulture,
            $"{location.Latitude},{location.Longitude}");
        var path = QueryHelpers.AddQueryString(
            "weather/currentConditions/json",
            new Dictionary<string, string?>
            {
                ["api-version"] = "1.1",
                ["query"] = query,
                ["unit"] = "metric",
                ["language"] = "ko-KR"
            });

        using var document = await GetJsonAsync(path, cancellationToken);
        if (!document.RootElement.TryGetProperty("results", out var results)
            || results.GetArrayLength() == 0)
        {
            return null;
        }

        var weather = results[0];
        return new CurrentWeatherResult(
            ReadDateTimeOffset(weather, "dateTime") ?? DateTimeOffset.UtcNow,
            ReadString(weather, "phrase") ?? "Unknown",
            ReadNestedDouble(weather, "temperature", "value"),
            ReadInt32(weather, "relativeHumidity"),
            ReadNestedDouble(weather, "wind", "speed", "value"),
            ReadBoolean(weather, "hasPrecipitation"));
    }

    public async Task<IReadOnlyList<DailyWeatherResult>> GetDailyForecastAsync(
        GeoPoint location,
        int days,
        CancellationToken cancellationToken = default)
    {
        if (days is not (1 or 5 or 10 or 15 or 25 or 45))
        {
            throw new ArgumentOutOfRangeException(
                nameof(days),
                days,
                "Azure Maps supports 1, 5, 10, 15, 25, or 45 forecast days.");
        }

        var query = string.Create(
            CultureInfo.InvariantCulture,
            $"{location.Latitude},{location.Longitude}");
        var path = QueryHelpers.AddQueryString(
            "weather/forecast/daily/json",
            new Dictionary<string, string?>
            {
                ["api-version"] = "1.1",
                ["query"] = query,
                ["duration"] = days.ToString(CultureInfo.InvariantCulture),
                ["unit"] = "metric",
                ["language"] = "ko-KR"
            });

        using var document = await GetJsonAsync(path, cancellationToken);
        if (!document.RootElement.TryGetProperty("forecasts", out var forecasts))
        {
            return [];
        }

        return forecasts.EnumerateArray().Select(ParseForecast).ToArray();
    }

    private async Task<JsonDocument> GetJsonAsync(string path, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.ClientId))
        {
            throw new InvalidOperationException(
                "AzureMaps:ClientId must be configured with the Azure Maps account client ID.");
        }

        var accessToken = await credential.GetTokenAsync(
            new TokenRequestContext(TokenScopes),
            cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.Token);
        request.Headers.Add("x-ms-client-id", _options.ClientId);

        using var response = await httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await JsonDocument.ParseAsync(content, cancellationToken: cancellationToken);
    }

    private static PlaceResult? ParsePlace(JsonElement result)
    {
        if (!result.TryGetProperty("poi", out var pointOfInterest)
            || !result.TryGetProperty("position", out var position))
        {
            return null;
        }

        var name = ReadString(pointOfInterest, "name");
        var latitude = ReadDouble(position, "lat");
        var longitude = ReadDouble(position, "lon");
        if (string.IsNullOrWhiteSpace(name) || latitude is null || longitude is null)
        {
            return null;
        }

        var category = pointOfInterest.TryGetProperty("categories", out var categories)
            && categories.ValueKind == JsonValueKind.Array
            ? string.Join(", ", categories.EnumerateArray().Select(item => item.GetString()))
            : null;
        var address = result.TryGetProperty("address", out var addressElement)
            ? ReadString(addressElement, "freeformAddress")
            : null;

        return new PlaceResult(
            name,
            category,
            address,
            new GeoPoint(latitude.Value, longitude.Value),
            ReadDouble(result, "dist"));
    }

    private static DailyWeatherResult ParseForecast(JsonElement forecast)
    {
        var date = ReadDateTimeOffset(forecast, "date")?.Date ?? DateTime.UtcNow.Date;
        var daySummary = forecast.TryGetProperty("day", out var day)
            ? ReadString(day, "phrase")
            : null;
        var nightSummary = forecast.TryGetProperty("night", out var night)
            ? ReadString(night, "phrase")
            : null;
        var hasPrecipitation = (forecast.TryGetProperty("day", out day)
                && ReadBoolean(day, "hasPrecipitation"))
            || (forecast.TryGetProperty("night", out night)
                && ReadBoolean(night, "hasPrecipitation"));

        return new DailyWeatherResult(
            DateOnly.FromDateTime(date),
            daySummary,
            nightSummary,
            ReadNestedDouble(forecast, "temperature", "minimum", "value"),
            ReadNestedDouble(forecast, "temperature", "maximum", "value"),
            hasPrecipitation);
    }

    private static string? ReadString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

    private static double? ReadDouble(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.TryGetDouble(out var value)
            ? value
            : null;

    private static int? ReadInt32(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property) && property.TryGetInt32(out var value)
            ? value
            : null;

    private static bool ReadBoolean(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind is JsonValueKind.True or JsonValueKind.False
        && property.GetBoolean();

    private static DateTimeOffset? ReadDateTimeOffset(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
        && property.TryGetDateTimeOffset(out var value)
            ? value
            : null;

    private static double? ReadNestedDouble(JsonElement element, params string[] path)
    {
        var current = element;
        foreach (var propertyName in path)
        {
            if (!current.TryGetProperty(propertyName, out current))
            {
                return null;
            }
        }

        return current.TryGetDouble(out var value) ? value : null;
    }
}
