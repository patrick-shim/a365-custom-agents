using System.Net;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using JapanExpert.Direct;

namespace JapanExpert.Direct.Tests;

[TestClass]
public sealed class ConsoleConversationTests
{
    [TestMethod]
    public async Task AcceptsChannelRecorrelatedReplyAfterOAuthChallenge()
    {
        var getCount = 0;
        var postCount = 0;
        using var handler = new StubHttpMessageHandler(request =>
        {
            if (request.Method == HttpMethod.Post
                && request.RequestUri!.AbsolutePath.EndsWith("/conversations", StringComparison.Ordinal))
            {
                return JsonResponse(
                    """{"conversationId":"conversation","token":"token","expires_in":1800}""");
            }

            if (request.Method == HttpMethod.Post
                && request.RequestUri!.AbsolutePath.EndsWith("/activities", StringComparison.Ordinal))
            {
                postCount++;
                return JsonResponse(postCount == 1
                    ? """{"id":"sent-id"}"""
                    : """{"id":"verification-id"}""");
            }

            if (request.Method == HttpMethod.Get
                && request.RequestUri!.AbsolutePath.EndsWith("/activities", StringComparison.Ordinal))
            {
                getCount++;
                return getCount == 1
                    ? JsonResponse("""
                        {
                          "activities": [
                            {"id":"sent-id","type":"message","text":"weather","from":{"id":"test-user"}},
                            {
                              "id":"oauth-id",
                              "type":"message",
                              "replyToId":"sent-id",
                              "from":{"id":"bot"},
                              "attachments":[{
                                "contentType":"application/vnd.microsoft.card.oauth",
                                "content":{
                                  "connectionName":"connection",
                                  "text":"Please sign in",
                                  "buttons":[{
                                    "type":"signin",
                                    "value":"https://token.botframework.com/api/oauth/signin?signin=test"
                                  }]
                                }
                              }]
                            }
                          ],
                          "watermark":"1"
                        }
                        """)
                    : JsonResponse("""
                        {
                          "activities": [
                            {"id":"verification-id","type":"message","text":"123456","from":{"id":"test-user"}},
                            {
                              "id":"reply-id",
                              "type":"message",
                              "replyToId":"channel-recorrelated-id",
                              "text":"Tokyo weather is clear.",
                              "from":{"id":"bot"}
                            }
                          ],
                          "watermark":"2"
                        }
                        """);
            }

            Assert.Fail($"Unexpected request: {request.Method} {request.RequestUri}");
            return new HttpResponseMessage(HttpStatusCode.InternalServerError);
        });
        using var httpClient = new HttpClient(handler);
        var directLine = new DirectLineClient(httpClient);
        var options = DirectClientOptions.Parse(
            [
                "--message", "weather",
                "--no-browser",
                "--poll-ms", "1",
                "--user-id", "test-user"
            ],
            name => name == DirectClientOptions.DefaultSecretEnvironmentVariable
                ? "test-secret"
                : null);
        using var input = new StringReader("123456\n");
        using var output = new StringWriter();
        var conversation = new ConsoleConversation(
            directLine,
            options,
            input,
            output,
            delay: (_, _) => Task.CompletedTask);

        await conversation.RunAsync();

        StringAssert.Contains(output.ToString(), "agent> Tokyo weather is clear.");
    }

    private static HttpResponseMessage JsonResponse(string content) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(content, Encoding.UTF8, "application/json")
    };

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> callback)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            Task.FromResult(callback(request));
    }
}
