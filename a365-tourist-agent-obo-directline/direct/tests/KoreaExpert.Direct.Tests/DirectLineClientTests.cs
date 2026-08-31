using System.Net;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using KoreaExpert.Direct;

namespace KoreaExpert.Direct.Tests;

[TestClass]
public sealed class DirectLineClientTests
{
    [TestMethod]
    public async Task StartConversationUsesSecretOnlyForInitialAuthorization()
    {
        using var handler = new StubHttpMessageHandler(request =>
        {
            Assert.AreEqual(HttpMethod.Post, request.Method);
            Assert.AreEqual("/v3/directline/conversations", request.RequestUri!.AbsolutePath);
            Assert.AreEqual("Bearer secret", request.Headers.Authorization?.ToString());
            return JsonResponse("""
                {"conversationId":"conversation","token":"token","expires_in":1800,"streamUrl":"https://example.invalid/stream"}
                """);
        });
        using var client = new HttpClient(handler);
        var directLine = new DirectLineClient(client);

        var conversation = await directLine.StartConversationAsync("secret", "test-user", "Test User");

        Assert.AreEqual("conversation", conversation.ConversationId);
        Assert.AreEqual("test-user", conversation.UserId);
    }

    [TestMethod]
    public void OptionsRejectInsecureExternalEndpointAndAllowLoopback()
    {
        Assert.ThrowsExactly<DirectClientOptionsException>(() =>
            DirectClientOptions.Parse(
                ["--endpoint", "http://example.invalid/v3/directline"],
                name => name == DirectClientOptions.DefaultSecretEnvironmentVariable
                    ? "test-secret"
                    : null));

        var options = DirectClientOptions.Parse(
            ["--endpoint", "http://127.0.0.1:3978/v3/directline"],
            name => name == DirectClientOptions.DefaultSecretEnvironmentVariable
                ? "test-secret"
                : null);

        Assert.AreEqual("http://127.0.0.1:3978/v3/directline", options.Endpoint.AbsoluteUri);
    }

    private static HttpResponseMessage JsonResponse(string content) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(content, Encoding.UTF8, "application/json")
    };

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> callback) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(callback(request));
    }
}
