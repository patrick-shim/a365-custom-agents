using System.Globalization;
using System.Text.Json;

namespace JapanExpert.Weather;

/// <summary>
/// Strict guard for the undocumented JMA <c>bosai</c> forecast JSON payload.
/// <para>
/// The endpoint is not a documented public API and its shape changed during 2026, so the response
/// is validated before any mapping. Legacy or drifted payloads fail explicitly with
/// <see cref="InvalidDataException"/> rather than being partially interpreted.
/// </para>
/// </summary>
public static class JmaForecastSchema
{
    /// <summary>Value arrays this backend actually consumes and therefore length-checks.</summary>
    private static readonly string[] ConsumedSeries =
        ["weathers", "weatherCodes", "pops", "tempsMin", "tempsMax"];

    /// <summary>Property names that only ever appeared in the pre-2026 payload shape.</summary>
    private static readonly string[] LegacyMarkers = ["srf", "pfw", "forecasts", "weekly"];

    /// <summary>Validates the payload shape and returns the forecast group array.</summary>
    public static JsonElement EnsureSupported(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: the configured bosai endpoint "
                + "returned a legacy or unsupported payload instead of the expected forecast array.");
        }

        if (root.GetArrayLength() == 0)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: the forecast array was empty.");
        }

        foreach (var group in root.EnumerateArray())
        {
            EnsureGroup(group);
        }

        return root;
    }

    /// <summary>Reads and validates <c>reportDatetime</c> from the first forecast group.</summary>
    public static DateTimeOffset ReadReportedAt(JsonElement root)
    {
        var first = root[0];
        return ParseTimestamp(first, "reportDatetime");
    }

    /// <summary>Reads <c>publishingOffice</c> from the first forecast group.</summary>
    public static string ReadPublishingOffice(JsonElement root) =>
        root[0].GetProperty("publishingOffice").GetString()!;

    private static void EnsureGroup(JsonElement group)
    {
        if (group.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: a forecast group was not an object.");
        }

        foreach (var marker in LegacyMarkers)
        {
            if (group.TryGetProperty(marker, out _))
            {
                throw new InvalidDataException(
                    "The JMA forecast schema guard rejected a legacy bosai payload: unsupported "
                    + $"container '{marker}' is no longer part of the supported forecast contract.");
            }
        }

        if (!group.TryGetProperty("publishingOffice", out var office)
            || office.ValueKind != JsonValueKind.String
            || string.IsNullOrWhiteSpace(office.GetString()))
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: publishingOffice was missing.");
        }

        _ = ParseTimestamp(group, "reportDatetime");

        if (!group.TryGetProperty("timeSeries", out var timeSeries)
            || timeSeries.ValueKind != JsonValueKind.Array
            || timeSeries.GetArrayLength() == 0)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: timeSeries was missing or empty.");
        }

        foreach (var series in timeSeries.EnumerateArray())
        {
            EnsureSeries(series);
        }
    }

    private static void EnsureSeries(JsonElement series)
    {
        if (series.ValueKind != JsonValueKind.Object
            || !series.TryGetProperty("timeDefines", out var timeDefines)
            || timeDefines.ValueKind != JsonValueKind.Array
            || timeDefines.GetArrayLength() == 0)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: timeDefines was missing or empty.");
        }

        foreach (var time in timeDefines.EnumerateArray())
        {
            if (time.ValueKind != JsonValueKind.String
                || !DateTimeOffset.TryParse(
                    time.GetString(),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out _))
            {
                throw new InvalidDataException(
                    "The JMA forecast schema guard rejected the response: a timeDefines entry was "
                    + "not an ISO-8601 timestamp.");
            }
        }

        if (!series.TryGetProperty("areas", out var areas)
            || areas.ValueKind != JsonValueKind.Array
            || areas.GetArrayLength() == 0)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: areas was missing or empty.");
        }

        var expectedLength = timeDefines.GetArrayLength();
        foreach (var area in areas.EnumerateArray())
        {
            EnsureArea(area, expectedLength);
        }
    }

    private static void EnsureArea(JsonElement area, int expectedLength)
    {
        if (area.ValueKind != JsonValueKind.Object
            || !area.TryGetProperty("area", out var descriptor)
            || descriptor.ValueKind != JsonValueKind.Object
            || !descriptor.TryGetProperty("code", out var code)
            || code.ValueKind != JsonValueKind.String
            || !descriptor.TryGetProperty("name", out var name)
            || name.ValueKind != JsonValueKind.String)
        {
            throw new InvalidDataException(
                "The JMA forecast schema guard rejected the response: an area descriptor was missing "
                + "its code or name.");
        }

        foreach (var seriesName in ConsumedSeries)
        {
            if (!area.TryGetProperty(seriesName, out var values))
            {
                continue;
            }

            if (values.ValueKind != JsonValueKind.Array
                || values.GetArrayLength() != expectedLength)
            {
                throw new InvalidDataException(
                    $"The JMA forecast schema guard rejected the response: '{seriesName}' did not "
                    + "align with timeDefines.");
            }
        }
    }

    private static DateTimeOffset ParseTimestamp(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String
            || !DateTimeOffset.TryParse(
                property.GetString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var value))
        {
            throw new InvalidDataException(
                $"The JMA forecast schema guard rejected the response: '{propertyName}' was missing "
                + "or was not an ISO-8601 timestamp.");
        }

        return value;
    }
}
