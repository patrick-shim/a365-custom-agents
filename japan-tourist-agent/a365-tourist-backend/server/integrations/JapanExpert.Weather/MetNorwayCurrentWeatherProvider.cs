using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather;

/// <summary>
/// Clearly labelled third-party current-conditions source. MET Norway is the Norwegian
/// Meteorological Institute; its output is a model estimate and is never presented as a Japan
/// Meteorological Agency observation, forecast, or warning.
/// </summary>
public sealed class MetNorwayCurrentWeatherProvider(
    HttpClient httpClient,
    IOptions<MetNorwayOptions> options,
    TimeProvider timeProvider) : ICurrentWeatherProvider
{
    /// <summary>Attribution name for the labelled third-party current-conditions source.</summary>
    public const string ProviderName =
        "MET Norway Locationforecast 2.0 (Norwegian Meteorological Institute, third party)";

    /// <summary>Attribution link for the labelled third-party current-conditions source.</summary>
    public const string AttributionUrl =
        "https://api.met.no/weatherapi/locationforecast/2.0/documentation";

    private const string LicenseNotice =
        "Norwegian Licence for Open Government Data (NLOD) 2.0 and Creative Commons Attribution 4.0";

    private const string ScopeNotice =
        "Third-party model estimate from the Norwegian Meteorological Institute. This is not a "
        + "Japan Meteorological Agency observation, forecast, or warning. Use the JMA forecast and "
        + "alert tools for authoritative Japanese guidance.";

    private readonly MetNorwayOptions _options = options.Value;

    public async Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(location);
        location.EnsureWithinJapan();

        if (!_options.Enabled)
        {
            throw new InvalidOperationException(
                "The MET Norway current-conditions source is disabled by configuration.");
        }

        var path = QueryHelpers.AddQueryString(
            "compact",
            new Dictionary<string, string?>
            {
                ["lat"] = FormatCoordinate(location.Latitude, _options.CoordinateDecimals),
                ["lon"] = FormatCoordinate(location.Longitude, _options.CoordinateDecimals)
            });

        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.UserAgent.ParseAdd(_options.UserAgent);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var response = await httpClient.SendAsync(request, cancellationToken);
        EnsureUsableResponse(response.StatusCode);

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        if (!document.RootElement.TryGetProperty("properties", out var properties)
            || properties.ValueKind != JsonValueKind.Object
            || !properties.TryGetProperty("timeseries", out var timeseries)
            || timeseries.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "The MET Norway response did not use the documented Locationforecast envelope.");
        }

        if (timeseries.GetArrayLength() == 0)
        {
            return null;
        }

        var first = timeseries[0];
        if (!first.TryGetProperty("data", out var data)
            || !data.TryGetProperty("instant", out var instant)
            || !instant.TryGetProperty("details", out var details)
            || details.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException(
                "The MET Norway response did not contain instant observation details.");
        }

        var symbolCode = ReadSymbolCode(data);
        return new CurrentWeatherResult(
            ReadTimestamp(first, "time") ?? timeProvider.GetUtcNow(),
            MetNorwaySymbols.Describe(symbolCode),
            symbolCode,
            ReadDouble(details, "air_temperature"),
            ReadInt32(details, "relative_humidity"),
            ReadPrecipitation(data),
            ReadDouble(details, "wind_speed") is { } metersPerSecond
                ? Math.Round(metersPerSecond * 3.6, 1, MidpointRounding.AwayFromZero)
                : null,
            new WeatherSource(
                ProviderName,
                AttributionUrl,
                LicenseNotice,
                ScopeNotice,
                timeProvider.GetUtcNow()));
    }

    /// <summary>Truncates a coordinate; MET Norway rejects more than four decimal places.</summary>
    internal static string FormatCoordinate(double value, int decimals)
    {
        var scale = Math.Pow(10, decimals);
        var truncated = Math.Truncate(value * scale) / scale;
        return truncated.ToString(
            "0." + new string('#', decimals),
            CultureInfo.InvariantCulture);
    }

    private static void EnsureUsableResponse(HttpStatusCode statusCode)
    {
        if (statusCode == HttpStatusCode.TooManyRequests)
        {
            throw new HttpRequestException(
                "The MET Norway endpoint rate-limited this request.",
                inner: null,
                HttpStatusCode.TooManyRequests);
        }

        if (statusCode == HttpStatusCode.Forbidden)
        {
            throw new HttpRequestException(
                "The MET Norway endpoint refused this request; the configured user agent may be rejected.",
                inner: null,
                HttpStatusCode.Forbidden);
        }

        if ((int)statusCode >= 400)
        {
            throw new HttpRequestException(
                "The MET Norway endpoint is temporarily unavailable.",
                inner: null,
                statusCode);
        }
    }

    private static string? ReadSymbolCode(JsonElement data)
    {
        string[] windows = ["next_1_hours", "next_6_hours", "next_12_hours"];
        foreach (var window in windows)
        {
            if (data.TryGetProperty(window, out var forecast)
                && forecast.TryGetProperty("summary", out var summary)
                && summary.TryGetProperty("symbol_code", out var symbol)
                && symbol.ValueKind == JsonValueKind.String)
            {
                return symbol.GetString();
            }
        }

        return null;
    }

    private static double? ReadPrecipitation(JsonElement data) =>
        data.TryGetProperty("next_1_hours", out var window)
        && window.TryGetProperty("details", out var details)
            ? ReadDouble(details, "precipitation_amount")
            : null;

    private static DateTimeOffset? ReadTimestamp(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
        && DateTimeOffset.TryParse(
            property.GetString(),
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var value)
            ? value
            : null;

    private static double? ReadDouble(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.Number
        && property.TryGetDouble(out var value)
            ? value
            : null;

    private static int? ReadInt32(JsonElement element, string propertyName) =>
        ReadDouble(element, propertyName) is { } value
            ? (int)Math.Round(value, MidpointRounding.AwayFromZero)
            : null;
}

/// <summary>Documented transformation of MET Norway symbol codes into short English text.</summary>
public static class MetNorwaySymbols
{
    private static readonly (string Prefix, string English)[] Descriptions =
    [
        ("clearsky", "Clear sky"),
        ("fair", "Fair"),
        ("partlycloudy", "Partly cloudy"),
        ("cloudy", "Cloudy"),
        ("fog", "Fog"),
        ("lightrainshowersandthunder", "Light rain showers and thunder"),
        ("rainshowersandthunder", "Rain showers and thunder"),
        ("heavyrainshowersandthunder", "Heavy rain showers and thunder"),
        ("lightrainshowers", "Light rain showers"),
        ("rainshowers", "Rain showers"),
        ("heavyrainshowers", "Heavy rain showers"),
        ("lightsleetshowers", "Light sleet showers"),
        ("sleetshowers", "Sleet showers"),
        ("heavysleetshowers", "Heavy sleet showers"),
        ("lightsnowshowers", "Light snow showers"),
        ("snowshowers", "Snow showers"),
        ("heavysnowshowers", "Heavy snow showers"),
        ("lightrainandthunder", "Light rain and thunder"),
        ("rainandthunder", "Rain and thunder"),
        ("heavyrainandthunder", "Heavy rain and thunder"),
        ("lightrain", "Light rain"),
        ("heavyrain", "Heavy rain"),
        ("rain", "Rain"),
        ("lightsleet", "Light sleet"),
        ("heavysleet", "Heavy sleet"),
        ("sleet", "Sleet"),
        ("lightsnow", "Light snow"),
        ("heavysnow", "Heavy snow"),
        ("snow", "Snow")
    ];

    /// <summary>Maps a MET Norway symbol code such as <c>partlycloudy_day</c> to English text.</summary>
    public static string Describe(string? symbolCode)
    {
        if (string.IsNullOrWhiteSpace(symbolCode))
        {
            return "Unknown conditions";
        }

        var normalized = symbolCode.Trim().ToUpperInvariant();
        var separator = normalized.IndexOf('_', StringComparison.Ordinal);
        var suffix = separator >= 0 ? normalized[(separator + 1)..] : string.Empty;
        var stem = separator >= 0 ? normalized[..separator] : normalized;

        foreach (var (prefix, english) in Descriptions)
        {
            if (string.Equals(stem, prefix.ToUpperInvariant(), StringComparison.Ordinal))
            {
                return suffix switch
                {
                    "DAY" => $"{english} (day)",
                    "NIGHT" => $"{english} (night)",
                    "POLARTWILIGHT" => $"{english} (polar twilight)",
                    _ => english
                };
            }
        }

        return "Unknown conditions";
    }
}
