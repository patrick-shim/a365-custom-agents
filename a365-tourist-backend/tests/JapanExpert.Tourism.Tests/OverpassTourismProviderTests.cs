using System.Net;

namespace JapanExpert.Tourism.Tests;

[TestClass]
public sealed class OverpassTourismProviderTests
{
    private const string TokyoAttractionsJson = """
        {
          "version": 0.6,
          "generator": "Overpass API",
          "elements": [
            {
              "type": "node",
              "id": 3352550973,
              "lat": 35.7147651,
              "lon": 139.7966553,
              "tags": {
                "tourism": "attraction",
                "name": "浅草寺",
                "name:en": "Sensoji Temple",
                "addr:province": "東京都",
                "addr:city": "台東区",
                "addr:quarter": "浅草",
                "addr:block_number": "2",
                "addr:housenumber": "3",
                "website": "https://www.senso-ji.jp/",
                "phone": "+81 3-3842-0181",
                "opening_hours": "06:00-17:00"
              }
            },
            {
              "type": "way",
              "id": 178161164,
              "center": { "lat": 35.6896, "lon": 139.7006 },
              "tags": {
                "tourism": "museum",
                "name": "東京都現代美術館",
                "name:en": "Museum of Contemporary Art Tokyo"
              }
            },
            {
              "type": "node",
              "id": 999,
              "lat": 35.6800,
              "lon": 139.7600,
              "tags": { "tourism": "attraction" }
            },
            {
              "type": "node",
              "id": 1000,
              "lat": 35.6801,
              "tags": { "tourism": "attraction", "name": "Missing longitude" }
            }
          ]
        }
        """;

    [TestMethod]
    public async Task SearchAttractionsAsyncMapsOpenStreetMapTagsWithOdblAttribution()
    {
        var handler = new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson);
        var provider = OverpassTestFactory.CreateProvider(handler);

        var results = await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.HasCount(2, results);
        var museum = results.Single(place => place.Id == "way/178161164");
        var temple = results.Single(place => place.Id == "node/3352550973");

        Assert.AreEqual("Museum of Contemporary Art Tokyo", museum.Name);
        Assert.AreEqual("東京都現代美術館", museum.LocalName);
        Assert.AreEqual("tourism=museum", museum.Category);
        Assert.AreEqual(TourismPlaceKind.Attraction, museum.Kind);

        Assert.AreEqual("Sensoji Temple", temple.Name);
        Assert.AreEqual("浅草寺", temple.LocalName);
        Assert.AreEqual("東京都 台東区 浅草 2 3", temple.Address);
        Assert.AreEqual("https://www.senso-ji.jp/", temple.Website);
        Assert.AreEqual("+81 3-3842-0181", temple.Telephone);
        Assert.AreEqual("06:00-17:00", temple.OpeningHours);
        Assert.IsGreaterThan(0, temple.DistanceMeters);

        Assert.AreEqual(OverpassTourismProvider.ProviderName, temple.Source.Name);
        Assert.AreEqual(OverpassTourismProvider.AttributionUrl, temple.Source.AttributionUrl);
        Assert.AreEqual(OverpassTourismProvider.License, temple.Source.License);
        StringAssert.Contains(temple.Source.Notice, "OpenStreetMap contributors");
    }

    [TestMethod]
    public async Task SearchAttractionsAsyncOrdersResultsByDistanceFromCenter()
    {
        var handler = new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson);
        var provider = OverpassTestFactory.CreateProvider(handler);

        var results = await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual("way/178161164", results[0].Id);
        Assert.IsLessThan(results[1].DistanceMeters, results[0].DistanceMeters);
    }

    [TestMethod]
    public async Task SearchAttractionsAsyncBoundsRadiusFetchCapAndTokyoDefaults()
    {
        var handler = new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson);
        var provider = OverpassTestFactory.CreateProvider(handler);

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        var body = handler.OverpassQuery!;
        StringAssert.Contains(body, "[out:json][timeout:25];");
        StringAssert.Contains(body, "(around:5000,35.6762,139.6503);");
        StringAssert.Contains(body, "out center 24;");
        StringAssert.Contains(body, "\"tourism\"~\"^(attraction|museum|viewpoint|gallery|artwork|theme_park|zoo|aquarium)$\"");
        StringAssert.Contains(body, "\"religion\"~\"^(shinto|buddhist)$\"");
        StringAssert.Contains(body, "[\"heritage\"]");
        Assert.AreEqual(
            "https://overpass-api.de/api/interpreter",
            handler.RequestUri!.AbsoluteUri);
        StringAssert.Contains(handler.UserAgent!, "JapanExpertTests/1.0");
    }

    [TestMethod]
    public async Task SearchAttractionsAsyncCapsFetchAtConfiguredMaximum()
    {
        var handler = new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson);
        var provider = OverpassTestFactory.CreateProvider(
            handler,
            new OverpassOptions
            {
                UserAgent = OverpassTestFactory.TestUserAgent,
                MaximumFetchElements = 30,
                FetchMultiplier = 5
            });

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(limit: 20),
            TestContext.CancellationToken);

        StringAssert.Contains(handler.OverpassQuery!, "out center 30;");
    }

    [TestMethod]
    public async Task SearchAccommodationAsyncQueriesOnlyLodgingTags()
    {
        const string lodgingJson = """
            {
              "elements": [
                {
                  "type": "node",
                  "id": 42,
                  "lat": 35.6812,
                  "lon": 139.7671,
                  "tags": {
                    "tourism": "hotel",
                    "name": "Marunouchi Hotel",
                    "addr:full": "東京都千代田区丸の内1-6-3"
                  }
                },
                {
                  "type": "node",
                  "id": 43,
                  "lat": 35.6800,
                  "lon": 139.7700,
                  "tags": { "tourism": "hostel", "name": "Nihonbashi Hostel" }
                }
              ]
            }
            """;
        var handler = new OverpassHandler(HttpStatusCode.OK, lodgingJson);
        var provider = OverpassTestFactory.CreateProvider(handler);

        var results = await provider.SearchAccommodationAsync(
            OverpassTestFactory.TokyoRequest(radiusMeters: 10_000, limit: 10),
            TestContext.CancellationToken);

        Assert.HasCount(2, results);
        Assert.AreEqual(TourismPlaceKind.Accommodation, results[0].Kind);
        Assert.AreEqual("東京都千代田区丸の内1-6-3", results[0].Address);
        var body = handler.OverpassQuery!;
        StringAssert.Contains(
            body,
            "\"tourism\"~\"^(hotel|hostel|guest_house|motel|apartment|camp_site|alpine_hut)$\"");
        Assert.DoesNotContain("historic", body, StringComparison.Ordinal);
    }

    [TestMethod]
    public async Task SearchAccommodationAsyncAppliesNameFilterLocally()
    {
        const string lodgingJson = """
            {
              "elements": [
                {
                  "type": "node", "id": 42, "lat": 35.6812, "lon": 139.7671,
                  "tags": { "tourism": "hotel", "name": "Marunouchi Hotel" }
                },
                {
                  "type": "node", "id": 43, "lat": 35.6800, "lon": 139.7700,
                  "tags": { "tourism": "hostel", "name": "Nihonbashi Hostel" }
                }
              ]
            }
            """;
        var handler = new OverpassHandler(HttpStatusCode.OK, lodgingJson);
        var provider = OverpassTestFactory.CreateProvider(handler);

        var results = await provider.SearchAccommodationAsync(
            OverpassTestFactory.TokyoRequest(
                category: "hostel",
                nameContains: "nihonbashi",
                radiusMeters: 10_000,
                limit: 10),
            TestContext.CancellationToken);

        Assert.HasCount(1, results);
        Assert.AreEqual("Nihonbashi Hostel", results[0].Name);
        StringAssert.Contains(
            handler.OverpassQuery!,
            "[\"tourism\"=\"hostel\"]");
    }

    [TestMethod]
    public async Task SearchRejectsCoordinatesOutsideJapan()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.SearchAttractionsAsync(
                new TourismSearchRequest(
                    TourismCategories.All,
                    NameContains: null,
                    new TourismLocation(37.5665, 126.9780),
                    5_000,
                    8),
                TestContext.CancellationToken));
    }

    [TestMethod]
    [DataRow(99, 8)]
    [DataRow(50_001, 8)]
    [DataRow(5_000, 0)]
    [DataRow(5_000, 21)]
    public async Task SearchRejectsRadiusAndLimitOutsideContractBounds(int radiusMeters, int limit)
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(radiusMeters: radiusMeters, limit: limit),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task SearchRejectsUnsupportedCategoryWithGuidance()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson));

        var exception = await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(category: "palace"),
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "Supported values are");
        StringAssert.Contains(exception.Message, "museum");
    }

    [TestMethod]
    public async Task SearchRejectsOverlongNameFilter()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson));

        await Assert.ThrowsExactlyAsync<ArgumentException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(nameContains: new string('a', 65)),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RateLimitedOverpassSurfacesTooManyRequests()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.TooManyRequests, "rate limited", "text/plain"));

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.TooManyRequests, exception.StatusCode);
    }

    [TestMethod]
    public async Task NotAcceptableOverpassIsTreatedAsInvalidProviderResponse()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.NotAcceptable, "not acceptable", "text/plain"));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));
    }

    [TestMethod]
    [DataRow(HttpStatusCode.InternalServerError)]
    [DataRow(HttpStatusCode.BadGateway)]
    [DataRow(HttpStatusCode.GatewayTimeout)]
    public async Task ServerErrorsSurfaceAsTransientHttpFailures(HttpStatusCode statusCode)
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(statusCode, "unavailable", "text/plain"));

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));

        Assert.AreEqual(statusCode, exception.StatusCode);
    }

    [TestMethod]
    public async Task MissingElementsArrayIsTreatedAsSchemaDrift()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, """{"version":0.6,"osm3s":{}}"""));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "elements array");
    }

    [TestMethod]
    public async Task RuntimeRemarkIsTreatedAsProviderFailure()
    {
        var provider = OverpassTestFactory.CreateProvider(new OverpassHandler(
            HttpStatusCode.OK,
            """{"elements":[],"remark":"runtime error: Query timed out in queryendpoint"}"""));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task ArrayResponseEnvelopeIsRejected()
    {
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, "[]"));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task CallerCancellationIsPropagated()
    {
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();
        var provider = OverpassTestFactory.CreateProvider(
            new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson));

        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() =>
            provider.SearchAttractionsAsync(
                OverpassTestFactory.TokyoRequest(),
                cancellation.Token));
    }

    [TestMethod]
    public void DistanceUsesGreatCircleMathematics()
    {
        var distance = JapanGeography.DistanceMeters(
            new TourismLocation(35.6762, 139.6503),
            new TourismLocation(35.6812, 139.7671));

        Assert.IsGreaterThan(10_000, distance);
        Assert.IsLessThan(12_000, distance);
    }

    [TestMethod]
    public void DefaultUserAgentIsSourceSafeAndContactable()
    {
        var userAgent = new OverpassOptions().UserAgent;

        Assert.AreEqual(
            "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/rg-a365-custom-agents)",
            userAgent);
        StringAssert.Contains(userAgent, "+https://github.com/patrick-shim/rg-a365-custom-agents");
        Assert.DoesNotContain("@", userAgent, StringComparison.Ordinal);
        Assert.DoesNotContain("example.com", userAgent, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TODO", userAgent, StringComparison.OrdinalIgnoreCase);
        Assert.IsTrue(new OverpassOptions().IsValid());
    }

    [TestMethod]
    public async Task DefaultUserAgentIsSentOnEveryOverpassRequest()
    {
        var handler = new OverpassHandler(HttpStatusCode.OK, TokyoAttractionsJson);
        var provider = OverpassTestFactory.CreateProvider(handler, new OverpassOptions());

        await provider.SearchAttractionsAsync(
            OverpassTestFactory.TokyoRequest(),
            TestContext.CancellationToken);

        Assert.AreEqual(
            "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/rg-a365-custom-agents)",
            handler.UserAgent);
    }

    [TestMethod]
    [DataRow("JapanExpertMcp/1.0")]
    [DataRow("curl/8.0")]
    [DataRow("   ")]
    public void UserAgentWithoutAContactReferenceIsRejected(string userAgent) =>
        Assert.IsFalse(new OverpassOptions { UserAgent = userAgent }.IsValid());

    [TestMethod]
    [DataRow("JapanExpertMcp/1.0 (+https://contoso.example/japan-expert)")]
    [DataRow("JapanExpertMcp/1.0 (mailto:ops@contoso.example)")]
    public void OperatorSuppliedContactableAgentIsAccepted(string userAgent) =>
        Assert.IsTrue(new OverpassOptions { UserAgent = userAgent }.IsValid());

    public TestContext TestContext { get; set; } = null!;
}
