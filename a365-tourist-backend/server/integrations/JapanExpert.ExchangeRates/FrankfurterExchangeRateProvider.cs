using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Frankfurter v2 client pinned to European Central Bank reference rates.
/// <para>
/// The provider reads the documented v2 <c>rates</c> route, which answers with a JSON array of
/// rate rows shaped <c>[{ "date": "2026-08-28", "base": "USD", "quote": "JPY", "rate": 159.68 }]</c>.
/// It never calls a conversion endpoint, so all arithmetic stays local and auditable, and the
/// returned quote always carries the observation date reported by the upstream response.
/// </para>
/// <para>
/// Because a single quote currency is requested, exactly one row is expected. A response that is
/// not an array, carries more than one row, or reports a different base or quote currency is
/// rejected as provider drift rather than being partially interpreted. That guard is what catches
/// an endpoint accidentally pointed back at the v1 <c>latest</c>/<c>symbols</c> object contract.
/// </para>
/// </summary>
public sealed class FrankfurterExchangeRateProvider(
    HttpClient httpClient,
    IOptions<FrankfurterOptions> options)
{
    /// <summary>Attribution name for the Frankfurter reference-rate source.</summary>
    public const string ProviderName = "Frankfurter v2 (European Central Bank reference rates)";

    /// <summary>Attribution link for the Frankfurter reference-rate source.</summary>
    public const string AttributionUrl = "https://frankfurter.dev/";

    /// <summary>Documented v2 route for latest and historical published rates.</summary>
    private const string RatesEndpoint = "rates";

    private const string FreshnessNote =
        "European Central Bank reference rates are published once per working day around 16:00 CET "
        + "and are not transaction rates. Conversion arithmetic is performed locally by Japan Expert.";

    private readonly FrankfurterOptions _options = options.Value;

    public async Task<ExchangeRateQuote?> TryGetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default)
    {
        if (!_options.Enabled)
        {
            return null;
        }

        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        var parameters = new Dictionary<string, string?>
        {
            ["base"] = source,
            ["quotes"] = target,
            ["providers"] = _options.Providers
        };
        if (asOfDate is { } requestedDate)
        {
            parameters["date"] = requestedDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        var path = QueryHelpers.AddQueryString(RatesEndpoint, parameters);
        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        if (TryReadSingleRow(document.RootElement) is not { } row)
        {
            return null;
        }

        EnsureCurrencyPair(row, source, target);
        var rate = ReadPositiveRate(row);
        var observationDate = ReadObservationDate(row, asOfDate);

        return new ExchangeRateQuote(
            source,
            target,
            rate,
            observationDate,
            new DateTimeOffset(observationDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc)),
            new ExchangeRateSource(
                ProviderName,
                AttributionUrl,
                asOfDate is null
                    ? $"Latest {_options.Providers} reference rate"
                    : $"Historical {_options.Providers} reference rate",
                FreshnessNote,
                DateTimeOffset.UtcNow));
    }

    /// <summary>
    /// Returns the single expected rate row, <see langword="null"/> when the provider published no
    /// observation, and throws when the payload does not match the documented v2 array contract.
    /// </summary>
    private static JsonElement? TryReadSingleRow(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned an unexpected envelope: the documented rates response is a "
                + "JSON array of rate rows.");
        }

        var rowCount = root.GetArrayLength();
        if (rowCount == 0)
        {
            return null;
        }

        if (rowCount > 1)
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned more than one rate row for a single-quote request.");
        }

        var row = root[0];
        if (row.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned a rate row that was not an object.");
        }

        return row;
    }

    private static void EnsureCurrencyPair(JsonElement row, string source, string target)
    {
        if (!MatchesCurrency(row, "base", source))
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned a rate for a different base currency than requested.");
        }

        if (!MatchesCurrency(row, "quote", target))
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned a rate for a different quote currency than requested.");
        }
    }

    private static bool MatchesCurrency(JsonElement row, string propertyName, string expected) =>
        row.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
        && string.Equals(property.GetString(), expected, StringComparison.OrdinalIgnoreCase);

    private static decimal ReadPositiveRate(JsonElement row)
    {
        if (!row.TryGetProperty("rate", out var rateElement)
            || rateElement.ValueKind != JsonValueKind.Number
            || !rateElement.TryGetDecimal(out var rate)
            || rate <= 0)
        {
            throw new InvalidDataException(
                "Frankfurter v2 did not return a positive numeric rate value.");
        }

        return rate;
    }

    private static DateOnly ReadObservationDate(JsonElement row, DateOnly? asOfDate)
    {
        if (!row.TryGetProperty("date", out var dateElement)
            || dateElement.ValueKind != JsonValueKind.String
            || !DateOnly.TryParseExact(
                dateElement.GetString(),
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var observationDate))
        {
            throw new InvalidDataException(
                "Frankfurter v2 did not return a valid observation date.");
        }

        // A historical request may legitimately resolve back to the previous working day, but an
        // observation dated after the requested day is provider drift.
        if (asOfDate is { } requestedDate && observationDate > requestedDate)
        {
            throw new InvalidDataException(
                "Frankfurter v2 returned an observation dated after the requested date.");
        }

        return observationDate;
    }
}
