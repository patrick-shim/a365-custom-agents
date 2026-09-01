using System.ComponentModel.DataAnnotations;

namespace JapanExpert.Weather;

/// <summary>
/// Japan Meteorological Agency source configuration.
/// <para>
/// The alert feed is the documented JMA XML Atom feed. The forecast endpoint is the
/// <c>bosai</c> JSON service, which JMA does not document as a public API and which changed shape
/// during 2026; it is therefore configurable, guarded by a strict schema check, and rejected when
/// it returns a stale report or a legacy payload.
/// </para>
/// </summary>
public sealed class JmaOptions
{
    public const string SectionName = "Jma";

    /// <summary>Documented JMA XML Atom feed for high-frequency bulletins.</summary>
    public const string DefaultAlertFeedAddress =
        "https://www.data.jma.go.jp/developer/xml/feed/extra.xml";

    /// <summary>Undocumented JMA bosai forecast JSON prefix, ending with a slash.</summary>
    public const string DefaultForecastBaseAddress =
        "https://www.jma.go.jp/bosai/forecast/data/forecast/";

    /// <summary>Enables the guarded bosai forecast source.</summary>
    public bool ForecastEnabled { get; init; } = true;

    [Required]
    public string ForecastBaseAddress { get; init; } = DefaultForecastBaseAddress;

    [Required]
    public string AlertFeedAddress { get; init; } = DefaultAlertFeedAddress;

    /// <summary>
    /// Maximum accepted age of <c>reportDatetime</c>. JMA publishes prefecture forecasts three
    /// times a day, so anything older than this window is treated as an unusable stale payload.
    /// </summary>
    [Range(3, 72)]
    public int MaximumForecastAgeHours { get; init; } = 24;

    /// <summary>Tolerance for a report timestamp that is ahead of the host clock.</summary>
    [Range(1, 12)]
    public int MaximumForecastClockSkewHours { get; init; } = 3;

    /// <summary>Hard cap on Atom entries inspected before area filtering.</summary>
    [Range(10, 500)]
    public int MaximumFeedEntries { get; init; } = 200;

    /// <summary>Substrings that mark an Atom entry title as a warning, advisory, or alert.</summary>
    public IReadOnlyList<string> AlertTitleKeywords { get; init; } = ["警報", "注意報", "警戒"];

    /// <summary>Response body cap in bytes for JMA requests.</summary>
    [Range(65_536, 16_777_216)]
    public int MaximumResponseBytes { get; init; } = 4 * 1024 * 1024;

    /// <summary>Request timeout in seconds for JMA requests.</summary>
    [Range(5, 60)]
    public int TimeoutSeconds { get; init; } = 20;

    public bool IsValid() =>
        IsSecureAbsolute(ForecastBaseAddress)
        && ForecastBaseAddress.EndsWith('/')
        && IsSecureAbsolute(AlertFeedAddress)
        && AlertTitleKeywords.Count > 0;

    private static bool IsSecureAbsolute(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && (uri.Scheme == Uri.UriSchemeHttps || uri.IsLoopback);
}

/// <summary>
/// MET Norway Locationforecast configuration. MET Norway is used only as a clearly labelled
/// third-party current-conditions fallback. Its terms require an identifying User-Agent and
/// coordinates truncated to at most four decimals.
/// </summary>
public sealed class MetNorwayOptions
{
    public const string SectionName = "MetNorway";

    public const string DefaultBaseAddress = "https://api.met.no/weatherapi/locationforecast/2.0/";

    /// <summary>
    /// Source-safe default agent. MET Norway requires an identifying User-Agent with a contact
    /// reference; a public project URL satisfies that policy without committing a mailbox, user
    /// principal name, or any other tenant-bound identifier. Operators may override it.
    /// </summary>
    public const string DefaultUserAgent =
        "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/rg-a365-custom-agents)";

    /// <summary>Enables the labelled third-party current-conditions source.</summary>
    public bool Enabled { get; init; } = true;

    [Required]
    public string BaseAddress { get; init; } = DefaultBaseAddress;

    [Required]
    [MinLength(16)]
    public string UserAgent { get; init; } = DefaultUserAgent;

    /// <summary>Decimal places retained for outgoing coordinates. MET Norway allows at most four.</summary>
    [Range(1, 4)]
    public int CoordinateDecimals { get; init; } = 4;

    [Range(65_536, 8_388_608)]
    public int MaximumResponseBytes { get; init; } = 2 * 1024 * 1024;

    [Range(5, 60)]
    public int TimeoutSeconds { get; init; } = 20;

    public bool IsValid() =>
        Uri.TryCreate(BaseAddress, UriKind.Absolute, out var baseAddress)
        && (baseAddress.Scheme == Uri.UriSchemeHttps || baseAddress.IsLoopback)
        && BaseAddress.EndsWith('/')
        && HasContactReference(UserAgent);

    /// <summary>
    /// A usable agent string names the caller and carries a contact reference. A "+URL" project
    /// link satisfies the MET Norway terms without committing a tenant-bound mailbox or user
    /// principal name; an explicit <c>mailto:</c> is also accepted for operators who prefer it.
    /// </summary>
    internal static bool HasContactReference(string userAgent) =>
        !string.IsNullOrWhiteSpace(userAgent)
        && userAgent.Trim().Length >= 16
        && (userAgent.Contains("+http", StringComparison.OrdinalIgnoreCase)
            || userAgent.Contains("mailto:", StringComparison.OrdinalIgnoreCase));
}
