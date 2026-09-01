namespace KoreaExpert.Weather;

public interface IWeatherProvider
{
    Task<CurrentWeatherResult?> GetCurrentWeatherAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<DailyWeatherResult>> GetDailyForecastAsync(
        WeatherLocation location,
        int days,
        CancellationToken cancellationToken = default);
}
