using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace SeoulTourist.ExchangeRates;

public sealed class FrankfurterExchangeRateProvider(
    HttpClient httpClient,
    IOptions<FrankfurterOptions> options)
{
    private const string ProviderName = "Frankfurter (European Central Bank reference rates)";
    private const string AttributionUrl = "https://frankfurter.dev/";
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
        var endpoint = asOfDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "latest";
        var path = QueryHelpers.AddQueryString(
            endpoint,
            new Dictionary<string, string?>
            {
                ["base"] = source,
                ["symbols"] = target
            });

        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        if (!document.RootElement.TryGetProperty("rates", out var rates)
            || rates.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("Frankfurter returned an invalid rates object.");
        }

        if (!rates.TryGetProperty(target, out var rateElement)
            || !rateElement.TryGetDecimal(out var rate)
            || rate <= 0)
        {
            return null;
        }

        if (!document.RootElement.TryGetProperty("date", out var dateElement)
            || !DateOnly.TryParseExact(
                dateElement.GetString(),
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var observedDate))
        {
            throw new InvalidDataException("Frankfurter response did not contain a valid date.");
        }
        var observedAt = new DateTimeOffset(
            observedDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc));
        return new ExchangeRateQuote(
            source,
            target,
            rate,
            observedAt,
            new ExchangeRateSource(
                ProviderName,
                AttributionUrl,
                asOfDate is null ? "Latest ECB reference rate" : "Historical ECB reference rate",
                "ECB reference rates are generally updated once per working day and are not transaction rates.",
                DateTimeOffset.UtcNow));
    }
}
