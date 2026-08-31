using System.ComponentModel.DataAnnotations;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Frankfurter v2 configuration. Frankfurter is a credential-free front end over published
/// central-bank reference rates; the provider list is pinned to the European Central Bank so the
/// returned observation always has a documented origin.
/// <para>
/// v2 serves rates from the <c>rates</c> route
/// (<c>rates?base=USD&amp;quotes=JPY&amp;providers=ECB</c>, with an optional
/// <c>date=YYYY-MM-DD</c> for a historical observation) and returns a JSON array of rate rows.
/// The base address must therefore point at a v2 prefix; the v1 <c>latest</c>/<c>symbols</c>
/// object contract is not supported.
/// </para>
/// </summary>
public sealed class FrankfurterOptions
{
    public const string SectionName = "Frankfurter";

    public const string DefaultBaseAddress = "https://api.frankfurter.dev/v2/";

    public const string DefaultProviders = "ECB";

    public bool Enabled { get; init; } = true;

    [Required]
    public string BaseAddress { get; init; } = DefaultBaseAddress;

    /// <summary>Frankfurter v2 <c>providers</c> query value. Pinned to the ECB by default.</summary>
    [Required]
    public string Providers { get; init; } = DefaultProviders;

    [Range(5, 60)]
    public int TimeoutSeconds { get; init; } = 20;

    [Range(65_536, 4_194_304)]
    public int MaximumResponseBytes { get; init; } = 1024 * 1024;

    public bool IsValid() =>
        Uri.TryCreate(BaseAddress, UriKind.Absolute, out var baseAddress)
        && (baseAddress.Scheme == Uri.UriSchemeHttps || baseAddress.IsLoopback)
        && BaseAddress.EndsWith('/')
        && !string.IsNullOrWhiteSpace(Providers);
}

/// <summary>
/// Direct European Central Bank SDMX data configuration used as the credential-free fallback.
/// The ECB publishes euro-based reference rates, so non-euro pairs are derived as EUR cross rates.
/// </summary>
public sealed class EcbSdmxOptions
{
    public const string SectionName = "EcbSdmx";

    public const string DefaultBaseAddress = "https://data-api.ecb.europa.eu/service/data/EXR/";

    public bool Enabled { get; init; } = true;

    [Required]
    public string BaseAddress { get; init; } = DefaultBaseAddress;

    /// <summary>Lookback window in days used when a historical observation date is requested.</summary>
    [Range(1, 30)]
    public int HistoricalLookbackDays { get; init; } = 7;

    [Range(5, 60)]
    public int TimeoutSeconds { get; init; } = 20;

    [Range(65_536, 4_194_304)]
    public int MaximumResponseBytes { get; init; } = 1024 * 1024;

    public bool IsValid() =>
        Uri.TryCreate(BaseAddress, UriKind.Absolute, out var baseAddress)
        && (baseAddress.Scheme == Uri.UriSchemeHttps || baseAddress.IsLoopback)
        && BaseAddress.EndsWith('/');
}
