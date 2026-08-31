using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace KoreaExpert.ExchangeRates;

public sealed partial class KoreaEximbankExchangeRateProvider(
    HttpClient httpClient,
    IOptions<KoreaEximbankOptions> options)
{
    private const string ProviderName = "Korea Eximbank Current Exchange Rate API";
    private const string AttributionUrl = "https://www.koreaexim.go.kr/ir/HPHKIR020M01?apino=2";
    private static readonly TimeSpan KoreaOffset = TimeSpan.FromHours(9);
    private readonly KoreaEximbankOptions _options = options.Value;

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

        if (string.IsNullOrWhiteSpace(_options.AuthKey))
        {
            throw new InvalidOperationException(
                "KoreaEximbank:AuthKey is required when the provider is enabled.");
        }

        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        var requestedDate = asOfDate ?? DateOnly.FromDateTime(
            DateTimeOffset.UtcNow.ToOffset(KoreaOffset).Date);

        for (var lookback = 0; lookback <= _options.MaximumLookbackDays; lookback++)
        {
            var observedDate = requestedDate.AddDays(-lookback);
            var rates = await GetRatesAsync(observedDate, cancellationToken);
            if (rates.Count == 0)
            {
                continue;
            }

            if (!rates.TryGetValue(source, out var sourceKrwPerUnit)
                || !rates.TryGetValue(target, out var targetKrwPerUnit))
            {
                return null;
            }

            var retrievedAt = DateTimeOffset.UtcNow;
            return new ExchangeRateQuote(
                source,
                target,
                sourceKrwPerUnit / targetKrwPerUnit,
                new DateTimeOffset(
                    observedDate.ToDateTime(new TimeOnly(11, 0)),
                    KoreaOffset),
                new ExchangeRateSource(
                    ProviderName,
                    AttributionUrl,
                    "Daily official reference rate",
                    "Published on Korean business days around 11:00 KST; non-business days use the latest prior publication.",
                    retrievedAt));
        }

        return null;
    }

    private async Task<IReadOnlyDictionary<string, decimal>> GetRatesAsync(
        DateOnly date,
        CancellationToken cancellationToken)
    {
        var path = QueryHelpers.AddQueryString(
            "site/program/financial/exchangeJSON",
            new Dictionary<string, string?>
            {
                ["authkey"] = _options.AuthKey,
                ["searchdate"] = date.ToString("yyyyMMdd", CultureInfo.InvariantCulture),
                ["data"] = "AP01"
            });
        using var response = await httpClient.GetAsync(path, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);
        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidDataException("Korea Eximbank returned an invalid response shape.");
        }

        if (document.RootElement.GetArrayLength() == 0)
        {
            return new Dictionary<string, decimal>(StringComparer.Ordinal);
        }

        var result = ReadInt32(document.RootElement[0], "result");
        if (result is not 1)
        {
            throw result switch
            {
                3 => new UnauthorizedAccessException("Korea Eximbank authentication failed."),
                4 => new HttpRequestException(
                    "Korea Eximbank request limit was reached.",
                    null,
                    HttpStatusCode.TooManyRequests),
                _ => new InvalidDataException("Korea Eximbank returned an invalid result.")
            };
        }

        var rates = new Dictionary<string, decimal>(StringComparer.Ordinal)
        {
            ["KRW"] = 1m
        };
        foreach (var item in document.RootElement.EnumerateArray())
        {
            var unitText = ReadString(item, "cur_unit");
            var rateText = ReadString(item, "deal_bas_r");
            var unitMatch = CurrencyUnit().Match(unitText ?? string.Empty);
            if (!unitMatch.Success
                || !decimal.TryParse(
                    rateText,
                    NumberStyles.Number,
                    CultureInfo.InvariantCulture,
                    out var krwRate)
                || krwRate <= 0)
            {
                continue;
            }

            var unitCount = unitMatch.Groups["count"].Success
                ? decimal.Parse(unitMatch.Groups["count"].Value, CultureInfo.InvariantCulture)
                : 1m;
            rates[unitMatch.Groups["code"].Value] = krwRate / unitCount;
        }

        return rates;
    }

    private static string? ReadString(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;

    private static int? ReadInt32(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind == JsonValueKind.Number
        && property.TryGetInt32(out var value)
            ? value
            : null;

    [GeneratedRegex(
        "^(?<code>[A-Z]{3})(?:\\((?<count>[1-9][0-9]*)\\))?$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CurrencyUnit();
}
