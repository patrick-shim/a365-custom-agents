using System.ComponentModel.DataAnnotations;

namespace JapanExpert.Tourism;

/// <summary>
/// Bounded in-process response cache settings for the OpenStreetMap Overpass source.
/// OpenStreetMap place data changes slowly, so a long time to live keeps a public community
/// endpoint from being called once per user turn.
/// </summary>
public sealed class TourismCacheOptions
{
    public const string SectionName = "Cache";

    /// <summary>Time to live in seconds. Zero disables caching entirely.</summary>
    [Range(0, 604_800)]
    public int TtlSeconds { get; init; } = 86_400;

    /// <summary>Total cache size budget, counted in cached result items.</summary>
    [Range(16, 100_000)]
    public int SizeLimit { get; init; } = 512;

    /// <summary>Largest single entry that may be cached, counted in result items.</summary>
    [Range(1, 1_000)]
    public int MaximumEntrySize { get; init; } = 64;

    public TimeSpan Ttl => TimeSpan.FromSeconds(TtlSeconds);

    public bool IsEnabled => TtlSeconds > 0;
}
