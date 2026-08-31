using SeoulTourist.AzureMaps;

namespace SeoulTourist.Tourism;

public sealed class AzureMapsTourismProvider(AzureMapsClient mapsClient) : ITourismProvider
{
    private const string ProviderName = "Microsoft Azure Maps";
    private const string AttributionUrl = "https://azure.microsoft.com/products/azure-maps/";

    public async Task<IReadOnlyList<TourismAttraction>> SearchAttractionsAsync(
        string query,
        TourismLocation center,
        int radiusMeters,
        int limit,
        CancellationToken cancellationToken = default)
    {
        var places = await mapsClient.SearchPointsOfInterestAsync(
            query,
            new GeoPoint(center.Latitude, center.Longitude),
            radiusMeters,
            limit,
            cancellationToken);
        var retrievedAt = DateTimeOffset.UtcNow;
        return [.. places.Select(place => new TourismAttraction(
            $"{place.Position.Latitude:R},{place.Position.Longitude:R}",
            place.Name,
            place.Category,
            place.Address,
            new TourismLocation(place.Position.Latitude, place.Position.Longitude),
            place.DistanceMeters,
            ImageUrl: null,
            Telephone: null,
            ModifiedAt: null,
            new TourismSource(ProviderName, AttributionUrl, retrievedAt)))];
    }
}
