using System.ComponentModel;
using System.Globalization;
using ModelContextProtocol.Server;
using KoreaExpert.ExchangeRates;
using KoreaExpert.Mcp.Hosting;

namespace KoreaExpert.Mcp.Currency;

[McpServerToolType]
public sealed class ExchangeRateTools(
    IExchangeRateProvider exchangeRateProvider,
    ILogger<ExchangeRateTools> logger)
{
    [McpServerTool(Name = "get_exchange_rate")]
    [Description("Gets an attributed exchange rate with its observation time, retrieval time, rate type, and freshness note.")]
    public Task<ExchangeRateQuote> GetExchangeRateAsync(
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Three-letter target currency code, such as KRW.")] string targetCurrency,
        [Description("Optional historical date in YYYY-MM-DD format.")] string? date = null,
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
    [Description("Converts an amount using an attributed provider rate and returns the rate source and freshness metadata.")]
    public async Task<ProviderCurrencyConversion> ConvertCurrencyAsync(
        [Description("Amount in the source currency.")] decimal amount,
        [Description("Three-letter source currency code, such as USD.")] string sourceCurrency,
        [Description("Three-letter target currency code, such as KRW.")] string targetCurrency,
        [Description("Optional historical date in YYYY-MM-DD format.")] string? date = null,
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
        return new ProviderCurrencyConversion(
            amount,
            quote.SourceCurrency,
            decimal.Round(amount * quote.Rate, 2, MidpointRounding.ToEven),
            quote.TargetCurrency,
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

public sealed record ProviderCurrencyConversion(
    decimal SourceAmount,
    string SourceCurrency,
    decimal TargetAmount,
    string TargetCurrency,
    ExchangeRateQuote Quote);
