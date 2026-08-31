using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Agents.Authentication.Msal;
using Microsoft.Agents.Authentication.Msal.Model;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Client;
using JapanExpert.AgentHost;

namespace JapanExpert.AgentHost.Tests;

[TestClass]
public sealed class AgentIdentityAuthorizationOptionsTests
{
    private static readonly string[] ExpectedAgenticHandlers =
        ["agentic-foundry", "agentic-purview", "agentic-mcp"];
    private static readonly string[] ExpectedOboHandlers =
        ["obo-user"];
    private const string TokenExchangeScope = "api://AzureADTokenExchange/.default";
    private const string MessagingBotApiScope = "5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default";
    private const string BotConnectorScope = "https://api.botframework.com/.default";
    private static readonly string[] ExpectedBlueprintFederatedConnections =
        ["ServiceConnection", "OboServiceConnection"];

    [TestMethod]
    public void FrontendModesUseDisjointAutoSignInHandlers()
    {
        var options = new AgentIdentityAuthorizationOptions();
        var agenticHandlers = options.GetHandlers(AgentFrontendMode.AgenticUser)
            .GetAutoSignInHandlerNames(includePurview: true, includeInternalMcp: true);
        var oboHandlers = options.GetHandlers(AgentFrontendMode.OnBehalfOf)
            .GetAutoSignInHandlerNames(includePurview: true, includeInternalMcp: true);

        CollectionAssert.AreEqual(
            ExpectedAgenticHandlers,
            agenticHandlers);
        CollectionAssert.AreEqual(
            ExpectedOboHandlers,
            oboHandlers);
        Assert.IsFalse(agenticHandlers.Intersect(oboHandlers, StringComparer.Ordinal).Any());
    }

    [TestMethod]
    public void OboHandlerReturnsRawBlueprintUserAssertion()
    {
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "appsettings.json");
        using var settings = JsonDocument.Parse(File.ReadAllText(path));
        var handlers = settings.RootElement
            .GetProperty("AgentApplication")
            .GetProperty("UserAuthorization")
            .GetProperty("Handlers");

        foreach (var handlerName in ExpectedOboHandlers)
        {
            var handler = handlers.GetProperty(handlerName);
            var handlerSettings = handler.GetProperty("Settings");

            Assert.AreEqual(
                "AzureBotUserAuthorization",
                handler.GetProperty("Type").GetString());
            Assert.AreEqual(
                "japan-expert-obo",
                handlerSettings.GetProperty("AzureBotOAuthConnectionName").GetString());
            Assert.IsFalse(handlerSettings.TryGetProperty("OBOConnectionName", out _));
            Assert.IsFalse(handlerSettings.TryGetProperty("OBOScopes", out _));
        }
    }

    [TestMethod]
    public void ChildIdentityConnectionsUseBlueprintFederation()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        using var settings = JsonDocument.Parse(File.ReadAllText(path));
        var connections = settings.RootElement.GetProperty("Connections");

        foreach (var connectionName in ExpectedBlueprintFederatedConnections)
        {
            var connection = connections
                .GetProperty(connectionName)
                .GetProperty("Settings");

            Assert.AreEqual(
                "FederatedCredentials",
                connection.GetProperty("AuthType").GetString());
            Assert.IsTrue(connection.TryGetProperty("ClientId", out _));
            Assert.IsTrue(connection.TryGetProperty("FederatedClientId", out _));
        }

        // OboServiceConnection only produces the child-bound parent assertion, so it targets the
        // Entra token-exchange audience. ServiceConnection is the ConnectionsMap default for
        // outbound /api/messages channel calls, which target the Agent 365 Messaging Bot API.
        CollectionAssert.AreEqual(
            new[] { TokenExchangeScope },
            connections.GetProperty("OboServiceConnection").GetProperty("Settings")
                .GetProperty("Scopes").EnumerateArray().Select(scope => scope.GetString()).ToArray());
        CollectionAssert.AreEqual(
            new[] { MessagingBotApiScope },
            connections.GetProperty("ServiceConnection").GetProperty("Settings")
                .GetProperty("Scopes").EnumerateArray().Select(scope => scope.GetString()).ToArray());

        Assert.IsTrue(connections
            .GetProperty("ServiceConnection")
            .GetProperty("Settings")
            .TryGetProperty("AgentId", out _));
        Assert.IsFalse(connections
            .GetProperty("OboServiceConnection")
            .GetProperty("Settings")
            .TryGetProperty("AgentId", out _));

        var obo = settings.RootElement.GetProperty("AgentIdentityObo");
        Assert.IsTrue(obo.TryGetProperty("AgentId", out _));
        Assert.AreEqual(
            "OboServiceConnection",
            obo.GetProperty("BlueprintConnectionName").GetString());
    }

    [TestMethod]
    public void DeployedConnectionAudiencesMatchTheirRuntimePurpose()
    {
        var templatePath = Path.Combine(
            RepositoryPaths.BackendRoot,
            "infra",
            "modules",
            "agent-host-container-app.bicep");
        var template = File.ReadAllText(templatePath);

        // Each connection has exactly one correct audience: the child-bound parent assertion uses
        // Entra token exchange, the agentic route's outbound channel calls use the Agent 365
        // Messaging Bot API, and only the OBO channel uses the Bot Connector.
        var expected = new (string Connection, string Scope)[]
        {
            ("OboServiceConnection", "api://AzureADTokenExchange/\\.default"),
            ("ServiceConnection", "5a807f24-c9de-44ee-a3a7-329e88a00ffc/\\.default"),
            ("OboChannelConnection", "https://api\\.botframework\\.com/\\.default")
        };

        foreach (var (connection, scope) in expected)
        {
            Assert.IsTrue(
                Regex.IsMatch(
                    template,
                    $"name: 'Connections__{connection}__Settings__Scopes__0'\\r?\\n\\s+value: '{scope}'"),
                $"{connection} must request its documented audience.");
        }
    }

    [TestMethod]
    public void FederatedBlueprintConnectionCreatesConfidentialClient()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDefaultMsalAuth(new ConfigurationBuilder().Build());
        using var provider = services.BuildServiceProvider();
        var settings = new ConnectionSettings
        {
            AuthType = AuthTypes.FederatedCredentials,
            Authority = "https://login.microsoftonline.com/11111111-1111-4111-8111-111111111111",
            ClientId = "22222222-2222-4222-8222-222222222222",
            FederatedClientId = "33333333-3333-4333-8333-333333333333"
        };

        var client = new MsalAuth(provider, settings).CreateClientApplication();

        Assert.IsInstanceOfType<IConfidentialClientApplication>(client);
    }
}
