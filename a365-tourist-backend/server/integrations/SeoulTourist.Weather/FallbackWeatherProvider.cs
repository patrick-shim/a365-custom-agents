using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace SeoulTourist.Weather;

public sealed partial class FallbackWeatherProvider(
    OpenMeteoWeatherProvider primary,
    OpenWeatherOneCallProvider fallback,
    IOptions<OpenWeatherOptions> options,
    ILogger<FallbackWeatherProvider> logger) : IWeatherProvider
{
    private readonly OpenWeatherOptions _options = options.Value;

    public async Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var result = await primary.GetCurrentWeatherAsync(location, cancellationToken);
            return result ?? await GetFallbackCurrentAsync(location, cancellationToken);
        }
        catch (Exception exception) when (CanFallback(exception, cancellationToken))
        {
            LogPrimaryFailure(logger, exception.GetType().Name);
            return await fallback.GetCurrentWeatherAsync(location, cancellationToken);
        }
    }

    public async Task<IReadOnlyList<DailyWeatherResult>> GetDailyForecastAsync(
        WeatherLocation location,
        int days,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var results = await primary.GetDailyForecastAsync(location, days, cancellationToken);
            return results.Count > 0
                ? results
                : await GetFallbackForecastAsync(location, days, cancellationToken);
        }
        catch (Exception exception) when (CanFallback(exception, cancellationToken))
        {
            LogPrimaryFailure(logger, exception.GetType().Name);
            return await fallback.GetDailyForecastAsync(location, days, cancellationToken);
        }
    }

    private Task<CurrentWeatherResult?> GetFallbackCurrentAsync(
        WeatherLocation location,
        CancellationToken cancellationToken) =>
        _options.Enabled
            ? fallback.GetCurrentWeatherAsync(location, cancellationToken)
            : Task.FromResult<CurrentWeatherResult?>(null);

    private Task<IReadOnlyList<DailyWeatherResult>> GetFallbackForecastAsync(
        WeatherLocation location,
        int days,
        CancellationToken cancellationToken) =>
        _options.Enabled
            ? fallback.GetDailyForecastAsync(location, days, cancellationToken)
            : Task.FromResult<IReadOnlyList<DailyWeatherResult>>([]);

    private bool CanFallback(Exception exception, CancellationToken cancellationToken) =>
        _options.Enabled
        && exception switch
        {
            HttpRequestException http when http.StatusCode is null => true,
            HttpRequestException http => http.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                or HttpStatusCode.InternalServerError
                or HttpStatusCode.BadGateway
                or HttpStatusCode.ServiceUnavailable
                or HttpStatusCode.GatewayTimeout,
            JsonException or InvalidDataException => true,
            TaskCanceledException => !cancellationToken.IsCancellationRequested,
            _ => false
        };

    [LoggerMessage(
        EventId = 3001,
        Level = LogLevel.Warning,
        Message = "The primary weather provider failed; using the configured OpenWeather fallback. exceptionType={ExceptionType}.")]
    private static partial void LogPrimaryFailure(ILogger logger, string exceptionType);
}
