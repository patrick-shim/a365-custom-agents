using System.ComponentModel.DataAnnotations;

namespace JapanExpert.AgentHost;

public sealed class InternalMcpOptions
{
    public const string SectionName = "InternalMcp";

    public bool Enabled { get; init; }

    public bool UseAuthentication { get; init; } = true;

    public string Audience { get; init; } = string.Empty;

    public string AttractionsEndpoint { get; init; } = string.Empty;

    public string WeatherEndpoint { get; init; } = string.Empty;

    public string AccommodationEndpoint { get; init; } = string.Empty;

    public string CurrencyEndpoint { get; init; } = string.Empty;

    [Range(1_024, 262_144)]
    public int MaximumContentCharacters { get; init; } = 65_536;

    public bool HasValidEndpoints(bool requireHttps = false) => GetEndpointValues().All(value =>
        Uri.TryCreate(value.Endpoint, UriKind.Absolute, out var endpoint)
        && (requireHttps
            ? string.Equals(endpoint.Scheme, "https", StringComparison.OrdinalIgnoreCase)
            : endpoint.Scheme is "http" or "https"));

    public bool HasValidAudience() =>
        !UseAuthentication
        || (Uri.TryCreate(Audience, UriKind.Absolute, out var audience)
            && string.Equals(audience.Scheme, "api", StringComparison.OrdinalIgnoreCase));

    public IReadOnlyList<InternalMcpServer> GetServers() =>
        [.. GetEndpointValues().Select(value => new InternalMcpServer(
            value.Name,
            new Uri(value.Endpoint),
            GetToolContracts(value.Name)))];

    public string GetDelegatedScope() => AgentIdentityAuthorizationScopes.InternalMcp(Audience);

    private IReadOnlyList<(string Name, string Endpoint)> GetEndpointValues() =>
    [
        ("attractions", AttractionsEndpoint),
        ("weather", WeatherEndpoint),
        ("accommodation", AccommodationEndpoint),
        ("currency", CurrencyEndpoint)
    ];

    // These contracts pin the tool surface published by the independently deployed MCP services in
    // server/mcp. Names, descriptions, parameter sets, and canonical schema fingerprints are owned
    // by those services; the host only verifies them and refuses to expose anything that drifts.
    private static IReadOnlyList<InternalMcpToolContract> GetToolContracts(string serverName) =>
        serverName switch
        {
            "attractions" =>
            [
                new(
                    "search_japan_attractions",
                    "Searches OpenStreetMap data through the Overpass API for attractions, museums, viewpoints, castles, heritage sites, Shinto shrines, and Buddhist temples near a point in Japan. Results are places, not tickets or availability, and include OpenStreetMap ODbL attribution.",
                    ["category", "nameContains", "latitude", "longitude", "radiusMeters", "limit"],
                    [],
                    "D4DCA9CA376808CFDF7DEB777D244623D74DF7E82538BF42D8BA21062D49C24F")
            ],
            "weather" =>
            [
                new(
                    "get_japan_current_weather",
                    "Gets current weather conditions for a point in Japan from the MET Norway Locationforecast service operated by the Norwegian Meteorological Institute. This is a clearly labelled third-party model estimate and is not a Japan Meteorological Agency observation, forecast, or warning.",
                    ["latitude", "longitude"],
                    [],
                    "26F792CDBE06CE4DEE8A831526824434E3ACB299EFB0817A4BEF4AB80D814444"),
                new(
                    "get_japan_weather_forecast",
                    "Gets the official Japan Meteorological Agency daily forecast for a Japanese prefecture. Japanese forecast text is returned verbatim alongside an English summary derived from JMA weather codes.",
                    ["prefecture", "officeCode", "days"],
                    [],
                    "AE7FBBBB7176B574090C559722D3C234C2E1AE84457F65105B08E0F85F0C88C9"),
                new(
                    "get_japan_weather_alerts",
                    "Gets current Japan Meteorological Agency warning, advisory, and alert bulletin headlines for a Japanese prefecture from the documented JMA XML feed. Each result links to the authoritative JMA document.",
                    ["prefecture", "officeCode", "limit"],
                    [],
                    "1D6354A11BFE3B32A77CB872E881C2609D2453C1EF2CB6789DF522EE4304E9D6")
            ],
            "accommodation" =>
            [
                new(
                    "search_japan_accommodation",
                    "Searches OpenStreetMap data through the Overpass API for lodging in Japan, including hotels, hostels, guest houses, motels, serviced apartments, camp sites, and mountain huts. Results are places with OpenStreetMap ODbL attribution, not live room inventory, availability, or prices.",
                    ["accommodationType", "nameContains", "latitude", "longitude", "radiusMeters", "limit"],
                    [],
                    "41C8856E6165D061A4524F46D9F2B8AC0DCE1FA975C085851C19C04C90E605EB")
            ],
            "currency" =>
            [
                new(
                    "convert_currency_with_rate",
                    "Converts an amount using a caller-supplied exchange rate. This tool performs arithmetic only, does not claim the rate is current, and formats the result with the target currency's minor-unit precision, so Japanese yen amounts have no decimal places.",
                    ["amount", "sourceCurrency", "exchangeRate", "targetCurrency", "rateObservedAt"],
                    ["amount", "sourceCurrency", "exchangeRate"],
                    "5873C97E3D25B9C0A1B32B1357473AEA8D97D0B5B0594CB4380D395E90A27446"),
                new(
                    "get_exchange_rate",
                    "Gets an attributed exchange rate with its observation date, retrieval time, rate type, source URL, and freshness note. Defaults to the Japanese yen as the target currency.",
                    ["sourceCurrency", "targetCurrency", "date"],
                    ["sourceCurrency"],
                    "FEAEBAFA6C8133B8234439C15A15991274982656A95E55E4C7E9BEC1E762965E"),
                new(
                    "convert_currency",
                    "Converts an amount using an attributed published reference rate and returns the rate source, observation date, and freshness metadata. Defaults to the Japanese yen and formats the result with the target currency's minor-unit precision.",
                    ["amount", "sourceCurrency", "targetCurrency", "date"],
                    ["amount", "sourceCurrency"],
                    "37322C857DA131EB30F784644E597D60587B970A7F6E9174F8DCEC737A386772")
            ],
            _ => throw new ArgumentOutOfRangeException(
                nameof(serverName),
                serverName,
                "Unknown internal MCP server.")
        };
}

public sealed record InternalMcpServer(
    string Name,
    Uri Endpoint,
    IReadOnlyList<InternalMcpToolContract> ToolContracts);

public sealed record InternalMcpToolContract(
    string Name,
    string Description,
    IReadOnlyList<string> Parameters,
    IReadOnlyList<string> RequiredParameters,
    string SchemaSha256);
