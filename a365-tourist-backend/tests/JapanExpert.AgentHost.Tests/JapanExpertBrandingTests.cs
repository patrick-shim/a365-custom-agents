using System.Text.Json;
using JapanExpert.AgentHost;

namespace JapanExpert.AgentHost.Tests;

[TestClass]
public sealed class JapanExpertBrandingTests
{
    private static readonly string[] ExpectedFoundryScopes = ["https://ai.azure.com/.default"];

    private static readonly Type AgentHostOptionsType = typeof(AgentHostOptions);

    private static readonly string[] ProductBrandedHostFiles =
    [
        "Program.cs",
        "JapanExpertApplication.cs",
        "PurviewDlpOptions.cs",
        "AgentFailureClassifier.cs"
    ];

    [TestMethod]
    public void PurviewApplicationNameDefaultsToJapanExpert()
    {
        var options = new PurviewDlpOptions();

        Assert.AreEqual("Japan Expert", options.AppName);
    }

    [TestMethod]
    public void ConfiguredPurviewApplicationNameUsesJapanExpert()
    {
        using var settings = ReadHostSettings("appsettings.json");

        Assert.AreEqual(
            "Japan Expert",
            settings.RootElement.GetProperty("PurviewDlp").GetProperty("AppName").GetString());
    }

    [TestMethod]
    public void OboAzureBotConnectionUsesJapanExpertNaming()
    {
        using var settings = ReadHostSettings("appsettings.json");

        var connectionName = settings.RootElement
            .GetProperty("AgentApplication")
            .GetProperty("UserAuthorization")
            .GetProperty("Handlers")
            .GetProperty("obo-user")
            .GetProperty("Settings")
            .GetProperty("AzureBotOAuthConnectionName")
            .GetString();

        Assert.AreEqual("japan-expert-obo", connectionName);
    }

    [TestMethod]
    public void DevelopmentLoggingCategoryMatchesTheRootNamespace()
    {
        using var settings = ReadHostSettings("appsettings.Development.json");

        var levels = settings.RootElement.GetProperty("Logging").GetProperty("LogLevel");

        Assert.IsTrue(levels.TryGetProperty("JapanExpert", out var level));
        Assert.AreEqual("Debug", level.GetString());
        Assert.IsFalse(levels.TryGetProperty("SeoulTourist", out _));
    }

    [TestMethod]
    public void LandingEndpointsUseJapanExpertBranding()
    {
        var program = RepositoryPaths.ReadAgentHostFile("Program.cs");

        StringAssert.Contains(program, "\"Japan Expert\"");
        StringAssert.Contains(program, "Japan Expert processes conversation and tool content");
        StringAssert.Contains(program, "Use of Japan Expert is subject to your organization's Microsoft 365 policies");
    }

    [TestMethod]
    public void ConversationGuidanceTargetsJapanRatherThanASingleCity()
    {
        var application = RepositoryPaths.ReadAgentHostFile("JapanExpertApplication.cs");

        StringAssert.Contains(application, "I can help plan a trip anywhere in Japan");
        StringAssert.Contains(application, "Tell me what you would like to plan in Japan.");
        StringAssert.Contains(application, "agentName: \"Japan Expert\"");
        StringAssert.Contains(application, "Governed Japan travel planning assistant");
    }

    [TestMethod]
    public void ModelEndpointIsTheFoundryProjectEndpointWithoutInlineRequestDetails()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var agentHost = settings.RootElement.GetProperty("AgentHost");

        var endpoint = new Uri(
            agentHost.GetProperty("FoundryProjectEndpoint").GetString()
            ?? throw new AssertFailedException("AgentHost:FoundryProjectEndpoint is missing."));

        // The OpenAI-compatible Responses surface lives at the Foundry account root; the
        // project-scoped /api/projects/<name> form does not publish /openai/v1. The configured
        // value must stay free of request paths, deployment segments, and api-version strings.
        Assert.AreEqual(
            "https://a365-ai-foundry.services.ai.azure.com/",
            endpoint.AbsoluteUri);
        Assert.AreEqual(Uri.UriSchemeHttps, endpoint.Scheme);
        Assert.AreEqual("a365-ai-foundry.services.ai.azure.com", endpoint.Host);
        Assert.AreEqual("/", endpoint.AbsolutePath);
        Assert.IsEmpty(endpoint.Query);
        Assert.DoesNotContain("/api/projects/", endpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("/openai/", endpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("responses", endpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("api-version", endpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
    }

    [TestMethod]
    public void HostCarriesNoLegacyAzureOpenAIAccountNaming()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var agentHost = settings.RootElement.GetProperty("AgentHost");

        // The Responses path is described entirely in Foundry terms: no account endpoint, no
        // chat/account-era option or configuration key survives.
        Assert.DoesNotContain("AzureOpenAI", agentHost.GetRawText(), StringComparison.Ordinal);
        Assert.DoesNotContain(
            "cognitiveservices.azure.com",
            agentHost.GetRawText(),
            StringComparison.OrdinalIgnoreCase);
        Assert.IsFalse(
            AgentHostOptionsType.GetProperties()
                .Any(property => property.Name.Contains("AzureOpenAI", StringComparison.Ordinal)),
            "AgentHostOptions must not expose Azure OpenAI account-era members.");
    }

    [TestMethod]
    public void ModelDeploymentNameIsSuppliedSeparatelyFromTheEndpoint()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var agentHost = settings.RootElement.GetProperty("AgentHost");

        Assert.AreEqual("gpt-5.6-sol", agentHost.GetProperty("FoundryModelDeployment").GetString());
    }

    [TestMethod]
    public void ChatClientResolvesTheModelThroughTheOpenAIResponsesClient()
    {
        var factory = RepositoryPaths.ReadAgentHostFile("AgentChatClientFactory.cs");

        StringAssert.Contains(factory, "new OpenAIClient(");
        StringAssert.Contains(factory, "new BearerTokenPolicy(credential, AgentIdentityAuthorizationScopes.Foundry)");
        StringAssert.Contains(factory, "BuildResponsesEndpoint(_agentHostOptions.FoundryProjectEndpoint)");
        StringAssert.Contains(factory, ".GetResponsesClient()");
        StringAssert.Contains(factory, ".AsIChatClientWithStoredOutputDisabled(_agentHostOptions.FoundryModelDeployment)");

        // The legacy chat-completions path must be gone: gpt-5.6-sol is a Responses API model.
        Assert.DoesNotContain("AzureOpenAIClient", factory, StringComparison.Ordinal);
        Assert.DoesNotContain("GetChatClient(", factory, StringComparison.Ordinal);
        Assert.DoesNotContain("using Azure.AI.OpenAI;", factory, StringComparison.Ordinal);
    }

    [TestMethod]
    public void ResponsesEndpointAppendsTheOpenAICompatibleBaseExactlyOnce()
    {
        var expected = new Uri(
            "https://a365-ai-foundry.services.ai.azure.com/openai/v1");

        Assert.AreEqual(
            expected,
            AgentChatClientFactory.BuildResponsesEndpoint(
                "https://a365-ai-foundry.services.ai.azure.com"));
        Assert.AreEqual(
            expected,
            AgentChatClientFactory.BuildResponsesEndpoint(
                "https://a365-ai-foundry.services.ai.azure.com/"));
        Assert.ThrowsExactly<ArgumentException>(
            () => AgentChatClientFactory.BuildResponsesEndpoint("  "));
    }

    [TestMethod]
    public void ConfiguredResponsesEndpointMatchesTheFoundryProjectOption()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var configured = settings.RootElement
            .GetProperty("AgentHost")
            .GetProperty("FoundryProjectEndpoint")
            .GetString()!;

        var responsesEndpoint = AgentChatClientFactory.BuildResponsesEndpoint(configured);

        Assert.AreEqual("/openai/v1", responsesEndpoint.AbsolutePath);
        Assert.IsEmpty(responsesEndpoint.Query);
        Assert.DoesNotContain("api-version", responsesEndpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("/responses", responsesEndpoint.AbsoluteUri, StringComparison.OrdinalIgnoreCase);
    }

    [TestMethod]
    public void FoundryTurnScopeMatchesTheConfiguredAgenticHandlerScope()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var scopes = settings.RootElement
            .GetProperty("AgentApplication")
            .GetProperty("UserAuthorization")
            .GetProperty("Handlers")
            .GetProperty("agentic-foundry")
            .GetProperty("Settings")
            .GetProperty("Scopes")
            .EnumerateArray()
            .Select(scope => scope.GetString())
            .ToArray();

        // The bearer token policy asks the per-turn credential for this exact scope, and the turn
        // token dictionary is keyed by it, so configuration and constant must not drift.
        CollectionAssert.AreEqual(ExpectedFoundryScopes, scopes);
        CollectionAssert.AreEqual(new[] { AgentIdentityAuthorizationScopes.Foundry }, scopes);
    }

    [TestMethod]
    public void RetiredCognitiveServicesScopeIsGoneFromTheWholeHostConfiguration()
    {
        var settings = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "appsettings.json"));

        // Project Responses endpoints are guarded by ai.azure.com; the old Azure OpenAI account
        // resource must not linger anywhere in host configuration.
        Assert.DoesNotContain(
            "https://cognitiveservices.azure.com/.default",
            settings,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("cognitiveservices.azure.com", settings, StringComparison.OrdinalIgnoreCase);
    }

    [TestMethod]
    public void BlueprintAndOboFlowsStaySeparateWhileSharingTheFoundryScope()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var handlers = settings.RootElement
            .GetProperty("AgentApplication")
            .GetProperty("UserAuthorization")
            .GetProperty("Handlers");

        // Blueprint/agentic flow: agentic handler federates through ServiceConnection.
        var agentic = handlers.GetProperty("agentic-foundry");
        Assert.AreEqual("AgenticUserAuthorization", agentic.GetProperty("Type").GetString());
        Assert.AreEqual(
            "ServiceConnection",
            agentic.GetProperty("Settings").GetProperty("AlternateBlueprintConnectionName").GetString());

        // OBO flow: distinct handler and Azure Bot connection; its Foundry scope is requested by
        // the token exchange at turn time rather than declared as a handler scope.
        var obo = handlers.GetProperty("obo-user");
        Assert.AreEqual("AzureBotUserAuthorization", obo.GetProperty("Type").GetString());
        Assert.AreEqual(
            "japan-expert-obo",
            obo.GetProperty("Settings").GetProperty("AzureBotOAuthConnectionName").GetString());
        Assert.IsFalse(obo.GetProperty("Settings").TryGetProperty("Scopes", out _));

        // Blueprint federation scopes are Agent 365 connection scopes and stay unchanged.
        foreach (var connectionName in new[] { "ServiceConnection", "OboServiceConnection" })
        {
            var connectionScopes = settings.RootElement
                .GetProperty("Connections")
                .GetProperty(connectionName)
                .GetProperty("Settings")
                .GetProperty("Scopes")
                .EnumerateArray()
                .Select(scope => scope.GetString())
                .ToArray();

            Assert.HasCount(1, connectionScopes);
            Assert.DoesNotContain("ai.azure.com", connectionScopes[0]!, StringComparison.OrdinalIgnoreCase);
        }
    }

    [TestMethod]
    public void OboTokenExchangeRequestsTheSameFoundryScopeAsTheAgenticFlow()
    {
        var application = RepositoryPaths.ReadAgentHostFile("JapanExpertApplication.cs");

        // Both protected frontend modes must land on the same Foundry resource constant so a single
        // Agent 365 permission grant covers the Blueprint child and the OBO child.
        StringAssert.Contains(application, "[AgentIdentityAuthorizationScopes.Foundry]");
        StringAssert.Contains(application, "accessTokens[AgentIdentityAuthorizationScopes.Foundry] = foundryToken;");
        Assert.DoesNotContain("cognitiveservices.azure.com", application, StringComparison.OrdinalIgnoreCase);
    }

    [TestMethod]
    public void DirectlyUsedCompileTimePackagesAreReferencedDirectly()
    {
        var project = RepositoryPaths.ReadAgentHostFile("JapanExpert.AgentHost.csproj");
        var factory = RepositoryPaths.ReadAgentHostFile("AgentChatClientFactory.cs");

        // Namespaces the host compiles against must come from direct references, never from a
        // transitive graph that a dependency bump could silently remove.
        foreach (var (usingDirective, package) in new[]
        {
            ("using OpenAI;", "OpenAI"),
            ("using OpenAI.Responses;", "OpenAI"),
            ("using System.ClientModel.Primitives;", "System.ClientModel")
        })
        {
            StringAssert.Contains(factory, usingDirective);
            StringAssert.Contains(
                project,
                $"<PackageReference Include=\"{package}\" />",
                $"{package} supplies {usingDirective} and must be referenced directly.");
        }

        StringAssert.Contains(project, "<PackageReference Include=\"Microsoft.Agents.AI.OpenAI\" />");
        Assert.DoesNotContain("Azure.AI.OpenAI\"", project, StringComparison.Ordinal);
    }

    [TestMethod]
    public void ExtensionsAiOpenAiIsReferencedOnlyAsARuntimeCompatibilityFloor()
    {
        var project = RepositoryPaths.ReadAgentHostFile("JapanExpert.AgentHost.csproj");

        // Present so the central pin binds: Microsoft.Agents.AI.OpenAI needs this assembly at
        // runtime but declares a lower minimum, and a transitive-only reference would resolve to
        // that lower floor instead of the centrally pinned version.
        StringAssert.Contains(project, "<PackageReference Include=\"Microsoft.Extensions.AI.OpenAI\" />");
        StringAssert.Contains(project, "Runtime compatibility floor only.");

        // ...but it must stay a runtime floor rather than a compile-time dependency. The package
        // ships its types under the Microsoft.Extensions.AI namespace, so a using directive cannot
        // distinguish it; the concrete signal is the OpenAI-client adapter this host used before
        // the Responses migration. Its return would make the package compile-time again.
        var hostSources = Directory.EnumerateFiles(
            Path.GetDirectoryName(RepositoryPaths.AgentHostFile("Program.cs"))!,
            "*.cs",
            SearchOption.AllDirectories);

        foreach (var sourceFile in hostSources)
        {
            Assert.DoesNotContain(
                ".AsIChatClient(",
                File.ReadAllText(sourceFile),
                StringComparison.Ordinal,
                $"{Path.GetFileName(sourceFile)} uses the Microsoft.Extensions.AI.OpenAI chat-completions "
                + "adapter, so the package is a compile-time dependency and must move to the direct "
                + "compile-time reference list.");
        }
    }

    [TestMethod]
    public void CentralPinKeepsTheExtensionsAiOpenAiRuntimeFloorAtOrAbove1080300()
    {
        var centralPins = File.ReadAllText(
            Path.Combine(RepositoryPaths.BackendRoot, "Directory.Packages.props"));

        var match = System.Text.RegularExpressions.Regex.Match(
            centralPins,
            "<PackageVersion\\s+Include=\"Microsoft\\.Extensions\\.AI\\.OpenAI\"\\s+Version=\"(?<version>[^\"]+)\"");

        Assert.IsTrue(match.Success, "Microsoft.Extensions.AI.OpenAI must stay centrally pinned.");
        Assert.IsTrue(
            Version.TryParse(match.Groups["version"].Value, out var pinned),
            $"Unexpected version format '{match.Groups["version"].Value}'.");
        Assert.IsGreaterThanOrEqualTo(
            new Version(10, 8, 3),
            pinned,
            "The Microsoft.Extensions.AI.OpenAI runtime floor must not regress below 10.8.3.");
    }

    [TestMethod]
    public void ResponsesAdapterIsReferencedAndLegacyAzureOpenAIPackageIsRemoved()
    {
        var project = RepositoryPaths.ReadAgentHostFile("JapanExpert.AgentHost.csproj");

        StringAssert.Contains(project, "<PackageReference Include=\"Microsoft.Agents.AI.OpenAI\" />");

        // The Azure OpenAI account-era client package is gone for good; the deliberately retained
        // Microsoft.Extensions.AI.OpenAI runtime floor must not be mistaken for it.
        Assert.DoesNotContain(
            "<PackageReference Include=\"Azure.AI.OpenAI\" />",
            project,
            StringComparison.Ordinal);
        Assert.DoesNotContain("using Azure.AI.OpenAI;", project, StringComparison.Ordinal);
        StringAssert.Contains(project, "<PackageReference Include=\"Microsoft.Extensions.AI.OpenAI\" />");
    }

    [TestMethod]
    public void AgentHostConfigurationExposesNoUnusedOrTenantBoundModelOptions()
    {
        using var settings = ReadHostSettings("appsettings.json");
        var agentHost = settings.RootElement.GetProperty("AgentHost");

        var allowedKeys = new[]
        {
            "FoundryProjectEndpoint",
            "FoundryModelDeployment",
            "MaximumPromptCharacters"
        };
        var actualKeys = agentHost.EnumerateObject().Select(property => property.Name).ToArray();

        CollectionAssert.AreEquivalent(allowedKeys, actualKeys);
        foreach (var boundOption in AgentHostOptionsType.GetProperties())
        {
            Assert.Contains(
                boundOption.Name,
                allowedKeys,
                $"AgentHostOptions.{boundOption.Name} has no configured counterpart.");
        }
    }

    [TestMethod]
    public void HostConfigurationCarriesNoSubscriptionResourceGroupOrTenantIdentifiers()
    {
        var settings = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "appsettings.json"));

        foreach (var forbidden in new[] { "subscriptionId", "resourceGroup", "/subscriptions/", "tenantId\":\"" })
        {
            Assert.DoesNotContain(
                forbidden,
                settings,
                StringComparison.OrdinalIgnoreCase,
                $"appsettings.json must not carry '{forbidden}'.");
        }

        using var document = JsonDocument.Parse(settings);
        Assert.IsEmpty(document.RootElement.GetProperty("TokenValidation").GetProperty("TenantId").GetString()!);
        Assert.IsEmpty(document.RootElement.GetProperty("PurviewDlp").GetProperty("TenantId").GetString()!);
        Assert.IsEmpty(document.RootElement.GetProperty("PurviewDlp").GetProperty("ApplicationId").GetString()!);
    }

    [TestMethod]
    public void EveryClassifiedFailureCodeUsesTheJapanExpertPrefix()
    {
        foreach (var kind in Enum.GetValues<AgentFailureKind>())
        {
            var failure = AgentFailureClassifier.Classify(
                new InvalidOperationException("canary"),
                kind);

            StringAssert.StartsWith(failure.Code, "JEX-");
            Assert.DoesNotContain("STA-", failure.Code, StringComparison.Ordinal);
        }
    }

    [TestMethod]
    public void ProductBrandedHostSourceCarriesNoSeoulIdentifiers()
    {
        foreach (var fileName in ProductBrandedHostFiles)
        {
            var source = RepositoryPaths.ReadAgentHostFile(fileName);

            Assert.IsFalse(
                source.Contains("Seoul", StringComparison.OrdinalIgnoreCase),
                $"{fileName} still contains Seoul product branding.");
            Assert.DoesNotContain(
                "STA-",
                source,
                StringComparison.Ordinal,
                $"{fileName} still contains a Seoul Tourist Assistant error-code prefix.");
        }
    }

    private static JsonDocument ReadHostSettings(string fileName) =>
        JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, fileName)));
}
