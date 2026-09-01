using System.ComponentModel.DataAnnotations;

namespace JapanExpert.Tourism;

/// <summary>
/// Configuration for the OpenStreetMap Overpass API instance used for Japan place search.
/// The endpoint is configurable so an operator can move to a self-hosted or contracted
/// instance without a code change. No credential is required or accepted.
/// </summary>
public sealed class OverpassOptions
{
    public const string SectionName = "Overpass";

    /// <summary>Community Overpass instance used by default.</summary>
    public const string DefaultEndpoint = "https://overpass-api.de/api/interpreter";

    /// <summary>
    /// Source-safe default agent. It names the product and version and carries a public project
    /// URL as the contact reference, which is what the OpenStreetMap, Overpass, MET Norway, and
    /// Wikimedia policies ask for. It deliberately avoids a mailbox, user principal name, or any
    /// other tenant-bound identifier so it is safe to commit. Operators may override it.
    /// </summary>
    public const string DefaultUserAgent =
        "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/rg-a365-custom-agents)";

    [Required]
    public string Endpoint { get; init; } = DefaultEndpoint;

    /// <summary>
    /// Sent on every Overpass request. Overpass instances require an informative agent that
    /// identifies the application and carries a contact reference.
    /// </summary>
    [Required]
    [MinLength(16)]
    public string UserAgent { get; init; } = DefaultUserAgent;

    /// <summary>Server-side Overpass QL <c>[timeout:n]</c> budget in seconds.</summary>
    [Range(5, 60)]
    public int QueryTimeoutSeconds { get; init; } = 25;

    /// <summary>Hard cap on elements requested from Overpass before local filtering.</summary>
    [Range(10, 200)]
    public int MaximumFetchElements { get; init; } = 120;

    /// <summary>Multiplier applied to the caller limit when computing the Overpass fetch cap.</summary>
    [Range(1, 5)]
    public int FetchMultiplier { get; init; } = 3;

    /// <summary>Response body cap in bytes enforced on the shared <see cref="HttpClient"/>.</summary>
    [Range(65_536, 8_388_608)]
    public int MaximumResponseBytes { get; init; } = 2 * 1024 * 1024;

    public bool IsValid() =>
        Uri.TryCreate(Endpoint, UriKind.Absolute, out var endpoint)
        && (endpoint.Scheme == Uri.UriSchemeHttps || endpoint.IsLoopback)
        && HasContactReference(UserAgent);

    /// <summary>
    /// A usable agent string names the caller and carries a contact reference. A "+URL" project
    /// link satisfies the community data policies without committing a tenant-bound mailbox or
    /// user principal name; an explicit <c>mailto:</c> is also accepted for operators who prefer it.
    /// </summary>
    internal static bool HasContactReference(string userAgent) =>
        !string.IsNullOrWhiteSpace(userAgent)
        && userAgent.Trim().Length >= 16
        && (userAgent.Contains("+http", StringComparison.OrdinalIgnoreCase)
            || userAgent.Contains("mailto:", StringComparison.OrdinalIgnoreCase));
}
