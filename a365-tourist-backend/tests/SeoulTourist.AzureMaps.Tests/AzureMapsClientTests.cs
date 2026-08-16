using System.Net;
using System.Text;
using Azure.Core;
using Microsoft.Extensions.Options;
using SeoulTourist.AzureMaps;

namespace SeoulTourist.AzureMaps.Tests;

[TestClass]
public sealed class AzureMapsClientTests
{
    [TestMethod]
    public async Task SearchPointsOfInterestAsyncMapsResponseAndAuthenticatesRequest()
    {
        const string responseJson = """
            {
              "results": [
                {
                  "poi": { "name": "Gyeongbokgung Palace", "categories": ["tourist attraction"] },
                  "address": { "freeformAddress": "161 Sajik-ro, Jongno-gu" },
                  "position": { "lat": 37.5796, "lon": 126.9770 },
                  "dist": 1500.5
                }
              ]
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var client = CreateClient(handler);

        var results = await client.SearchPointsOfInterestAsync(
            "palace",
            new GeoPoint(37.5665, 126.9780),
            5000,
            8,
            TestContext.CancellationToken);

        Assert.HasCount(1, results);
        Assert.AreEqual("Gyeongbokgung Palace", results[0].Name);
        Assert.AreEqual("Bearer", handler.AuthorizationScheme);
        Assert.AreEqual("test-token", handler.AuthorizationToken);
        Assert.AreEqual("maps-client-id", handler.AzureMapsClientId);
        StringAssert.Contains(handler.RequestUri!.Query, "query=palace");
        StringAssert.Contains(handler.RequestUri.Query, "language=ko-KR");
    }

    [TestMethod]
    public async Task GetDailyForecastAsyncRejectsUnsupportedDuration()
    {
        var client = CreateClient(new RecordingHandler("{}"));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            client.GetDailyForecastAsync(
                new GeoPoint(37.5665, 126.9780),
                7,
                TestContext.CancellationToken));
    }

    public TestContext TestContext { get; set; } = null!;

    private static AzureMapsClient CreateClient(HttpMessageHandler handler)
    {
        var httpClient = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://atlas.microsoft.com/")
        };

        return new AzureMapsClient(
            httpClient,
            new StaticTokenCredential(),
            Options.Create(new AzureMapsOptions { ClientId = "maps-client-id" }));
    }

    private sealed class StaticTokenCredential : TokenCredential
    {
        private static readonly AccessToken Token = new(
            "test-token",
            DateTimeOffset.UtcNow.AddHours(1));

        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) => Token;

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) => ValueTask.FromResult(Token);
    }

    private sealed class RecordingHandler(string responseJson) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        public string? AuthorizationScheme { get; private set; }

        public string? AuthorizationToken { get; private set; }

        public string? AzureMapsClientId { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationToken = request.Headers.Authorization?.Parameter;
            AzureMapsClientId = request.Headers.GetValues("x-ms-client-id").Single();

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
            });
        }
    }
}
