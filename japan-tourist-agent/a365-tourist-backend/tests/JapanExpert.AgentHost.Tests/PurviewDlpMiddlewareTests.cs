using System.Collections.Concurrent;
using System.Net;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Microsoft.Agents.AI.Purview;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.DependencyInjection;
using JapanExpert.AgentHost;

namespace JapanExpert.AgentHost.Tests;

[TestClass]
public sealed class PurviewDlpMiddlewareTests
{
    private static readonly Guid TestUserId = Guid.Parse("11111111-1111-4111-8111-111111111111");
    private static readonly Guid TestTenantId = Guid.Parse("22222222-2222-4222-8222-222222222222");
    private static readonly Guid TestApplicationId = Guid.Parse("33333333-3333-4333-8333-333333333333");

    [TestMethod]
    [TestCategory("Purview")]
    public void PurviewActivityUsesGraphWireCasing()
    {
        PurviewSerializationWorkaround.Apply();
        var packageAssembly = typeof(PurviewSettings).Assembly;
        var activityType = packageAssembly.GetType(
            "Microsoft.Agents.AI.Purview.Models.Common.Activity")
            ?? throw new AssertFailedException("The Purview activity type was not found.");
        var activityMetadataType = packageAssembly.GetType(
            "Microsoft.Agents.AI.Purview.Models.Common.ActivityMetadata")
            ?? throw new AssertFailedException("The Purview activity metadata type was not found.");
        var uploadText = Enum.Parse(activityType, "UploadText");
        var activityMetadata = Activator.CreateInstance(activityMetadataType, uploadText)
            ?? throw new AssertFailedException("The Purview activity metadata could not be created.");
        var serializationUtils = packageAssembly.GetType(
            "Microsoft.Agents.AI.Purview.Serialization.PurviewSerializationUtils")
            ?? throw new AssertFailedException("The Purview serializer utility was not found.");
        var options = serializationUtils
            .GetProperty("SerializationSettings", BindingFlags.Public | BindingFlags.Static)
            ?.GetValue(null) as JsonSerializerOptions
            ?? throw new AssertFailedException("The Purview serializer settings were not found.");

        Assert.AreEqual(
            "{\"activity\":\"uploadText\"}",
            JsonSerializer.Serialize(activityMetadata, activityMetadataType, options));
    }

    [TestMethod]
    [TestCategory("Purview")]
    public void PurviewConversationIncludesAgentIdentityMetadata()
    {
        PurviewSerializationWorkaround.Apply();
        var packageAssembly = typeof(PurviewSettings).Assembly;
        var metadataType = packageAssembly.GetType(
            "Microsoft.Agents.AI.Purview.Models.Common.ProcessConversationMetadata")
            ?? throw new AssertFailedException("The Purview conversation metadata type was not found.");
        var metadata = RuntimeHelpers.GetUninitializedObject(metadataType);
        using var scope = PurviewSerializationWorkaround.PushAgentMetadata(
            TestApplicationId.ToString(),
            TestTenantId.ToString(),
            "Japan Tourist Expert Test",
            "1.0");
        var serializationUtils = packageAssembly.GetType(
            "Microsoft.Agents.AI.Purview.Serialization.PurviewSerializationUtils")!;
        var options = (JsonSerializerOptions)serializationUtils
            .GetProperty("SerializationSettings", BindingFlags.Public | BindingFlags.Static)!
            .GetValue(null)!;

        using var document = JsonDocument.Parse(JsonSerializer.Serialize(metadata, metadataType, options));
        var agent = document.RootElement.GetProperty("agents")[0];
        Assert.AreEqual(TestApplicationId.ToString(), agent.GetProperty("blueprintId").GetString());
        Assert.AreEqual(TestTenantId.ToString(), agent.GetProperty("identifier").GetString());
        Assert.AreEqual("Japan Tourist Expert Test", agent.GetProperty("name").GetString());
        Assert.AreEqual("1.0", agent.GetProperty("version").GetString());
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task ProcessContentRequestMatchesGraphContract()
    {
        await using var graph = await PurviewGraphStub.StartAsync([
            PurviewGraphStub.AllowResponse,
            PurviewGraphStub.AllowResponse
        ]);
        using var inner = new RecordingChatClient("model output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);
        using var scope = PurviewSerializationWorkaround.PushAgentMetadata(
            TestApplicationId.ToString(),
            TestTenantId.ToString(),
            "Japan Tourist Expert Test",
            "1.0");

        await client.GetResponseAsync(
            [CreateProtectedMessage("prompt")],
            new ChatOptions { ConversationId = Guid.NewGuid().ToString() });

        using var request = JsonDocument.Parse(graph.ProcessContentRequests.First());
        var entry = request.RootElement.GetProperty("contentToProcess").GetProperty("contentEntries")[0];
        Assert.IsTrue(Guid.TryParse(entry.GetProperty("correlationId").GetString(), out _));
        Assert.AreEqual(
            "uploadText",
            request.RootElement
                .GetProperty("contentToProcess")
                .GetProperty("activityMetadata")
                .GetProperty("activity")
                .GetString());
        Assert.AreEqual(
            TestApplicationId.ToString(),
            entry.GetProperty("agents")[0].GetProperty("blueprintId").GetString());
        Assert.AreEqual(
            "microsoft.graph.aiAgentInfo",
            entry.GetProperty("agents")[0].GetProperty("@odata.type").GetString());
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task BlockedInputNeverInvokesModel()
    {
        await using var graph = await PurviewGraphStub.StartAsync([
            PurviewGraphStub.BlockResponse
        ]);
        using var inner = new RecordingChatClient("model output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);

        var response = await client.GetResponseAsync([CreateProtectedMessage("sensitive prompt")]);

        Assert.AreEqual(0, inner.NonStreamingCalls);
        Assert.AreEqual("Prompt blocked by test policy", response.Text);
        Assert.AreEqual(ChatRole.System, response.Messages.Single().Role);
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task BlockedOutputReplacesSensitiveModelResponse()
    {
        await using var graph = await PurviewGraphStub.StartAsync([
            PurviewGraphStub.AllowResponse,
            PurviewGraphStub.BlockResponse
        ]);
        using var inner = new RecordingChatClient("sensitive model output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);

        var response = await client.GetResponseAsync([CreateProtectedMessage("allowed prompt")]);

        Assert.AreEqual(1, inner.NonStreamingCalls);
        Assert.AreEqual("Response blocked by test policy", response.Text);
        Assert.DoesNotContain("sensitive model output", response.Text, StringComparison.Ordinal);
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task StreamingDoesNotEmitBlockedOutputChunks()
    {
        await using var graph = await PurviewGraphStub.StartAsync([
            PurviewGraphStub.AllowResponse,
            PurviewGraphStub.BlockResponse
        ]);
        using var inner = new RecordingChatClient("sensitive streaming output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);
        var text = new StringBuilder();

        await foreach (var update in client.GetStreamingResponseAsync(
            [CreateProtectedMessage("allowed prompt")]))
        {
            text.Append(update.Text);
        }

        Assert.AreEqual(1, inner.NonStreamingCalls);
        Assert.AreEqual(0, inner.StreamingCalls);
        Assert.AreEqual("Response blocked by test policy", text.ToString());
        Assert.DoesNotContain("sensitive streaming output", text.ToString(), StringComparison.Ordinal);
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task FailClosedWhenPurviewEvaluationFails()
    {
        await using var graph = await PurviewGraphStub.StartAsync([], HttpStatusCode.InternalServerError);
        using var inner = new RecordingChatClient("model output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);

        await Assert.ThrowsExactlyAsync<PurviewRequestException>(() =>
            client.GetResponseAsync([CreateProtectedMessage("prompt")]));

        Assert.AreEqual(0, inner.NonStreamingCalls);
    }

    [TestMethod]
    [TestCategory("Purview")]
    public async Task MissingUserIdentityFailsClosedBeforeModelInvocation()
    {
        await using var graph = await PurviewGraphStub.StartAsync([
            PurviewGraphStub.AllowResponse
        ]);
        using var inner = new RecordingChatClient("model output");
        using var client = CreatePurviewClient(inner, graph.BaseUri);

        await Assert.ThrowsExactlyAsync<PurviewRequestException>(() =>
            client.GetResponseAsync([new ChatMessage(ChatRole.User, "prompt")]));

        Assert.AreEqual(0, inner.NonStreamingCalls);
    }

    [TestMethod]
    [TestCategory("Purview")]
    public void ToolArgumentProtectionRequiresWorkIqDisabled()
    {
        var options = new Agent365HostOptions();

        Assert.IsFalse(options.EnableWorkIq, "WorkIQ must default off until tool arguments have DLP coverage.");
    }

    [TestMethod]
    [TestCategory("Purview")]
    public void ToolResultProtectionRequiresWorkIqDisabled()
    {
        var options = new Agent365HostOptions();

        Assert.IsFalse(options.EnableWorkIq, "WorkIQ must default off until tool results have DLP coverage.");
    }

    [TestMethod]
    [TestCategory("Purview")]
    public void MiddlewareOrderKeepsPurviewOutsideFunctionInvocationAndTelemetry()
    {
        var factory = RepositoryPaths.ReadAgentHostFile("AgentChatClientFactory.cs");

        var functionInvocationIndex = factory.IndexOf("chatClientBuilder.UseFunctionInvocation(", StringComparison.Ordinal);
        var purviewIndex = factory.IndexOf("chatClientBuilder.WithPurview(", StringComparison.Ordinal);
        var telemetryIndex = factory.IndexOf("chatClientBuilder.UseOpenTelemetry(", StringComparison.Ordinal);

        Assert.IsGreaterThanOrEqualTo(0, functionInvocationIndex);
        Assert.IsGreaterThanOrEqualTo(0, purviewIndex);
        Assert.IsGreaterThan(purviewIndex, functionInvocationIndex);
        Assert.IsGreaterThan(functionInvocationIndex, telemetryIndex);
    }

    [TestMethod]
    public void MessageEndpointsRequireFrontendPoliciesBeforeLocalOverrides()
    {
        var program = RepositoryPaths.ReadAgentHostFile("Program.cs");

        var agenticAuthorizationIndex = program.IndexOf(
            "agenticMessages.RequireAuthorization(AgentFrontendAuthorization.AgenticUserPolicy)",
            StringComparison.Ordinal);
        var oboAuthorizationIndex = program.IndexOf(
            "oboMessages.RequireAuthorization(AgentFrontendAuthorization.OnBehalfOfPolicy)",
            StringComparison.Ordinal);
        var agenticLocalOverrideIndex = program.IndexOf(
            "agenticMessages.AllowAnonymous()",
            StringComparison.Ordinal);
        var oboLocalOverrideIndex = program.IndexOf(
            "oboMessages.AllowAnonymous()",
            StringComparison.Ordinal);

        Assert.IsGreaterThanOrEqualTo(0, agenticAuthorizationIndex);
        Assert.IsGreaterThanOrEqualTo(0, oboAuthorizationIndex);
        Assert.IsGreaterThan(agenticAuthorizationIndex, agenticLocalOverrideIndex);
        Assert.IsGreaterThan(oboAuthorizationIndex, oboLocalOverrideIndex);
    }

    [TestMethod]
    public void HostDoesNotExposeUnprotectedMvcControllers()
    {
        var program = RepositoryPaths.ReadAgentHostFile("Program.cs");

        Assert.IsFalse(program.Contains("AddControllers()", StringComparison.Ordinal));
        Assert.IsFalse(program.Contains("MapControllers()", StringComparison.Ordinal));
    }

    [TestMethod]
    public void ObservabilityBaggageSeparatesCallerAndAgenticUserIdentity()
    {
        var application = RepositoryPaths.ReadAgentHostFile("JapanExpertApplication.cs");

        StringAssert.Contains(application, ".ConversationId(conversationId");
        StringAssert.Contains(application, ".ChannelName(channelName");
        StringAssert.Contains(application, ".UserId(callerId");
        StringAssert.Contains(application, ".AgenticUserId(agenticUserId");
        StringAssert.Contains(application, ".AgentBlueprintId(agentBlueprintId");
        StringAssert.Contains(application, "turnContext.Activity.From?.AadObjectId");
        StringAssert.Contains(application, "turnContext.Activity.Recipient?.AgenticUserId");
    }

    [TestMethod]
    public void ObservabilityInvocationUsesChildScopeWithoutSensitiveContent()
    {
        var application = RepositoryPaths.ReadAgentHostFile("JapanExpertApplication.cs");

        StringAssert.Contains(application, "AgentIdentityAuthorizationScopes.ObservabilityDefault");
        StringAssert.Contains(application, "InvokeAgentScope.Start(");
        StringAssert.Contains(application, "new CallerDetails(");
        StringAssert.Contains(application, "content: string.Empty");
        Assert.DoesNotContain("RecordInputMessages", application);
        Assert.DoesNotContain("RecordOutputMessages", application);
    }

    private static ChatMessage CreateProtectedMessage(string text)
    {
        var message = new ChatMessage(ChatRole.User, text);
        message.SetUserId(TestUserId);
        return message;
    }

    private static IChatClient CreatePurviewClient(IChatClient inner, Uri graphBaseUri)
    {
        PurviewSerializationWorkaround.Apply();
        var settings = new PurviewSettings("Japan Tourist Expert Test")
        {
            AppVersion = "1.0",
            TenantId = TestTenantId.ToString(),
            PurviewAppLocation = new PurviewAppLocation(
                PurviewLocationType.Application,
                TestApplicationId.ToString()),
            IgnoreExceptions = false,
            GraphBaseUri = graphBaseUri,
            BlockedPromptMessage = "Prompt blocked by test policy",
            BlockedResponseMessage = "Response blocked by test policy"
        };

        return inner
            .AsBuilder()
            .WithPurview(new AppTokenCredential(TestTenantId, TestApplicationId), settings)
            .Build();
    }

    private sealed class RecordingChatClient(string responseText) : IChatClient
    {
        public int NonStreamingCalls { get; private set; }

        public int StreamingCalls { get; private set; }

        public void Dispose()
        {
        }

        public Task<ChatResponse> GetResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            CancellationToken cancellationToken = default)
        {
            NonStreamingCalls++;
            return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, responseText)));
        }

        public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            [EnumeratorCancellation] CancellationToken cancellationToken = default)
        {
            StreamingCalls++;
            await Task.Yield();
            yield return new ChatResponseUpdate(ChatRole.Assistant, responseText);
        }

        public object? GetService(Type serviceType, object? serviceKey = null) =>
            serviceType.IsInstanceOfType(this) ? this : null;
    }

    private sealed class AppTokenCredential(Guid tenantId, Guid applicationId) : TokenCredential
    {
        private readonly AccessToken _token = new(
            CreateUnsignedToken(tenantId, applicationId),
            DateTimeOffset.UtcNow.AddHours(1));

        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) => _token;

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) => ValueTask.FromResult(_token);

        private static string CreateUnsignedToken(Guid tenantId, Guid applicationId)
        {
            static string Encode(object value) => Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(value))
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');

            return $"{Encode(new { alg = "none", typ = "JWT" })}.{Encode(new
            {
                tid = tenantId,
                appid = applicationId,
                idtyp = "app",
                exp = DateTimeOffset.UtcNow.AddHours(1).ToUnixTimeSeconds()
            })}.";
        }
    }

    private sealed class PurviewGraphStub : IAsyncDisposable
    {
        public const string AllowResponse =
            "{\"id\":\"allow\",\"protectionScopeState\":\"notModified\",\"policyActions\":[],\"processingErrors\":[]}";

        public const string BlockResponse =
            "{\"id\":\"block\",\"protectionScopeState\":\"notModified\",\"policyActions\":[{\"action\":\"blockAccess\"}],\"processingErrors\":[]}";

        private readonly WebApplication _application;
        private readonly ConcurrentQueue<string> _processContentRequests;

        private PurviewGraphStub(
            WebApplication application,
            Uri baseUri,
            ConcurrentQueue<string> processContentRequests)
        {
            _application = application;
            BaseUri = baseUri;
            _processContentRequests = processContentRequests;
        }

        public Uri BaseUri { get; }

        public IReadOnlyCollection<string> ProcessContentRequests => _processContentRequests;

        public static async Task<PurviewGraphStub> StartAsync(
            IEnumerable<string> processContentResponses,
            HttpStatusCode processContentStatus = HttpStatusCode.OK)
        {
            var responses = new ConcurrentQueue<string>(processContentResponses);
            var processContentRequests = new ConcurrentQueue<string>();
            var builder = WebApplication.CreateSlimBuilder();
            builder.WebHost.ConfigureKestrel(options => options.Listen(IPAddress.Loopback, 0));
            var application = builder.Build();

            application.MapPost("/{**path}", async context =>
            {
                var path = context.Request.Path.Value ?? string.Empty;
                context.Response.ContentType = "application/json";

                if (path.EndsWith("/protectionScopes/compute", StringComparison.Ordinal))
                {
                    await context.Response.WriteAsync("{\"value\":[]}");
                    return;
                }

                if (path.EndsWith("/activities/contentActivities", StringComparison.Ordinal))
                {
                    context.Response.StatusCode = StatusCodes.Status201Created;
                    await context.Response.WriteAsync("{\"statusCode\":201}");
                    return;
                }

                if (path.EndsWith("/processContent", StringComparison.Ordinal))
                {
                    using var reader = new StreamReader(context.Request.Body, Encoding.UTF8);
                    processContentRequests.Enqueue(await reader.ReadToEndAsync());
                    context.Response.StatusCode = (int)processContentStatus;
                    if (responses.TryDequeue(out var response))
                    {
                        await context.Response.WriteAsync(response);
                    }
                    return;
                }

                context.Response.StatusCode = StatusCodes.Status404NotFound;
            });

            await application.StartAsync();
            var addresses = application.Services
                .GetRequiredService<IServer>()
                .Features
                .Get<IServerAddressesFeature>()
                ?.Addresses;
            var address = addresses?.Single()
                ?? throw new InvalidOperationException("Purview test server did not expose an address.");

            return new PurviewGraphStub(
                application,
                new Uri($"{address.TrimEnd('/')}/"),
                processContentRequests);
        }

        public async ValueTask DisposeAsync()
        {
            await _application.StopAsync();
            await _application.DisposeAsync();
        }
    }
}
