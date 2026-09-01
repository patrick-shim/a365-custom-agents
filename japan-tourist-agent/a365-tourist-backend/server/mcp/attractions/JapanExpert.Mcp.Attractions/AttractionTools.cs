using System.ComponentModel;
using JapanExpert.Mcp.Hosting;
using JapanExpert.Tourism;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Attractions;

/// <summary>
/// Japan attraction search backed by OpenStreetMap data served through an Overpass API instance.
/// Every result carries Open Database License attribution for OpenStreetMap contributors.
/// </summary>
[McpServerToolType]
public sealed class AttractionTools(
    ITourismProvider tourismProvider,
    ILogger<AttractionTools> logger)
{
    [McpServerTool(Name = "search_japan_attractions")]
    [Description(
        "Searches OpenStreetMap data through the Overpass API for attractions, museums, viewpoints, "
        + "castles, heritage sites, Shinto shrines, and Buddhist temples near a point in Japan. "
        + "Results are places, not tickets or availability, and include OpenStreetMap ODbL attribution.")]
    public Task<IReadOnlyList<TourismPlace>> SearchJapanAttractionsAsync(
        [Description(
            "Attraction category. One of: all, aquarium, artwork, attraction, castle, gallery, "
            + "heritage, monument, museum, ruins, shrine, temple, theme_park, viewpoint, zoo.")]
        string category = TourismCategories.All,
        [Description("Optional case-insensitive substring filter applied to the place name.")]
        string? nameContains = null,
        [Description("Center latitude inside Japan. Defaults to central Tokyo.")]
        double latitude = JapanGeography.DefaultLatitude,
        [Description("Center longitude inside Japan. Defaults to central Tokyo.")]
        double longitude = JapanGeography.DefaultLongitude,
        [Description("Search radius in meters, from 100 through 50000.")]
        int radiusMeters = 5_000,
        [Description("Maximum number of results, from 1 through 20.")]
        int limit = 8,
        CancellationToken cancellationToken = default)
    {
        var request = new TourismSearchRequest(
            category,
            nameContains,
            new TourismLocation(latitude, longitude),
            radiusMeters,
            limit).Validate();

        return McpToolExecution.RunAsync(
            "attractions.search",
            logger,
            token => tourismProvider.SearchAttractionsAsync(request, token),
            cancellationToken);
    }
}
