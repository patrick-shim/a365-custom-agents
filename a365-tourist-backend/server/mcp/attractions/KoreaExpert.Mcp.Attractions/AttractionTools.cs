using System.ComponentModel;
using ModelContextProtocol.Server;
using KoreaExpert.Mcp.Hosting;
using KoreaExpert.Tourism;

namespace KoreaExpert.Mcp.Attractions;

[McpServerToolType]
public sealed class AttractionTools(
    ITourismProvider tourismProvider,
    ILogger<AttractionTools> logger)
{
    [McpServerTool(Name = "search_korea_attractions")]
    [Description("Searches attributed Microsoft Azure Maps data for Korea attractions near a specified point.")]
    public Task<IReadOnlyList<TourismAttraction>> SearchKoreaAttractionsAsync(
        [Description("Place type or attraction name, such as palace, museum, market, or N Seoul Tower.")]
        string query,
        [Description("Center latitude. Defaults to Seoul City Hall.")]
        double latitude = 37.5665,
        [Description("Center longitude. Defaults to Seoul City Hall.")]
        double longitude = 126.9780,
        [Description("Search radius in meters, from 100 through 50000.")]
        int radiusMeters = 5000,
        [Description("Maximum number of results, from 1 through 20.")]
        int limit = 8,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(radiusMeters, 100);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(radiusMeters, 50_000);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, 20);

        return McpToolExecution.RunAsync(
            "attractions.search",
            logger,
            token => tourismProvider.SearchAttractionsAsync(
                query,
                new TourismLocation(latitude, longitude),
                radiusMeters,
                limit,
                token),
            cancellationToken);
    }
}
