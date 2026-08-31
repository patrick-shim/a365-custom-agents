using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather;

/// <summary>
/// Japan Meteorological Agency prefecture forecast built from the configurable <c>bosai</c>
/// forecast JSON endpoint. The payload is validated by <see cref="JmaForecastSchema"/> and
/// rejected when it is stale, so a silently changed upstream contract can never be mapped.
/// </summary>
public sealed class JmaForecastProvider(
    HttpClient httpClient,
    IOptions<JmaOptions> options,
    TimeProvider timeProvider) : IWeatherForecastProvider
{
    /// <summary>Attribution name for the JMA forecast product.</summary>
    public const string ProviderName = "Japan Meteorological Agency (気象庁) prefecture forecast";

    /// <summary>Attribution link for the JMA forecast product.</summary>
    public const string AttributionUrl = "https://www.jma.go.jp/bosai/forecast/";

    private const string LicenseNotice =
        "Japan Meteorological Agency website terms of use (https://www.jma.go.jp/jma/kishou/info/coment.html)";

    private const string TransformationNotice =
        "Source: Japan Meteorological Agency. Retrieved from the configurable JMA bosai forecast "
        + "JSON endpoint, which JMA does not publish as a documented API, and accepted only after a "
        + "strict schema and freshness guard. Japanese forecast text is preserved verbatim; English "
        + "summaries are a Japan Expert transformation of JMA text and weather telop codes.";

    private static readonly TimeSpan JapanOffset = TimeSpan.FromHours(9);
    private readonly JmaOptions _options = options.Value;

    public async Task<WeatherForecastResult> GetForecastAsync(
        JapanArea area,
        int days,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(area);
        ArgumentOutOfRangeException.ThrowIfLessThan(days, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(days, IWeatherForecastProvider.MaximumDays);

        if (!_options.ForecastEnabled)
        {
            throw new InvalidOperationException(
                "The Japan Meteorological Agency forecast source is disabled by configuration.");
        }

        if (!Uri.TryCreate(_options.ForecastBaseAddress, UriKind.Absolute, out var baseAddress))
        {
            throw new InvalidOperationException(
                "Jma:ForecastBaseAddress must be an absolute HTTPS URI ending with a slash.");
        }

        var requestUri = new Uri(baseAddress, $"{area.OfficeCode}.json");
        using var response = await httpClient.GetAsync(requestUri, cancellationToken);
        JmaHttp.EnsureUsableResponse(response.StatusCode, "forecast");

        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        var root = JmaForecastSchema.EnsureSupported(document.RootElement);
        var reportedAt = JmaForecastSchema.ReadReportedAt(root);
        EnsureFresh(reportedAt);

        var retrievedAt = timeProvider.GetUtcNow();
        return new WeatherForecastResult(
            area.OfficeCode,
            area.PrefectureEnglish,
            area.PrefectureJapanese,
            ReadPrimaryAreaName(root),
            JmaForecastSchema.ReadPublishingOffice(root),
            reportedAt,
            BuildDays(root, days, reportedAt),
            new WeatherSource(
                ProviderName,
                AttributionUrl,
                LicenseNotice,
                TransformationNotice,
                retrievedAt));
    }

    private void EnsureFresh(DateTimeOffset reportedAt)
    {
        var now = timeProvider.GetUtcNow();
        var age = now - reportedAt;
        if (age > TimeSpan.FromHours(_options.MaximumForecastAgeHours))
        {
            throw new InvalidDataException(
                "The Japan Meteorological Agency forecast payload was stale: the report timestamp "
                + $"was older than {_options.MaximumForecastAgeHours} hours.");
        }

        if (age < -TimeSpan.FromHours(_options.MaximumForecastClockSkewHours))
        {
            throw new InvalidDataException(
                "The Japan Meteorological Agency forecast payload was rejected: the report timestamp "
                + "was implausibly far ahead of the current time.");
        }
    }

    private static string ReadPrimaryAreaName(JsonElement root) =>
        root[0]
            .GetProperty("timeSeries")[0]
            .GetProperty("areas")[0]
            .GetProperty("area")
            .GetProperty("name")
            .GetString()!;

    private static List<DailyWeatherResult> BuildDays(
        JsonElement root,
        int days,
        DateTimeOffset reportedAt)
    {
        var japaneseText = new Dictionary<DateOnly, string>();
        var weatherCodes = new Dictionary<DateOnly, string>();
        var probabilities = new Dictionary<DateOnly, int>();
        var minimums = new Dictionary<DateOnly, double>();
        var maximums = new Dictionary<DateOnly, double>();

        foreach (var group in root.EnumerateArray())
        {
            foreach (var series in group.GetProperty("timeSeries").EnumerateArray())
            {
                var dates = ReadDates(series);
                var area = series.GetProperty("areas")[0];
                Collect(area, "weathers", dates, japaneseText);
                Collect(area, "weatherCodes", dates, weatherCodes);
                CollectInt32(area, "pops", dates, probabilities);
                CollectDouble(area, "tempsMin", dates, minimums);
                CollectDouble(area, "tempsMax", dates, maximums);
            }
        }

        var firstDate = DateOnly.FromDateTime(reportedAt.ToOffset(JapanOffset).Date);
        var results = new List<DailyWeatherResult>(days);
        for (var offset = 0; offset < days; offset++)
        {
            var date = firstDate.AddDays(offset);
            japaneseText.TryGetValue(date, out var japanese);
            weatherCodes.TryGetValue(date, out var code);
            if (japanese is null
                && code is null
                && !probabilities.ContainsKey(date)
                && !minimums.ContainsKey(date)
                && !maximums.ContainsKey(date))
            {
                continue;
            }

            results.Add(new DailyWeatherResult(
                date,
                JmaWeatherSummary.Describe(japanese, code),
                japanese,
                code,
                minimums.TryGetValue(date, out var minimum) ? minimum : null,
                maximums.TryGetValue(date, out var maximum) ? maximum : null,
                probabilities.TryGetValue(date, out var probability) ? probability : null));
        }

        if (results.Count == 0)
        {
            throw new InvalidDataException(
                "The Japan Meteorological Agency forecast payload contained no usable daily values.");
        }

        return results;
    }

    private static DateOnly[] ReadDates(JsonElement series)
    {
        var timeDefines = series.GetProperty("timeDefines");
        var dates = new DateOnly[timeDefines.GetArrayLength()];
        for (var index = 0; index < dates.Length; index++)
        {
            var timestamp = DateTimeOffset.Parse(
                timeDefines[index].GetString()!,
                CultureInfo.InvariantCulture);
            dates[index] = DateOnly.FromDateTime(timestamp.ToOffset(JapanOffset).Date);
        }

        return dates;
    }

    private static void Collect(
        JsonElement area,
        string propertyName,
        DateOnly[] dates,
        Dictionary<DateOnly, string> target)
    {
        if (!area.TryGetProperty(propertyName, out var values))
        {
            return;
        }

        for (var index = 0; index < dates.Length; index++)
        {
            var value = values[index].ValueKind == JsonValueKind.String
                ? values[index].GetString()
                : null;
            if (!string.IsNullOrWhiteSpace(value))
            {
                target.TryAdd(dates[index], Normalize(value));
            }
        }
    }

    private static void CollectInt32(
        JsonElement area,
        string propertyName,
        DateOnly[] dates,
        Dictionary<DateOnly, int> target)
    {
        if (!area.TryGetProperty(propertyName, out var values))
        {
            return;
        }

        for (var index = 0; index < dates.Length; index++)
        {
            if (TryReadNumber(values[index], out var parsed))
            {
                var value = (int)Math.Round(parsed, MidpointRounding.AwayFromZero);
                target[dates[index]] = target.TryGetValue(dates[index], out var existing)
                    ? Math.Max(existing, value)
                    : value;
            }
        }
    }

    private static void CollectDouble(
        JsonElement area,
        string propertyName,
        DateOnly[] dates,
        Dictionary<DateOnly, double> target)
    {
        if (!area.TryGetProperty(propertyName, out var values))
        {
            return;
        }

        for (var index = 0; index < dates.Length; index++)
        {
            if (TryReadNumber(values[index], out var parsed))
            {
                target.TryAdd(dates[index], parsed);
            }
        }
    }

    private static bool TryReadNumber(JsonElement element, out double value)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Number when element.TryGetDouble(out value):
                return true;
            case JsonValueKind.String:
                return double.TryParse(
                    element.GetString(),
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out value);
            default:
                value = 0;
                return false;
        }
    }

    private static string Normalize(string value) =>
        value.Replace('\u3000', ' ').Trim();
}

/// <summary>Shared JMA status-code translation used by the forecast and alert providers.</summary>
internal static class JmaHttp
{
    internal static void EnsureUsableResponse(HttpStatusCode statusCode, string operation)
    {
        if (statusCode == HttpStatusCode.TooManyRequests)
        {
            throw new HttpRequestException(
                $"The Japan Meteorological Agency {operation} endpoint rate-limited this request.",
                inner: null,
                HttpStatusCode.TooManyRequests);
        }

        if (statusCode == HttpStatusCode.NotFound)
        {
            throw new HttpRequestException(
                $"The Japan Meteorological Agency {operation} endpoint has no data for this area.",
                inner: null,
                HttpStatusCode.NotFound);
        }

        if ((int)statusCode >= 400)
        {
            throw new HttpRequestException(
                $"The Japan Meteorological Agency {operation} endpoint is temporarily unavailable.",
                inner: null,
                statusCode);
        }
    }
}
