using System.ComponentModel.DataAnnotations;

namespace KoreaExpert.AgentHost;

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
                    "search_korea_attractions",
                    "Searches attributed Microsoft Azure Maps data for Korea attractions near a specified point.",
                    ["query", "latitude", "longitude", "radiusMeters", "limit"],
                    ["query"],
                    "4C1A15FF94EA712679A8D1444499DE6C548D25316423C7A32C896732E95C8A27")
            ],
            "weather" =>
            [
                new(
                    "get_korea_current_weather",
                    "Gets attributed current weather for a location in Korea.",
                    ["latitude", "longitude"],
                    [],
                    "83D638AD2BF9E735A9760B4193FE053602D04CF0F54023B34BAE8A3BE15F50D5"),
                new(
                    "get_korea_weather_forecast",
                    "Gets an attributed daily weather forecast for itinerary planning in Korea.",
                    ["latitude", "longitude", "days"],
                    [],
                    "8C5CDE1ED82981F17F5A5282A8AF788D6561650F99B881CDE9B40094D5358292"),
                new(
                    "get_korea_weather_alerts",
                    "Gets current government weather alerts for a location in Korea when the optional alert provider is configured.",
                    ["latitude", "longitude"],
                    [],
                    "83D638AD2BF9E735A9760B4193FE053602D04CF0F54023B34BAE8A3BE15F50D5")
            ],
            "accommodation" =>
            [
                new(
                    "search_korea_accommodation",
                    "Searches Microsoft Azure Maps for accommodation locations in Korea. This returns places, not live room inventory or prices.",
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
