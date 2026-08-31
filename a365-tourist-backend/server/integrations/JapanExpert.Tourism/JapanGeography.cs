namespace JapanExpert.Tourism;

/// <summary>
/// Japan-only coordinate defaults, service-area bounds, and distance maths. The MCP contract
/// refuses coordinates outside Japan so the Japan Expert tools cannot be repurposed as a global
/// place search.
/// </summary>
public static class JapanGeography
{
    /// <summary>Tokyo default centre used by every Japan search tool.</summary>
    public const double DefaultLatitude = 35.6762;

    /// <summary>Tokyo default centre used by every Japan search tool.</summary>
    public const double DefaultLongitude = 139.6503;

    private const double EarthRadiusMeters = 6_371_008.8;

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

    /// <summary>Default Tokyo centre.</summary>
    public static TourismLocation DefaultCenter { get; } =
        new(DefaultLatitude, DefaultLongitude);

    /// <summary>True when the coordinate falls inside the supported Japan service area.</summary>
    public static bool IsWithinJapan(double latitude, double longitude) =>
        ServiceArea.Any(box =>
            latitude >= box.MinLat
            && latitude <= box.MaxLat
            && longitude >= box.MinLon
            && longitude <= box.MaxLon);

    /// <summary>Throws when the supplied coordinate is outside the supported Japan service area.</summary>
    public static void EnsureWithinJapan(TourismLocation location)
    {
        ArgumentNullException.ThrowIfNull(location);

        if (!IsWithinJapan(location.Latitude, location.Longitude))
        {
            throw new ArgumentOutOfRangeException(
                nameof(location),
                "Coordinates must fall inside Japan, including Hokkaido, Honshu, Shikoku, Kyushu, "
                + "the Nansei islands, and the Izu and Ogasawara island chains.");
        }
    }

    /// <summary>Great-circle distance in metres between two coordinates.</summary>
    public static double DistanceMeters(TourismLocation from, TourismLocation to)
    {
        ArgumentNullException.ThrowIfNull(from);
        ArgumentNullException.ThrowIfNull(to);

        var fromLatitude = double.DegreesToRadians(from.Latitude);
        var toLatitude = double.DegreesToRadians(to.Latitude);
        var deltaLatitude = double.DegreesToRadians(to.Latitude - from.Latitude);
        var deltaLongitude = double.DegreesToRadians(to.Longitude - from.Longitude);

        var haversine = (Math.Sin(deltaLatitude / 2) * Math.Sin(deltaLatitude / 2))
            + (Math.Cos(fromLatitude)
                * Math.Cos(toLatitude)
                * Math.Sin(deltaLongitude / 2)
                * Math.Sin(deltaLongitude / 2));
        var angle = 2 * Math.Atan2(Math.Sqrt(haversine), Math.Sqrt(1 - haversine));
        return Math.Round(EarthRadiusMeters * angle, 1, MidpointRounding.AwayFromZero);
    }
}
