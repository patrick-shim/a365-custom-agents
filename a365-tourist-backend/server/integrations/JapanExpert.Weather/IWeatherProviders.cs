namespace JapanExpert.Weather;

/// <summary>
/// Point current-conditions estimate. Implementations must be labelled third-party sources and
/// must never present their output as a Japan Meteorological Agency forecast or warning.
/// </summary>
public interface ICurrentWeatherProvider
{
    Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default);
}

/// <summary>Authoritative Japan Meteorological Agency prefecture forecast.</summary>
public interface IWeatherForecastProvider
{
    /// <summary>Maximum forecast horizon exposed by the Japan forecast contract.</summary>
    public const int MaximumDays = 7;

    Task<WeatherForecastResult> GetForecastAsync(
        JapanArea area,
        int days,
        CancellationToken cancellationToken = default);
}

/// <summary>Authoritative Japan Meteorological Agency warning and advisory bulletins.</summary>
public interface IWeatherAlertProvider
{
    /// <summary>Maximum bulletin count exposed by the Japan alert contract.</summary>
    public const int MaximumAlerts = 25;

    Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        JapanArea area,
        int limit,
        CancellationToken cancellationToken = default);
}
