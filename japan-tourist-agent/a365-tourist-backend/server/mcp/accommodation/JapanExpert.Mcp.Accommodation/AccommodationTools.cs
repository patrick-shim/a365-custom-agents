using System.ComponentModel;
using JapanExpert.Mcp.Hosting;
using JapanExpert.Tourism;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Accommodation;

/// <summary>
/// Japan accommodation search backed by OpenStreetMap data served through an Overpass API
/// instance. Results are lodging places, never live room inventory, availability, or prices.
/// </summary>
[McpServerToolType]
public sealed class AccommodationTools(
    ITourismProvider tourismProvider,
    ILogger<AccommodationTools> logger)
{
    [McpServerTool(Name = "search_japan_accommodation")]
    [Description(
        "Searches OpenStreetMap data through the Overpass API for lodging in Japan, including "
        + "hotels, hostels, guest houses, motels, serviced apartments, camp sites, and mountain "
        + "huts. Results are places with OpenStreetMap ODbL attribution, not live room inventory, "
        + "availability, or prices.")]
    public Task<IReadOnlyList<TourismPlace>> SearchJapanAccommodationAsync(
        [Description(
            "Accommodation type. One of: all, alpine_hut, apartment, camp_site, guest_house, "
            + "hostel, hotel, motel.")]
        string accommodationType = TourismCategories.All,
        [Description("Optional case-insensitive substring filter applied to the property name.")]
        string? nameContains = null,
        [Description("Center latitude inside Japan. Defaults to central Tokyo.")]
        double latitude = JapanGeography.DefaultLatitude,
        [Description("Center longitude inside Japan. Defaults to central Tokyo.")]
        double longitude = JapanGeography.DefaultLongitude,
        [Description("Search radius in meters, from 100 through 50000.")]
        int radiusMeters = 10_000,
        [Description("Maximum number of results, from 1 through 20.")]
        int limit = 10,
        CancellationToken cancellationToken = default)
    {
        var request = new TourismSearchRequest(
            accommodationType,
            nameContains,
            new TourismLocation(latitude, longitude),
            radiusMeters,
            limit).Validate();

        return McpToolExecution.RunAsync(
            "accommodation.search",
            logger,
            token => tourismProvider.SearchAccommodationAsync(request, token),
            cancellationToken);
    }
}
