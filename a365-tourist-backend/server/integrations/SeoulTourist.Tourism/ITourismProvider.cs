namespace SeoulTourist.Tourism;

public interface ITourismProvider
{
    Task<IReadOnlyList<TourismAttraction>> SearchAttractionsAsync(
        string query,
        TourismLocation center,
        int radiusMeters,
        int limit,
        CancellationToken cancellationToken = default);
}
