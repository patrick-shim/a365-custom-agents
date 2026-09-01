using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using JapanExpert.AgentHost;

namespace JapanExpert.AgentHost.Tests;

[TestClass]
public sealed class PurviewGraphProxyTests
{
    private static readonly Guid TestUserId = Guid.Parse("11111111-1111-4111-8111-111111111111");

    [TestMethod]
    public async Task RejectsNonLoopbackRequestsWithoutForwarding()
    {
        var handler = new RecordingHandler();
        var proxy = CreateProxy(handler);
        var context = CreateContext(IPAddress.Parse("10.0.0.1"));

        await proxy.ForwardAsync(
            context,
            $"users/{TestUserId}/dataSecurityAndGovernance/processContent",
            CancellationToken.None);

        Assert.AreEqual(StatusCodes.Status404NotFound, context.Response.StatusCode);
        Assert.AreEqual(0, handler.CallCount);
    }

    [TestMethod]
    public async Task LoopbackRequestForwardsGraphResponseWithoutExposingRoute()
    {
        const string graphResponse =
            "{\"error\":{\"code\":\"BadRequest\",\"message\":\"Invalid correlationId.\"}}";
        var handler = new RecordingHandler(graphResponse);
        var proxy = CreateProxy(handler);
        var context = CreateContext(IPAddress.Loopback);
        context.Request.Headers.Authorization = "Bearer test-token";

        await proxy.ForwardAsync(
            context,
            $"users/{TestUserId}/dataSecurityAndGovernance/processContent",
            CancellationToken.None);

        Assert.AreEqual(StatusCodes.Status400BadRequest, context.Response.StatusCode);
        Assert.AreEqual(1, handler.CallCount);
        Assert.AreEqual(
            $"https://graph.microsoft.com/v1.0/users/{TestUserId}/dataSecurityAndGovernance/processContent",
            handler.RequestUri?.AbsoluteUri);
        Assert.AreEqual("Bearer test-token", handler.Authorization);
        Assert.IsTrue(Guid.TryParse(handler.ClientRequestId, out _));
        context.Response.Body.Position = 0;
        using var reader = new StreamReader(context.Response.Body, Encoding.UTF8);
        Assert.AreEqual(graphResponse, await reader.ReadToEndAsync());
    }

    [TestMethod]
    public async Task EmptyTextFunctionIntermediateDoesNotCallGraph()
    {
        var handler = new RecordingHandler();
        var proxy = CreateProxy(handler);
        var context = CreateContext(IPAddress.Loopback);
        var correlationId = Guid.NewGuid();
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes($$"""
                        {
                            "contentToProcess": {
                                "contentEntries": [
                                    {
                                        "correlationId": "{{correlationId}}",
                                        "content": {
                                            "@odata.type": "microsoft.graph.textContent",
                                            "data": ""
                                        }
                                    }
                                ]
                            }
                        }
                        """));

        await proxy.ForwardAsync(
                context,
                $"users/{TestUserId}/dataSecurityAndGovernance/processContent",
                CancellationToken.None);

        Assert.AreEqual(StatusCodes.Status200OK, context.Response.StatusCode);
        Assert.AreEqual(0, handler.CallCount);
        context.Response.Body.Position = 0;
        using var reader = new StreamReader(context.Response.Body, Encoding.UTF8);
        using var response = JsonDocument.Parse(await reader.ReadToEndAsync());
        Assert.AreEqual(0, response.RootElement.GetProperty("policyActions").GetArrayLength());
    }

    private static PurviewGraphProxy CreateProxy(RecordingHandler handler) =>
        new(
            new TestHttpClientFactory(handler),
            Options.Create(new PurviewDlpOptions
            {
                UseCompatibilityProxy = true,
                GraphBaseUri = new Uri("https://graph.microsoft.com/v1.0/")
            }),
            NullLogger<PurviewGraphProxy>.Instance);

    private static DefaultHttpContext CreateContext(IPAddress remoteAddress)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = remoteAddress;
        context.Request.ContentType = "application/json";
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes("{}"));
        context.Response.Body = new MemoryStream();
        return context;
    }

    private sealed class TestHttpClientFactory(RecordingHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    private sealed class RecordingHandler(string? responseBody = null) : HttpMessageHandler
    {
        public int CallCount { get; private set; }

        public Uri? RequestUri { get; private set; }

        public string? Authorization { get; private set; }

        public string? ClientRequestId { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            CallCount++;
            RequestUri = request.RequestUri;
            Authorization = request.Headers.Authorization?.ToString();
            ClientRequestId = request.Headers.TryGetValues("Client-Request-Id", out var values)
                ? values.Single()
                : null;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent(
                    responseBody ?? "{}",
                    Encoding.UTF8,
                    "application/json"),
                Headers =
                {
                    { "request-id", "test-request-id" }
                }
            });
        }
    }
}
