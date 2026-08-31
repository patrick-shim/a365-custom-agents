using System.ComponentModel;
using ModelContextProtocol.Server;
using KoreaExpert.AzureMaps;
using KoreaExpert.Mcp.Hosting;

namespace KoreaExpert.Mcp.Accommodation;

[McpServerToolType]
public sealed class AccommodationTools(
    AzureMapsClient mapsClient,
    ILogger<AccommodationTools> logger)
{
    [McpServerTool(Name = "search_korea_accommodation")]
    [Description("Searches Microsoft Azure Maps for accommodation locations in Korea. This returns places, not live room inventory or prices.")]
    public Task<IReadOnlyList<PlaceResult>> SearchKoreaAccommodationAsync(
        [Description("Accommodation query such as hotel, hostel, guesthouse, or a property name.")]
        string query = "hotel",
        [Description("Center latitude. Defaults to Seoul City Hall.")]
        double latitude = 37.5665,
        [Description("Center longitude. Defaults to Seoul City Hall.")]
        double longitude = 126.9780,
        [Description("Search radius in meters, from 100 through 50000.")]
        int radiusMeters = 10_000,
        [Description("Maximum number of results, from 1 through 20.")]
        int limit = 10,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(radiusMeters, 100);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(radiusMeters, 50_000);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, 20);

        return McpToolExecution.RunAsync(
            "accommodation.search",
            logger,
            token => mapsClient.SearchPointsOfInterestAsync(
                query,
                new GeoPoint(latitude, longitude),
                radiusMeters,
                limit,
                token),
            cancellationToken);
    }
}
