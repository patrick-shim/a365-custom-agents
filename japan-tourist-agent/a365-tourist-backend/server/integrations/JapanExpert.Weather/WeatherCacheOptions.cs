using System.ComponentModel.DataAnnotations;

namespace JapanExpert.Weather;

/// <summary>
/// Bounded in-process response cache settings for the Japan weather sources. Each source gets its
/// own time to live because their publication cadences differ sharply: JMA prefecture forecasts
/// are issued a few times a day, the JMA bulletin feed must stay near real time for warnings, and
/// MET Norway asks clients not to re-request a point forecast aggressively.
/// </summary>
public sealed class WeatherCacheOptions
{
    public const string SectionName = "Cache";

    /// <summary>JMA prefecture forecast time to live in seconds. Zero disables caching.</summary>
    [Range(0, 86_400)]
    public int ForecastTtlSeconds { get; init; } = 1_800;

    /// <summary>
    /// JMA warning and advisory bulletin time to live in seconds. Kept deliberately short so a
    /// newly issued warning is not withheld from a traveller. Zero disables caching.
    /// </summary>
    [Range(0, 3_600)]
    public int AlertTtlSeconds { get; init; } = 60;

    /// <summary>
    /// MET Norway current-conditions time to live in seconds. Conservative relative to the
    /// upstream Expires header, which is typically around thirty minutes. Zero disables caching.
    /// </summary>
    [Range(0, 86_400)]
    public int CurrentTtlSeconds { get; init; } = 600;

    /// <summary>Total cache size budget, counted in cached result items.</summary>
    [Range(16, 100_000)]
    public int SizeLimit { get; init; } = 256;

    /// <summary>Largest single entry that may be cached, counted in result items.</summary>
    [Range(1, 1_000)]
    public int MaximumEntrySize { get; init; } = 64;

    public TimeSpan ForecastTtl => TimeSpan.FromSeconds(ForecastTtlSeconds);

    public TimeSpan AlertTtl => TimeSpan.FromSeconds(AlertTtlSeconds);

    public TimeSpan CurrentTtl => TimeSpan.FromSeconds(CurrentTtlSeconds);
}
