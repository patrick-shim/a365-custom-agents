namespace JapanExpert.Weather;

/// <summary>WGS84 coordinate pair used for point weather lookups inside Japan.</summary>
public sealed record WeatherLocation(double Latitude, double Longitude)
{
    /// <summary>Tokyo default centre for the Japan weather tools.</summary>
    public const double DefaultLatitude = 35.6762;

    /// <summary>Tokyo default centre for the Japan weather tools.</summary>
    public const double DefaultLongitude = 139.6503;

    /// <summary>
    /// Approximate coverage envelope for Japan expressed as a small set of boxes. A single
    /// rectangle around the archipelago would also cover the Korean peninsula, so the main
    /// archipelago, the western Kyushu islands, the Nansei islands, the Izu and Ogasawara chain,
    /// Minamitorishima, and Okinotorishima are bounded separately.
    /// </summary>
    private static readonly (double MinLat, double MaxLat, double MinLon, double MaxLon)[] ServiceArea =
    [
        (30.90, 45.60, 129.30, 146.00),
        (32.00, 34.80, 128.30, 129.35),
        (24.00, 30.90, 122.90, 131.50),
        (24.00, 34.90, 138.00, 142.50),
        (24.20, 24.40, 153.90, 154.10),
        (20.30, 20.50, 136.00, 136.20)
    ];

    /// <summary>Tokyo default centre.</summary>
    public static WeatherLocation Default { get; } = new(DefaultLatitude, DefaultLongitude);

    /// <summary>Fails closed on coordinates outside the supported Japan service area.</summary>
    public WeatherLocation EnsureWithinJapan()
    {
        var withinJapan = ServiceArea.Any(box =>
            Latitude >= box.MinLat
            && Latitude <= box.MaxLat
            && Longitude >= box.MinLon
            && Longitude <= box.MaxLon);
        if (!withinJapan)
        {
            throw new ArgumentOutOfRangeException(
                nameof(Latitude),
                "Coordinates must fall inside Japan, including Hokkaido, Honshu, Shikoku, Kyushu, "
                + "the Nansei islands, and the Izu and Ogasawara island chains.");
        }

        return this;
    }
}

/// <summary>
/// Provenance for a weather result. <see cref="Notice"/> states plainly whether the value is an
/// authoritative Japan Meteorological Agency product or a labelled third-party estimate.
/// </summary>
public sealed record WeatherSource(
    string Name,
    string AttributionUrl,
    string License,
    string Notice,
    DateTimeOffset RetrievedAt);

/// <summary>Point current-conditions estimate. Never an official JMA warning or forecast.</summary>
public sealed record CurrentWeatherResult(
    DateTimeOffset ObservedAt,
    string Summary,
    string? SymbolCode,
    double? TemperatureCelsius,
    int? RelativeHumidityPercent,
    double? PrecipitationMillimeters,
    double? WindSpeedKilometersPerHour,
    WeatherSource Source);

/// <summary>One JMA forecast day for a prefecture forecast area.</summary>
public sealed record DailyWeatherResult(
    DateOnly Date,
    string Summary,
    string? SummaryJapanese,
    string? WeatherCode,
    double? MinimumTemperatureCelsius,
    double? MaximumTemperatureCelsius,
    int? MaximumPrecipitationProbabilityPercent);

/// <summary>Attributed JMA forecast for one prefecture forecast office and area.</summary>
public sealed record WeatherForecastResult(
    string OfficeCode,
    string PrefectureEnglish,
    string PrefectureJapanese,
    string AreaName,
    string PublishingOffice,
    DateTimeOffset ReportedAt,
    IReadOnlyList<DailyWeatherResult> Days,
    WeatherSource Source);

/// <summary>One JMA warning, advisory, or alert bulletin headline.</summary>
public sealed record WeatherAlert(
    string Id,
    string Sender,
    string Headline,
    string Description,
    string? AreaName,
    DateTimeOffset PublishedAt,
    string DetailUrl,
    WeatherSource Source);
