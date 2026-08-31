namespace SeoulTourist.Weather;

public sealed record WeatherLocation(double Latitude, double Longitude);

public sealed record WeatherSource(
    string Name,
    string AttributionUrl,
    DateTimeOffset RetrievedAt);

public sealed record CurrentWeatherResult(
    DateTimeOffset ObservedAt,
    string Summary,
    double? TemperatureCelsius,
    double? ApparentTemperatureCelsius,
    int? RelativeHumidityPercent,
    double? PrecipitationMillimeters,
    double? WindSpeedKilometersPerHour,
    WeatherSource Source);

public sealed record DailyWeatherResult(
    DateOnly Date,
    string Summary,
    double? MinimumTemperatureCelsius,
    double? MaximumTemperatureCelsius,
    int? MaximumPrecipitationProbabilityPercent,
    WeatherSource Source);

public sealed record WeatherAlert(
    string Id,
    string Sender,
    string Event,
    DateTimeOffset StartsAt,
    DateTimeOffset EndsAt,
    string Description,
    WeatherSource Source);
