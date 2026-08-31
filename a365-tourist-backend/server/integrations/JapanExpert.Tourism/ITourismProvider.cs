namespace JapanExpert.Tourism;

/// <summary>
/// Narrow tourism contract consumed by the attractions and accommodation MCP services.
/// Provider transport, query language, and tag mapping stay behind this interface.
/// </summary>
public interface ITourismProvider
{
    Task<IReadOnlyList<TourismPlace>> SearchAttractionsAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<TourismPlace>> SearchAccommodationAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default);
}
