using System.Net;
using System.Text;
using Microsoft.Extensions.Options;
using KoreaExpert.Tourism;

namespace KoreaExpert.Tourism.Tests;

[TestClass]
public sealed class KtoTourApiProviderTests
{
    [TestMethod]
    public async Task SearchAttractionsAsyncMapsAndFiltersKtoResults()
    {
        const string responseJson = """
            {
              "response": {
                "header": { "resultCode": "0000", "resultMsg": "OK" },
                "body": {
                  "items": {
                    "item": [
                      {
                        "contentid": "264337",
                        "contenttypeid": "76",
                        "title": "Gyeongbokgung Palace",
                        "addr1": "161 Sajik-ro, Jongno-gu, Seoul",
                        "mapx": "126.9770",
                        "mapy": "37.5796",
                        "firstimage": "https://example.test/palace.jpg",
                        "tel": "+82-2-3700-3900",
                        "modifiedtime": "20260808143000"
                      },
                      {
                        "contentid": "far-away",
                        "contenttypeid": "76",
                        "title": "Outside the selected radius",
                        "mapx": "127.2000",
                        "mapy": "37.7000"
                      }
                    ]
                  }
                }
              }
            }
            """;
        var handler = new RecordingHandler(responseJson);
        var provider = CreateProvider(handler);

        var results = await provider.SearchAttractionsAsync(
            "palace",
            new TourismLocation(37.5665, 126.9780),
            5_000,
            8,
            TestContext.CancellationToken);

        Assert.HasCount(1, results);
        Assert.AreEqual("Gyeongbokgung Palace", results[0].Name);
        Assert.AreEqual("Tourist attraction", results[0].Category);
        Assert.AreEqual(TimeSpan.FromHours(9), results[0].ModifiedAt!.Value.Offset);
        Assert.AreEqual("Korea Tourism Organization TourAPI Service2", results[0].Source.Name);
        StringAssert.Contains(handler.RequestUri!.AbsolutePath, "/EngService2/searchKeyword2");
        StringAssert.Contains(handler.RequestUri.Query, "keyword=palace");
        StringAssert.Contains(handler.RequestUri.Query, "lDongRegnCd=11");
    }

    [TestMethod]
    public async Task SearchAttractionsAsyncRejectsProviderErrorEnvelope()
    {
        const string responseJson = """
            {
              "response": {
                "header": { "resultCode": "30", "resultMsg": "SERVICE KEY IS NOT REGISTERED" }
              }
            }
            """;
        var provider = CreateProvider(new RecordingHandler(responseJson));

        var exception = await Assert.ThrowsExactlyAsync<InvalidOperationException>(() =>
            provider.SearchAttractionsAsync(
                "museum",
                new TourismLocation(37.5665, 126.9780),
                5_000,
                8,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "result code 30");
    }

    public TestContext TestContext { get; set; } = null!;

    private static KtoTourApiProvider CreateProvider(HttpMessageHandler handler)
    {
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://apis.data.go.kr/B551011/")
        };
        return new KtoTourApiProvider(
            client,
            Options.Create(new KtoTourApiOptions { ServiceKey = "test-service-key" }));
    }

    private sealed class RecordingHandler(string responseJson) : HttpMessageHandler
    {
        public Uri? RequestUri { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestUri = request.RequestUri;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseJson, Encoding.UTF8, "application/json")
            });
        }
    }
}
