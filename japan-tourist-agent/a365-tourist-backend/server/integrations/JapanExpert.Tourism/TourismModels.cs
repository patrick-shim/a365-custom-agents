namespace JapanExpert.Tourism;

/// <summary>WGS84 coordinate pair used by every tourism contract.</summary>
public sealed record TourismLocation(double Latitude, double Longitude);

/// <summary>Attribution block returned with every tourism result.</summary>
public sealed record TourismSource(
    string Name,
    string AttributionUrl,
    string License,
    string Notice,
    DateTimeOffset RetrievedAt);

/// <summary>Distinguishes the two Japan place contracts served by this backend.</summary>
public enum TourismPlaceKind
{
    Attraction,
    Accommodation
}

/// <summary>A single attributed OpenStreetMap place inside Japan.</summary>
public sealed record TourismPlace(
    string Id,
    string Name,
    string? LocalName,
    TourismPlaceKind Kind,
    string? Category,
    string? Address,
    TourismLocation Position,
    double DistanceMeters,
    string? Website,
    string? Telephone,
    string? OpeningHours,
    TourismSource Source);

/// <summary>Validated, bounded search request shared by the attraction and accommodation tools.</summary>
public sealed record TourismSearchRequest(
    string Category,
    string? NameContains,
    TourismLocation Center,
    int RadiusMeters,
    int Limit)
{
    public const int MinimumRadiusMeters = 100;
    public const int MaximumRadiusMeters = 50_000;
    public const int MinimumLimit = 1;
    public const int MaximumLimit = 20;
    public const int MaximumNameFilterLength = 64;

    /// <summary>Fails closed on out-of-range bounds and on coordinates outside Japan.</summary>
    public TourismSearchRequest Validate()
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(Category);
        ArgumentOutOfRangeException.ThrowIfLessThan(RadiusMeters, MinimumRadiusMeters);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(RadiusMeters, MaximumRadiusMeters);
        ArgumentOutOfRangeException.ThrowIfLessThan(Limit, MinimumLimit);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(Limit, MaximumLimit);

        if (NameContains is { Length: > MaximumNameFilterLength })
        {
            throw new ArgumentException(
                $"nameContains must be {MaximumNameFilterLength} characters or fewer.",
                nameof(NameContains));
        }

        JapanGeography.EnsureWithinJapan(Center);
        return this;
    }
}
