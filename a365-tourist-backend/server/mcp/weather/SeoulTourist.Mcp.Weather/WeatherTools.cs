using System.ComponentModel;
using ModelContextProtocol.Server;
using SeoulTourist.Mcp.Hosting;
using SeoulTourist.Weather;

namespace SeoulTourist.Mcp.Weather;

[McpServerToolType]
public sealed class WeatherTools(
    IWeatherProvider weatherProvider,
    IWeatherAlertProvider weatherAlertProvider,
    ILogger<WeatherTools> logger)
{
    [McpServerTool(Name = "get_seoul_current_weather")]
    [Description("Gets attributed current weather for a location in Seoul.")]
    public Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        [Description("Latitude in Seoul.")] double latitude = 37.5665,
        [Description("Longitude in Seoul.")] double longitude = 126.9780,
        CancellationToken cancellationToken = default) =>
        McpToolExecution.RunAsync(
            "weather.current",
            logger,
            token => weatherProvider.GetCurrentWeatherAsync(
                new WeatherLocation(latitude, longitude),
                token),
            cancellationToken);

    [McpServerTool(Name = "get_seoul_weather_forecast")]
    [Description("Gets an attributed daily weather forecast for itinerary planning in Seoul.")]
    public Task<IReadOnlyList<DailyWeatherResult>> GetWeatherForecastAsync(
        [Description("Latitude in Seoul.")] double latitude = 37.5665,
        [Description("Longitude in Seoul.")] double longitude = 126.9780,
        [Description("Forecast duration from 1 through 16 days.")]
        int days = 5,
        CancellationToken cancellationToken = default) =>
        McpToolExecution.RunAsync(
            "weather.forecast",
            logger,
            token => weatherProvider.GetDailyForecastAsync(
                new WeatherLocation(latitude, longitude),
                days,
                token),
            cancellationToken);

    [McpServerTool(Name = "get_seoul_weather_alerts")]
    [Description("Gets current government weather alerts for a location in Seoul when the optional alert provider is configured.")]
    public Task<IReadOnlyList<WeatherAlert>> GetWeatherAlertsAsync(
        [Description("Latitude in Seoul.")] double latitude = 37.5665,
        [Description("Longitude in Seoul.")] double longitude = 126.9780,
        CancellationToken cancellationToken = default) =>
        McpToolExecution.RunAsync(
            "weather.alerts",
            logger,
            token => weatherAlertProvider.GetAlertsAsync(
                new WeatherLocation(latitude, longitude),
                token),
            cancellationToken);
}
