using System.Globalization;
using System.Text;

namespace JapanExpert.Tourism;

/// <summary>
/// Maps bounded Japan place searches onto OpenStreetMap data served by an Overpass API
/// instance. Every result carries ODbL attribution for OpenStreetMap contributors.
/// </summary>
public sealed class OverpassTourismProvider(OverpassClient client) : ITourismProvider
{
    /// <summary>Attribution name required by the Open Database License.</summary>
    public const string ProviderName = "OpenStreetMap contributors (via Overpass API)";

    /// <summary>Attribution link required by the Open Database License.</summary>
    public const string AttributionUrl = "https://www.openstreetmap.org/copyright";

    /// <summary>License identifier surfaced with every place result.</summary>
    public const string License = "Open Data Commons Open Database License (ODbL) 1.0";

    private const string Notice =
        "Data \u00a9 OpenStreetMap contributors, available under the ODbL. Retrieved through an "
        + "Overpass API instance and filtered to Japan. Opening hours, contacts, and categories are "
        + "community-maintained and may be incomplete.";

    private const int MaximumNameLength = 120;
    private const int MaximumAddressLength = 200;
    private const int MaximumTelephoneLength = 32;
    private const int MaximumOpeningHoursLength = 120;

    public Task<IReadOnlyList<TourismPlace>> SearchAttractionsAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var validated = request.Validate();
        return SearchAsync(
            validated,
            TourismCategories.ResolveAttractionSelectors(validated.Category),
            TourismPlaceKind.Attraction,
            cancellationToken);
    }

    public Task<IReadOnlyList<TourismPlace>> SearchAccommodationAsync(
        TourismSearchRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        var validated = request.Validate();
        return SearchAsync(
            validated,
            TourismCategories.ResolveAccommodationSelectors(validated.Category),
            TourismPlaceKind.Accommodation,
            cancellationToken);
    }

    private async Task<IReadOnlyList<TourismPlace>> SearchAsync(
        TourismSearchRequest request,
        IReadOnlyList<string> selectors,
        TourismPlaceKind kind,
        CancellationToken cancellationToken)
    {
        var fetchLimit = ResolveFetchLimit(request.Limit);
        var query = BuildQuery(
            selectors,
            request.Center,
            request.RadiusMeters,
            fetchLimit,
            client.QueryTimeoutSeconds);
        var elements = await client.QueryAsync(query, cancellationToken);
        var source = new TourismSource(
            ProviderName,
            AttributionUrl,
            License,
            Notice,
            DateTimeOffset.UtcNow);

        return
        [
            .. elements
                .Select(element => Map(element, request.Center, kind, source))
                .OfType<TourismPlace>()
                .Where(place => MatchesNameFilter(place, request.NameContains))
                .OrderBy(place => place.DistanceMeters)
                .ThenBy(place => place.Id, StringComparer.Ordinal)
                .Take(request.Limit)
        ];
    }

    /// <summary>Bounded fetch cap: never more than the configured maximum element count.</summary>
    internal int ResolveFetchLimit(int limit) =>
        Math.Clamp(limit * client.FetchMultiplier, limit, client.MaximumFetchElements);

    internal static string BuildQuery(
        IReadOnlyList<string> selectors,
        TourismLocation center,
        int radiusMeters,
        int fetchLimit,
        int queryTimeoutSeconds)
    {
        var latitude = OverpassClient.FormatCoordinate(center.Latitude);
        var longitude = OverpassClient.FormatCoordinate(center.Longitude);
        var builder = new StringBuilder();
        builder.Append(CultureInfo.InvariantCulture, $"[out:json][timeout:{queryTimeoutSeconds}];(");
        foreach (var selector in selectors)
        {
            builder.Append(CultureInfo.InvariantCulture, $"nwr{selector}");
            builder.Append(CultureInfo.InvariantCulture, $"(around:{radiusMeters},{latitude},{longitude});");
        }

        builder.Append(CultureInfo.InvariantCulture, $");out center {fetchLimit};");
        return builder.ToString();
    }

    private static bool MatchesNameFilter(TourismPlace place, string? nameContains)
    {
        if (string.IsNullOrWhiteSpace(nameContains))
        {
            return true;
        }

        var filter = nameContains.Trim();
        return place.Name.Contains(filter, StringComparison.OrdinalIgnoreCase)
            || (place.LocalName?.Contains(filter, StringComparison.OrdinalIgnoreCase) ?? false);
    }

    private static TourismPlace? Map(
        OverpassElement element,
        TourismLocation center,
        TourismPlaceKind kind,
        TourismSource source)
    {
        var name = Truncate(
            FirstTag(element, "name:en", "int_name", "name", "name:ja"),
            MaximumNameLength);
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        var localName = Truncate(FirstTag(element, "name", "name:ja"), MaximumNameLength);
        var position = new TourismLocation(element.Latitude, element.Longitude);
        return new TourismPlace(
            string.Create(CultureInfo.InvariantCulture, $"{element.Type}/{element.Id}"),
            name,
            string.Equals(localName, name, StringComparison.Ordinal) ? null : localName,
            kind,
            DescribeCategory(element),
            Truncate(ComposeAddress(element), MaximumAddressLength),
            position,
            JapanGeography.DistanceMeters(center, position),
            ReadWebsite(element),
            SanitizeTelephone(FirstTag(element, "phone", "contact:phone")),
            Truncate(FirstTag(element, "opening_hours"), MaximumOpeningHoursLength),
            source);
    }

    private static string? DescribeCategory(OverpassElement element)
    {
        if (element.Tags.TryGetValue("tourism", out var tourism))
        {
            return $"tourism={tourism}";
        }

        if (element.Tags.TryGetValue("historic", out var historic))
        {
            return $"historic={historic}";
        }

        if (element.Tags.TryGetValue("amenity", out var amenity)
            && string.Equals(amenity, "place_of_worship", StringComparison.Ordinal))
        {
            return element.Tags.TryGetValue("religion", out var religion)
                ? $"place_of_worship religion={religion}"
                : "place_of_worship";
        }

        return element.Tags.ContainsKey("heritage") ? "heritage" : null;
    }

    private static string? ComposeAddress(OverpassElement element)
    {
        if (element.Tags.TryGetValue("addr:full", out var full))
        {
            return full;
        }

        string[] ordered =
        [
            "addr:postcode",
            "addr:province",
            "addr:city",
            "addr:suburb",
            "addr:quarter",
            "addr:neighbourhood",
            "addr:block_number",
            "addr:housenumber"
        ];
        var parts = ordered
            .Select(key => element.Tags.TryGetValue(key, out var value) ? value : null)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToArray();
        return parts.Length == 0 ? null : string.Join(' ', parts);
    }

    private static string? ReadWebsite(OverpassElement element)
    {
        var candidate = FirstTag(element, "website", "contact:website", "url");
        return Uri.TryCreate(candidate, UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
                ? uri.AbsoluteUri
                : null;
    }

    private static string? SanitizeTelephone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var builder = new StringBuilder(MaximumTelephoneLength);
        foreach (var character in value.Trim())
        {
            if (builder.Length == MaximumTelephoneLength)
            {
                break;
            }

            if (char.IsAsciiDigit(character) || character is '+' or '-' or ' ' or '(' or ')')
            {
                builder.Append(character);
            }
        }

        var sanitized = builder.ToString().Trim();
        return sanitized.Length == 0 ? null : sanitized;
    }

    private static string? FirstTag(OverpassElement element, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (element.Tags.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return null;
    }

    private static string? Truncate(string? value, int maximumLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        return trimmed.Length <= maximumLength ? trimmed : trimmed[..maximumLength];
    }
}
