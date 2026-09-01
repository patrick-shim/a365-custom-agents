using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace KoreaExpert.ExchangeRates;

public sealed class ForexRateApiExchangeRateProvider(
    HttpClient httpClient,
    IOptions<ForexRateApiOptions> options)
{
    private const string ProviderName = "ForexRateAPI";
    private const string AttributionUrl = "https://forexrateapi.com/";
    private readonly ForexRateApiOptions _options = options.Value;

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

        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            throw new InvalidOperationException(
                "ForexRateApi:ApiKey is required when the provider is enabled.");
        }

        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        var endpoint = asOfDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? "latest";
        var path = QueryHelpers.AddQueryString(
            endpoint,
            new Dictionary<string, string?>
            {
                ["base"] = source,
                ["currencies"] = target
            });
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Add("X-API-KEY", _options.ApiKey);
        using var response = await httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var content = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            content,
            cancellationToken: cancellationToken);

        if (!ReadBoolean(document.RootElement, "success"))
        {
            throw new InvalidDataException("ForexRateAPI returned an unsuccessful response.");
        }

        if (!document.RootElement.TryGetProperty("rates", out var rates)
            || rates.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException("ForexRateAPI returned an invalid rates object.");
        }

        if (!rates.TryGetProperty(target, out var rateElement)
            || !rateElement.TryGetDecimal(out var rate)
            || rate <= 0)
        {
            return null;
        }

        if (!document.RootElement.TryGetProperty("timestamp", out var timestampElement)
            || !timestampElement.TryGetInt64(out var unixTimestamp))
        {
            throw new InvalidDataException("ForexRateAPI response did not contain a valid timestamp.");
        }

        var timestamp = DateTimeOffset.FromUnixTimeSeconds(unixTimestamp);
        return new ExchangeRateQuote(
            source,
            target,
            rate,
            timestamp,
            new ExchangeRateSource(
                ProviderName,
                AttributionUrl,
                asOfDate is null ? "Delayed market rate" : "Historical market rate",
                "Update delay depends on the configured ForexRateAPI subscription plan.",
                DateTimeOffset.UtcNow));
    }

    private static bool ReadBoolean(JsonElement element, string propertyName) =>
        element.TryGetProperty(propertyName, out var property)
        && property.ValueKind is JsonValueKind.True or JsonValueKind.False
        && property.GetBoolean();

}
