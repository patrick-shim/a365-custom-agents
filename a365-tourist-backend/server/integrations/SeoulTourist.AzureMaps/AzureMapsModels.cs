namespace SeoulTourist.AzureMaps;

public sealed record GeoPoint(double Latitude, double Longitude);

public sealed record PlaceResult(
    string Name,
    string? Category,
    string? Address,
    GeoPoint Position,
    double? DistanceMeters);

public sealed record CurrentWeatherResult(
    DateTimeOffset ObservedAt,
    string Summary,
    double? TemperatureCelsius,
    int? RelativeHumidityPercent,
    double? WindSpeedKilometersPerHour,
    bool HasPrecipitation);

public sealed record DailyWeatherResult(
    DateOnly Date,
    string? DaySummary,
    string? NightSummary,
    double? MinimumTemperatureCelsius,
    double? MaximumTemperatureCelsius,
    bool HasPrecipitation);
