using System.ComponentModel.DataAnnotations;

namespace SeoulTourist.AgentHost;

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

    private static IReadOnlyList<InternalMcpToolContract> GetToolContracts(string serverName) =>
        serverName switch
        {
            "attractions" =>
            [
                new(
                    "search_seoul_attractions",
                    "Searches attributed Microsoft Azure Maps data for Seoul attractions near a specified point.",
                    ["query", "latitude", "longitude", "radiusMeters", "limit"],
                    ["query"],
                    "4C1A15FF94EA712679A8D1444499DE6C548D25316423C7A32C896732E95C8A27")
            ],
            "weather" =>
            [
                new(
                    "get_seoul_current_weather",
                    "Gets attributed current weather for a location in Seoul.",
                    ["latitude", "longitude"],
                    [],
                    "254F216785FE8B307FD402CDB4CE986CC3D3E80D8E4B16C195B7A1A46A274E23"),
                new(
                    "get_seoul_weather_forecast",
                    "Gets an attributed daily weather forecast for itinerary planning in Seoul.",
                    ["latitude", "longitude", "days"],
                    [],
                    "224ED685D98C549F0504D5244F4B327B2CE915015F163EE374ED8F51B793CF37"),
                new(
                    "get_seoul_weather_alerts",
                    "Gets current government weather alerts for a location in Seoul when the optional alert provider is configured.",
                    ["latitude", "longitude"],
                    [],
                    "254F216785FE8B307FD402CDB4CE986CC3D3E80D8E4B16C195B7A1A46A274E23")
            ],
            "accommodation" =>
            [
                new(
                    "search_seoul_accommodation",
                    "Searches Microsoft Azure Maps for accommodation locations in Seoul. This returns places, not live room inventory or prices.",
                    ["query", "latitude", "longitude", "radiusMeters", "limit"],
                    [],
                    "B9F5CEB20CFC015D8D6CBCBE79621C75C0E0610D5055021A9270BC4C1904409B")
            ],
            "currency" =>
            [
                new(
                    "convert_currency_with_rate",
                    "Converts an amount using a caller-supplied exchange rate. This tool performs arithmetic and does not claim the rate is current.",
                    ["amount", "sourceCurrency", "targetCurrency", "exchangeRate", "rateObservedAt"],
                    ["amount", "sourceCurrency", "targetCurrency", "exchangeRate"],
                    "19F8CA7AC557BCF787FDE7B03924ED19C25581E69C761EF049C69E3ECDFE9D5F"),
                new(
                    "get_exchange_rate",
                    "Gets an attributed exchange rate with its observation time, retrieval time, rate type, and freshness note.",
                    ["sourceCurrency", "targetCurrency", "date"],
                    ["sourceCurrency", "targetCurrency"],
                    "6F88B51C86D245586179F4E71F2562ACFF2C97542E351F415437B647A8474850"),
                new(
                    "convert_currency",
                    "Converts an amount using an attributed provider rate and returns the rate source and freshness metadata.",
                    ["amount", "sourceCurrency", "targetCurrency", "date"],
                    ["amount", "sourceCurrency", "targetCurrency"],
                    "FF99667CE359D80009B12F6A7D2E6EC200B4ECD10CDFF1503300427E17621B08")
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
