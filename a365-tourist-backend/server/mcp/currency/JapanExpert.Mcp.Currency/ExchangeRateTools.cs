using System.ComponentModel;
using System.Globalization;
using JapanExpert.ExchangeRates;
using JapanExpert.Mcp.Hosting;
using ModelContextProtocol.Server;

namespace JapanExpert.Mcp.Currency;

/// <summary>
/// Attributed exchange-rate lookup and conversion for Japan travel budgeting. Rates come from
/// published European Central Bank reference data; the conversion arithmetic is local.
/// </summary>
[McpServerToolType]
public sealed class ExchangeRateTools(
    IExchangeRateProvider exchangeRateProvider,
    ILogger<ExchangeRateTools> logger)
{
    [McpServerTool(Name = "get_exchange_rate")]
    [Description(
        "Gets an attributed exchange rate with its observation date, retrieval time, rate type, "
        + "source URL, and freshness note. Defaults to the Japanese yen as the target currency.")]
    public Task<ExchangeRateQuote> GetExchangeRateAsync(
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Three-letter target currency code. Defaults to JPY.")]
        string targetCurrency = CurrencyCodes.DefaultTravelCurrency,
        [Description("Optional historical observation date in YYYY-MM-DD format.")]
        string? date = null,
        CancellationToken cancellationToken = default) =>
        McpToolExecution.RunAsync(
            "currency.rate",
            logger,
            token => exchangeRateProvider.GetRateAsync(
                sourceCurrency,
                targetCurrency,
                ParseDate(date),
                token),
            cancellationToken);

    [McpServerTool(Name = "convert_currency")]
    [Description(
        "Converts an amount using an attributed published reference rate and returns the rate "
        + "source, observation date, and freshness metadata. Defaults to the Japanese yen and "
        + "formats the result with the target currency's minor-unit precision.")]
    public async Task<ProviderCurrencyConversion> ConvertCurrencyAsync(
        [Description("Amount in the source currency.")] decimal amount,
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Three-letter target currency code. Defaults to JPY.")]
        string targetCurrency = CurrencyCodes.DefaultTravelCurrency,
        [Description("Optional historical observation date in YYYY-MM-DD format.")]
        string? date = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(amount);
        var quote = await McpToolExecution.RunAsync(
            "currency.convert",
            logger,
            token => exchangeRateProvider.GetRateAsync(
                sourceCurrency,
                targetCurrency,
                ParseDate(date),
                token),
            cancellationToken);
        var converted = CurrencyCodes.Round(amount * quote.Rate, quote.TargetCurrency);
        return new ProviderCurrencyConversion(
            amount,
            quote.SourceCurrency,
            converted,
            quote.TargetCurrency,
            CurrencyCodes.Format(converted, quote.TargetCurrency),
            CurrencyCodes.GetDecimalDigits(quote.TargetCurrency),
            quote);
    }

    private static DateOnly? ParseDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (DateOnly.TryParseExact(
            value,
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out var date))
        {
            return date;
        }

        throw new ArgumentException("Dates must use YYYY-MM-DD format.", nameof(value));
    }
}

/// <summary>Conversion result carrying the full provider quote and its attribution.</summary>
public sealed record ProviderCurrencyConversion(
    decimal SourceAmount,
    string SourceCurrency,
    decimal TargetAmount,
    string TargetCurrency,
    string FormattedTargetAmount,
    int TargetCurrencyDecimalDigits,
    ExchangeRateQuote Quote);
