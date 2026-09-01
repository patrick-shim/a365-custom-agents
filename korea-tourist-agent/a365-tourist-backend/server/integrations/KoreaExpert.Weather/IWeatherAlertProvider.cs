namespace KoreaExpert.Weather;

public interface IWeatherAlertProvider
{
    Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default);
}
