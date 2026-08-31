using System.Reflection;
using System.Text.Json;
using JapanExpert.AgentHost;
using JapanExpert.Mcp.Accommodation;
using JapanExpert.Mcp.Attractions;
using JapanExpert.Mcp.Currency;
using JapanExpert.Mcp.Weather;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Tools.Tests;

/// <summary>
/// Locks the Japan Expert MCP tool surface: names, descriptions, and generated input schemas.
/// The agent host validates the exact tool-name set before exposing tools to the model, so a
/// rename here is a breaking contract change and must fail this test first.
/// </summary>
[TestClass]
public sealed class McpToolContractTests
{
    private static readonly Type[] ToolTypes =
    [
        typeof(AttractionTools),
        typeof(AccommodationTools),
        typeof(WeatherTools),
        typeof(CurrencyTools),
        typeof(ExchangeRateTools)
    ];

    private static readonly string[] AttractionParameterNames =
        ["category", "nameContains", "latitude", "longitude", "radiusMeters", "limit"];

    private static readonly string[] ConvertCurrencyRequiredParameters =
        ["amount", "sourceCurrency"];

    private static readonly string[] LodgingTypeNames =
        ["hotel", "hostel", "guest_house", "motel", "apartment", "camp_site", "alpine_hut"];

    [TestMethod]
    public void ToolNamesMatchTheJapanExpertContract()
    {
        string[] expected =
        [
            "convert_currency",
            "convert_currency_with_rate",
            "get_exchange_rate",
            "get_japan_current_weather",
            "get_japan_weather_alerts",
            "get_japan_weather_forecast",
            "search_japan_accommodation",
            "search_japan_attractions"
        ];

        CollectionAssert.AreEqual(expected, ToolNames());
    }

    [TestMethod]
    public void NoActiveToolNameStillReferencesSeoul()
    {
        foreach (var name in ToolNames())
        {
            Assert.DoesNotContain("seoul", name, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("korea", name, StringComparison.OrdinalIgnoreCase);
        }
    }

    [TestMethod]
    public void EveryToolTypeIsDiscoverableByTheMcpServer()
    {
        foreach (var toolType in ToolTypes)
        {
            Assert.IsNotNull(
                toolType.GetCustomAttribute<McpServerToolTypeAttribute>(),
                $"{toolType.Name} must be annotated with McpServerToolType.");
        }
    }

    [TestMethod]
    public void AttractionToolSchemaExposesJapanBoundsAndTokyoDefaults()
    {
        var schema = McpToolSchema.For(
            typeof(AttractionTools),
            nameof(AttractionTools.SearchJapanAttractionsAsync));

        Assert.AreEqual("search_japan_attractions", schema.Name);
        StringAssert.Contains(schema.Description, "OpenStreetMap");
        StringAssert.Contains(schema.Description, "ODbL attribution");

        var properties = schema.Properties;
        CollectionAssert.AreEquivalent(
            AttractionParameterNames,
            properties.Keys.ToArray());
        Assert.AreEqual("all", properties["category"].GetProperty("default").GetString());
        Assert.AreEqual(35.6762, properties["latitude"].GetProperty("default").GetDouble());
        Assert.AreEqual(139.6503, properties["longitude"].GetProperty("default").GetDouble());
        Assert.AreEqual(5000, properties["radiusMeters"].GetProperty("default").GetInt32());
        Assert.AreEqual(8, properties["limit"].GetProperty("default").GetInt32());
        StringAssert.Contains(
            properties["category"].GetProperty("description").GetString()!,
            "museum");
    }

    [TestMethod]
    public void AccommodationToolSchemaExposesLodgingTypesAndTokyoDefaults()
    {
        var schema = McpToolSchema.For(
            typeof(AccommodationTools),
            nameof(AccommodationTools.SearchJapanAccommodationAsync));

        Assert.AreEqual("search_japan_accommodation", schema.Name);
        StringAssert.Contains(schema.Description, "not live room inventory");

        var properties = schema.Properties;
        Assert.AreEqual("all", properties["accommodationType"].GetProperty("default").GetString());
        Assert.AreEqual(35.6762, properties["latitude"].GetProperty("default").GetDouble());
        Assert.AreEqual(10000, properties["radiusMeters"].GetProperty("default").GetInt32());
        Assert.AreEqual(10, properties["limit"].GetProperty("default").GetInt32());
        var description = properties["accommodationType"].GetProperty("description").GetString()!;
        foreach (var lodging in LodgingTypeNames)
        {
            StringAssert.Contains(description, lodging);
        }
    }

    [TestMethod]
    public void CurrentWeatherToolIsLabelledAsAThirdPartyEstimate()
    {
        var schema = McpToolSchema.For(
            typeof(WeatherTools),
            nameof(WeatherTools.GetJapanCurrentWeatherAsync));

        Assert.AreEqual("get_japan_current_weather", schema.Name);
        StringAssert.Contains(schema.Description, "MET Norway");
        StringAssert.Contains(
            schema.Description,
            "not a Japan Meteorological Agency observation, forecast, or warning");
        Assert.AreEqual(35.6762, schema.Properties["latitude"].GetProperty("default").GetDouble());
        Assert.AreEqual(139.6503, schema.Properties["longitude"].GetProperty("default").GetDouble());
    }

    [TestMethod]
    public void ForecastToolDefaultsToTokyoAndNamesJmaAsTheAuthority()
    {
        var schema = McpToolSchema.For(
            typeof(WeatherTools),
            nameof(WeatherTools.GetJapanWeatherForecastAsync));

        Assert.AreEqual("get_japan_weather_forecast", schema.Name);
        StringAssert.Contains(schema.Description, "official Japan Meteorological Agency");
        Assert.AreEqual("Tokyo", schema.Properties["prefecture"].GetProperty("default").GetString());
        Assert.AreEqual(5, schema.Properties["days"].GetProperty("default").GetInt32());
        StringAssert.Contains(
            schema.Properties["officeCode"].GetProperty("description").GetString()!,
            "130000");
    }

    [TestMethod]
    public void AlertToolReadsTheDocumentedJmaFeed()
    {
        var schema = McpToolSchema.For(
            typeof(WeatherTools),
            nameof(WeatherTools.GetJapanWeatherAlertsAsync));

        Assert.AreEqual("get_japan_weather_alerts", schema.Name);
        StringAssert.Contains(schema.Description, "documented JMA XML feed");
        Assert.AreEqual("Tokyo", schema.Properties["prefecture"].GetProperty("default").GetString());
        Assert.AreEqual(10, schema.Properties["limit"].GetProperty("default").GetInt32());
    }

    [TestMethod]
    public void CurrencyToolsKeepGenericNamesAndDefaultToJapaneseYen()
    {
        var rate = McpToolSchema.For(
            typeof(ExchangeRateTools),
            nameof(ExchangeRateTools.GetExchangeRateAsync));
        var convert = McpToolSchema.For(
            typeof(ExchangeRateTools),
            nameof(ExchangeRateTools.ConvertCurrencyAsync));
        var arithmetic = McpToolSchema.For(
            typeof(CurrencyTools),
            nameof(CurrencyTools.ConvertCurrency));

        Assert.AreEqual("get_exchange_rate", rate.Name);
        Assert.AreEqual("convert_currency", convert.Name);
        Assert.AreEqual("convert_currency_with_rate", arithmetic.Name);

        Assert.AreEqual("JPY", rate.Properties["targetCurrency"].GetProperty("default").GetString());
        Assert.AreEqual("JPY", convert.Properties["targetCurrency"].GetProperty("default").GetString());
        Assert.AreEqual(
            "JPY",
            arithmetic.Properties["targetCurrency"].GetProperty("default").GetString());
        StringAssert.Contains(arithmetic.Description, "does not claim the rate is current");
    }

    [TestMethod]
    public void RequiredParametersStayRequired()
    {
        var convert = McpToolSchema.For(
            typeof(ExchangeRateTools),
            nameof(ExchangeRateTools.ConvertCurrencyAsync));

        CollectionAssert.AreEquivalent(
            ConvertCurrencyRequiredParameters,
            convert.Required);
    }

    [TestMethod]
    public void CancellationTokensAreNotExposedInToolSchemas()
    {
        foreach (var (toolType, methodName) in AllToolMethods())
        {
            var schema = McpToolSchema.For(toolType, methodName);
            Assert.DoesNotContain(
                "cancellationToken",
                schema.Properties.Keys,
                StringComparer.Ordinal);
        }
    }

    [TestMethod]
    public void HostPinsMatchTheSchemasPublishedByEveryMcpTool()
    {
        var options = new InternalMcpOptions
        {
            AttractionsEndpoint = "https://attractions.example/mcp",
            WeatherEndpoint = "https://weather.example/mcp",
            AccommodationEndpoint = "https://accommodation.example/mcp",
            CurrencyEndpoint = "https://currency.example/mcp"
        };
        var expected = options.GetServers()
            .SelectMany(server => server.ToolContracts)
            .ToDictionary(contract => contract.Name, StringComparer.Ordinal);
        var actual = AllToolMethods()
            .Select(entry => McpToolSchema.For(entry.ToolType, entry.MethodName))
            .ToDictionary(schema => schema.Name, StringComparer.Ordinal);

        CollectionAssert.AreEquivalent(expected.Keys.ToArray(), actual.Keys.ToArray());
        foreach (var contract in expected.Values)
        {
            var schema = actual[contract.Name];
            Assert.AreEqual(contract.Description, schema.Description);
            Assert.AreEqual(
                contract.SchemaSha256,
                InternalMcpToolCatalog.ComputeSchemaFingerprint(schema.InputSchema),
                $"Schema fingerprint drifted for {contract.Name}.");
        }
    }

    private static string[] ToolNames() =>
        [.. AllToolMethods()
            .Select(entry => McpToolSchema.For(entry.ToolType, entry.MethodName).Name)
            .Order(StringComparer.Ordinal)];

    private static IEnumerable<(Type ToolType, string MethodName)> AllToolMethods() =>
        ToolTypes.SelectMany(toolType => toolType
            .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .Where(method => method.GetCustomAttribute<McpServerToolAttribute>() is not null)
            .Select(method => (toolType, method.Name)));
}

/// <summary>Reads the protocol-level tool definition the MCP server would publish.</summary>
internal sealed record McpToolSchema(
    string Name,
    string Description,
    JsonElement InputSchema,
    IReadOnlyDictionary<string, JsonElement> Properties,
    string[] Required)
{
    internal static McpToolSchema For(Type toolType, string methodName)
    {
        var method = toolType.GetMethod(
            methodName,
            BindingFlags.Public | BindingFlags.Instance)
            ?? throw new InvalidOperationException($"{toolType.Name}.{methodName} was not found.");
        var tool = McpServerTool.Create(method, ToolStubs.CreateTarget(toolType)).ProtocolTool;

        var properties = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        if (tool.InputSchema.TryGetProperty("properties", out var propertyBag))
        {
            foreach (var property in propertyBag.EnumerateObject())
            {
                properties[property.Name] = property.Value.Clone();
            }
        }

        string[] required = tool.InputSchema.TryGetProperty("required", out var requiredBag)
            ? [.. requiredBag.EnumerateArray().Select(entry => entry.GetString()!)]
            : [];

        return new McpToolSchema(
            tool.Name!,
            tool.Description ?? string.Empty,
            tool.InputSchema.Clone(),
            properties,
            required);
    }
}
