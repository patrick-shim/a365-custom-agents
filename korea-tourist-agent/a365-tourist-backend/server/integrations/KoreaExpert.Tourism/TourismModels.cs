namespace KoreaExpert.Tourism;

public sealed record TourismLocation(double Latitude, double Longitude);

public sealed record TourismSource(
    string Name,
    string AttributionUrl,
    DateTimeOffset RetrievedAt);

public sealed record TourismAttraction(
    string ContentId,
    string Name,
    string? Category,
    string? Address,
    TourismLocation Position,
    double? DistanceMeters,
    string? ImageUrl,
    string? Telephone,
    DateTimeOffset? ModifiedAt,
    TourismSource Source);
