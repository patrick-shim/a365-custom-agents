using System.ComponentModel;
using JapanExpert.Mcp.Hosting;
using JapanExpert.Weather;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Weather;

/// <summary>
/// Japan weather tools. The Japan Meteorological Agency is authoritative for forecasts and
/// warnings; current conditions come from a clearly labelled third-party model source.
/// </summary>
[McpServerToolType]
public sealed class WeatherTools(
    ICurrentWeatherProvider currentWeatherProvider,
    IWeatherForecastProvider weatherForecastProvider,
    IWeatherAlertProvider weatherAlertProvider,
    ILogger<WeatherTools> logger)
{
    [McpServerTool(Name = "get_japan_current_weather")]
    [Description(
        "Gets current weather conditions for a point in Japan from the MET Norway Locationforecast "
        + "service operated by the Norwegian Meteorological Institute. This is a clearly labelled "
        + "third-party model estimate and is not a Japan Meteorological Agency observation, "
        + "forecast, or warning.")]
    public Task<CurrentWeatherResult?> GetJapanCurrentWeatherAsync(
        [Description("Latitude inside Japan. Defaults to central Tokyo.")]
        double latitude = WeatherLocation.DefaultLatitude,
        [Description("Longitude inside Japan. Defaults to central Tokyo.")]
        double longitude = WeatherLocation.DefaultLongitude,
        CancellationToken cancellationToken = default)
    {
        var location = new WeatherLocation(latitude, longitude).EnsureWithinJapan();
        return McpToolExecution.RunAsync(
            "weather.current",
            logger,
            token => currentWeatherProvider.GetCurrentWeatherAsync(location, token),
            cancellationToken);
    }

    [McpServerTool(Name = "get_japan_weather_forecast")]
    [Description(
        "Gets the official Japan Meteorological Agency daily forecast for a Japanese prefecture. "
        + "Japanese forecast text is returned verbatim alongside an English summary derived from "
        + "JMA weather codes.")]
    public Task<WeatherForecastResult> GetJapanWeatherForecastAsync(
        [Description("Japanese prefecture name in English or Japanese, such as Tokyo, Kyoto, or 北海道.")]
        string prefecture = JapanAreaCatalog.DefaultPrefecture,
        [Description(
            "Optional explicit JMA forecast office code, such as 130000 for Tokyo. When supplied it "
            + "overrides the prefecture name.")]
        string? officeCode = null,
        [Description("Forecast duration from 1 through 7 days.")]
        int days = 5,
        CancellationToken cancellationToken = default)
    {
        var area = JapanAreaCatalog.Resolve(prefecture, officeCode);
        ArgumentOutOfRangeException.ThrowIfLessThan(days, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, IWeatherForecastProvider.MaximumDays);

        return McpToolExecution.RunAsync(
            "weather.forecast",
            logger,
            token => weatherForecastProvider.GetForecastAsync(area, days, token),
            cancellationToken);
    }

    [McpServerTool(Name = "get_japan_weather_alerts")]
    [Description(
        "Gets current Japan Meteorological Agency warning, advisory, and alert bulletin headlines "
        + "for a Japanese prefecture from the documented JMA XML feed. Each result links to the "
        + "authoritative JMA document.")]
    public Task<IReadOnlyList<WeatherAlert>> GetJapanWeatherAlertsAsync(
        [Description("Japanese prefecture name in English or Japanese, such as Tokyo, Kyoto, or 北海道.")]
        string prefecture = JapanAreaCatalog.DefaultPrefecture,
        [Description(
            "Optional explicit JMA forecast office code, such as 130000 for Tokyo. When supplied it "
            + "overrides the prefecture name.")]
        string? officeCode = null,
        [Description("Maximum number of bulletins, from 1 through 25.")]
        int limit = 10,
        CancellationToken cancellationToken = default)
    {
        var area = JapanAreaCatalog.Resolve(prefecture, officeCode);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, IWeatherAlertProvider.MaximumAlerts);

        return McpToolExecution.RunAsync(
            "weather.alerts",
            logger,
            token => weatherAlertProvider.GetAlertsAsync(area, limit, token),
            cancellationToken);
    }
}
