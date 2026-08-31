using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace SeoulTourist.Tourism;

public sealed class KtoTourApiProvider(
    HttpClient httpClient,
    IOptions<KtoTourApiOptions> options) : ITourismProvider
{
    private const string ProviderName = "Korea Tourism Organization TourAPI Service2";
    private const string AttributionUrl = "https://api.visitkorea.or.kr/";
    private const double EarthRadiusMeters = 6_371_000;
    private readonly KtoTourApiOptions _options = options.Value;

    public async Task<IReadOnlyList<TourismAttraction>> SearchAttractionsAsync(
        string query,
        TourismLocation center,
        int radiusMeters,
        int limit,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(query);
        ValidateLocation(center);
        ArgumentOutOfRangeException.ThrowIfLessThan(radiusMeters, 100);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(radiusMeters, 50_000);
        ArgumentOutOfRangeException.ThrowIfLessThan(limit, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(limit, 20);
        if (string.IsNullOrWhiteSpace(_options.ServiceKey))
        {
            throw new InvalidOperationException(
                "KtoTourApi:ServiceKey must contain a decoded data.go.kr service key.");
        }

        var path = QueryHelpers.AddQueryString(
            $"{_options.ServiceName}/searchKeyword2",
            new Dictionary<string, string?>
            {
                ["serviceKey"] = _options.ServiceKey,
                ["MobileOS"] = _options.MobileOperatingSystem,
                ["MobileApp"] = _options.MobileApplication,
                ["_type"] = "json",
                ["keyword"] = query.Trim(),
                ["lDongRegnCd"] = "11",
                ["arrange"] = "A",
                ["numOfRows"] = Math.Min(Math.Max(limit * 5, 20), 100)
                    .ToString(CultureInfo.InvariantCulture),
                ["pageNo"] = "1"
            });

        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        var responseElement = document.RootElement.GetProperty("response");
        EnsureSuccessfulResponse(responseElement);
        if (!TryGetItems(responseElement, out var items))
        {
            return [];
        }

        var source = new TourismSource(ProviderName, AttributionUrl, DateTimeOffset.UtcNow);
        return EnumerateItems(items)
            .Select(item => ParseAttraction(item, center, source))
            .Where(attraction => attraction is not null
                && attraction.DistanceMeters <= radiusMeters)
            .Cast<TourismAttraction>()
            .OrderBy(attraction => attraction.DistanceMeters)
            .ThenBy(attraction => attraction.Name, StringComparer.Ordinal)
            .Take(limit)
            .ToArray();
    }

    private static void EnsureSuccessfulResponse(JsonElement response)
    {
        if (!response.TryGetProperty("header", out var header))
        {
            throw new InvalidDataException("KTO TourAPI response did not contain a header.");
        }

        var resultCode = ReadString(header, "resultCode");
        if (!string.Equals(resultCode, "0000", StringComparison.Ordinal))
        {
            var message = ReadString(header, "resultMsg") ?? "Unknown provider error";
            throw new InvalidOperationException(
                $"KTO TourAPI returned result code {resultCode ?? "missing"}: {message}");
        }
    }

    private static bool TryGetItems(JsonElement response, out JsonElement items)
    {
        if (response.TryGetProperty("body", out var body)
            && body.TryGetProperty("items", out var itemsContainer)
            && itemsContainer.ValueKind == JsonValueKind.Object
            && itemsContainer.TryGetProperty("item", out items)
            && items.ValueKind is JsonValueKind.Array or JsonValueKind.Object)
        {
            return true;
        }

        items = default;
        return false;
    }

    private static IEnumerable<JsonElement> EnumerateItems(JsonElement items)
    {
        if (items.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in items.EnumerateArray())
            {
                yield return item;
            }
        }
        else
        {
            yield return items;
        }
    }

    private static TourismAttraction? ParseAttraction(
        JsonElement item,
        TourismLocation center,
        TourismSource source)
    {
        var contentId = ReadString(item, "contentid");
        var name = ReadString(item, "title");
        var longitude = ReadDouble(item, "mapx");
        var latitude = ReadDouble(item, "mapy");
        if (string.IsNullOrWhiteSpace(contentId)
            || string.IsNullOrWhiteSpace(name)
            || longitude is null
            || latitude is null)
        {
            return null;
        }

        var position = new TourismLocation(latitude.Value, longitude.Value);
        var address = string.Join(
            " ",
            new[] { ReadString(item, "addr1"), ReadString(item, "addr2") }
                .Where(part => !string.IsNullOrWhiteSpace(part)));
        return new TourismAttraction(
            contentId,
            name,
            DescribeContentType(ReadString(item, "contenttypeid")),
            string.IsNullOrWhiteSpace(address) ? null : address,
            position,
            CalculateDistanceMeters(center, position),
            ReadHttpUrl(item, "firstimage"),
            ReadString(item, "tel"),
            ReadModifiedAt(item),
            source);
    }

    private static double CalculateDistanceMeters(
        TourismLocation first,
        TourismLocation second)
    {
        var latitudeDelta = DegreesToRadians(second.Latitude - first.Latitude);
        var longitudeDelta = DegreesToRadians(second.Longitude - first.Longitude);
        var firstLatitude = DegreesToRadians(first.Latitude);
        var secondLatitude = DegreesToRadians(second.Latitude);
        var haversine = Math.Pow(Math.Sin(latitudeDelta / 2), 2)
            + Math.Cos(firstLatitude)
            * Math.Cos(secondLatitude)
            * Math.Pow(Math.Sin(longitudeDelta / 2), 2);
        return EarthRadiusMeters * 2 * Math.Atan2(Math.Sqrt(haversine), Math.Sqrt(1 - haversine));
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180;

    private static DateTimeOffset? ReadModifiedAt(JsonElement item)
    {
        var value = ReadString(item, "modifiedtime");
        return DateTime.TryParseExact(
            value,
            "yyyyMMddHHmmss",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var localTime)
                ? new DateTimeOffset(
                    DateTime.SpecifyKind(localTime, DateTimeKind.Unspecified),
                    TimeSpan.FromHours(9))
                : null;
    }

    private static string? ReadHttpUrl(JsonElement item, string propertyName)
    {
        var value = ReadString(item, propertyName);
        return Uri.TryCreate(value, UriKind.Absolute, out var uri)
            && uri.Scheme is "http" or "https"
                ? uri.AbsoluteUri
                : null;
    }

    private static string? ReadString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        return property.ValueKind switch
        {
            JsonValueKind.String => property.GetString(),
            JsonValueKind.Number => property.GetRawText(),
            _ => null
        };
    }

    private static double? ReadDouble(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        if (property.ValueKind == JsonValueKind.Number
            && property.TryGetDouble(out var numericValue))
        {
            return numericValue;
        }

        return property.ValueKind == JsonValueKind.String
            && double.TryParse(
                property.GetString(),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var textValue)
            ? textValue
            : null;
    }

    private static string? DescribeContentType(string? contentTypeId) => contentTypeId switch
    {
        "12" or "76" => "Tourist attraction",
        "14" or "78" => "Cultural facility",
        "15" or "85" => "Festival or performance",
        "25" or "75" => "Travel course",
        "28" or "79" => "Leisure or sports",
        "32" or "80" => "Accommodation",
        "38" or "77" => "Shopping",
        "39" or "82" => "Restaurant",
        _ => null
    };

    private static void ValidateLocation(TourismLocation location)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Latitude, -90);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Latitude, 90);
        ArgumentOutOfRangeException.ThrowIfLessThan(location.Longitude, -180);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(location.Longitude, 180);
    }
}
