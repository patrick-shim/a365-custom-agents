namespace KoreaExpert.Weather;

public sealed class UnavailableWeatherAlertProvider : IWeatherAlertProvider
{
    public Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        WeatherLocation location,
        CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<WeatherAlert>>([]);
}
