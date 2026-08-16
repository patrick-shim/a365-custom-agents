using System.Net;
using System.Text;
using Azure.Core;
using Microsoft.Extensions.Options;
using SeoulTourist.AzureMaps;
using SeoulTourist.Tourism;

namespace SeoulTourist.Tourism.Tests;

[TestClass]
public sealed class AzureMapsTourismProviderTests
{
    [TestMethod]
    public async Task MapsAttributedPointOfInterestToTourismContract()
    {
        const string responseJson = """
            {
              "results": [{
                "poi": {
                  "name": "Gyeongbokgung Palace",
                  "categories": ["tourist attraction", "historic site"]
                },
                "position": { "lat": 37.5796, "lon": 126.9770 },
                "address": { "freeformAddress": "161 Sajik-ro, Jongno-gu, Seoul" },
                "dist": 1450.0
              }]
            }
            """;
        var client = new AzureMapsClient(
            new HttpClient(new StaticResponseHandler(responseJson))
            {
                BaseAddress = new Uri("https://atlas.microsoft.com/")
            },
            new StaticTokenCredential(),
            Options.Create(new AzureMapsOptions { ClientId = "maps-client-id" }));
        var provider = new AzureMapsTourismProvider(client);

        var results = await provider.SearchAttractionsAsync(
            "palace",
            new TourismLocation(37.5665, 126.9780),
            5000,
            8,
            TestContext.CancellationToken);

        Assert.HasCount(1, results);
        Assert.AreEqual("Gyeongbokgung Palace", results[0].Name);
        Assert.AreEqual(1450.0, results[0].DistanceMeters);
        Assert.AreEqual("Microsoft Azure Maps", results[0].Source.Name);
        StringAssert.Contains(results[0].Category!, "historic site");
    }

    public TestContext TestContext { get; set; } = null!;

    private sealed class StaticResponseHandler(string responseJson) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
            });
    }

    private sealed class StaticTokenCredential : TokenCredential
    {
        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) =>
            new("test-token", DateTimeOffset.UtcNow.AddMinutes(5));

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(GetToken(requestContext, cancellationToken));
    }
}
