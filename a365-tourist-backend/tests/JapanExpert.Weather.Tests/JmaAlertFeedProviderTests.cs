using System.Net;

namespace JapanExpert.Weather.Tests;

[TestClass]
public sealed class JmaAlertFeedProviderTests
{
    /// <summary>Recorded shape of the documented JMA XML Atom bulletin feed.</summary>
    private const string AlertFeedXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>高頻度）随時発表・更新される情報</title>
          <updated>2026-08-30T08:00:00Z</updated>
          <entry>
            <title>気象警報・注意報</title>
            <id>urn:uuid:11111111-1111-4111-8111-111111111111</id>
            <updated>2026-08-30T07:53:00Z</updated>
            <author><name>気象庁</name></author>
            <link type="application/xml" href="https://www.data.jma.go.jp/developer/xml/data/tokyo-warning.xml"/>
            <content type="text">東京都気象警報・注意報</content>
          </entry>
          <entry>
            <title>土砂災害警戒情報</title>
            <id>urn:uuid:22222222-2222-4222-8222-222222222222</id>
            <updated>2026-08-30T07:40:00Z</updated>
            <author><name>大阪管区気象台</name></author>
            <link type="application/xml" href="https://www.data.jma.go.jp/developer/xml/data/osaka-landslide.xml"/>
            <content type="text">大阪府土砂災害警戒情報</content>
          </entry>
          <entry>
            <title>府県気象情報</title>
            <id>urn:uuid:33333333-3333-4333-8333-333333333333</id>
            <updated>2026-08-30T07:20:00Z</updated>
            <author><name>気象庁</name></author>
            <link type="application/xml" href="https://www.data.jma.go.jp/developer/xml/data/tokyo-information.xml"/>
            <content type="text">東京都府県気象情報</content>
          </entry>
        </feed>
        """;

    [TestMethod]
    public async Task ReturnsOnlyWarningBulletinsForTheRequestedPrefecture()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, AlertFeedXml, "application/xml");
        var provider = WeatherTestFactory.CreateAlertProvider(handler);

        var alerts = await provider.GetAlertsAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            10,
            TestContext.CancellationToken);

        Assert.HasCount(1, alerts);
        Assert.AreEqual("気象警報・注意報", alerts[0].Headline);
        Assert.AreEqual("東京都気象警報・注意報", alerts[0].Description);
        Assert.AreEqual("気象庁", alerts[0].Sender);
        Assert.AreEqual("東京都", alerts[0].AreaName);
        Assert.AreEqual(
            "https://www.data.jma.go.jp/developer/xml/data/tokyo-warning.xml",
            alerts[0].DetailUrl);
        Assert.AreEqual(
            new DateTimeOffset(2026, 8, 30, 7, 53, 0, TimeSpan.Zero),
            alerts[0].PublishedAt);
        StringAssert.Contains(alerts[0].Source.Name, "Japan Meteorological Agency");
        Assert.AreEqual(
            "https://www.data.jma.go.jp/developer/xml/feed/extra.xml",
            alerts[0].Source.AttributionUrl);
        StringAssert.Contains(alerts[0].Source.Notice, "authoritative area list and detail");
    }

    [TestMethod]
    public async Task SelectsBulletinsForOtherPrefectures()
    {
        var provider = WeatherTestFactory.CreateAlertProvider(
            new RecordingHandler(HttpStatusCode.OK, AlertFeedXml, "application/xml"));

        var alerts = await provider.GetAlertsAsync(
            JapanAreaCatalog.Resolve("Osaka"),
            10,
            TestContext.CancellationToken);

        Assert.HasCount(1, alerts);
        Assert.AreEqual("土砂災害警戒情報", alerts[0].Headline);
    }

    [TestMethod]
    public async Task RequestsTheDocumentedAtomFeedAddress()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, AlertFeedXml, "application/xml");
        var provider = WeatherTestFactory.CreateAlertProvider(handler);

        await provider.GetAlertsAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            10,
            TestContext.CancellationToken);

        Assert.AreEqual(
            "https://www.data.jma.go.jp/developer/xml/feed/extra.xml",
            handler.RequestUri!.AbsoluteUri);
    }

    [TestMethod]
    public async Task CapsResultsAtTheRequestedLimit()
    {
        var provider = WeatherTestFactory.CreateAlertProvider(
            new RecordingHandler(HttpStatusCode.OK, AlertFeedXml, "application/xml"));

        var alerts = await provider.GetAlertsAsync(
            JapanAreaCatalog.Resolve("Tokyo"),
            1,
            TestContext.CancellationToken);

        Assert.HasCount(1, alerts);
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(26)]
    public async Task RejectsAlertLimitOutsideContractBounds(int limit)
    {
        var provider = WeatherTestFactory.CreateAlertProvider(
            new RecordingHandler(HttpStatusCode.OK, AlertFeedXml, "application/xml"));

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(() =>
            provider.GetAlertsAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                limit,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task RejectsNonAtomPayload()
    {
        var provider = WeatherTestFactory.CreateAlertProvider(new RecordingHandler(
            HttpStatusCode.OK,
            "<rss version=\"2.0\"><channel /></rss>",
            "application/xml"));

        var exception = await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetAlertsAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                10,
                TestContext.CancellationToken));

        StringAssert.Contains(exception.Message, "documented Atom envelope");
    }

    [TestMethod]
    public async Task RejectsMalformedXml()
    {
        var provider = WeatherTestFactory.CreateAlertProvider(
            new RecordingHandler(HttpStatusCode.OK, "<feed", "application/xml"));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            provider.GetAlertsAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                10,
                TestContext.CancellationToken));
    }

    [TestMethod]
    public async Task FeedOutageSurfacesTransientHttpFailure()
    {
        var provider = WeatherTestFactory.CreateAlertProvider(
            new RecordingHandler(HttpStatusCode.ServiceUnavailable, "down", "text/plain"));

        var exception = await Assert.ThrowsExactlyAsync<HttpRequestException>(() =>
            provider.GetAlertsAsync(
                JapanAreaCatalog.Resolve("Tokyo"),
                10,
                TestContext.CancellationToken));

        Assert.AreEqual(HttpStatusCode.ServiceUnavailable, exception.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
