using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Direct European Central Bank SDMX fallback. The ECB publishes euro-based daily reference
/// rates, so any non-euro pair is derived locally as a EUR cross rate from two observations that
/// must share the same publication date.
/// </summary>
public sealed class EcbSdmxExchangeRateProvider(
    HttpClient httpClient,
    IOptions<EcbSdmxOptions> options)
{
    /// <summary>Attribution name for the direct ECB data source.</summary>
    public const string ProviderName = "European Central Bank euro foreign exchange reference rates";

    /// <summary>Attribution link for the direct ECB data source.</summary>
    public const string AttributionUrl =
        "https://data.ecb.europa.eu/data/datasets/EXR";

    private const string FreshnessNote =
        "European Central Bank euro reference rates published once per working day around 16:00 CET. "
        + "Non-euro pairs are derived locally as EUR cross rates from same-day observations and are "
        + "not transaction rates.";

    private readonly EcbSdmxOptions _options = options.Value;

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
        if (string.Equals(source, target, StringComparison.Ordinal))
        {
            return null;
        }

        var required = new List<string>(2);
        if (!string.Equals(source, CurrencyCodes.EuroCurrency, StringComparison.Ordinal))
        {
            required.Add(source);
        }

        if (!string.Equals(target, CurrencyCodes.EuroCurrency, StringComparison.Ordinal))
        {
            required.Add(target);
        }

        if (required.Count == 0)
        {
            return null;
        }

        var observations = await ReadObservationsAsync(required, asOfDate, cancellationToken);
        if (observations is null)
        {
            return null;
        }

        var perEuro = observations.Value.PerEuro;
        if (!TryResolvePerEuro(source, perEuro, out var sourcePerEuro)
            || !TryResolvePerEuro(target, perEuro, out var targetPerEuro)
            || sourcePerEuro <= 0)
        {
            return null;
        }

        var rate = targetPerEuro / sourcePerEuro;
        var observationDate = observations.Value.ObservationDate;
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
                    ? "Latest ECB euro reference rate cross"
                    : "Historical ECB euro reference rate cross",
                FreshnessNote,
                DateTimeOffset.UtcNow));
    }

    private static bool TryResolvePerEuro(
        string currency,
        Dictionary<string, decimal> perEuro,
        out decimal value)
    {
        if (string.Equals(currency, CurrencyCodes.EuroCurrency, StringComparison.Ordinal))
        {
            value = 1m;
            return true;
        }

        return perEuro.TryGetValue(currency, out value);
    }

    private async Task<(DateOnly ObservationDate, Dictionary<string, decimal> PerEuro)?>
        ReadObservationsAsync(
            IReadOnlyList<string> currencies,
            DateOnly? asOfDate,
            CancellationToken cancellationToken)
    {
        var key = $"D.{string.Join('+', currencies)}.EUR.SP00.A";
        var parameters = new Dictionary<string, string?>
        {
            ["format"] = "csvdata",
            ["detail"] = "dataonly",
            ["lastNObservations"] = "1"
        };
        if (asOfDate is { } date)
        {
            parameters["startPeriod"] = date
                .AddDays(-_options.HistoricalLookbackDays)
                .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            parameters["endPeriod"] = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            QueryHelpers.AddQueryString(key, parameters));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/csv"));

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.NoContent)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        var csv = await response.Content.ReadAsStringAsync(cancellationToken);
        return ParseCsv(csv, currencies);
    }

    /// <summary>
    /// Parses the ECB SDMX CSV projection. Column positions are resolved from the header row, so
    /// an added column does not silently shift the parsed values.
    /// </summary>
    internal static (DateOnly ObservationDate, Dictionary<string, decimal> PerEuro)? ParseCsv(
        string csv,
        IReadOnlyList<string> currencies)
    {
        var lines = csv.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (lines.Length < 2)
        {
            return null;
        }

        var header = lines[0].Split(',', StringSplitOptions.TrimEntries);
        var currencyIndex = Array.FindIndex(header, column =>
            string.Equals(column, "CURRENCY", StringComparison.OrdinalIgnoreCase));
        var periodIndex = Array.FindIndex(header, column =>
            string.Equals(column, "TIME_PERIOD", StringComparison.OrdinalIgnoreCase));
        var valueIndex = Array.FindIndex(header, column =>
            string.Equals(column, "OBS_VALUE", StringComparison.OrdinalIgnoreCase));
        if (currencyIndex < 0 || periodIndex < 0 || valueIndex < 0)
        {
            throw new InvalidDataException(
                "The European Central Bank response did not contain the expected SDMX CSV columns.");
        }

        var perEuro = new Dictionary<string, decimal>(StringComparer.Ordinal);
        DateOnly? observationDate = null;
        for (var index = 1; index < lines.Length; index++)
        {
            var fields = lines[index].Split(',', StringSplitOptions.TrimEntries);
            if (fields.Length <= Math.Max(currencyIndex, Math.Max(periodIndex, valueIndex)))
            {
                continue;
            }

            if (!DateOnly.TryParseExact(
                    fields[periodIndex],
                    "yyyy-MM-dd",
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.None,
                    out var period)
                || !decimal.TryParse(
                    fields[valueIndex],
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out var value)
                || value <= 0)
            {
                continue;
            }

            var currency = fields[currencyIndex].ToUpperInvariant();
            if (observationDate is { } existing && existing != period)
            {
                throw new InvalidDataException(
                    "The European Central Bank returned observations from different publication "
                    + "dates, so a same-day cross rate could not be derived.");
            }

            observationDate ??= period;
            perEuro[currency] = value;
        }

        if (observationDate is null
            || currencies.Any(currency => !perEuro.ContainsKey(currency)))
        {
            return null;
        }

        return (observationDate.Value, perEuro);
    }
}
