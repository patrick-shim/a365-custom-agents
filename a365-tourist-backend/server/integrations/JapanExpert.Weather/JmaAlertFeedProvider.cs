using System.Globalization;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather;

/// <summary>
/// Japan Meteorological Agency warning and advisory bulletins read from the documented JMA XML
/// Atom feed. Only bulletin headlines are returned; the linked JMA document remains the
/// authoritative detail and its URL is included on every result.
/// </summary>
public sealed class JmaAlertFeedProvider(
    HttpClient httpClient,
    IOptions<JmaOptions> options,
    TimeProvider timeProvider) : IWeatherAlertProvider
{
    /// <summary>Attribution name for the JMA XML feed product.</summary>
    public const string ProviderName = "Japan Meteorological Agency (気象庁) XML bulletin feed";

    private const string LicenseNotice =
        "Japan Meteorological Agency XML feed terms of use (https://xml.kishou.go.jp/)";

    private const string UsageNotice =
        "Source: Japan Meteorological Agency. Official warning, advisory, and alert bulletin "
        + "headlines from the documented JMA XML Atom feed, filtered to the requested prefecture. "
        + "Open the linked JMA document for the authoritative area list and detail.";

    private const int MaximumTextLength = 300;
    private static readonly XNamespace Atom = "http://www.w3.org/2005/Atom";
    private readonly JmaOptions _options = options.Value;

    public async Task<IReadOnlyList<WeatherAlert>> GetAlertsAsync(
        JapanArea area,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(area);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, IWeatherAlertProvider.MaximumAlerts);

        if (!Uri.TryCreate(_options.AlertFeedAddress, UriKind.Absolute, out var feedAddress))
        {
            throw new InvalidOperationException(
                "Jma:AlertFeedAddress must be an absolute HTTPS URI.");
        }

        using var response = await httpClient.GetAsync(feedAddress, cancellationToken);
        JmaHttp.EnsureUsableResponse(response.StatusCode, "alert feed");

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = XmlReader.Create(
            content,
            new XmlReaderSettings
            {
                Async = true,
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                MaxCharactersFromEntities = 0,
                IgnoreComments = true,
                IgnoreProcessingInstructions = true,
                IgnoreWhitespace = true
            });

        XDocument feed;
        try
        {
            feed = await XDocument.LoadAsync(reader, LoadOptions.None, cancellationToken);
        }
        catch (XmlException)
        {
            throw new InvalidDataException(
                "The Japan Meteorological Agency alert feed did not contain well-formed XML.");
        }

        if (feed.Root is null
            || feed.Root.Name != Atom + "feed")
        {
            throw new InvalidDataException(
                "The Japan Meteorological Agency alert feed did not use the documented Atom envelope.");
        }

        var source = new WeatherSource(
            ProviderName,
            _options.AlertFeedAddress,
            LicenseNotice,
            UsageNotice,
            timeProvider.GetUtcNow());
        var results = new List<WeatherAlert>(limit);
        var inspected = 0;

        foreach (var entry in feed.Root.Elements(Atom + "entry"))
        {
            if (inspected >= _options.MaximumFeedEntries || results.Count >= limit)
            {
                break;
            }

            inspected++;
            if (TryReadAlert(entry, area, source) is { } alert)
            {
                results.Add(alert);
            }
        }

        return results;
    }

    private WeatherAlert? TryReadAlert(XElement entry, JapanArea area, WeatherSource source)
    {
        var headline = Read(entry, "title");
        if (headline is null || !IsAlertHeadline(headline))
        {
            return null;
        }

        var description = Read(entry, "content") ?? headline;
        var sender = entry.Element(Atom + "author")?.Element(Atom + "name")?.Value.Trim();
        if (!MatchesArea(area, description, headline, sender))
        {
            return null;
        }

        var detailUrl = ReadDetailUrl(entry);
        var id = Read(entry, "id") ?? detailUrl;
        if (id is null || detailUrl is null)
        {
            return null;
        }

        return new WeatherAlert(
            Truncate(id),
            Truncate(sender ?? ProviderName),
            Truncate(headline),
            Truncate(description),
            area.PrefectureJapanese,
            ReadPublishedAt(entry),
            detailUrl,
            source);
    }

    private bool IsAlertHeadline(string headline) =>
        _options.AlertTitleKeywords.Any(keyword =>
            !string.IsNullOrWhiteSpace(keyword)
            && headline.Contains(keyword, StringComparison.Ordinal));

    private static bool MatchesArea(
        JapanArea area,
        string description,
        string headline,
        string? sender)
    {
        return Contains(description, area) || Contains(headline, area) || Contains(sender, area);

        static bool Contains(string? value, JapanArea area) =>
            !string.IsNullOrWhiteSpace(value)
            && (value.Contains(area.PrefectureJapanese, StringComparison.Ordinal)
                || value.Contains(area.MatchStem, StringComparison.Ordinal));
    }

    private static string? ReadDetailUrl(XElement entry)
    {
        foreach (var link in entry.Elements(Atom + "link"))
        {
            var href = link.Attribute("href")?.Value;
            if (Uri.TryCreate(href, UriKind.Absolute, out var uri)
                && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp))
            {
                return uri.AbsoluteUri;
            }
        }

        return null;
    }

    private DateTimeOffset ReadPublishedAt(XElement entry)
    {
        var raw = Read(entry, "updated") ?? Read(entry, "published");
        return DateTimeOffset.TryParse(
            raw,
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var value)
            ? value
            : timeProvider.GetUtcNow();
    }

    private static string? Read(XElement entry, string name)
    {
        var value = entry.Element(Atom + name)?.Value.Trim();
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static string Truncate(string value) =>
        value.Length <= MaximumTextLength ? value : value[..MaximumTextLength];
}
